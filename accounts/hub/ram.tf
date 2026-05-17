resource "aws_ram_resource_share" "tgw" {
  name                      = "hub-tgw-share"
  allow_external_principals = true

  tags = { Name = "hub-tgw-share" }
}

resource "aws_ram_resource_association" "tgw" {
  resource_arn       = aws_ec2_transit_gateway.this.arn
  resource_share_arn = aws_ram_resource_share.tgw.arn
}

resource "aws_ram_principal_association" "dev" {
  principal          = "arn:aws:iam::${var.dev_account_id}:root"
  resource_share_arn = aws_ram_resource_share.tgw.arn
}
