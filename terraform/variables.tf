variable "subscription_id" {
  description = "Azure subscription ID to deploy into. Required by the azurerm v4 provider."
  type        = string
}

variable "org_id" {
  description = "Your organization / tenant identifier. Threaded into resource tags so demo resources are traceable to an owner."
  type        = string
  default     = ""
}

variable "location" {
  description = "Azure region for all resources (e.g. eastus, westeurope)."
  type        = string
  default     = "eastus"
}

variable "name_prefix" {
  description = "Prefix for resource names. Keeps a stack's resources grouped and identifiable."
  type        = string
}

variable "vnet_cidr" {
  description = "CIDR block for the virtual network. A /24 is plenty for a minimal demo network."
  type        = string
  default     = "10.0.0.0/24"
}

variable "subnet_cidr" {
  description = "CIDR for the single workload subnet. Must fall within vnet_cidr."
  type        = string
  default     = "10.0.0.0/26"
}

variable "allowed_ssh_cidr" {
  description = <<-EOT
    Source CIDR permitted to reach SSH (port 22). Set this to your own IP (e.g. "203.0.113.4/32").
    Defaulting to "*" leaves SSH open to the entire internet — fine for a throwaway demo, a liability otherwise.
  EOT
  type        = string
  default     = "*"
}

variable "create_vm" {
  description = "Whether to deploy the public IP + NIC + Linux VM. Set false for a network-only stack (VNet + subnet + NSG)."
  type        = bool
  default     = true
}

variable "admin_username" {
  description = "Admin username for the Linux VM."
  type        = string
  default     = "azureuser"
}

variable "admin_ssh_public_key" {
  description = "SSH public key contents (e.g. from ~/.ssh/id_ed25519.pub) for VM login. Password auth is disabled. Required when create_vm = true."
  type        = string
  default     = ""
}

variable "vm_size" {
  description = "VM size. B-series burstable is cheapest for light/dev workloads (B1s ~ 1 vCPU / 1 GiB)."
  type        = string
  default     = "Standard_B1s"
}

variable "os_disk_type" {
  description = "Managed OS disk SKU. Standard_LRS (HDD) is the lowest cost; StandardSSD_LRS / Premium_LRS cost more."
  type        = string
  default     = "Standard_LRS"
}

variable "vm_image" {
  description = "Source platform image for the VM (publisher/offer/sku/version)."
  type = object({
    publisher = string
    offer     = string
    sku       = string
    version   = string
  })
  default = {
    publisher = "Canonical"
    offer     = "ubuntu-24_04-lts"
    sku       = "server"
    version   = "latest"
  }
}

variable "tags" {
  description = "Tags merged onto every taggable resource (azurerm has no provider-level default_tags)."
  type        = map(string)
  default     = {}
}
