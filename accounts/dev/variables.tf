variable "aws_region" {
  type        = string
  default     = "us-east-1"
  description = "AWS region for all resources"
}

variable "dev_account_id" {
  type        = string
  description = "AWS Account ID of the dev spoke account"
}

variable "owner" {
  type        = string
  description = "Owner tag applied to all resources"
}

variable "state_bucket" {
  type        = string
  description = "S3 bucket name for Terraform remote state (same bucket as hub, different key)"
}

variable "lock_table" {
  type        = string
  description = "DynamoDB table name for Terraform state locking"
}
