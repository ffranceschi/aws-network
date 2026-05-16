output "vpc_id" {
  value = aws_vpc.this.id
}

output "igw_id" {
  value = length(aws_internet_gateway.this) > 0 ? aws_internet_gateway.this[0].id : null
}

output "public_subnet_ids" {
  value = aws_subnet.public[*].id
}

output "tgw_subnet_ids" {
  value = aws_subnet.tgw[*].id
}

output "workload_subnet_ids" {
  value = aws_subnet.workload[*].id
}
