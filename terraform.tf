provider "azurerm" {
  features {}
}

variable "location" {
  default = "eastus"
}

# Resource Group
resource "azurerm_resource_group" "main" {
  name     = "ai-infra-rg"
  location = var.location
}

# VNet & Subnets
resource "azurerm_virtual_network" "main" {
  name                = "central-vnet"
  address_space       = ["10.0.0.0/16"]
  location            = var.location
  resource_group_name = azurerm_resource_group.main.name
}

resource "azurerm_subnet" "bastion" {
  name                 = "BastionSubnet"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = ["10.0.0.0/24"]
}

resource "azurerm_subnet" "firewall" {
  name                 = "AzureFirewallSubnet"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = ["10.0.1.0/24"]
}

resource "azurerm_subnet" "vm" {
  name                 = "VMSubnet"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = ["10.0.2.0/24"]
}

resource "azurerm_subnet" "storage" {
  name                 = "StorageSubnet"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = ["10.0.3.0/24"]
}

# NSG and association
resource "azurerm_network_security_group" "vm_nsg" {
  name                = "vm-nsg"
  location            = var.location
  resource_group_name = azurerm_resource_group.main.name

  security_rule {
    name                       = "AllowInternal"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "*"
    source_address_prefix      = "10.0.0.0/16"
    destination_address_prefix = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
  }
}

resource "azurerm_subnet_network_security_group_association" "vm" {
  subnet_id                 = azurerm_subnet.vm.id
  network_security_group_id = azurerm_network_security_group.vm_nsg.id
}

# Azure Bastion
resource "azurerm_public_ip" "bastion" {
  name                = "bastion-ip"
  resource_group_name = azurerm_resource_group.main.name
  location            = var.location
  allocation_method   = "Static"
  sku                 = "Standard"
}

resource "azurerm_bastion_host" "bastion" {
  name                = "bastion-host"
  location            = var.location
  resource_group_name = azurerm_resource_group.main.name

  dns_name            = "ai-bastion-host"
  ip_configuration {
    name                 = "bastion-ipconfig"
    subnet_id            = azurerm_subnet.bastion.id
    public_ip_address_id = azurerm_public_ip.bastion.id
  }
}

# Storage Account (ZRS, private access)
resource "azurerm_storage_account" "shared" {
  name                     = "aisharedstorage01"
  resource_group_name      = azurerm_resource_group.main.name
  location                 = var.location
  account_tier             = "Standard"
  account_replication_type = "ZRS"
  account_kind             = "StorageV2"
  enable_https_traffic_only = true
  allow_blob_public_access = false
  network_rules {
    default_action             = "Deny"
    bypass                    = ["AzureServices"]
    virtual_network_subnet_ids = [azurerm_subnet.storage.id]
  }
}

resource "azurerm_storage_container" "ingress" {
  name                  = "ingress"
  storage_account_name  = azurerm_storage_account.shared.name
  container_access_type = "private"
}

resource "azurerm_storage_container" "egress" {
  name                  = "egress"
  storage_account_name  = azurerm_storage_account.shared.name
  container_access_type = "private"
}

resource "azurerm_storage_container" "standard" {
  name                  = "standard"
  storage_account_name  = azurerm_storage_account.shared.name
  container_access_type = "private"
}

# Main AI VM
resource "azurerm_windows_virtual_machine" "ai_vm" {
  name                = "main-ai-vm"
  resource_group_name = azurerm_resource_group.main.name
  location            = var.location
  size                = "Standard_NC48ads_A100_v4"
  admin_username      = "azureuser"
  admin_password      = "P@ssword1234!"
  network_interface_ids = [azurerm_network_interface.ai_nic.id]
  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Premium_LRS"
  }

  source_image_reference {
    publisher = "MicrosoftWindowsServer"
    offer     = "WindowsServer"
    sku       = "2022-datacenter"
    version   = "latest"
  }
}

resource "azurerm_network_interface" "ai_nic" {
  name                = "ai-vm-nic"
  location            = var.location
  resource_group_name = azurerm_resource_group.main.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.vm.id
    private_ip_address_allocation = "Dynamic"
  }
}

# Secondary Dev VM
resource "azurerm_windows_virtual_machine" "dev_vm" {
  name                = "dev-vm"
  resource_group_name = azurerm_resource_group.main.name
  location            = var.location
  size                = "Standard_FX24mds"
  admin_username      = "azureuser"
  admin_password      = "P@ssword1234!"
  network_interface_ids = [azurerm_network_interface.dev_nic.id]
  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Premium_LRS"
  }

  source_image_reference {
    publisher = "MicrosoftWindowsServer"
    offer     = "WindowsServer"
    sku       = "2022-datacenter"
    version   = "latest"
  }
}

resource "azurerm_network_interface" "dev_nic" {
  name                = "dev-vm-nic"
  location            = var.location
  resource_group_name = azurerm_resource_group.main.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.vm.id
    private_ip_address_allocation = "Dynamic"
  }
}
