locals {
  function_name = "${var.name_prefix}-lambda"
}

# Package (zip) if not using image
data "archive_file" "lambda_zip" {
  count       = var.image_uri == null && var.lambda_src_dir != null ? 1 : 0
  type        = "zip"
  source_dir  = var.lambda_src_dir
  output_path = "${path.module}/build/${local.function_name}.zip"
}

resource "aws_iam_role" "lambda_role" {
  name               = "${var.name_prefix}-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
}

data "aws_iam_policy_document" "lambda_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

# Base policy
data "aws_iam_policy_document" "lambda_policy" {
  statement {
    sid     = "Logs"
    actions = ["logs:CreateLogGroup","logs:CreateLogStream","logs:PutLogEvents"]
    resources = ["*"]
  }

  # Read config object
  statement {
    sid = "ReadConfig"
    actions = ["s3:GetObject"]
    resources = [
      "arn:aws:s3:::${var.config_bucket}/${var.config_key}"
    ]
  }

  # Allow write to dest buckets
  dynamic "statement" {
    for_each = var.s3_destination_bucket_arns
    content {
      sid     = "WriteTo${replace(statement.value, ":", "_")}"
      actions = ["s3:PutObject","s3:AbortMultipartUpload","s3:PutObjectAcl","s3:PutObjectTagging","s3:ListBucket"]
      resources = [
        statement.value,
        "${statement.value}/*"
      ]
    }
  }

  # Optional: read secret
  dynamic "statement" {
    for_each = var.create_secret || var.secret_arn != null ? [1] : []
    content {
      sid     = "SecretsRead"
      actions = ["secretsmanager:GetSecretValue"]
      resources = [
        var.create_secret ? aws_secretsmanager_secret.ftp[0].arn : var.secret_arn
      ]
    }
  }
}

resource "aws_iam_policy" "lambda_inline" {
  name   = "${var.name_prefix}-policy"
  policy = data.aws_iam_policy_document.lambda_policy.json
}

resource "aws_iam_role_policy_attachment" "attach" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = aws_iam_policy.lambda_inline.arn
}

# Upload config JSON (Terraform owns it)
resource "aws_s3_object" "config" {
  bucket       = var.config_bucket
  key          = var.config_key
  content      = jsonencode(var.config_object)
  content_type = "application/json"
  etag         = filemd5("${path.module}/.keep") # prevents 'computed' diffs; optional trick
}

# Optional secret creation
resource "aws_secretsmanager_secret" "ftp" {
  count = var.create_secret ? 1 : 0
  name  = var.secret_name
}

resource "aws_secretsmanager_secret_version" "ftp" {
  count         = var.create_secret ? 1 : 0
  secret_id     = aws_secretsmanager_secret.ftp[0].id
  secret_string = jsonencode(var.secret_json)
}

# Lambda
resource "aws_lambda_function" "this" {
  function_name = local.function_name
  role          = aws_iam_role.lambda_role.arn
  timeout       = var.timeout_seconds
  memory_size   = var.memory_size_mb
  layers        = var.lambda_layers
  publish       = true
  reserved_concurrent_executions = var.reserved_concurrent_executions

  dynamic "environment" {
    for_each = [1]
    content {
      variables = var.env_vars
    }
  }

  dynamic "image_uri" {
    for_each = var.image_uri != null ? [1] : []
    content  = var.image_uri
  }

  dynamic "filename" {
    for_each = var.image_uri == null ? [1] : []
    content  = data.archive_file.lambda_zip[0].output_path
  }

  dynamic "source_code_hash" {
    for_each = var.image_uri == null ? [1] : []
    content  = data.archive_file.lambda_zip[0].output_base64sha256
  }

  # Only set runtime/handler if using zip
  dynamic "runtime" {
    for_each = var.image_uri == null ? [1] : []
    content  = var.runtime
  }

  dynamic "handler" {
    for_each = var.image_uri == null ? [1] : []
    content  = var.handler
  }
}

# Logs retention
resource "aws_cloudwatch_log_group" "lg" {
  name              = "/aws/lambda/${aws_lambda_function.this.function_name}"
  retention_in_days = var.log_retention_days
}

# Schedule (EventBridge)
resource "aws_cloudwatch_event_rule" "cron" {
  name                = "${var.name_prefix}-cron"
  schedule_expression = var.schedule_expression
}

resource "aws_cloudwatch_event_target" "cron_target" {
  rule      = aws_cloudwatch_event_rule.cron.name
  target_id = "lambda"
  arn       = aws_lambda_function.this.arn
}

resource "aws_lambda_permission" "allow_events" {
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.this.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.cron.arn
}
