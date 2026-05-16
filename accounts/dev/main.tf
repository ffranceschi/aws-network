module "vpc" {
  source = "../../modules/vpc"

  vpc_cidr    = "10.10.0.0/16"
  environment = "dev"
  azs         = ["${var.aws_region}a", "${var.aws_region}b"]

  tgw_subnet_cidrs      = ["10.10.2.0/28", "10.10.3.0/28"]
  workload_subnet_cidrs = ["10.10.0.0/24", "10.10.1.0/24"]

  enable_igw = false
}
