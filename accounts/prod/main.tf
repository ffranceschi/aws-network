module "vpc" {
  source = "../../modules/vpc"

  vpc_cidr    = "10.11.0.0/16"
  environment = "prod"
  azs         = ["${var.aws_region}a", "${var.aws_region}b"]

  tgw_subnet_cidrs      = ["10.11.2.0/28", "10.11.3.0/28"]
  workload_subnet_cidrs = ["10.11.0.0/24", "10.11.1.0/24"]

  enable_igw = false
}
