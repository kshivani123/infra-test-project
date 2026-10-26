variable "region" {
  type    = string
  default = "ap-south-1"
}

variable "environment" {
  type = string
}

variable "owner" {
  type = string
}

variable "subnet_id" {
  type = string
}

variable "vpc_security_group_ids" {
  type    = list(string)
  default = []
}

# same shape as the module input - passed straight through
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
    protected = optional(bool, false)
    subnet_id = optional(string)
    tags      = optional(map(string), {})
  }))
}
