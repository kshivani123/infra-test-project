############################
# group1 - CLI / API only
############################
# "Programmatic only" = access keys and no login profile. No console password
# is ever created for these users, so there's nothing to log in with.

resource "aws_iam_group" "group1" {
  name = "group1"
}

resource "aws_iam_user" "programmatic" {
  for_each = toset(local.programmatic_users)

  name = each.key
  tags = { AccessType = "programmatic" }
}

resource "aws_iam_user_group_membership" "programmatic" {
  for_each = aws_iam_user.programmatic

  user   = each.value.name
  groups = [aws_iam_group.group1.name]
}

resource "aws_iam_access_key" "programmatic" {
  for_each = aws_iam_user.programmatic

  user    = each.value.name
  pgp_key = var.pgp_key
}

# Only thing the group itself grants: rotating your own keys. Actual job
# permissions are per user (ci gets the task 4 policy, engine can assume roleB)
data "aws_iam_policy_document" "group1" {
  statement {
    sid = "RotateOwnAccessKeys"
    actions = [
      "iam:CreateAccessKey",
      "iam:DeleteAccessKey",
      "iam:UpdateAccessKey",
      "iam:ListAccessKeys",
      "iam:GetAccessKeyLastUsed",
    ]
    # $$ so terraform leaves ${aws:username} for IAM to resolve
    resources = ["arn:aws:iam::${local.account_a_id}:user/$${aws:username}"]
  }
}

resource "aws_iam_group_policy" "group1" {
  name   = "self-service-keys"
  group  = aws_iam_group.group1.name
  policy = data.aws_iam_policy_document.group1.json
}

############################
# group2 - console + CLI
############################

resource "aws_iam_group" "group2" {
  name = "group2"
}

resource "aws_iam_user" "console" {
  for_each = toset(local.console_users)

  name = each.key
  tags = { AccessType = "console+cli" }
}

resource "aws_iam_user_group_membership" "console" {
  for_each = aws_iam_user.console

  user   = each.value.name
  groups = [aws_iam_group.group2.name]
}

resource "aws_iam_user_login_profile" "console" {
  for_each = aws_iam_user.console

  user                    = each.value.name
  pgp_key                 = var.pgp_key
  password_reset_required = true

  lifecycle {
    # once they change their password, don't fight them over it
    ignore_changes = [password_reset_required, password_length]
  }
}

# CLI: these users create their own keys after first login (allowed below),
# so no secret for them ends up in terraform state.
#
# Permissions: they can manage their own password/keys/MFA, and that's it
# until MFA is on. The real work happens by assuming roleA.
data "aws_iam_policy_document" "group2" {
  statement {
    sid = "ManageOwnCredentials"
    actions = [
      "iam:GetUser",
      "iam:ChangePassword",
      "iam:GetAccountPasswordPolicy",
      "iam:CreateAccessKey",
      "iam:DeleteAccessKey",
      "iam:UpdateAccessKey",
      "iam:ListAccessKeys",
      "iam:GetAccessKeyLastUsed",
      "iam:ListMFADevices",
      "iam:EnableMFADevice",
      "iam:ResyncMFADevice",
      "iam:DeactivateMFADevice",
    ]
    resources = ["arn:aws:iam::${local.account_a_id}:user/$${aws:username}"]
  }

  statement {
    sid = "ManageOwnVirtualMFA"
    actions = [
      "iam:CreateVirtualMFADevice",
      "iam:DeleteVirtualMFADevice",
    ]
    resources = ["arn:aws:iam::${local.account_a_id}:mfa/*"]
  }

  statement {
    sid       = "ListVirtualMFA"
    actions   = ["iam:ListVirtualMFADevices"]
    resources = ["*"]
  }

  statement {
    sid       = "AssumeAdminRole"
    actions   = ["sts:AssumeRole"]
    resources = [aws_iam_role.roleA.arn]
  }

  # Without MFA you can only set MFA up. GetSessionToken is excluded so the
  # CLI can still get MFA-backed session creds.
  statement {
    sid    = "DenyEverythingElseWithoutMFA"
    effect = "Deny"
    not_actions = [
      "iam:GetUser",
      "iam:ChangePassword",
      "iam:GetAccountPasswordPolicy",
      "iam:CreateVirtualMFADevice",
      "iam:EnableMFADevice",
      "iam:ListMFADevices",
      "iam:ListVirtualMFADevices",
      "iam:ResyncMFADevice",
      "sts:GetSessionToken",
    ]
    resources = ["*"]

    condition {
      test     = "BoolIfExists"
      variable = "aws:MultiFactorAuthPresent"
      values   = ["false"]
    }
  }
}

resource "aws_iam_group_policy" "group2" {
  name   = "self-service-and-assume-admin"
  group  = aws_iam_group.group2.name
  policy = data.aws_iam_policy_document.group2.json
}
