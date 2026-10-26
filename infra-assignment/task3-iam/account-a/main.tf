# Account A - 000000000000
# Apply this before account-b: roleC's trust policy references roleB, and IAM
# rejects a trust policy whose principal doesn't exist yet.

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
  region = "ap-south-1"

  allowed_account_ids = ["000000000000"] # fail fast if run with the wrong profile
}

locals {
  account_a_id = "000000000000"
  account_b_id = "111111111111"

  programmatic_users = ["engine", "ci"]
  console_users      = ["rahul.verma", "neha.joshi"]
}

variable "pgp_key" {
  description = <<-EOT
    Base64 public PGP key (or keybase:username). Used to encrypt the generated
    access-key secrets and console passwords so they don't sit in state in
    plain text.
  EOT
  type = string
}
