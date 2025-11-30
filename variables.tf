
variable "environment" {
  description = "Environment name"
  type        = string
  default     = "dev"
}

variable "s3_bucket_name" {
  description = "S3 bucket name for Snowpipe data"
  type        = string
}

variable "s3_prefix" {
  description = "S3 prefix/folder path for data files"
  type        = string
}