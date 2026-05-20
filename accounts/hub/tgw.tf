resource "aws_ec2_transit_gateway" "this" {
  description                     = "Hub Transit Gateway"
  default_route_table_association = "disable"
  default_route_table_propagation = "disable"
  auto_accept_shared_attachments  = "enable"
  dns_support                     = "enable"

  tags = { Name = "hub-tgw" }
}

# Hub route table — associada ao hub attachment; contém rotas para os spokes
resource "aws_ec2_transit_gateway_route_table" "main" {
  transit_gateway_id = aws_ec2_transit_gateway.this.id

  tags = { Name = "hub-tgw-rt-hub" }
}

# Dev route table — associada ao dev attachment; rotas apenas para o hub (sem rota para prod)
resource "aws_ec2_transit_gateway_route_table" "dev" {
  transit_gateway_id = aws_ec2_transit_gateway.this.id

  tags = { Name = "hub-tgw-rt-dev" }
}

resource "aws_ec2_transit_gateway_route" "dev_to_hub" {
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.dev.id
  destination_cidr_block         = "10.0.0.0/16"
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.hub.id
}

resource "aws_ec2_transit_gateway_route" "dev_default" {
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.dev.id
  destination_cidr_block         = "0.0.0.0/0"
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.hub.id
}

# Prod route table — associada ao prod attachment; rotas apenas para o hub (sem rota para dev)
resource "aws_ec2_transit_gateway_route_table" "prod" {
  transit_gateway_id = aws_ec2_transit_gateway.this.id

  tags = { Name = "hub-tgw-rt-prod" }
}

resource "aws_ec2_transit_gateway_route" "prod_to_hub" {
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.prod.id
  destination_cidr_block         = "10.0.0.0/16"
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.hub.id
}

resource "aws_ec2_transit_gateway_route" "prod_default" {
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.prod.id
  destination_cidr_block         = "0.0.0.0/0"
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.hub.id
}

resource "aws_ec2_transit_gateway_vpc_attachment" "hub" {
  transit_gateway_id = aws_ec2_transit_gateway.this.id
  vpc_id             = module.vpc.vpc_id
  subnet_ids         = module.vpc.tgw_subnet_ids

  transit_gateway_default_route_table_association = false
  transit_gateway_default_route_table_propagation = false

  tags = { Name = "hub-tgw-attachment" }
}

resource "aws_ec2_transit_gateway_route_table_association" "hub" {
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.hub.id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.main.id
}

# Phase 2: added after accounts/dev is applied
# Route table association MUST be done by hub (TGW owner) not by spoke account
data "terraform_remote_state" "dev" {
  count   = var.dev_tgw_attachment_done ? 1 : 0
  backend = "s3"
  config = {
    bucket  = var.state_bucket
    key     = "dev/terraform.tfstate"
    region  = var.aws_region
    encrypt = true
  }
}

resource "aws_ec2_transit_gateway_route_table_association" "dev" {
  count                          = var.dev_tgw_attachment_done ? 1 : 0
  transit_gateway_attachment_id  = data.terraform_remote_state.dev[0].outputs.tgw_attachment_id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.dev.id
}

resource "aws_ec2_transit_gateway_route" "to_dev_vpc" {
  count                          = var.dev_tgw_attachment_done ? 1 : 0
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.main.id
  destination_cidr_block         = "10.10.0.0/16"
  transit_gateway_attachment_id  = data.terraform_remote_state.dev[0].outputs.tgw_attachment_id
}

# Phase 2: added after accounts/prod is applied
# Route table association MUST be done by hub (TGW owner) not by spoke account
data "terraform_remote_state" "prod" {
  count   = var.prod_tgw_attachment_done ? 1 : 0
  backend = "s3"
  config = {
    bucket  = var.state_bucket
    key     = "prod/terraform.tfstate"
    region  = var.aws_region
    encrypt = true
  }
}

resource "aws_ec2_transit_gateway_route_table_association" "prod" {
  count                          = var.prod_tgw_attachment_done ? 1 : 0
  transit_gateway_attachment_id  = data.terraform_remote_state.prod[0].outputs.tgw_attachment_id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.prod.id
}

resource "aws_ec2_transit_gateway_route" "to_prod_vpc" {
  count                          = var.prod_tgw_attachment_done ? 1 : 0
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.main.id
  destination_cidr_block         = "10.11.0.0/16"
  transit_gateway_attachment_id  = data.terraform_remote_state.prod[0].outputs.tgw_attachment_id
}

# Blackhole routes — spoke-to-spoke traffic is explicitly dropped
resource "aws_ec2_transit_gateway_route" "dev_blackhole_prod" {
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.dev.id
  destination_cidr_block         = "10.11.0.0/16"
  blackhole                      = true
}

resource "aws_ec2_transit_gateway_route" "prod_blackhole_dev" {
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.prod.id
  destination_cidr_block         = "10.10.0.0/16"
  blackhole                      = true
}
