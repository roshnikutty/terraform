terraform {
  required_providers {
    snowflake = {
      source  = "snowflakedb/snowflake"
      version = ">= 1.0.0"
    }
    null = {
      source  = "hashicorp/null"
      version = ">= 3.0.0"
    }
    aws = {
      source  = "hashicorp/aws"
      version = ">= 4.0.0"
    }
  }
}

provider "snowflake" {
  organization_name = var.snowflake_organization_name
  account_name      = var.snowflake_account_name
  user              = var.snowflake_user
  password          = var.snowflake_password
  role              = var.snowflake_role
  preview_features_enabled = [
    "snowflake_database_datasource",
    "snowflake_file_format_resource",
    "snowflake_table_resource",
    "snowflake_storage_integration_resource",
    "snowflake_stage_resource",
    "snowflake_pipe_resource"
  ]
}