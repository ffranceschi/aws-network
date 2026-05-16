output "attachment_id" {
  value       = aws_ec2_transit_gateway_vpc_attachment.this.id
  description = "ID of the Transit Gateway VPC attachment — needed by hub account to add route table association and static routes"
}
