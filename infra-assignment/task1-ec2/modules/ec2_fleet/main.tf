data "aws_ssm_parameter" "al2023" {
  count = var.ami_id == null ? 1 : 0
  name  = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

locals {
  ami_id = var.ami_id != null ? var.ami_id : data.aws_ssm_parameter.al2023[0].insecure_value

  # lifecycle.prevent_destroy only accepts a literal - it can't be set from
  # each.value. So instead of one resource with a per-key flag, the same map is
  # split in two: protected entries go to their own resource block that has
  # prevent_destroy = true. Both are still driven by var.instances.
  regular   = { for name, cfg in var.instances : name => cfg if !cfg.protected }
  protected = { for name, cfg in var.instances : name => cfg if cfg.protected }

  all_instances = merge(aws_instance.this, aws_instance.protected)
}

resource "aws_instance" "this" {
  for_each = local.regular

  ami                    = local.ami_id
  instance_type          = each.value.instance_type
  key_name               = each.value.key_name
  subnet_id              = coalesce(each.value.subnet_id, var.subnet_id)
  vpc_security_group_ids = var.vpc_security_group_ids

  metadata_options {
    http_tokens = "required" # IMDSv2 only
  }

  root_block_device {
    volume_type = each.value.root_volume.type
    volume_size = each.value.root_volume.size
    iops        = each.value.root_volume.iops
    throughput  = each.value.root_volume.throughput
    encrypted   = true

    tags = {
      Name        = "${each.key}-root"
      Environment = var.environment
      Owner       = var.owner
    }
  }

  # required tags go last so a per-instance tag can't overwrite them
  tags = merge(each.value.tags, {
    Name        = each.key
    Environment = var.environment
    Owner       = var.owner
  })

  lifecycle {
    # the SSM parameter moves every time AWS publishes a new AL2023 build;
    # without this every plan after a release would want to replace the boxes
    ignore_changes = [ami]
  }
}

resource "aws_instance" "protected" {
  for_each = local.protected

  ami                    = local.ami_id
  instance_type          = each.value.instance_type
  key_name               = each.value.key_name
  subnet_id              = coalesce(each.value.subnet_id, var.subnet_id)
  vpc_security_group_ids = var.vpc_security_group_ids

  # prevent_destroy only stops terraform. This stops the console / CLI too.
  disable_api_termination = true

  metadata_options {
    http_tokens = "required"
  }

  root_block_device {
    volume_type           = each.value.root_volume.type
    volume_size           = each.value.root_volume.size
    iops                  = each.value.root_volume.iops
    throughput            = each.value.root_volume.throughput
    encrypted             = true
    delete_on_termination = false # keep the data even if the instance does go

    tags = {
      Name        = "${each.key}-root"
      Environment = var.environment
      Owner       = var.owner
    }
  }

  tags = merge(each.value.tags, {
    Name        = each.key
    Environment = var.environment
    Owner       = var.owner
  })

  lifecycle {
    prevent_destroy = true
    ignore_changes  = [ami]
  }
}
