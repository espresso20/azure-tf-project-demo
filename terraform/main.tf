locals {
  # azurerm has no provider-level default_tags, so we merge this onto each
  # taggable resource below. Single source of truth for cross-cutting tags.
  # org_id is folded in here (when set) so demo resources trace back to an owner.
  common_tags = merge(
    var.tags,
    var.org_id == "" ? {} : { OrgId = var.org_id },
  )

  vm_count = var.create_vm ? 1 : 0
}

resource "azurerm_resource_group" "this" {
  name     = "${var.name_prefix}-rg"
  location = var.location
  tags     = local.common_tags
}

resource "azurerm_virtual_network" "this" {
  name                = "${var.name_prefix}-vnet"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  address_space       = [var.vnet_cidr]
  tags                = local.common_tags
}

resource "azurerm_subnet" "this" {
  # Subnets don't carry tags in azurerm — they inherit context from the VNet/RG.
  name                 = "${var.name_prefix}-subnet"
  resource_group_name  = azurerm_resource_group.this.name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = [var.subnet_cidr]
}

resource "azurerm_network_security_group" "this" {
  name                = "${var.name_prefix}-nsg"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  tags                = local.common_tags

  # Inbound SSH, scoped to allowed_ssh_cidr. Lock this to your own /32 in tfvars;
  # "*" exposes port 22 to the whole internet.
  security_rule {
    name                       = "allow-ssh-inbound"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = var.allowed_ssh_cidr
    destination_address_prefix = "*"
  }

  # Outbound internet is permitted by Azure's default rules — no explicit rule needed.
}

resource "azurerm_subnet_network_security_group_association" "this" {
  subnet_id                 = azurerm_subnet.this.id
  network_security_group_id = azurerm_network_security_group.this.id
}

# ── Compute (optional, gated by create_vm) ───────────────────────────────────
# Standard SKU + Static. Basic public IPs are retired (Azure, Sep 2025), so
# "Basic/dynamic to save money" no longer applies — Standard Static is the floor.
resource "azurerm_public_ip" "this" {
  count = local.vm_count

  name                = "${var.name_prefix}-pip"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = local.common_tags
}

resource "azurerm_network_interface" "this" {
  count = local.vm_count

  name                = "${var.name_prefix}-nic"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  tags                = local.common_tags

  ip_configuration {
    name                          = "primary"
    subnet_id                     = azurerm_subnet.this.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.this[count.index].id
  }
}

resource "azurerm_linux_virtual_machine" "this" {
  count = local.vm_count

  name                  = "${var.name_prefix}-vm"
  location              = azurerm_resource_group.this.location
  resource_group_name   = azurerm_resource_group.this.name
  size                  = var.vm_size
  admin_username        = var.admin_username
  network_interface_ids = [azurerm_network_interface.this[count.index].id]
  tags                  = local.common_tags

  admin_ssh_key {
    username   = var.admin_username
    public_key = var.admin_ssh_public_key
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = var.os_disk_type
  }

  source_image_reference {
    publisher = var.vm_image.publisher
    offer     = var.vm_image.offer
    sku       = var.vm_image.sku
    version   = var.vm_image.version
  }

  lifecycle {
    # Password auth is off — a VM with no SSH key would deploy but lock you out.
    # Catch it at plan time instead.
    precondition {
      condition     = trimspace(var.admin_ssh_public_key) != ""
      error_message = "admin_ssh_public_key must be set when create_vm = true (password auth is disabled)."
    }
  }
}
