# rt-public: public-a and public-b subnets
resource "aws_route_table" "public" {
  vpc_id = module.vpc.vpc_id

  tags = { Name = "hub-rt-public" }
}

resource "aws_route" "public_igw" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = module.vpc.igw_id
}

# Pre-created unconditionally: this return route must exist before dev traffic
# arrives via NAT, so it cannot be gated on dev_tgw_attachment_done.
resource "aws_route" "public_to_dev" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "10.10.0.0/16"
  transit_gateway_id     = aws_ec2_transit_gateway.this.id

  depends_on = [aws_ec2_transit_gateway_vpc_attachment.hub]
}

# Pre-created unconditionally: this return route must exist before prod traffic
# arrives via NAT, so it cannot be gated on prod_tgw_attachment_done.
resource "aws_route" "public_to_prod" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "10.11.0.0/16"
  transit_gateway_id     = aws_ec2_transit_gateway.this.id

  depends_on = [aws_ec2_transit_gateway_vpc_attachment.hub]
}

resource "aws_route_table_association" "public" {
  count          = length(module.vpc.public_subnet_ids)
  subnet_id      = module.vpc.public_subnet_ids[count.index]
  route_table_id = aws_route_table.public.id
}

# rt-tgw-attachment: hub TGW attachment subnets
resource "aws_route_table" "tgw_attachment" {
  vpc_id = module.vpc.vpc_id

  tags = { Name = "hub-rt-tgw-attachment" }
}

resource "aws_route" "tgw_attachment_default" {
  route_table_id         = aws_route_table.tgw_attachment.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.this.id
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

  egress {
    rule_no    = 100
    protocol   = "-1"
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 0
    to_port    = 0
  }

  tags = { Name = "hub-nacl-tgw-attachment" }
}
