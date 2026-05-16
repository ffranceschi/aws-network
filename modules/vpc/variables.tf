variable "vpc_cidr" {
  type        = string
  description = "CIDR block for the VPC"
}

variable "environment" {
  type        = string
  description = "Environment name (hub, dev, prod) — used as prefix for resource names"
}

variable "azs" {
  type        = list(string)
  description = "List of availability zones. Must match the length of each subnet CIDR list provided"
}

variable "public_subnet_cidrs" {
  type        = list(string)
  default     = []
  description = "CIDRs for public subnets (NAT GW, IGW). Must have same length as azs when provided"
}

variable "tgw_subnet_cidrs" {
  type        = list(string)
  description = "CIDRs for Transit Gateway attachment subnets. Must have same length as azs"
}

variable "workload_subnet_cidrs" {
  type        = list(string)
  default     = []
  description = "CIDRs for workload subnets. Must have same length as azs when provided"
}

variable "enable_igw" {
  type        = bool
  default     = false
  description = "Whether to create an Internet Gateway. Set true for hub account, false for spoke accounts"
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "Additional tags to apply to all resources"
}
