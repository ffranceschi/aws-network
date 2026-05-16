variable "transit_gateway_id" {
  type        = string
  description = "ID of the Transit Gateway to attach to (shared via RAM from hub account)"
}

variable "vpc_id" {
  type        = string
  description = "VPC ID to attach to the Transit Gateway"
}

variable "subnet_ids" {
  type        = list(string)
  description = "List of subnet IDs for the TGW attachment ENIs (one per AZ)"
}

variable "environment" {
  type        = string
  description = "Environment name (dev, prod) — used as prefix for resource names"
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "Additional tags to apply to all resources"
}
