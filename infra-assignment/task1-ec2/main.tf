terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.40"
    }
  }
}

provider "aws" {
  region = var.region
}

module "ec2_fleet" {
  source = "./modules/ec2_fleet"

  environment            = var.environment
  owner                  = var.owner
  subnet_id              = var.subnet_id
  vpc_security_group_ids = var.vpc_security_group_ids
  instances              = var.instances
}
