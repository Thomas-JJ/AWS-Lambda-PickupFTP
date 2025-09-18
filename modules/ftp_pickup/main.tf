terraform {
  required_providers {
    archive = {
      source  = "hashicorp/archive"
      version = ">= 2.4.0"
    }
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
}

locals {
  function_name = "${var.name_prefix}-lambda"
}

data "archive_file" "lambda_zip" {
  type        = "zip"
  source_dir  = var.lambda_src_dir
  output_path = "${path.module}/lambda.zip"
}

resource "aws_lambda_layer_version" "paramiko" {
  count               = var.paramiko_layer_zip != null ? 1 : 0
  layer_name          = "${var.name_prefix}-paramiko"
  filename            = "${var.paramiko_layer_zip}"
  compatible_runtimes = [var.runtime]
  description         = "Paramiko + deps layer"
}

# IAM assume-role
data "aws_iam_policy_document" "lambda_assume" {
  statement {
    sid     = "LambdaAssumeRole"
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "lambda_role" {
  name               = "${var.name_prefix}-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
}

data "aws_iam_policy_document" "lambda_policy" {
  statement {
    sid     = "Logs"
    effect  = "Allow"
    actions = ["logs:CreateLogGroup","logs:CreateLogStream","logs:PutLogEvents"]
    resources = ["*"]
  }

  statement {
    sid     = "S3Objects"
    effect  = "Allow"
    actions = [
      "s3:PutObject",
      "s3:GetObject",
      "s3:AbortMultipartUpload",
      "s3:PutObjectTagging"
    ]
    resources = ["arn:aws:s3:::*/*"]
  }
  statement {
    sid      = "S3ListConfig"
    effect   = "Allow"
    actions  = ["s3:ListBucket"]
    resources = ["arn:aws:s3:::${var.config_bucket}"]
  }
  statement {
    sid       = "SecretsRead"
    effect    = "Allow"
    actions   = ["secretsmanager:GetSecretValue"]
    resources = [var.secret_arn]
  }
}

resource "aws_iam_policy" "lambda_inline" {
  name   = "${var.name_prefix}-policy"
  policy = data.aws_iam_policy_document.lambda_policy.json
}

resource "aws_iam_role_policy_attachment" "attach_inline" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = aws_iam_policy.lambda_inline.arn
}

resource "aws_lambda_function" "this" {
  function_name = local.function_name
  role          = aws_iam_role.lambda_role.arn

  package_type     = "Zip"
  filename         = data.archive_file.lambda_zip.output_path
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
  runtime          = var.runtime
  handler          = var.handler

  timeout     = var.timeout_seconds
  memory_size = var.memory_size_mb
  publish     = true

  layers = var.paramiko_layer_zip != null ? [aws_lambda_layer_version.paramiko[0].arn] : []

  reserved_concurrent_executions = var.reserved_concurrent_executions


  environment {
    variables = merge(
      {
        CONFIG_BUCKET = var.config_bucket
        CONFIG_FILE   = var.config_file
      }
    )
  }
}

# Logs retention
resource "aws_cloudwatch_log_group" "lg" {
  name              = "/aws/lambda/${aws_lambda_function.this.function_name}"
  retention_in_days = var.log_retention_days
}

# EventBridge schedule
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
