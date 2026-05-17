variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "project_name" {
  type    = string
  default = "aws-network-poc"
}

variable "owner" {
  type = string
}

variable "profile" {
  type        = string
  default     = null
  description = "AWS CLI profile to use for authentication. When null, uses the default credential chain (env vars, instance profile, etc.)"
}

