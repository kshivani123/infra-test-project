variable "environment" {
  description = "Value for the Environment tag (e.g. staging, prod)."
  type        = string
}

variable "owner" {
  description = "Value for the Owner tag. Team or person accountable for these instances."
  type        = string
}

variable "subnet_id" {
  description = "Default subnet. Individual instances can override it."
  type        = string
}

variable "vpc_security_group_ids" {
  type    = list(string)
  default = []
}

variable "ami_id" {
  description = "AMI to use. Leave null to pick up the latest Amazon Linux 2023 from SSM."
  type        = string
  default     = null
}

# One entry per instance. The map key is used as the Name tag and as the
# key in the outputs, so keep it stable - renaming a key means a new instance.
variable "instances" {
  type = map(object({
    instance_type = string
    key_name      = string

    root_volume = object({
      type       = string
      size       = number
      iops       = optional(number)
      throughput = optional(number)
    })

    # true => instance goes into the prevent_destroy resource (see main.tf)
    protected = optional(bool, false)

    subnet_id = optional(string)
    tags      = optional(map(string), {})
  }))

  validation {
    # st1/sc1 are valid EBS types but can't be used as a boot volume
    condition = alltrue([
      for i in values(var.instances) :
      contains(["gp2", "gp3", "io1", "io2", "standard"], i.root_volume.type)
    ])
    error_message = "root_volume.type must be gp2, gp3, io1, io2 or standard (st1/sc1 are not bootable)."
  }

  validation {
    condition = alltrue([
      for i in values(var.instances) :
      !contains(["io1", "io2"], i.root_volume.type) || i.root_volume.iops != null
    ])
    error_message = "io1/io2 root volumes need iops set."
  }

  validation {
    condition = alltrue([
      for i in values(var.instances) :
      i.root_volume.throughput == null || i.root_volume.type == "gp3"
    ])
    error_message = "throughput can only be set on gp3 volumes."
  }
}
