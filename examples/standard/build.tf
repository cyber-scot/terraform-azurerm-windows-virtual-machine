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

#module "bastion" {
#  source = "cyber-scot/bastion/azurerm"
#
#  rg_name  = module.rg.rg_name
#  location = module.rg.rg_location
#  tags     = module.rg.rg_tags
#
#  bastion_host_name                  = "bst-${var.short}-${var.loc}-${var.env}-01"
#  create_bastion_nsg                 = true
#  create_bastion_nsg_rules           = true
#  create_bastion_subnet              = true
#  bastion_subnet_target_vnet_name    = module.network.vnet_name
#  bastion_subnet_target_vnet_rg_name = module.network.vnet_rg_name
#  bastion_subnet_range               = "10.0.1.0/27"
#}

module "windows_vms" {
  source = "../../"

  vms = [
    {
      rg_name                              = module.rg.rg_name
      location                             = module.rg.rg_location
      tags                                 = module.rg.rg_tags
      name                                 = "vm-${var.short}-${var.loc}-${var.env}-01"
      subnet_id                            = element(values(module.network.subnets_ids), 0)
      patch_mode                           = "AutomaticByOS"
      enable_automatic_updates             = true
      admin_username                       = "CyberScot"
      admin_password                       = "Password123!"
      vm_size                              = "Standard_B2ms"
      use_custom_image                     = false
      availability_zone                    = "1"
      timezone                             = "UTC"
      custom_data                          = null
      enable_encryption_at_host            = false
      allow_extension_operations           = true
      provision_vm_agent                   = true
      use_simple_image                     = true
      ultra_ssd_enabled                    = false
      vm_os_simple                         = "WindowsServer2019Datacenter"
      os_disk_name                         = "osdisk1"
      os_disk_caching                      = "ReadWrite"
      storage_account_type                 = "Standard_LRS"
      os_disk_size_gb                      = 30
      boot_diagnostics_storage_account_uri = "https://mystorageaccount.blob.core.windows.net/"
    },
    // ... add more VM configurations as needed
  ]
}
