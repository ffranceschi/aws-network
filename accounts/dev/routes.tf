# rt-workload: workload-a and workload-b subnets
resource "aws_route_table" "workload" {
  vpc_id = module.vpc.vpc_id

  tags = { Name = "dev-rt-workload" }
}

resource "aws_route" "workload_to_hub" {
  route_table_id         = aws_route_table.workload.id
  destination_cidr_block = "10.0.0.0/16"
  transit_gateway_id     = data.terraform_remote_state.hub.outputs.tgw_id

  depends_on = [module.tgw_spoke]
}

resource "aws_route" "workload_default" {
  route_table_id         = aws_route_table.workload.id
  destination_cidr_block = "0.0.0.0/0"
  transit_gateway_id     = data.terraform_remote_state.hub.outputs.tgw_id

  depends_on = [module.tgw_spoke]
}

resource "aws_route_table_association" "workload" {
  count          = length(module.vpc.workload_subnet_ids)
  subnet_id      = module.vpc.workload_subnet_ids[count.index]
  route_table_id = aws_route_table.workload.id
}

# rt-tgw-attachment: local only — TGW manages routing at this boundary
resource "aws_route_table" "tgw_attachment" {
  vpc_id = module.vpc.vpc_id

  tags = { Name = "dev-rt-tgw-attachment" }
}

resource "aws_route_table_association" "tgw_attachment" {
  count          = length(module.vpc.tgw_subnet_ids)
  subnet_id      = module.vpc.tgw_subnet_ids[count.index]
  route_table_id = aws_route_table.tgw_attachment.id
}

# NACL on TGW attachment subnets (stateless extra layer)
resource "aws_network_acl" "tgw_attachment" {
  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.tgw_subnet_ids

  ingress {
    rule_no    = 100
    protocol   = "-1"
    action     = "allow"
    cidr_block = "10.0.0.0/8"
    from_port  = 0
    to_port    = 0
  }

  ingress {
    rule_no    = 200
    protocol   = "tcp"
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 1024
    to_port    = 65535
  }

  # ICMP return traffic (ping responses from internet)
  ingress {
    rule_no    = 300
    protocol   = "icmp"
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = -1
    to_port    = -1
    icmp_type  = -1
    icmp_code  = -1
  }

  egress {
    rule_no    = 100
    protocol   = "-1"
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 0
    to_port    = 0
  }

  tags = { Name = "dev-nacl-tgw-attachment" }
}
