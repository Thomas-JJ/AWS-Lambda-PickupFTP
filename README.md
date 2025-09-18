# SFTP File Pickup Lambda Function

An AWS Lambda that connects to external SFTP servers and moves files into Amazon S3 using config-driven routing. Credentials live in AWS Secrets Manager; the routing config lives in S3.
## Features
- STFP only (Paramiko via Lambda Layer)
- Config-drive routing(JSON in S3)
- Prefix ("starts with") file matching + extension filter
- Optional delete on success and safe overwrite (timestamp suffix)
- Scheduled with Event Bridge cron
- Minimal, auditable IAM

## Overview

This Lambda function automates the process of:
- Connecting to SFTP servers using stored credentials
- Downloading files based on configurable pickup rules
- Uploading files to designated S3 buckets according to routing rules
- Managing file processing workflows with configuration-driven logic
- Environment level deployments

## Architecture

- **Runtime**: Python 3.12
- **Dependencies**: Paramiko (provided as a Lambda Layer zip)
- **Trigger**: EventBridge (CloudWatch) cron
- **Configuration**: JSON in S3 (read each run)
- **Credentials**: AWS Secrets Manager (host/port/user/password or private_key)
- **Target**: Amazon S3

## Prerequisites

- AWS CLI configured with appropriate permissions
- Terraform >= 0.12
- Python 3.12
- A prebuilt Paramiko layer zip (e.g. paramiko-layer-312.zip)
- An S3 bucket to hold the config JSON

## Configuration

### Terraform Variables

Copy `terraform.tfvars.example` to `terraform.tfvars` and configure the following variables:

```hcl
# Deployment configuration
name_prefix = "sftp-pickup-dev"

# S3 configuration bucket and routing config file
config_bucket = "my-configs-bucket"
config_file = "sftp_routing/configs.json"

# Lambda source and dependencies
lambda_src_dir = "./lambda"
paramiko_layer_zip = "paramiko-layer-312.zip"  # Included in deployment

# AWS Secrets Manager secret name for SFTP credentials
secret_name = "MySFTP_Secret_Name"

# Execution schedule (cron expression)
schedule_expression = "cron(0 10 ? * MON *)"  # Mondays 5:00 AM America/New_York (≈ 10:00 UTC)

# Lambda runtime configuration
runtime = "python3.12"
handler = "handler.lambda_handler"
memory_size_mb = 512
timeout_seconds = 60
reserved_concurrent_executions = null

# CloudWatch Logs retention
log_retention_days = 90
```

### SFTP Credentials Secret

Create a secret in AWS Secrets Manager with the following JSON format:

```json
{
  "username": "MyUser",
  "password": "Password123!",
  "private_key": "-----BEGIN RSA PRIVATE KEY-----\n[private key content]\n-----END RSA PRIVATE KEY-----",
  "host": "my.sftpsite.com",
  "port": 22
}
```

**Note**: Include either `password` OR `private_key` for authentication, not both.

### Configuration File Format

Create a JSON configuration file in your S3 config bucket at the specified path:

```json
{
  "connection": {
    "protocol": "sftp",
    "remote_path": "/in"
  },
  "defaults": {
    "delete_after_transfer": false,
    "overwrite_existing": true,
    "extension": ".csv"
  },
  "transfer_rules": [
    {
      "name": "Orders",
      "file_pattern": "ORDERS_",
      "target": { "bucket": "MyTargetBucket", "prefix": "Orders/" }
    },
    {
      "name": "OrdersDetails", 
      "file_pattern": "ORDERDETAILS_",
      "target": { "bucket": "MyTargetBucket", "prefix": "OrderDetails/" }
    }
  ]
}
```

#### Configuration Options:

- **connection**: SFTP connection settings
  - `protocol`: Connection type (always "sftp")
  - `remote_path`: Base directory on SFTP server to scan for files

- **defaults**: Global default settings applied to all transfer rules
  - `delete_after_transfer`: Whether to delete files from SFTP after successful transfer
  - `overwrite_existing`: Whether to overwrite existing files in S3
  - `extension`: File extension filter (e.g., ".csv", ".txt")

- **transfer_rules**: Array of file processing rules
  - `name`: Descriptive name for the rule
  - `file_pattern`: Pattern to match filenames (e.g., "ORDERS_" matches files starting with "ORDERS_")
  - `target`: S3 destination configuration
    - `bucket`: Target S3 bucket name
    - `prefix`: S3 key prefix (folder path)
```

## Deployment

1. **Navigate to environment folder**:
   ```bash
    cd environments/dev
   ```

2. **Configure Terraform**:
   ```bash
   cp terraform.tfvars.example terraform.tfvars
   # Edit terraform.tfvars with your specific values
   ```

3. **Deploy Infrastructure**:
   ```bash
   terraform init
   terraform plan
   terraform apply
   ```

4. **Upload Configuration**:
   ```bash
   # Upload your routing configuration to the specified S3 bucket
   aws s3 cp configs.json s3://my-configs-bucket/sftp_routing/configs.json
   ```

## Required AWS Permissions

The Lambda function requires the following IAM permissions:

### S3 Permissions
- `s3:GetObject` (config bucket)
- `s3:PutObject` (destination buckets)
- `s3:ListBucket` (destination buckets)

### Secrets Manager Permissions
- `secretsmanager:GetSecretValue` (SFTP credentials)

### CloudWatch Logs Permissions
- `logs:CreateLogGroup`
- `logs:CreateLogStream`
- `logs:PutLogEvents`

## Monitoring

- **CloudWatch Logs**: Function execution logs are retained for the configured period
- **CloudWatch Metrics**: Standard Lambda metrics (duration, errors, invocations)
- **CloudWatch Alarms**: Configure alarms for error rates and execution failures

## Networking (Important)
If your SFTP provider requires allow-listing a fixed public IP, attach the Lambda to private subnets with a NAT Gateway (Elastic IP) and provide that IP to the provider.
Without a VPC, Lambda egress IPs are ephemeral and may be blocked → connection timeouts.


## Troubleshooting

### Common Issues

1. **Connection Timeout**:
   - Verify SFTP host and port in secrets
   - Check network connectivity and security groups

2. **Authentication Failures**:
   - Verify credentials in AWS Secrets Manager
   - Ensure private key format is correct (if using key-based auth)

3. **S3 Upload Errors**:
   - Check IAM permissions for destination buckets
   - Verify bucket names and regions

4. **Configuration Errors**:
   - Validate JSON format in configuration file
   - Ensure config file path matches terraform.tfvars

### Logs Location

Function logs are available in CloudWatch Logs under:
```
/aws/lambda/{name_prefix}-lambda
```

## Scheduling

The function runs on a schedule defined by the `schedule_expression` variable. The default configuration runs every hour:

```
cron(0/60 * * * ? *)
```

Modify this expression to change the execution frequency. Use [AWS cron expressions](https://docs.aws.amazon.com/lambda/latest/dg/services-cloudwatchevents-expressions.html) format.

## Development

### Local Testing

1. Set up local environment:
   ```bash
   pip install paramiko boto3
   ```

2. Configure AWS credentials and test configuration

3. Run function locally with test events

### Updating Configuration

Configuration changes can be made by updating the JSON file in S3. Changes take effect on the next Lambda execution.

## Security Considerations

- SFTP credentials are stored securely in AWS Secrets Manager
- Lambda function runs with least-privilege IAM permissions
- Network access can be restricted using VPC configuration
- All file transfers occur over encrypted connections

## Support

For issues or questions:
1. Check CloudWatch Logs for detailed error messages
2. Verify all configuration parameters
3. Ensure AWS permissions are correctly configured
4. Test SFTP connectivity independently if needed