output "roleA_arn" {
  value = aws_iam_role.roleA.arn
}

output "roleB_arn" {
  value = aws_iam_role.roleB.arn
}

# PGP-encrypted. Decrypt with:
#   terraform output -json access_keys | jq -r '.engine.secret' | base64 -d | gpg -d
output "access_keys" {
  value = {
    for name, k in aws_iam_access_key.programmatic : name => {
      id     = k.id
      secret = k.encrypted_secret
    }
  }
}

output "initial_passwords" {
  value = { for name, p in aws_iam_user_login_profile.console : name => p.encrypted_password }
}
