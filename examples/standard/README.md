
```hcl
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
      admin_username                       = "CyberScot"
      admin_password                       = "Password123!"
      vm_size                              = "Standard_B2ms"
      timezone                             = "UTC"
      use_simple_image                     = true
      vm_os_simple                         = "Windows11Gen2"
    },
  ]
}
```
## Requirements

No requirements.

## Providers

| Name | Version |
|------|---------|
| <a name="provider_azurerm"></a> [azurerm](#provider\_azurerm) | 3.73.0 |
| <a name="provider_external"></a> [external](#provider\_external) | 2.3.1 |
| <a name="provider_http"></a> [http](#provider\_http) | 3.4.0 |

## Modules

| Name | Source | Version |
|------|--------|---------|
| <a name="module_network"></a> [network](#module\_network) | cyber-scot/network/azurerm | n/a |
| <a name="module_nsg"></a> [nsg](#module\_nsg) | cyber-scot/nsg/azurerm | n/a |
| <a name="module_rg"></a> [rg](#module\_rg) | cyber-scot/rg/azurerm | n/a |
| <a name="module_windows_vms"></a> [windows\_vms](#module\_windows\_vms) | ../../ | n/a |

## Resources

| Name | Type |
|------|------|
| [azurerm_client_config.current](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/data-sources/client_config) | data source |
| [external_external.detect_os](https://registry.terraform.io/providers/hashicorp/external/latest/docs/data-sources/external) | data source |
| [external_external.generate_timestamp](https://registry.terraform.io/providers/hashicorp/external/latest/docs/data-sources/external) | data source |
| [http_http.client_ip](https://registry.terraform.io/providers/hashicorp/http/latest/docs/data-sources/http) | data source |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_Regions"></a> [Regions](#input\_Regions) | Converts shorthand name to longhand name via lookup on map list | `map(string)` | <pre>{<br>  "eus": "East US",<br>  "euw": "West Europe",<br>  "uks": "UK South",<br>  "ukw": "UK West"<br>}</pre> | no |
| <a name="input_env"></a> [env](#input\_env) | The env variable, for example - prd for production. normally passed via TF\_VAR. | `string` | `"prd"` | no |
| <a name="input_loc"></a> [loc](#input\_loc) | The loc variable, for the shorthand location, e.g. uks for UK South.  Normally passed via TF\_VAR. | `string` | `"uks"` | no |
| <a name="input_short"></a> [short](#input\_short) | The shorthand name of to be used in the build, e.g. cscot for CyberScot.  Normally passed via TF\_VAR. | `string` | `"cscot"` | no |
| <a name="input_static_tags"></a> [static\_tags](#input\_static\_tags) | The tags variable | `map(string)` | <pre>{<br>  "Contact": "info@cyber.scot",<br>  "CostCentre": "671888",<br>  "ManagedBy": "Terraform"<br>}</pre> | no |

## Outputs

No outputs.
