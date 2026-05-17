variable "aws_region" {
  type        = string
  default     = "us-east-1"
  description = "AWS region for all resources"
}

variable "hub_account_id" {
  type        = string
  description = "AWS Account ID of the hub account"
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
  description = "S3 bucket name for Terraform remote state"
}

variable "profile" {
  type        = string
  default     = null
  description = "AWS CLI profile usado como credencial base para o assume_role. Quando null usa a chain padrão."
}

variable "dev_tgw_attachment_done" {
  type        = bool
  default     = false
  description = "Set to true after accounts/dev is applied to add TGW route and association for dev spoke"
}
