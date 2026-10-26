# Added for Task 2. Bucket + table are created by ../task2-state-backend
# (that stack has to exist first). Backend blocks can't use variables, so the
# values are hardcoded here; for multiple envs I'd leave this block empty and
# pass -backend-config=envs/<env>.hcl at init time instead.
#
# Moving existing local state up:  terraform init -migrate-state

terraform {
  backend "s3" {
    bucket         = "acme-tfstate-000000000000-aps1"
    key            = "ec2-fleet/staging/terraform.tfstate"
    region         = "ap-south-1"
    dynamodb_table = "terraform-locks"
    encrypt        = true
  }
}
