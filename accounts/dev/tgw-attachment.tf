data "terraform_remote_state" "hub" {
  backend = "s3"
  config = {
    bucket  = var.state_bucket
    key     = "hub/terraform.tfstate"
    region  = var.aws_region
    encrypt = true
  }
}

module "tgw_spoke" {
  source = "../../modules/tgw-spoke"

  transit_gateway_id = data.terraform_remote_state.hub.outputs.tgw_id
  vpc_id             = module.vpc.vpc_id
  subnet_ids         = module.vpc.tgw_subnet_ids
  environment        = "dev"
}
