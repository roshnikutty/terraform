############################################
# IAM Role + Storage Integration Setup for Auto-Ingest
#
# This file contains resources for enabling Snowpipe auto-ingest using:
# - AWS IAM role for Snowflake to assume

# - Snowflake Storage Integration
# - Alternative stage configuration using storage integration
#
# To enable auto-ingest:
# 1. Verify `var.snowflake_aws_account_id` is correct for your region (DESC STORAGE INTEGRATION doc).
# 2. Uncomment all resources in this file and apply.
# 3. In snowpipe.tf:
# - Comment out the access key stage (snowflake_stage.stage_tf)
# - Update pipe's copy_statement to reference snowflake_stage.stage_tf_integration
# - Set `auto_ingest = true` on the pipe
# 4. Manual step - Configure S3 bucket event notifications to Snowflake SQS (get ARN from DESC PIPE).
# 5. Remove/rotate AWS access key credentials from variables.
# 6. Manual step - Run `DESC STORAGE INTEGRATION my_s3_integration_<env>` to get external ID for hardened trust policy.
# 7. After enabling, remove manual ALTER PIPE REFRESH operational steps.
############################################
# AWS IAM Role for Snowflake to assume


data "snowflake_database" "snowpipe_db" {
  name = var.database
}

# Check if schema exists by listing all schemas in the database
data "snowflake_schemas" "all_schemas" {
  in {
    database = data.snowflake_database.snowpipe_db.name
  }
}

locals {
  # Check if the schema exists in the list
  schema_exists = contains([for s in data.snowflake_schemas.all_schemas.schemas : s.show_output[0].name], upper(var.schema))
}

resource "snowflake_schema" "ingest_schema" {
  count = local.schema_exists ? 0 : 1

  database = data.snowflake_database.snowpipe_db.name
  name     = upper(var.schema)
  comment  = "Terraform managed schema for Snowpipe ingestion"
}

locals {
  schema_name = upper(var.schema)
}


resource "snowflake_file_format" "csv_format" {
  database = data.snowflake_database.snowpipe_db.name
  schema   = local.schema_name
  name     = local.effective_file_format_name

  format_type = "CSV"

  field_delimiter     = "|"
  skip_header         = 0
  null_if             = ["\\N"]
  empty_field_as_null = true
  trim_space          = true

  lifecycle {
    ignore_changes = all
  }
}


resource "snowflake_table" "raw_data_table" {
  database = data.snowflake_database.snowpipe_db.name
  schema   = local.schema_name
  name     = local.effective_table_name
  comment  = "Raw ingested S3 lines with basic metadata"

  column {
    name = "RAW_LINE"
    type = "STRING"
  }
  column {
    name = "FILE_NAME"
    type = "STRING"
  }
  column {
    name = "ROW_NUMBER"
    type = "NUMBER"
  }
  column {
    name = "INGESTED_AT"
    type = "TIMESTAMP_NTZ"
    default {
      expression = "CURRENT_TIMESTAMP"
    }
  }

  lifecycle {
    ignore_changes = all
  }
}

# Pipe (auto-ingest enabled with storage integration)
resource "snowflake_pipe" "s3_pipe" {
  name     = local.effective_pipe_name
  database = data.snowflake_database.snowpipe_db.name
  schema   = local.schema_name

  copy_statement = <<-SQL
    COPY INTO "${data.snowflake_database.snowpipe_db.name}"."${local.schema_name}"."${snowflake_table.raw_data_table.name}" (RAW_LINE, FILE_NAME, ROW_NUMBER, INGESTED_AT)
    FROM (
      SELECT
        $1,
        METADATA$FILENAME,
        METADATA$FILE_ROW_NUMBER,
        CURRENT_TIMESTAMP
      FROM @"${data.snowflake_database.snowpipe_db.name}"."${local.schema_name}"."${snowflake_stage.stage_tf_integration.name}"
    )
    FILE_FORMAT = (FORMAT_NAME = '"${data.snowflake_database.snowpipe_db.name}"."${local.schema_name}"."${snowflake_file_format.csv_format.name}"')
    ON_ERROR = 'CONTINUE'
  SQL

  auto_ingest = true
  depends_on  = [snowflake_table.raw_data_table, snowflake_file_format.csv_format, snowflake_stage.stage_tf_integration]

  lifecycle {
    ignore_changes = all
  }
}


# Data source to reference existing IAM role if it exists
data "aws_iam_role" "existing_role" {
  count = var.create_iam_role ? 0 : 1
  name  = "snowflake-snowpipe-role-dev"
}

resource "aws_iam_role" "snowflake_ingest_role" {
  count = var.create_iam_role ? 1 : 0
  name  = "snowflake-snowpipe-role-dev"

  # Initial placeholder trust policy - will be updated by aws_iam_role_policy_attachment below
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Principal = {
          Service = "s3.amazonaws.com"
        },
        Action = "sts:AssumeRole"
      }
    ]
  })

  lifecycle {
    ignore_changes = [assume_role_policy]
  }
}

locals {
  iam_role_name = var.create_iam_role ? aws_iam_role.snowflake_ingest_role[0].name : data.aws_iam_role.existing_role[0].name
  iam_role_arn  = var.create_iam_role ? aws_iam_role.snowflake_ingest_role[0].arn : data.aws_iam_role.existing_role[0].arn
  iam_role_id   = var.create_iam_role ? aws_iam_role.snowflake_ingest_role[0].id : data.aws_iam_role.existing_role[0].id
}

# Update the IAM role trust policy after storage integration is created
resource "null_resource" "update_trust_policy" {
  triggers = {
    integration_arn = snowflake_storage_integration.s3_integration.storage_aws_iam_user_arn
    role_name       = local.iam_role_name
  }

  provisioner "local-exec" {
    command = <<-EOT
      AWS_ACCESS_KEY_ID=${var.aws_access_key} AWS_SECRET_ACCESS_KEY=${var.aws_secret_key} \
      aws iam update-assume-role-policy \
        --role-name ${local.iam_role_name} \
        --region us-east-1 \
        --policy-document '{
          "Version": "2012-10-17",
          "Statement": [{
            "Effect": "Allow",
            "Principal": {
              "AWS": "${snowflake_storage_integration.s3_integration.storage_aws_iam_user_arn}"
            },
            "Action": "sts:AssumeRole"
          }]
        }'
    EOT
  }

  depends_on = [
    snowflake_storage_integration.s3_integration
  ]
}

# IAM Policy granting S3 read permissions
resource "aws_iam_role_policy" "snowflake_ingest_policy" {
  name = "snowflake-snowpipe-policy"
  role = local.iam_role_id
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Sid    = "ListAndReadObjects",
      Effect = "Allow",
      Action = [
        "s3:GetObject",
        "s3:GetObjectVersion",
        "s3:ListBucket",
        "s3:GetBucketLocation"
      ],
      Resource = ["arn:aws:s3:::${var.s3_bucket_name}",
    "arn:aws:s3:::${var.s3_bucket_name}/${replace(var.s3_prefix, "/$", "")}*"] }]
  })

  lifecycle {
    ignore_changes = all
  }
}

# Snowflake Storage Integration
resource "snowflake_storage_integration" "s3_integration" {
  name                      = "my_s3_integration_${var.environment}"
  type                      = "EXTERNAL_STAGE"
  enabled                   = true
  storage_provider          = "S3"
  storage_allowed_locations = ["s3://${var.s3_bucket_name}/${var.s3_prefix}"]
  storage_aws_role_arn      = local.iam_role_arn
  comment                   = "Storage integration for Snowpipe auto-ingest from S3"

  lifecycle {
    ignore_changes = all
  }
}

# Update IAM role trust policy with Snowflake-generated values
# NOTE: You need to manually update the IAM role trust policy after apply
# Run: DESC STORAGE INTEGRATION my_s3_integration_dev; in Snowflake
# Then manually update the IAM role trust policy with the returned values
# resource "null_resource" "update_iam_trust_policy" {
#   count = var.enable_storage_integration ? 1 : 0
#
#   triggers = {
#     storage_integration_id = snowflake_storage_integration.s3_integration.id
#     iam_role_name          = aws_iam_role.snowflake_ingest_role.name
#   }
#
#   provisioner "local-exec" {
#     command = <<-EOT
#       aws iam update-assume-role-policy \
#         --role-name ${aws_iam_role.snowflake_ingest_role.name} \
#         --policy-document '{
#           "Version": "2012-10-17",
#           "Statement": [{
#             "Effect": "Allow",
#             "Principal": {
#               "AWS": "${snowflake_storage_integration.s3_integration.storage_aws_iam_user_arn}"
#             },
#             "Action": "sts:AssumeRole",
#             "Condition": {
#               "StringEquals": {
#                 "sts:ExternalId": "${snowflake_storage_integration.s3_integration.storage_aws_external_id}"
#               }
#             }
#           }]
#         }'
#     EOT
#   }
#
#   depends_on = [snowflake_storage_integration.s3_integration]
# }

# Alternative Stage using Storage Integration (replaces access key stage)


resource "snowflake_stage" "stage_tf_integration" {
  name                = local.effective_stage_name
  url                 = "s3://${var.s3_bucket_name}/${var.s3_prefix}"
  database            = data.snowflake_database.snowpipe_db.name
  schema              = local.schema_name
  storage_integration = snowflake_storage_integration.s3_integration.name
  comment             = "Stage using storage integration (preferred for auto-ingest)"

  depends_on = [snowflake_storage_integration.s3_integration]

  lifecycle {
    ignore_changes = all
  }
}
