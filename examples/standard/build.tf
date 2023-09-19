module "rg" {
  source = "cyber-scot/rg/azurerm"

  name     = "rg-${var.short}-${var.loc}-${var.env}-01"
  location = local.location
  tags     = local.tags
}

module "network" {
  source = "cyber-scot/network/azurerm"

  rg_name  = module.rg.rg_name
  location = module.rg.rg_location
  tags     = module.rg.rg_tags

  vnet_name          = "vnet-${var.short}-${var.loc}-${var.env}-01"
  vnet_location      = module.rg.rg_location
  vnet_address_space = ["10.0.0.0/16"]

  subnets = {
    "sn1-${module.network.vnet_name}" = {
      prefix            = "10.0.0.0/24",
      service_endpoints = ["Microsoft.Storage"]
    }
  }
}

module "nsg" {
  source = "cyber-scot/nsg/azurerm"

  rg_name  = module.rg.rg_name
  location = module.rg.rg_location
  tags     = module.rg.rg_tags

  nsg_name              = "nsg-${var.short}-${var.loc}-${var.env}-01"
  associate_with_subnet = true
  subnet_id             = element(values(module.network.subnets_ids), 0)
  custom_nsg_rules = {
    "AllowVnetInbound" = {
      priority                   = 100
      direction                  = "Inbound"
      access                     = "Allow"
      protocol                   = "Tcp"
      source_port_range          = "*"
      destination_port_range     = "*"
      source_address_prefix      = "VirtualNetwork"
      destination_address_prefix = "VirtualNetwork"
    }
  }
}

module "bastion" {
  source = "cyber-scot/bastion/azurerm"

  rg_name  = module.rg.rg_name
  location = module.rg.rg_location
  tags     = module.rg.rg_tags

  bastion_host_name                  = "bst-${var.short}-${var.loc}-${var.env}-01"
  create_bastion_nsg                 = true
  create_bastion_nsg_rules           = true
  create_bastion_subnet              = true
  bastion_subnet_target_vnet_name    = module.network.vnet_name
  bastion_subnet_target_vnet_rg_name = module.network.vnet_rg_name
  bastion_subnet_range               = "10.0.1.0/27"
}

module "windows_10_vms" {
  source = "cyber-scot/windows-virtual-machine/azurerm"

  count = 2

  vms = [
    {
      rg_name        = module.rg.rg_name
      location       = module.rg.rg_location
      tags           = module.rg.rg_tags
      name           = "vm-${var.short}-${var.loc}-${var.env}-${format("%02d", count.index + 1)}"
      subnet_id      = element(values(module.network.subnets_ids), 0)
      admin_username = "Local${title(var.short)}${title(var.env)}Admin"
      admin_password = data.azurerm_key_vault_secret.mgmt_admin_pwd.value
      vm_size        = "Standard_B2ms"
      timezone       = "UTC"
      vm_os_simple   = "Windows10Gen2"
      os_disk = {
        disk_size_gb = 256
      }
      run_vm_command = {
        inline = "try { Set-ExecutionPolicy Bypass -Scope Process -Force; [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072; iex ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1')) } catch { Write-Error 'An error occurred:' $_; exit 1 }"
      }
    },
  ]
}


resource "azurerm_application_security_group" "server_asg" {
  rg_name  = module.rg.rg_name
  location = module.rg.rg_location
  tags     = module.rg.rg_tags

  name = "asg-server-${var.short}-${var.loc}-${var.env}-01"
}

module "windows_server" {
  source = "cyber-scot/windows-virtual-machine/azurerm"

  vms = [
    {
      rg_name        = module.rg.rg_name
      location       = module.rg.rg_location
      tags           = module.rg.rg_tags
      name           = "web-${var.short}-${var.loc}-${var.env}-01"
      subnet_id      = element(values(module.network.subnets_ids), 0)
      create_asg     = false
      asg_id         = azurerm_application_security_group.server_asg.id
      admin_username = "Local${title(var.short)}${title(var.env)}Admin"
      admin_password = data.azurerm_key_vault_secret.mgmt_admin_pwd.value
      vm_size        = "Standard_B2ms"
      timezone       = "UTC"
      vm_os_simple   = "WindowsServer2022AzureEditionGen2"
      os_disk = {
        disk_size_gb = 128
      }
      run_vm_command = {
        inline = "try { Install-WindowsFeature -Name Web-Server -IncludeManagementTools } catch { Write-Error 'Failed to install IIS: $_'; exit 1 }"
      }
    },
    {
      rg_name        = module.rg.rg_name
      location       = module.rg.rg_location
      tags           = module.rg.rg_tags
      name           = "app-${var.short}-${var.loc}-${var.env}-01"
      subnet_id      = element(values(module.network.subnets_ids), 0)
      create_asg     = false
      asg_id         = azurerm_application_security_group.server_asg.id
      admin_username = "Local${title(var.short)}${title(var.env)}Admin"
      admin_password = data.azurerm_key_vault_secret.mgmt_admin_pwd.value
      vm_size        = "Standard_B2ms"
      timezone       = "UTC"
      vm_os_simple   = "WindowsServer2022AzureEditionGen2"
      os_disk = {
        disk_size_gb = 128
      }
      run_vm_command = {
        inline = "try { Install-WindowsFeature -Name Application-Server } catch { Write-Error 'Failed to install Application Server: $_'; exit 1 }"
      }
    },
  ]
}
