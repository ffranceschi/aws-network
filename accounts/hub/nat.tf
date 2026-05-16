resource "aws_eip" "nat" {
  domain = "vpc"

  tags = { Name = "hub-nat-eip" }

  depends_on = [module.vpc]
}

resource "aws_nat_gateway" "this" {
  allocation_id = aws_eip.nat.id
  subnet_id     = module.vpc.public_subnet_ids[0]

  tags = { Name = "hub-nat-gw" }
}
