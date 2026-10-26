# Account B - 111111111111

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

  allowed_account_ids = ["111111111111"]
}

variable "roleB_arn" {
  description = "Exact ARN of roleB in account A. The only principal allowed to assume roleC."
  type        = string
  default     = "arn:aws:iam::000000000000:role/roleB"
}

variable "bucket_name" {
  type    = string
  default = "acme-shared-data-111111111111"
}

resource "aws_s3_bucket" "shared" {
  bucket = var.bucket_name
}

resource "aws_s3_bucket_public_access_block" "shared" {
  bucket = aws_s3_bucket.shared.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "shared" {
  bucket = aws_s3_bucket.shared.id

  versioning_configuration {
    status = "Enabled"
  }
}

# Trust: roleB's ARN, not account A's root. See NOTES.md (task 3, Q2).
data "aws_iam_policy_document" "roleC_trust" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "AWS"
      identifiers = [var.roleB_arn]
    }
  }
}

# "Full access" to one bucket - every S3 action, but only on this bucket and
# its objects. No ListAllMyBuckets, nothing on any other bucket.
data "aws_iam_policy_document" "roleC" {
  statement {
    sid     = "FullAccessToSharedBucket"
    actions = ["s3:*"]
    resources = [
      aws_s3_bucket.shared.arn,
      "${aws_s3_bucket.shared.arn}/*",
    ]
  }
}

resource "aws_iam_role" "roleC" {
  name                 = "roleC"
  assume_role_policy   = data.aws_iam_policy_document.roleC_trust.json
  max_session_duration = 3600
}

resource "aws_iam_role_policy" "roleC" {
  name   = "s3-${var.bucket_name}"
  role   = aws_iam_role.roleC.name
  policy = data.aws_iam_policy_document.roleC.json
}

output "roleC_arn" {
  value = aws_iam_role.roleC.arn
}
