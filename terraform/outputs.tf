output "resource_group_name" {
  description = "Name of the resource group holding the stack."
  value       = azurerm_resource_group.this.name
}

output "vnet_id" {
  description = "Resource ID of the virtual network."
  value       = azurerm_virtual_network.this.id
}

output "subnet_id" {
  description = "Resource ID of the workload subnet."
  value       = azurerm_subnet.this.id
}

output "vm_name" {
  description = "Name of the VM, or null when create_vm = false."
  value       = one(azurerm_linux_virtual_machine.this[*].name)
}

output "public_ip_address" {
  description = "Public IP of the VM, or null when create_vm = false."
  value       = one(azurerm_public_ip.this[*].ip_address)
}

output "ssh_command" {
  description = "Ready-to-paste SSH command, or null when create_vm = false."
  value       = var.create_vm ? "ssh ${var.admin_username}@${one(azurerm_public_ip.this[*].ip_address)}" : null
}
