
variable "environment" {
  type        = string
}

variable "name_prefix" {
  description = "Short name prefix for all resources (e.g., ftp-pickup-dev)"
  type        = string
}

# Packaging (choose one in tfvars)
variable "lambda_src_dir" {
  description = "Local dir with handler.py (ZIP deploy). Leave null if using container image."
  type        = string
  default     = null
}
variable "image_uri" {
  description = "ECR image URI (container deploy). Leave null to use ZIP."
  type        = string
  default     = null
}

# Where the JSON config will live (Terraform writes it)
variable "config_bucket" {
  type = string
}
variable "config_key" {
  type = string
}

# Core transfer settings (config pieces split into vars)
variable "protocol" {
  description = "ftp | ftps | sftp"
  type        = string
  default     = "ftps"
}

variable "ftp_host" { type = string }
variable "ftp_port" {
  type    = number
  default = 21
}

# Usually use Secrets Manager at runtime. If you truly want inline creds,
# add vars for username/password and set them in module config instead.
variable "secret_arn" {
  description = "Existing Secrets Manager ARN that holds {username,password,private_key}."
  type        = string
  default     = null
}

variable "source_roots" {
  description = "Default pickup folder(s) on the FTP server"
  type        = list(string)
  default     = ["/incoming"]
}

# Routes: use empty string for optional fields when not needed
variable "routes" {
  description = "Filename routing rules"
  type = list(object({
    pattern               = string
    destination           = string            # s3://bucket/prefix/
    pickup                = string            # "" to use default
    archive_on_source     = string            # "" to skip archiving
    delete_after_transfer = bool              # false keeps original unless archive is set
    on_conflict           = string            # skip | overwrite | suffix
  }))
}

variable "s3_server_side_encryption" {
  description = "SSE mode for uploads (e.g., AES256)"
  type        = string
  default     = "AES256"
}
variable "s3_storage_class" {
  type    = string
  default = null
}
variable "s3_acl" {
  type    = string
  default = null
}

variable "delete_after_transfer_default" {
  description = "Global default if a route doesn't specify"
  type        = bool
  default     = false
}
variable "on_conflict_default" {
  description = "Global conflict mode if a route doesn't specify"
  type        = string
  default     = "skip"
}

# Schedule & Lambda runtime
variable "schedule_expression" {
  type    = string
  default = "cron(0/15 * * * ? *)"
}
variable "memory_size_mb" {
  type    = number
  default = 512
}
variable "timeout_seconds" {
  type    = number
  default = 300
}
variable "reserved_concurrent_executions" {
  description = "Set 1 to avoid overlapping runs"
  type        = number
  default     = 1
}
variable "lambda_layers" {
  description = "Paramiko layer for SFTP, etc."
  type        = list(string)
  default     = []
}

# Extra environment vars (merged in)
variable "extra_env_vars" {
  type    = map(string)
  default = {}
}
