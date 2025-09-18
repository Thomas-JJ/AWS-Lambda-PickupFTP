locals {

  lambda_src_dir = "${path.module}/lambda"

}


data "aws_secretsmanager_secret" "ftp" { 
  name = var.secret_name 
}

module "ftp_pickup" {
  source      = "../../modules/ftp_pickup"

  name_prefix = var.name_prefix

  config_bucket = var.config_bucket
  config_file = var.config_file

  lambda_src_dir = local.lambda_src_dir

  paramiko_layer_zip  =   var.paramiko_layer_zip

  secret_arn = data.aws_secretsmanager_secret.ftp.arn

  schedule_expression            = var.schedule_expression

  runtime                         = var.runtime
  handler                         = var.handler

  memory_size_mb                 = var.memory_size_mb
  timeout_seconds                = var.timeout_seconds
  reserved_concurrent_executions = var.reserved_concurrent_executions
  log_retention_days             = var.log_retention_days

}
