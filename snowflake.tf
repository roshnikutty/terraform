terraform {
  required_providers {
    snowflake = {
      source  = "snowflakedb/snowflake"
      version = ">= 1.0.0"
    }
  }
}

provider "snowflake" {
  organization_name = var.snowflake_organization_name
  account_name      = var.snowflake_account_name
  user              = var.snowflake_user
  password          = var.snowflake_password
  role              = var.snowflake_role
}


variable "snowflake_password" {
  type      = string
  sensitive = true
}

variable "snowflake_user" {
  type = string
}

variable "snowflake_account_name" {
  type = string
}

variable "snowflake_organization_name" {
  type = string
}

variable "snowflake_role" {
  type    = string
  default = "ACCOUNTADMIN"
}