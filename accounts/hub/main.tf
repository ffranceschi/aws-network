module "vpc" {
  source = "../../modules/vpc"

  vpc_cidr    = "10.0.0.0/16"
  environment = "hub"
  azs         = ["${var.aws_region}a", "${var.aws_region}b"]

  public_subnet_cidrs = ["10.0.0.0/24", "10.0.1.0/24"]
  tgw_subnet_cidrs    = ["10.0.2.0/28", "10.0.3.0/28"]

  enable_igw = true

  tags = {
    Environment = "hub"
  }
}
