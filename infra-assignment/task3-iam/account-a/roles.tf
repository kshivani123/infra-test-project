############################
# roleA - admin, minus IAM
############################
# Trusted by the two group2 users directly (not the account root), MFA required.

data "aws_iam_policy_document" "roleA_trust" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "AWS"
      identifiers = [for u in aws_iam_user.console : u.arn]
    }

    condition {
      test     = "Bool"
      variable = "aws:MultiFactorAuthPresent"
      values   = ["true"]
    }
  }
}

# Allow + NotAction instead of AdministratorAccess + Deny iam:*.
# A blanket Deny would also kill iam:PassRole, and then you can't launch an
# EC2 instance with a profile, create a Lambda, an ECS service... which makes
# "admin" pretty useless. So: everything outside IAM, plus the handful of
# read / pass actions that other services need to function. Nothing here can
# create or change users, roles or policies.
data "aws_iam_policy_document" "roleA" {
  statement {
    sid         = "AllExceptIAM"
    not_actions = ["iam:*"]
    resources   = ["*"]
  }

  statement {
    sid = "IAMBitsOtherServicesNeed"
    actions = [
      "iam:PassRole",
      "iam:GetRole",
      "iam:ListRoles",
      "iam:ListInstanceProfiles",
      "iam:CreateServiceLinkedRole",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role" "roleA" {
  name                 = "roleA"
  assume_role_policy   = data.aws_iam_policy_document.roleA_trust.json
  max_session_duration = 3600
}

resource "aws_iam_role_policy" "roleA" {
  name   = "admin-except-iam"
  role   = aws_iam_role.roleA.name
  policy = data.aws_iam_policy_document.roleA.json
}

############################
# roleB - can only hop to roleC in account B
############################
# Who uses it: the engine service account. It's the workload that needs the
# shared bucket in account B.

data "aws_iam_policy_document" "roleB_trust" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "AWS"
      identifiers = [aws_iam_user.programmatic["engine"].arn]
    }
  }
}

data "aws_iam_policy_document" "roleB" {
  statement {
    sid       = "AssumeRoleCInAccountB"
    actions   = ["sts:AssumeRole"]
    resources = ["arn:aws:iam::${local.account_b_id}:role/roleC"]
  }
}

resource "aws_iam_role" "roleB" {
  name                 = "roleB"
  assume_role_policy   = data.aws_iam_policy_document.roleB_trust.json
  max_session_duration = 3600
}

resource "aws_iam_role_policy" "roleB" {
  name   = "assume-roleC-only"
  role   = aws_iam_role.roleB.name
  policy = data.aws_iam_policy_document.roleB.json
}

# Not strictly needed (same-account trust naming the user is enough on its
# own) but it makes engine's permissions readable from the user side too.
resource "aws_iam_user_policy" "engine_assume_roleB" {
  name = "assume-roleB"
  user = aws_iam_user.programmatic["engine"].name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "sts:AssumeRole"
      Resource = aws_iam_role.roleB.arn
    }]
  })
}
