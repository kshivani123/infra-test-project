output "instance_ids" {
  description = "Instance name => instance ID"
  value       = { for name, inst in local.all_instances : name => inst.id }
}

output "private_ips" {
  description = "Instance name => private IP"
  value       = { for name, inst in local.all_instances : name => inst.private_ip }
}
