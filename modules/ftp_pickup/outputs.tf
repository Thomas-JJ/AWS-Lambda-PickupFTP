output "function_name" {
  value = aws_lambda_function.this.function_name
}

output "config_s3_uri" {
  value = "s3://${aws_s3_object.config.bucket}/${aws_s3_object.config.key}"
}

output "secret_arn" {
  value       = var.create_secret ? aws_secretsmanager_secret.ftp[0].arn : var.secret_arn
  description = "Secrets Manager ARN used by the function (if any)"
}
