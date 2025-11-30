# Import existing resources into Terraform state
# Run: terraform plan -generate-config-out=generated.tf
# This will import resources and generate their configuration

import {
  to = snowflake_file_format.csv_format
  id = "\"ROSHNI_DB\".\"INGEST_SCHEMA\".\"CSV_FORMAT\""
}

import {
  to = snowflake_table.raw_data_table
  id = "\"ROSHNI_DB\".\"INGEST_SCHEMA\".\"RAW_DATA_TABLE\""
}

import {
  to = snowflake_storage_integration.s3_integration
  id = "my_s3_integration_dev"
}

import {
  to = snowflake_stage.stage_tf_integration
  id = "\"ROSHNI_DB\".\"INGEST_SCHEMA\".\"S3_STAGE\""
}

import {
  to = snowflake_pipe.s3_pipe
  id = "\"ROSHNI_DB\".\"INGEST_SCHEMA\".\"S3_PIPE\""
}

import {
  to = aws_iam_role_policy.snowflake_ingest_policy
  id = "snowflake-snowpipe-role-dev:snowflake-snowpipe-policy"
}
