# Fixed version of the roleB -> roleC snippet. Lives in account B
# (111111111111). What was wrong is in NOTES.md, task 5.

variable "shared_bucket_name" {
  type    = string
  default = "acme-shared-data-111111111111"
}

data "aws_iam_policy_document" "roleC_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type = "AWS"
      # was .../user/roleB - roleB is a role, so the ARN is .../role/roleB
      identifiers = ["arn:aws:iam::000000000000:role/roleB"]
    }
  }
}

resource "aws_iam_role" "roleC" {
  name               = "roleC"
  assume_role_policy = data.aws_iam_policy_document.roleC_trust.json
}

resource "aws_iam_role_policy" "roleC_s3" {
  name = "roleC-s3-access"
  role = aws_iam_role.roleC.name # was a pasted markdown link, not HCL

  # was s3:* on "*" - task says one named bucket
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = "s3:*"
      Resource = [
        "arn:aws:s3:::${var.shared_bucket_name}",
        "arn:aws:s3:::${var.shared_bucket_name}/*",
      ]
    }]
  })
}

# Reminder: this is only half of a cross-account assume. roleB in account A
# also needs sts:AssumeRole on this role's ARN in its own permissions
# (see task3-iam/account-a/roles.tf). Both sides have to say yes.
