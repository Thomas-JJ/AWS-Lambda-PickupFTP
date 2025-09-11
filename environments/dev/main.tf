terraform {
  required_version = ">= 1.3.0"
}

locals {
  # Build the exact JSON the Lambda expects from simple vars
  config_object = {
    protocol = var.protocol
    ftp = {
      host                        = var.ftp_host
      port                        = var.ftp_port
      username                    = null                    # creds come from secret
      password                    = null
      secrets_manager_secret_name = var.secret_arn
    }
    source_roots = var.source_roots
    routes       = [
      for r in var.routes : {
        pattern               = r.pattern
        pickup                = r.pickup
        destination           = r.destination
        archive_on_source     = r.archive_on_source
        delete_after_transfer = r.delete_after_transfer
        on_conflict           = r.on_conflict
      }
    ]
    s3 = {
      server_side_encryption = var.s3_server_side_encryption
      storage_class          = var.s3_storage_class
      acl                    = var.s3_acl
    }
    delete_after_transfer = var.delete_after_transfer_default
    on_conflict           = var.on_conflict_default
  }

  # Derive the unique destination bucket ARNs from the routes
  dest_bucket_arns = distinct([
    for r in var.routes : "arn:aws:s3:::" ~ element(split("/", replace(r.destination, "s3://", "")), 0)
  ])
}

module "ftp_pickup" {
  source      = "../../modules/ftp_pickup"
  name_prefix = var.name_prefix

  # Packaging (choose one)
  lambda_src_dir = var.lambda_src_dir
  image_uri      = var.image_uri
  lambda_layers  = var.lambda_layers

  # Upload config JSON (owned by Terraform)
  config_bucket = var.config_bucket
  config_key    = var.config_key
  config_object = local.config_object

  # IAM for the destination buckets
  s3_destination_bucket_arns = local.dest_bucket_arns

  # Lambda runtime
  memory_size_mb                  = var.memory_size_mb
  timeout_seconds                 = var.timeout_seconds
  reserved_concurrent_executions  = var.reserved_concurrent_executions

  # Schedule
  schedule_expression = var.schedule_expression

  # Env for the function (add your own through extra_env_vars)
  env_vars = merge(
    {
      CONFIG_S3_BUCKET = var.config_bucket
      CONFIG_S3_KEY    = var.config_key
    },
    var.extra_env_vars
  )
}
