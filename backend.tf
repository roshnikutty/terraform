terraform {
  backend "s3" {
    bucket = "terraform-test-state91"
    key    = "snowpipe/terraform.tfstate"
    region = "us-east-1"
  }
}
