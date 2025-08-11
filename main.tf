
terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "=3.0.0"
    }
  }
}


provider "azurerm" {
  features {}
}

resource "azurerm_resource_group" "tf-rg-1" {
  name     = "r-group-1"
  location = "West Europe"
  tags = {
    environment = "dev"
  }
}

resource "azurerm_virtual_network" "tf-vn-1" {
  name                = "azure-vn-1"
  address_space       = ["10.0.0.0/16"]
  location            = azurerm_resource_group.tf-rg-1.location
  resource_group_name = azurerm_resource_group.tf-rg-1.name
}

resource "azurerm_subnet" "tf-sn-1" {
  name                 = "azure-sn-1"
  resource_group_name  = azurerm_resource_group.tf-rg-1.name
  virtual_network_name = azurerm_virtual_network.tf-vn-1.name
  address_prefixes     = ["10.0.1.0/24"]
}

resource "azurerm_subnet" "tf-sn-appgw" {
  name                 = "azure-sn-appgw"
  resource_group_name  = azurerm_resource_group.tf-rg-1.name
  virtual_network_name = azurerm_virtual_network.tf-vn-1.name
  address_prefixes     = ["10.0.2.0/24"]
}

variable "vm_count" {
  default = 2
}

resource "azurerm_public_ip" "tf-pip" {
  count               = var.vm_count
  name                = "azure-pip-${count.index + 1}"
  location            = azurerm_resource_group.tf-rg-1.location
  resource_group_name = azurerm_resource_group.tf-rg-1.name
  allocation_method   = "Static"
  sku                 = "Standard"
}

resource "azurerm_network_interface" "tf-nic" {
  count               = var.vm_count
  name                = "azure-nic-${count.index + 1}"
  location            = azurerm_resource_group.tf-rg-1.location
  resource_group_name = azurerm_resource_group.tf-rg-1.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.tf-sn-1.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.tf-pip[count.index].id
  }
}

resource "azurerm_network_security_group" "tf-nsg" {
  name                = "azure-nsg-ssh"
  location            = azurerm_resource_group.tf-rg-1.location
  resource_group_name = azurerm_resource_group.tf-rg-1.name

  security_rule {
    name                       = "SSH"
    priority                   = 1001
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

}

resource "azurerm_network_security_rule" "http" {
  name                        = "HTTP"
  priority                    = 1002
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "80"
  source_address_prefix       = "*"
  destination_address_prefix  = "*"
  resource_group_name         = azurerm_resource_group.tf-rg-1.name
  network_security_group_name = azurerm_network_security_group.tf-nsg.name
}

resource "azurerm_network_interface_security_group_association" "tf-nsg-assoc" {
  count                      = var.vm_count
  network_interface_id       = azurerm_network_interface.tf-nic[count.index].id
  network_security_group_id  = azurerm_network_security_group.tf-nsg.id
}

resource "azurerm_linux_virtual_machine" "tf-vm" {
  count               = var.vm_count
  name                = "azure-linux-vm-${count.index + 1}"
  resource_group_name = azurerm_resource_group.tf-rg-1.name
  location            = azurerm_resource_group.tf-rg-1.location
  size                = "Standard_B1s"
  admin_username      = "pathumdilhara"

  network_interface_ids = [
    azurerm_network_interface.tf-nic[count.index].id
  ]

  admin_ssh_key {
    username   = "pathumdilhara"
    public_key = file("~/.ssh/id_rsa.pub")
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-focal"
    sku       = "20_04-lts"
    version   = "latest"
  }
}

resource "azurerm_public_ip" "tf-ip-appgw" {
  name                = "appgw-public-ip"
  location            = azurerm_resource_group.tf-rg-1.location
  resource_group_name = azurerm_resource_group.tf-rg-1.name
  allocation_method   = "Static"
  sku                 = "Standard"
}


resource "azurerm_application_gateway" "tf-appgw" {
  name                = "appgw-1"
  location            = azurerm_resource_group.tf-rg-1.location
  resource_group_name = azurerm_resource_group.tf-rg-1.name
  sku {
    name     = "Standard_v2"
    tier     = "Standard_v2"
    capacity = 2
  }

  gateway_ip_configuration {
    name      = "appgw-ip-config"
    subnet_id = azurerm_subnet.tf-sn-appgw.id
  }

  frontend_port {
    name = "frontendPort"
    port = 80
  }

  frontend_ip_configuration {
    name                 = "frontendIP"
    public_ip_address_id = azurerm_public_ip.tf-ip-appgw.id
  }

  backend_address_pool {
  name = "backendPool"

   }

  backend_http_settings {
    name                  = "httpSettings"
    port                  = 80
    protocol              = "Http"
    cookie_based_affinity = "Disabled"
    request_timeout       = 30
  }

  http_listener {
    name                           = "listener"
    frontend_ip_configuration_name = "frontendIP"
    frontend_port_name             = "frontendPort"
    protocol                       = "Http"
  }

  request_routing_rule {
    name                       = "rule1"
    rule_type                  = "Basic"
    http_listener_name         = "listener"
    backend_address_pool_name  = "backendPool"
    backend_http_settings_name = "httpSettings"
  }
}

