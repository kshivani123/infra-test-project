environment = "staging"
owner       = "platform-team"

# replace with real IDs from the target VPC
subnet_id              = "subnet-0a1b2c3d4e5f60718"
vpc_security_group_ids = ["sg-0123456789abcdef0"]

# key pairs are expected to exist already (one per role, so revoking one
# doesn't lock us out of everything)
instances = {
  bastion-01 = {
    instance_type = "t3.micro"
    key_name      = "stg-bastion"
    root_volume   = { type = "standard", size = 8 }
  }

  web-01 = {
    instance_type = "t3.small"
    key_name      = "stg-web"
    root_volume   = { type = "gp2", size = 20 }
  }

  app-01 = {
    instance_type = "m5.large"
    key_name      = "stg-app"
    root_volume   = { type = "gp3", size = 30, iops = 3000, throughput = 250 }
  }

  batch-01 = {
    instance_type = "c5.xlarge"
    key_name      = "stg-batch"
    root_volume   = { type = "io1", size = 50, iops = 2000 }
  }

  db-01 = {
    instance_type = "r5.large"
    key_name      = "stg-db"
    root_volume   = { type = "io2", size = 100, iops = 5000 }
    protected     = true
    tags          = { Backup = "daily" }
  }
}
