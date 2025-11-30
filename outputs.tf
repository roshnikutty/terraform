# Output the Snowflake-generated AWS account ID and external ID
# These values are needed to update the IAM role trust policy

output "storage_integration_name" {
  description = "Name of the Snowflake storage integration"
  value       = snowflake_storage_integration.s3_integration.name
}

output "snowflake_iam_user_arn" {
  description = "Snowflake IAM user ARN that will assume the role (use this to update the trust policy)"
  value       = snowflake_storage_integration.s3_integration.storage_aws_iam_user_arn
}

output "snowflake_external_id" {
  description = "Snowflake external ID for the IAM role trust policy (use this to update the trust policy)"
  value       = snowflake_storage_integration.s3_integration.storage_aws_external_id
  sensitive   = true
}

output "iam_role_arn" {
  description = "ARN of the IAM role that Snowflake will assume"
  value       = aws_iam_role.snowflake_ingest_role.arn
}

output "desc_integration_command" {
  description = "Run this Snowflake command to view integration details"
  value       = "DESC STORAGE INTEGRATION ${snowflake_storage_integration.s3_integration.name};"
}
