output "vpc_id" {
  value       = module.vpc.vpc_id
  description = "Dev VPC ID"
}

output "tgw_attachment_id" {
  value       = module.tgw_spoke.attachment_id
  description = "TGW attachment ID — read by hub account in phase 2 to add route table association and static route"
}

output "workload_subnet_ids" {
  value       = module.vpc.workload_subnet_ids
  description = "Workload subnet IDs — use for deploying resources"
}
