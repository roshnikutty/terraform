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
# - Comment out the access key stage (snowflake_stage.circana_stage_tf)
# - Update pipe's copy_statement to reference snowflake_stage.circana_stage_tf_integration
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

resource "snowflake_schema" "ingest_schema" {
  database = data.snowflake_database.snowpipe_db.name
  name     = upper(var.schema)
  comment  = "Terraform managed schema for Snowpipe ingestion"
}


resource "snowflake_file_format" "csv_format" {
  database = data.snowflake_database.snowpipe_db.name
  schema   = snowflake_schema.ingest_schema.name
  name     = local.effective_file_format_name

  format_type = "CSV"

  field_delimiter     = "|"
  skip_header         = 0
  null_if             = ["\\N"]
  empty_field_as_null = true
  trim_space          = true
}


resource "snowflake_table" "raw_data_table" {
  database = data.snowflake_database.snowpipe_db.name
  schema   = snowflake_schema.ingest_schema.name
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
}

# Pipe (auto-ingest enabled with storage integration)
resource "snowflake_pipe" "s3_pipe" {
  name     = local.effective_pipe_name
  database = data.snowflake_database.snowpipe_db.name
  schema   = snowflake_schema.ingest_schema.name

  copy_statement = <<-SQL
    COPY INTO ${data.snowflake_database.snowpipe_db.name}.${snowflake_schema.ingest_schema.name}.${snowflake_table.raw_data_table.name} (RAW_LINE, FILE_NAME, ROW_NUMBER, INGESTED_AT)
    FROM (
      SELECT
        $1,
        METADATA$FILENAME,
        METADATA$FILE_ROW_NUMBER,
        CURRENT_TIMESTAMP
      FROM @${data.snowflake_database.snowpipe_db.name}.${snowflake_schema.ingest_schema.name}.MY_S3_STAGE_${upper(var.environment)}
    )
    FILE_FORMAT = (FORMAT_NAME = '${data.snowflake_database.snowpipe_db.name}.${snowflake_schema.ingest_schema.name}.${snowflake_file_format.csv_format.name}')
    ON_ERROR = 'CONTINUE'
  SQL

  auto_ingest = true
  depends_on  = [snowflake_table.raw_data_table, snowflake_file_format.csv_format, snowflake_stage.circana_stage_tf_integration]
}


resource "aws_iam_role" "snowflake_ingest_role" {
  name = "snowflake-snowpipe-role-${var.environment}"

  # Basic trust policy - allows Snowflake to assume this role
  # This will be updated by aws_iam_role_policy_attachment after storage integration is created
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect    = "Allow",
        Principal = { AWS = "arn:aws:iam::${var.snowflake_aws_account_id}:root" },
        Action    = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Environment = var.environment
    Purpose     = "Snowflake Snowpipe Auto-Ingest"
  }

  # Ignore changes to assume_role_policy after initial creation
  # It will be managed by the null_resource below
  lifecycle {
    ignore_changes = [assume_role_policy]
  }
}

# IAM Policy granting S3 read permissions
resource "aws_iam_role_policy" "snowflake_ingest_policy" {
  name = "snowflake-snowpipe-policy-${var.environment}"
  role = aws_iam_role.snowflake_ingest_role.id
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
}

# Snowflake Storage Integration
resource "snowflake_storage_integration" "s3_integration" {
  name                      = "my_s3_integration_${var.environment}"
  type                      = "EXTERNAL_STAGE"
  enabled                   = true
  storage_provider          = "S3"
  storage_allowed_locations = ["s3://${var.s3_bucket_name}/${var.s3_prefix}"]
  storage_aws_role_arn      = aws_iam_role.snowflake_ingest_role.arn
  comment                   = "Storage integration for Snowpipe auto-ingest from S3"

  depends_on = [aws_iam_role.snowflake_ingest_role]
}

# Update IAM role trust policy with Snowflake-generated values
resource "null_resource" "update_iam_trust_policy" {
  count = var.enable_storage_integration ? 1 : 0

  triggers = {
    storage_integration_id = snowflake_storage_integration.s3_integration.id
    iam_role_name          = aws_iam_role.snowflake_ingest_role.name
  }

  provisioner "local-exec" {
    command = <<-EOT
      aws iam update-assume-role-policy \
        --role-name ${aws_iam_role.snowflake_ingest_role.name} \
        --policy-document '{
          "Version": "2012-10-17",
          "Statement": [{
            "Effect": "Allow",
            "Principal": {
              "AWS": "${snowflake_storage_integration.s3_integration.storage_aws_iam_user_arn}"
            },
            "Action": "sts:AssumeRole",
            "Condition": {
              "StringEquals": {
                "sts:ExternalId": "${snowflake_storage_integration.s3_integration.storage_aws_external_id}"
              }
            }
          }]
        }'
    EOT
  }

  depends_on = [snowflake_storage_integration.s3_integration]
}

# Alternative Stage using Storage Integration (replaces access key stage)


resource "snowflake_stage" "circana_stage_tf_integration" {
  name                = local.effective_stage_name
  url                 = "s3://${var.s3_bucket_name}/${var.s3_prefix}"
  database            = data.snowflake_database.snowpipe_db.name
  schema              = snowflake_schema.ingest_schema.name
  storage_integration = snowflake_storage_integration.s3_integration.name
  comment             = "Stage using storage integration (preferred for auto-ingest)"

  depends_on = [snowflake_schema.ingest_schema,
  snowflake_storage_integration.s3_integration]
}
