
```hcl
resource "azurerm_public_ip" "pip" {
  count = var.public_ip_sku == null ? 0 : 1

  name                = var.pip_name != null ? var.pip_name : "pip-${var.name}"
  location            = var.location
  resource_group_name = var.rg_name
  allocation_method   = "Static"
  domain_name_label   = coalesce(var.pip_custom_dns_label, var.vm_hostname)
  sku                 = var.public_ip_sku
}

resource "azurerm_network_interface" "nic" {
  name                = var.nic_name != null ? var.nic_name : "nic-${var.name}"
  resource_group_name = var.rg_name
  location            = var.location

  enable_accelerated_networking = var.enable_accelerated_networking

  ip_configuration {
    name                          = var.nic_ipconfig_name != null ? var.nic_ipconfig_name : "nic-ipconfig-${var.name}"
    primary                       = true
    private_ip_address_allocation = var.static_private_ip == null ? "Dynamic" : "Static"
    private_ip_address            = var.static_private_ip
    public_ip_address_id          = var.public_ip_sku == null ? null : join("", azurerm_public_ip.pip.*.id)
    subnet_id                     = var.subnet_id
  }
  tags = var.tags

  timeouts {
    create = "5m"
    delete = "10m"
  }
}

resource "azurerm_application_security_group" "asg" {
  name                = var.asg_name != null ? var.asg_name : "asg-${var.name}"
  location            = var.location
  resource_group_name = var.rg_name
  tags                = var.tags
}

resource "azurerm_network_interface_application_security_group_association" "asg_association" {
  network_interface_id          = azurerm_network_interface.nic.id
  application_security_group_id = azurerm_application_security_group.asg.id
}


resource "random_integer" "zone" {
  count = var.availability_zone == "random" ? 1 : 0
  min   = 1
  max   = 3
}

locals {
  sanitized_name = upper(replace(replace(replace(var.name, " ", ""), "-", ""), "_", ""))
  netbios_name   = substr(local.sanitized_name, 0, min(length(local.sanitized_name), 15))
  random_zone = tostring(random_integer.zone.result)
}


resource "azurerm_windows_virtual_machine" "this" {

  // Forces acceptance of marketplace terms before creating a VM
  depends_on = [
    azurerm_marketplace_agreement.plan_acceptance_simple,
    azurerm_marketplace_agreement.plan_acceptance_custom
  ]

  name                     = var.name
  resource_group_name      = var.rg_name
  location                 = var.location
  network_interface_ids    = [azurerm_network_interface.nic.id]
  license_type             = var.license_type
  patch_mode               = var.patch_mode
  enable_automatic_updates = var.enable_automatic_updates
  computer_name            = var.computer_name != null ? var.computer_name : local.netbios_name
  admin_username           = var.admin_username
  admin_password           = var.admin_password
  size                     = var.vm_size
  source_image_id          = try(var.use_custom_image, null) == true ? var.custom_source_image_id : null
  zone                     = var.availability_zone == "random" ? local.random_zone : var.availability_zone
  availability_set_id      = var.availability_set_id
  timezone                 = var.timezone
  custom_data              = var.custom_data

  #checkov:skip=CKV_AZURE_151:Ensure Encryption at host is enabled
  encryption_at_host_enabled = var.enable_encryption_at_host

  #checkov:skip=CKV_AZURE_50:Ensure Virtual Machine extensions are not installed
  allow_extension_operations = var.allow_extension_operations
  provision_vm_agent         = var.provision_vm_agent

  // Uses calculator
  dynamic "source_image_reference" {
    for_each = try(var.use_simple_image, null) == true && try(var.use_simple_image_with_plan, null) == false && try(var.use_custom_image, null) == false ? [1] : []
    content {
      publisher = var.vm_os_id == "" ? coalesce(var.vm_os_publisher, module.os_calculator[0].calculated_value_os_publisher) : ""
      offer     = var.vm_os_id == "" ? coalesce(var.vm_os_offer, module.os_calculator[0].calculated_value_os_offer) : ""
      sku       = var.vm_os_id == "" ? coalesce(var.vm_os_sku, module.os_calculator[0].calculated_value_os_sku) : ""
      version   = var.vm_os_id == "" ? var.vm_os_version : ""
    }
  }

  dynamic "additional_capabilities" {
  for_each = var.ultra_ssd_enabled ? [1] : []
  content {
    ultra_ssd_enabled = var.ultra_ssd_enabled
  }
}


  // Uses your own source image
  dynamic "source_image_reference" {
    for_each = try(var.use_simple_image, null) == false && try(var.use_simple_image_with_plan, null) == false && length(var.source_image_reference) > 0 && length(var.plan) == 0 && try(var.use_custom_image, null) == false ? [1] : []
    content {
      publisher = lookup(var.source_image_reference, "publisher", null)
      offer     = lookup(var.source_image_reference, "offer", null)
      sku       = lookup(var.source_image_reference, "sku", null)
      version   = lookup(var.source_image_reference, "version", null)
    }
  }

  // To be used when a VM with a plan is used
  dynamic "source_image_reference" {
    for_each = try(var.use_simple_image, null) == true && try(var.use_simple_image_with_plan, null) == true && try(var.use_custom_image, null) == false ? [1] : []
    content {
      publisher = var.vm_os_id == "" ? coalesce(var.vm_os_publisher, module.os_calculator_with_plan[0].calculated_value_os_publisher) : ""
      offer     = var.vm_os_id == "" ? coalesce(var.vm_os_offer, module.os_calculator_with_plan[0].calculated_value_os_offer) : ""
      sku       = var.vm_os_id == "" ? coalesce(var.vm_os_sku, module.os_calculator_with_plan[0].calculated_value_os_sku) : ""
      version   = var.vm_os_id == "" ? var.vm_os_version : ""
    }
  }

  dynamic "plan" {
    for_each = try(var.use_simple_image, null) == true && try(var.use_simple_image_with_plan, null) == true && try(var.use_custom_image, null) == false ? [1] : []
    content {
      name      = var.vm_os_id == "" ? coalesce(var.vm_os_sku, module.os_calculator_with_plan[0].calculated_value_os_sku) : ""
      product   = var.vm_os_id == "" ? coalesce(var.vm_os_offer, module.os_calculator_with_plan[0].calculated_value_os_offer) : ""
      publisher = var.vm_os_id == "" ? coalesce(var.vm_os_publisher, module.os_calculator_with_plan[0].calculated_value_os_publisher) : ""
    }
  }

  // Uses your own image with custom plan
  dynamic "source_image_reference" {
    for_each = try(var.use_simple_image, null) == false && try(var.use_simple_image_with_plan, null) == false && length(var.plan) > 0 && try(var.use_custom_image, null) == false ? [1] : []
    content {
      publisher = lookup(var.source_image_reference, "publisher", null)
      offer     = lookup(var.source_image_reference, "offer", null)
      sku       = lookup(var.source_image_reference, "sku", null)
      version   = lookup(var.source_image_reference, "version", null)
    }
  }


  dynamic "plan" {
    for_each = try(var.use_simple_image, null) == false && try(var.use_simple_image_with_plan, null) == false && length(var.plan) > 0 && try(var.use_custom_image, null) == false ? [1] : []
    content {
      name      = lookup(var.plan, "name", null)
      product   = lookup(var.plan, "product", null)
      publisher = lookup(var.plan, "publisher", null)
    }
  }

  dynamic "identity" {
    for_each = length(var.identity_ids) == 0 && var.identity_type == "SystemAssigned" ? [var.identity_type] : []
    content {
      type = var.identity_type
    }
  }

  dynamic "identity" {
    for_each = length(var.identity_ids) > 0 || var.identity_type == "UserAssigned" ? [var.identity_type] : []
    content {
      type         = var.identity_type
      identity_ids = length(var.identity_ids) > 0 ? var.identity_ids : []
    }
  }

  dynamic "identity" {
    for_each = length(var.identity_ids) > 0 || var.identity_type == "SystemAssigned, UserAssigned" ? [var.identity_type] : []
    content {
      type         = var.identity_type
      identity_ids = length(var.identity_ids) > 0 ? var.identity_ids : []
    }
  }

  priority        = var.spot_instance ? "Spot" : "Regular"
  max_bid_price   = var.spot_instance ? var.spot_instance_max_bid_price : null
  eviction_policy = var.spot_instance ? var.spot_instance_eviction_policy : null

  os_disk {
    name                 = var.os_disk_name != null ? var.os_disk_name : "os-${var.name}"
    caching              = var.os_disk_caching
    storage_account_type = var.storage_account_type
    disk_size_gb         = var.os_disk_size_gb
  }

dynamic "boot_diagnostics" {
  for_each = var.boot_diagnostics_storage_account_uri != null ? [1] : []
  content {
    storage_account_uri = var.boot_diagnostics_storage_account_uri
  }
}


  tags = var.tags
}

module "os_calculator" {
  source = "cyber-scot/windows-virtual-machine-os-sku-calculator/azurerm"
  count = try(var.use_simple_image, null) == true ? 1 : 0
  vm_os_simple = var.vm_os_simple
}

module "os_calculator_with_plan" {
  source = "cyber-scot/windows-virtual-machine-os-sku-with-plan-calculator/azurerm"
  count = try(var.use_simple_image_with_plan, null) == true ? 1 : 0
  vm_os_simple = var.vm_os_simple
}

// Use these modules and accept these terms at your own peril
resource "azurerm_marketplace_agreement" "plan_acceptance_simple" {
  count = try(var.use_simple_image_with_plan, null) == true && try(var.accept_plan, null) == true && try(var.use_custom_image, null) == false ? 1 : 0

  publisher = coalesce(var.vm_os_publisher, module.os_calculator_with_plan[0].calculated_value_os_publisher)
  offer     = coalesce(var.vm_os_offer, module.os_calculator_with_plan[0].calculated_value_os_offer)
  plan      = coalesce(var.vm_os_sku, module.os_calculator_with_plan[0].calculated_value_os_sku)
}

// Use these modules and accept these terms at your own peril
resource "azurerm_marketplace_agreement" "plan_acceptance_custom" {
  count = try(var.use_simple_image, null) == false && try(var.use_simple_image_with_plan, null) == false && length(var.plan) > 0 && try(var.accept_plan, null) == true && try(var.use_custom_image, null) == false ? 1 : 0

  publisher = lookup(var.plan, "publisher", null)
  offer     = lookup(var.plan, "product", null)
  plan      = lookup(var.plan, "name", null)
}
```
## Requirements

No requirements.

## Providers

| Name | Version |
|------|---------|
| <a name="provider_azurerm"></a> [azurerm](#provider\_azurerm) | n/a |
| <a name="provider_random"></a> [random](#provider\_random) | n/a |

## Modules

| Name | Source | Version |
|------|--------|---------|
| <a name="module_os_calculator"></a> [os\_calculator](#module\_os\_calculator) | cyber-scot/windows-virtual-machine-os-sku-calculator/azurerm | n/a |
| <a name="module_os_calculator_with_plan"></a> [os\_calculator\_with\_plan](#module\_os\_calculator\_with\_plan) | cyber-scot/windows-virtual-machine-os-sku-with-plan-calculator/azurerm | n/a |

## Resources

| Name | Type |
|------|------|
| [azurerm_application_security_group.asg](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/application_security_group) | resource |
| [azurerm_marketplace_agreement.plan_acceptance_custom](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/marketplace_agreement) | resource |
| [azurerm_marketplace_agreement.plan_acceptance_simple](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/marketplace_agreement) | resource |
| [azurerm_network_interface.nic](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/network_interface) | resource |
| [azurerm_network_interface_application_security_group_association.asg_association](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/network_interface_application_security_group_association) | resource |
| [azurerm_public_ip.pip](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/public_ip) | resource |
| [azurerm_windows_virtual_machine.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/windows_virtual_machine) | resource |
| [random_integer.zone](https://registry.terraform.io/providers/hashicorp/random/latest/docs/resources/integer) | resource |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_accept_plan"></a> [accept\_plan](#input\_accept\_plan) | Defines whether a plan should be accepted or not | `bool` | `true` | no |
| <a name="input_admin_password"></a> [admin\_password](#input\_admin\_password) | The admin password to be used on the VMSS that will be deployed. The password must meet the complexity requirements of Azure. | `string` | `""` | no |
| <a name="input_admin_username"></a> [admin\_username](#input\_admin\_username) | The admin username of the VM that will be deployed. | `string` | `"LibreDevOpsAdmin"` | no |
| <a name="input_allocation_method"></a> [allocation\_method](#input\_allocation\_method) | Defines how an IP address is assigned. Options are Static or Dynamic. | `string` | `"Dynamic"` | no |
| <a name="input_allow_extension_operations"></a> [allow\_extension\_operations](#input\_allow\_extension\_operations) | Whether extensions are allowed to execute on the VM | `bool` | `true` | no |
| <a name="input_asg_name"></a> [asg\_name](#input\_asg\_name) | The name of the application security group to be made | `string` | n/a | yes |
| <a name="input_availability_set_id"></a> [availability\_set\_id](#input\_availability\_set\_id) | Specifies the ID of the Availability Set in which the Virtual Machine should exist. | `string` | `null` | no |
| <a name="input_availability_zone"></a> [availability\_zone](#input\_availability\_zone) | The availability zone for the VMs to be created to | `string` | `null` | no |
| <a name="input_boot_diagnostics_storage_account_uri"></a> [boot\_diagnostics\_storage\_account\_uri](#input\_boot\_diagnostics\_storage\_account\_uri) | The Primary/Secondary Endpoint for the Azure Storage Account which should be used to store Boot Diagnostics. | `string` | `null` | no |
| <a name="input_computer_name"></a> [computer\_name](#input\_computer\_name) | The computer name of the host if specified, this module will attempt to use var.name by sanitising it | `string` | `null` | no |
| <a name="input_custom_data"></a> [custom\_data](#input\_custom\_data) | The Base64-Encoded Custom Data which should be used for this Virtual Machine. | `string` | `null` | no |
| <a name="input_custom_source_image_id"></a> [custom\_source\_image\_id](#input\_custom\_source\_image\_id) | The ID of a custom source image, if used | `string` | `null` | no |
| <a name="input_data_disk_size_gb"></a> [data\_disk\_size\_gb](#input\_data\_disk\_size\_gb) | Storage data disk size size. | `number` | `30` | no |
| <a name="input_enable_accelerated_networking"></a> [enable\_accelerated\_networking](#input\_enable\_accelerated\_networking) | (Optional) Enable accelerated networking on Network interface. | `bool` | `false` | no |
| <a name="input_enable_automatic_updates"></a> [enable\_automatic\_updates](#input\_enable\_automatic\_updates) | Should automatic updates be enabled? Defaults to false | `string` | `false` | no |
| <a name="input_enable_encryption_at_host"></a> [enable\_encryption\_at\_host](#input\_enable\_encryption\_at\_host) | Whether host encryption is enabled | `bool` | `false` | no |
| <a name="input_identity_ids"></a> [identity\_ids](#input\_identity\_ids) | Specifies a list of user managed identity ids to be assigned to the VM. | `list(string)` | `[]` | no |
| <a name="input_identity_type"></a> [identity\_type](#input\_identity\_type) | The Managed Service Identity Type of this Virtual Machine. | `string` | `""` | no |
| <a name="input_license_type"></a> [license\_type](#input\_license\_type) | Specifies the BYOL Type for this Virtual Machine. This is only applicable to Windows Virtual Machines. Possible values are Windows\_Client and Windows\_Server | `string` | `null` | no |
| <a name="input_location"></a> [location](#input\_location) | The location for this resource to be put in | `string` | n/a | yes |
| <a name="input_name"></a> [name](#input\_name) | The name to be used within this module for the name of the VM | `string` | n/a | yes |
| <a name="input_nic_ipconfig_name"></a> [nic\_ipconfig\_name](#input\_nic\_ipconfig\_name) | The name of the NIC IPconfig if specified | `string` | `null` | no |
| <a name="input_nic_name"></a> [nic\_name](#input\_nic\_name) | Specify the name of a NIC, if specified | `string` | `null` | no |
| <a name="input_os_disk_caching"></a> [os\_disk\_caching](#input\_os\_disk\_caching) | The type of caching for the OS disk | `string` | `"ReadWrite"` | no |
| <a name="input_os_disk_name"></a> [os\_disk\_name](#input\_os\_disk\_name) | The name of the OS disk if specified | `string` | `null` | no |
| <a name="input_os_disk_size_gb"></a> [os\_disk\_size\_gb](#input\_os\_disk\_size\_gb) | The size of the OS Disk in GiB | `string` | `"127"` | no |
| <a name="input_patch_mode"></a> [patch\_mode](#input\_patch\_mode) | The patching mode of the virtual machines being deployed, default is Manual | `string` | `"Manual"` | no |
| <a name="input_pip_custom_dns_label"></a> [pip\_custom\_dns\_label](#input\_pip\_custom\_dns\_label) | If you are using a public IP and wish to assign a custom DNS label, set here, otherwise, the VM host name will be used | `any` | `null` | no |
| <a name="input_pip_name"></a> [pip\_name](#input\_pip\_name) | If you are using a Public IP, set the name in this variable | `string` | `null` | no |
| <a name="input_plan"></a> [plan](#input\_plan) | When a plan VM is used with a image not in the calculator, this will contain the variables used | `map(any)` | `{}` | no |
| <a name="input_provision_vm_agent"></a> [provision\_vm\_agent](#input\_provision\_vm\_agent) | Whether the Azure agent is installed on this VM, default is true | `bool` | `true` | no |
| <a name="input_public_ip_sku"></a> [public\_ip\_sku](#input\_public\_ip\_sku) | If you wish to assign a public IP directly to your nic, set this to Standard | `string` | `null` | no |
| <a name="input_rg_name"></a> [rg\_name](#input\_rg\_name) | The name of the resource group, this module does not create a resource group, it is expecting the value of a resource group already exists | `string` | n/a | yes |
| <a name="input_source_image_reference"></a> [source\_image\_reference](#input\_source\_image\_reference) | Whether the module should use the a custom image | `map(any)` | `{}` | no |
| <a name="input_spot_instance"></a> [spot\_instance](#input\_spot\_instance) | Whether the VM is a spot instance or not | `bool` | `false` | no |
| <a name="input_spot_instance_eviction_policy"></a> [spot\_instance\_eviction\_policy](#input\_spot\_instance\_eviction\_policy) | The eviction policy for a spot instance | `string` | `null` | no |
| <a name="input_spot_instance_max_bid_price"></a> [spot\_instance\_max\_bid\_price](#input\_spot\_instance\_max\_bid\_price) | The max bid price for a spot instance | `string` | `null` | no |
| <a name="input_static_private_ip"></a> [static\_private\_ip](#input\_static\_private\_ip) | If you are using a static IP, set it in this variable | `string` | `null` | no |
| <a name="input_storage_account_type"></a> [storage\_account\_type](#input\_storage\_account\_type) | Defines the type of storage account to be created. Valid options are Standard\_LRS, Standard\_ZRS, Standard\_GRS, Standard\_RAGRS, Premium\_LRS. | `string` | `"Standard_LRS"` | no |
| <a name="input_subnet_id"></a> [subnet\_id](#input\_subnet\_id) | The subnet ID for the NICs which are created with the VMs to be added to | `string` | n/a | yes |
| <a name="input_tags"></a> [tags](#input\_tags) | A map of the tags to use on the resources that are deployed with this module. | `map(string)` | n/a | yes |
| <a name="input_timezone"></a> [timezone](#input\_timezone) | The timezone for your VM to be deployed with | `string` | `"GMT Standard Time"` | no |
| <a name="input_ultra_ssd_enabled"></a> [ultra\_ssd\_enabled](#input\_ultra\_ssd\_enabled) | Should the capacity to enable Data Disks of the UltraSSD\_LRS storage account type be supported on this Virtual Machine? | `bool` | `false` | no |
| <a name="input_use_custom_image"></a> [use\_custom\_image](#input\_use\_custom\_image) | If you want to use a custom image, this must be set to true | `bool` | `false` | no |
| <a name="input_use_simple_image"></a> [use\_simple\_image](#input\_use\_simple\_image) | Whether the module should use the simple OS calculator module, default is true | `bool` | `true` | no |
| <a name="input_use_simple_image_with_plan"></a> [use\_simple\_image\_with\_plan](#input\_use\_simple\_image\_with\_plan) | If you are using the Windows OS Sku Calculator with plan, set this to true. Default is false | `bool` | `false` | no |
| <a name="input_vm_amount"></a> [vm\_amount](#input\_vm\_amount) | A number, with the amount of VMs which is expected to be created | `number` | n/a | yes |
| <a name="input_vm_hostname"></a> [vm\_hostname](#input\_vm\_hostname) | The hostname of the vm | `string` | n/a | yes |
| <a name="input_vm_os_id"></a> [vm\_os\_id](#input\_vm\_os\_id) | The resource ID of the image that you want to deploy if you are using a custom image.Note, need to provide is\_windows\_image = true for windows custom images. | `string` | `""` | no |
| <a name="input_vm_os_offer"></a> [vm\_os\_offer](#input\_vm\_os\_offer) | The name of the offer of the image that you want to deploy. This is ignored when vm\_os\_id or vm\_os\_simple are provided. | `string` | `""` | no |
| <a name="input_vm_os_publisher"></a> [vm\_os\_publisher](#input\_vm\_os\_publisher) | The name of the publisher of the image that you want to deploy. This is ignored when vm\_os\_id or vm\_os\_simple are provided. | `string` | `""` | no |
| <a name="input_vm_os_simple"></a> [vm\_os\_simple](#input\_vm\_os\_simple) | Specify WindowsServer, to get the latest image version of the specified os.  Do not provide this value if a custom value is used for vm\_os\_publisher, vm\_os\_offer, and vm\_os\_sku. | `string` | `""` | no |
| <a name="input_vm_os_sku"></a> [vm\_os\_sku](#input\_vm\_os\_sku) | The sku of the image that you want to deploy. This is ignored when vm\_os\_id or vm\_os\_simple are provided. | `string` | `""` | no |
| <a name="input_vm_os_version"></a> [vm\_os\_version](#input\_vm\_os\_version) | The version of the image that you want to deploy. This is ignored when vm\_os\_id or vm\_os\_simple are provided. | `string` | `"latest"` | no |
| <a name="input_vm_size"></a> [vm\_size](#input\_vm\_size) | Specifies the size of the virtual machine. | `string` | `"Standard_B2ms"` | no |

## Outputs

No outputs.
