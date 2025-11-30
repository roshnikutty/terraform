# Environment Configuration
variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "dev"
}

# AWS Configuration
variable "aws_access_key" {
  description = "AWS Access Key"
  type        = string
  sensitive   = true
}

variable "aws_secret_key" {
  description = "AWS Secret Key"
  type        = string
  sensitive   = true
}

# S3 Configuration
variable "s3_bucket_name" {
  description = "S3 bucket name for Snowpipe data"
  type        = string
}

variable "s3_prefix" {
  description = "S3 prefix/folder path for data files"
  type        = string
}

# Snowflake Provider Configuration
variable "snowflake_organization_name" {
  description = "Snowflake organization name"
  type        = string
}

variable "snowflake_account_name" {
  description = "Snowflake account name"
  type        = string
}

variable "snowflake_user" {
  description = "Snowflake username"
  type        = string
}

variable "snowflake_password" {
  description = "Snowflake password"
  type        = string
  sensitive   = true
}

variable "snowflake_role" {
  description = "Snowflake role to use"
  type        = string
  default     = "ACCOUNTADMIN"
}

# Snowflake Resource Configuration
variable "database" {
  description = "Snowflake database name"
  type        = string
}

variable "schema" {
  description = "Snowflake schema name"
  type        = string
  default     = "ingest"
}

variable "snowflake_aws_account_id" {
  description = "AWS Account ID for Snowflake to assume role (region-specific) - only used if enable_storage_integration is false"
  type        = string
  default     = "123456789012" # Replace with your Snowflake AWS Account ID from DESC STORAGE INTEGRATION
}

variable "enable_storage_integration" {
  description = "Enable storage integration for auto-ingest (recommended). If false, uses basic trust policy with snowflake_aws_account_id"
  type        = bool
  default     = true
}

# Optional: Resource Name Overrides
variable "table_name" {
  description = "Name for the Snowflake table (defaults to raw_data_table_<env>)"
  type        = string
  default     = ""
}

variable "pipe_name" {
  description = "Name for the Snowpipe (defaults to s3_pipe_<env>)"
  type        = string
  default     = ""
}

variable "file_format_name" {
  description = "Name for the file format (defaults to csv_format_<env>)"
  type        = string
  default     = ""
}

# Locals for effective naming
locals {
  effective_stage_name       = "MY_S3_STAGE_${upper(var.environment)}"
  effective_table_name       = var.table_name != "" ? var.table_name : "raw_data_table_${var.environment}"
  effective_pipe_name        = var.pipe_name != "" ? var.pipe_name : "s3_pipe_${var.environment}"
  effective_file_format_name = var.file_format_name != "" ? var.file_format_name : "csv_format_${var.environment}"
}