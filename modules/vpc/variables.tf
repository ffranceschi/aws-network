variable "vpc_cidr" {
  type = string
}

variable "environment" {
  type = string
}

variable "azs" {
  type = list(string)
}

variable "public_subnet_cidrs" {
  type    = list(string)
  default = []
}

variable "tgw_subnet_cidrs" {
  type = list(string)
}

variable "workload_subnet_cidrs" {
  type    = list(string)
  default = []
}

variable "enable_igw" {
  type    = bool
  default = false
}

variable "tags" {
  type    = map(string)
  default = {}
}
