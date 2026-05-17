terraform {
  backend "s3" {
    key          = "hub/terraform.tfstate"
    encrypt      = true
    use_lockfile = true
  }
}
