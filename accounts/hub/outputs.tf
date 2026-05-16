output "vpc_id" {
  value       = module.vpc.vpc_id
  description = "Hub VPC ID"
}

output "tgw_id" {
  value       = aws_ec2_transit_gateway.this.id
  description = "Transit Gateway ID — used by spoke accounts to create attachments"
}

output "tgw_route_table_id" {
  value       = aws_ec2_transit_gateway_route_table.main.id
  description = "TGW main route table ID — used by hub phase 2 to associate spoke attachments"
}

output "nat_gateway_id" {
  value       = aws_nat_gateway.this.id
  description = "NAT Gateway ID — all spoke internet egress passes through this"
}

output "public_subnet_ids" {
  value       = module.vpc.public_subnet_ids
  description = "Public subnet IDs (where NAT GW lives)"
}

output "tgw_subnet_ids" {
  value       = module.vpc.tgw_subnet_ids
  description = "TGW attachment subnet IDs"
}
