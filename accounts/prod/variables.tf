variable "aws_region" {
  type        = string
  default     = "us-east-1"
  description = "AWS region for all resources"
}

variable "prod_account_id" {
  type        = string
  description = "AWS Account ID of the prod spoke account"
}

variable "owner" {
  type        = string
  description = "Owner tag applied to all resources"
}

variable "state_bucket" {
  type        = string
  description = "S3 bucket name for Terraform remote state (same bucket as hub, different key)"
}

variable "profile" {
  type        = string
  default     = null
  description = "AWS CLI profile usado como credencial base para o assume_role. Use ct8-hub pois a trust policy da role prod permite o root da conta hub."
}
