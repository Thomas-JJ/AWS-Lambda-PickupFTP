variable "name_prefix" {
  description = "Short name prefix for resources (e.g., aloha-ftp-pickup-dev)"
  type        = string
}

variable "config_bucket" {
  description = "S3 bucket with config file."
  type        = string
}

variable "config_file" {
  description = "perfix and file name of config."
  type        = string
}


variable "lambda_src_dir" {
  description = "Local directory containing handler.py"
  type        = string
}

variable "paramiko_layer_zip" {
  description = "Path to the local paramiko layer zip (e.g., paramiko-layer-312.zip). If null, no layer is created."
  type        = string
  default     = null
}

variable "runtime" {
  description = "Lambda runtime"
  type        = string
  default     = "python3.12"
}

variable "handler" {
  description = "Lambda handler"
  type        = string
  default     = "handler.lambda_handler"
}

variable "memory_size_mb" {
  type    = number
  default = 512
}

variable "timeout_seconds" {
  type    = number
  default = 60
}

variable "reserved_concurrent_executions" {
  description = "Set to a number to reserve; null leaves it unreserved"
  type        = number
  default     = null
}

variable "secret_name" {
  description = "Name of the AWS Secrets Manager secret (e.g. My_FTPShare)"
  type        = string
}

variable "schedule_expression" {
  description = "EventBridge schedule (cron(...) or rate(...))"
  type        = string
}

variable "log_retention_days" {
  type    = number

  default = 14
}
