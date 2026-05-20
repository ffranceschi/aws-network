terraform {
  required_version = ">= 1.10"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region  = var.aws_region
  profile = var.profile

  assume_role {
    role_arn = "arn:aws:iam::${var.prod_account_id}:role/TerraformExecutionRole"
  }

  default_tags {
    tags = {
      Project     = "aws-network-poc"
      ManagedBy   = "terraform"
      Environment = "prod"
      Owner       = var.owner
    }
  }
}
