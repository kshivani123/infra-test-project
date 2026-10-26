# Attaches ci-policy.json to the ci user created in task3-iam/account-a.
# Kept as a plain JSON file so it can be reviewed / diffed on its own.

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
  region              = "ap-south-1"
  allowed_account_ids = ["000000000000"]
}

data "aws_iam_user" "ci" {
  user_name = "ci"
}

resource "aws_iam_policy" "ci_deploy" {
  name        = "ci-payments-api-deploy"
  description = "Push payments-api image, roll the ECS service, read build artifacts"
  policy      = file("${path.module}/ci-policy.json")
}

resource "aws_iam_user_policy_attachment" "ci_deploy" {
  user       = data.aws_iam_user.ci.user_name
  policy_arn = aws_iam_policy.ci_deploy.arn
}
