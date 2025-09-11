variable "name_prefix" {
  description = "Short name prefix for all resources (e.g., ftp-pickup)"
  type        = string
}

variable "lambda_src_dir" {
  description = "Local directory containing handler.py and (optionally) vendored deps. Leave null if using container image."
  type        = string
  default     = null
}

variable "image_uri" {
  description = "ECR image URI if deploying as a container. Leave null to use zip + runtime."
  type        = string
  default     = null
}

variable "runtime" {
  type        = string
  default     = "python3.12"
}

variable "handler" {
  type        = string
  default     = "handler.lambda_handler"
}

variable "memory_size_mb" {
  type        = number
  default     = 512
}

variable "timeout_seconds" {
  type        = number
  default     = 300
}

variable "reserved_concurrent_executions" {
  description = "Set to 1 to prevent overlapping transfers; null for unbounded."
  type        = number
  default     = 1
}

variable "lambda_layers" {
  description = "Optional Lambda layer ARNs (e.g., Paramiko layer for SFTP)"
  type        = list(string)
  default     = []
}

variable "env_vars" {
  description = "Environment vars for the Lambda"
  type        = map(string)
  default     = {}
}

variable "config_bucket" {
  description = "S3 bucket that will hold config JSON"
  type        = string
}

variable "config_key" {
  description = "S3 key (object path) for the config JSON"
  type        = string
}

variable "config_object" {
  description = "The config JSON as a Terraform object (will be jsonencoded and uploaded)"
  type        = any
}

variable "schedule_expression" {
  description = "EventBridge cron or rate expression"
  type        = string
  default     = "cron(0/15 * * * ? *)"
}

variable "s3_destination_bucket_arns" {
  description = "List of destination bucket ARNs the Lambda can write to"
  type        = list(string)
  default     = []
}

variable "create_secret" {
  description = "If true, create a Secrets Manager secret for FTP creds (JSON)."
  type        = bool
  default     = false
}

variable "secret_name" {
  description = "Name for the secret (if create_secret=true)."
  type        = string
  default     = null
}

variable "secret_json" {
  description = "JSON object to store in the secret (e.g., {username=..., password=..., private_key=...})."
  type        = any
  default     = {}
}

variable "secret_arn" {
  description = "Existing secret ARN if not creating one."
  type        = string
  default     = null
}

variable "log_retention_days" {
  type        = number
  default     = 14
}
