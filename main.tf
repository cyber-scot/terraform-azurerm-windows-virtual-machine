resource "azurerm_public_ip" "pip" {
  for_each = { for vm in var.vms : vm.name => vm if vm.public_ip_sku != null }

  name                = each.value.pip_name != null ? each.value.pip_name : "pip-${each.value.name}"
  location            = each.value.location
  resource_group_name = each.value.rg_name
  allocation_method   = each.value.allocation_method
  domain_name_label   = coalesce(each.value.pip_custom_dns_label, each.value.vm_hostname)
  sku                 = each.value.public_ip_sku

  lifecycle {
    ignore_changes = [domain_name_label]
  }
}

resource "azurerm_network_interface" "nic" {
  for_each = { for vm in var.vms : vm.name => vm }

  name                          = each.value.nic_name
  location                      = each.value.location
  resource_group_name           = each.value.rg_name
  enable_accelerated_networking = each.value.enable_accelerated_networking

  ip_configuration {
    name                          = each.value.nic_ipconfig_name
    primary                       = true
    private_ip_address_allocation = each.value.static_private_ip == null ? "Dynamic" : "Static"
    private_ip_address            = each.value.static_private_ip
    public_ip_address_id          = lookup(each.value, "public_ip_sku", null) == null ? null : azurerm_public_ip.pip[each.key].id
    subnet_id                     = each.value.subnet_id
  }
  tags = each.value.tags

  timeouts {
    create = "5m"
    delete = "10m"
  }
}

resource "azurerm_application_security_group" "asg" {
  for_each = { for vm in var.vms : vm.name => vm }

  name                = each.value.asg_name != null ? each.value.asg_name : "asg-${each.value.name}"
  location            = each.value.location
  resource_group_name = each.value.rg_name
  tags                = each.value.tags
}

resource "azurerm_network_interface_application_security_group_association" "asg_association" {
  for_each = { for vm in var.vms : vm.name => vm }

  network_interface_id          = azurerm_network_interface.nic[each.key].id
  application_security_group_id = azurerm_application_security_group.asg.id
}


resource "random_integer" "zone" {
  for_each = { for vm in var.vms : vm.name => vm if each.value.availability_zone == "random" }
  min      = 1
  max      = 3
}

locals {
  sanitized_names = { for vm in var.vms : vm.name => upper(replace(replace(replace(vm.name, " ", ""), "-", ""), "_", "")) }
  netbios_names   = { for key, value in local.sanitized_names : key => substr(value, 0, min(length(value), 15)) }
  random_zones    = { for key, value in var.vms : key => value.availability_zone == "random" ? tostring(random_integer.zone[key].result) : value.availability_zone }
}

resource "azurerm_windows_virtual_machine" "this" {
  for_each = { for vm in var.vms : vm.name => vm }

  // Forces acceptance of marketplace terms before creating a VM
  depends_on = [
    azurerm_marketplace_agreement.plan_acceptance_simple,
    azurerm_marketplace_agreement.plan_acceptance_custom
  ]

  name                     = each.value.name
  resource_group_name      = each.value.rg_name
  location                 = each.value.location
  network_interface_ids    = [azurerm_network_interface.nic[each.key].id]
  license_type             = each.value.license_type
  patch_mode               = each.value.patch_mode
  enable_automatic_updates = each.value.enable_automatic_updates
  computer_name            = each.value.computer_name != null ? each.value.computer_name : local.netbios_name
  admin_username           = each.value.admin_username
  admin_password           = each.value.admin_password
  size                     = each.value.vm_size
  source_image_id          = try(each.value.use_custom_image, null) == true ? each.value.custom_source_image_id : null
  zone                     = each.value.availability_zone == "random" ? local.random_zone : each.value.availability_zone
  availability_set_id      = each.value.availability_set_id
  timezone                 = each.value.timezone
  custom_data              = each.value.custom_data
  tags                     = each.value.tags

  encryption_at_host_enabled = each.value.enable_encryption_at_host
  allow_extension_operations = each.value.allow_extension_operations
  provision_vm_agent         = each.value.provision_vm_agent

  dynamic "source_image_reference" {
    for_each = try(each.value.use_simple_image, null) == true && try(each.value.use_simple_image_with_plan, null) == false && try(each.value.use_custom_image, null) == false ? [1] : []
    content {
      publisher = each.value.vm_os_id == "" ? coalesce(each.value.vm_os_publisher, module.os_calculator[0].calculated_value_os_publisher) : ""
      offer     = each.value.vm_os_id == "" ? coalesce(each.value.vm_os_offer, module.os_calculator[0].calculated_value_os_offer) : ""
      sku       = each.value.vm_os_id == "" ? coalesce(each.value.vm_os_sku, module.os_calculator[0].calculated_value_os_sku) : ""
      version   = each.value.vm_os_id == "" ? each.value.vm_os_version : ""
    }
  }

  dynamic "additional_capabilities" {
    for_each = each.value.ultra_ssd_enabled ? [1] : []
    content {
      ultra_ssd_enabled = each.value.ultra_ssd_enabled
    }
  }

  dynamic "source_image_reference" {
    for_each = try(each.value.use_simple_image, null) == false && try(each.value.use_simple_image_with_plan, null) == false && length(each.value.source_image_reference) > 0 && length(each.value.plan) == 0 && try(each.value.use_custom_image, null) == false ? [1] : []
    content {
      publisher = lookup(each.value.source_image_reference, "publisher", null)
      offer     = lookup(each.value.source_image_reference, "offer", null)
      sku       = lookup(each.value.source_image_reference, "sku", null)
      version   = lookup(each.value.source_image_reference, "version", null)
    }
  }

  dynamic "source_image_reference" {
    for_each = try(each.value.use_simple_image, null) == true && try(each.value.use_simple_image_with_plan, null) == true && try(each.value.use_custom_image, null) == false ? [1] : []
    content {
      publisher = each.value.vm_os_id == "" ? coalesce(each.value.vm_os_publisher, module.os_calculator_with_plan[0].calculated_value_os_publisher) : ""
      offer     = each.value.vm_os_id == "" ? coalesce(each.value.vm_os_offer, module.os_calculator_with_plan[0].calculated_value_os_offer) : ""
      sku       = each.value.vm_os_id == "" ? coalesce(each.value.vm_os_sku, module.os_calculator_with_plan[0].calculated_value_os_sku) : ""
      version   = each.value.vm_os_id == "" ? each.value.vm_os_version : ""
    }
  }

  dynamic "plan" {
    for_each = try(each.value.use_simple_image, null) == true && try(each.value.use_simple_image_with_plan, null) == true && try(each.value.use_custom_image, null) == false ? [1] : []
    content {
      name      = each.value.vm_os_id == "" ? coalesce(each.value.vm_os_sku, module.os_calculator_with_plan[0].calculated_value_os_sku) : ""
      product   = each.value.vm_os_id == "" ? coalesce(each.value.vm_os_offer, module.os_calculator_with_plan[0].calculated_value_os_offer) : ""
      publisher = each.value.vm_os_id == "" ? coalesce(each.value.vm_os_publisher, module.os_calculator_with_plan[0].calculated_value_os_publisher) : ""
    }
  }

  dynamic "plan" {
    for_each = try(each.value.use_simple_image, null) == false && try(each.value.use_simple_image_with_plan, null) == false && length(each.value.plan) > 0 && try(each.value.use_custom_image, null) == false ? [1] : []
    content {
      name      = lookup(each.value.plan, "name", null)
      product   = lookup(each.value.plan, "product", null)
      publisher = lookup(each.value.plan, "publisher", null)
    }
  }

  dynamic "identity" {
    for_each = length(each.value.identity_ids) == 0 && each.value.identity_type == "SystemAssigned" ? [each.value.identity_type] : []
    content {
      type = each.value.identity_type
    }
  }

  dynamic "identity" {
    for_each = length(each.value.identity_ids) > 0 || each.value.identity_type == "UserAssigned" ? [each.value.identity_type] : []
    content {
      type         = each.value.identity_type
      identity_ids = length(each.value.identity_ids) > 0 ? each.value.identity_ids : []
    }
  }

  dynamic "identity" {
    for_each = length(each.value.identity_ids) > 0 || each.value.identity_type == "SystemAssigned, UserAssigned" ? [each.value.identity_type] : []
    content {
      type         = each.value.identity_type
      identity_ids = length(each.value.identity_ids) > 0 ? each.value.identity_ids : []
    }
  }

  priority        = each.value.spot_instance ? "Spot" : "Regular"
  max_bid_price   = each.value.spot_instance ? each.value.spot_instance_max_bid_price : null
  eviction_policy = each.value.spot_instance ? each.value.spot_instance_eviction_policy : null

  os_disk {
    name                 = each.value.os_disk_name != null ? each.value.os_disk_name : "os-${each.value.name}"
    caching              = each.value.os_disk_caching
    storage_account_type = each.value.storage_account_type
    disk_size_gb         = each.value.os_disk_size_gb
  }

  dynamic "boot_diagnostics" {
    for_each = each.value.boot_diagnostics_storage_account_uri != null ? [1] : []
    content {
      storage_account_uri = each.value.boot_diagnostics_storage_account_uri
    }
  }
}

module "os_calculator" {
  source       = "cyber-scot/windows-virtual-machine-os-sku-calculator/azurerm"
  for_each     = { for vm in var.vms : vm.name => vm if try(vm.use_simple_image, null) == true }
  vm_os_simple = each.value.vm_os_simple
}

module "os_calculator_with_plan" {
  source       = "cyber-scot/windows-virtual-machine-os-sku-with-plan-calculator/azurerm"
  for_each     = { for vm in var.vms : vm.name => vm if try(vm.use_simple_image_with_plan, null) == true }
  vm_os_simple = each.value.vm_os_simple
}

resource "azurerm_marketplace_agreement" "plan_acceptance_simple" {
  for_each = { for vm in var.vms : vm.name => vm if try(vm.use_simple_image_with_plan, null) == true && try(vm.accept_plan, null) == true && try(vm.use_custom_image, null) == false }

  publisher = coalesce(each.value.vm_os_publisher, module.os_calculator_with_plan[each.key].calculated_value_os_publisher)
  offer     = coalesce(each.value.vm_os_offer, module.os_calculator_with_plan[each.key].calculated_value_os_offer)
  plan      = coalesce(each.value.vm_os_sku, module.os_calculator_with_plan[each.key].calculated_value_os_sku)
}

resource "azurerm_marketplace_agreement" "plan_acceptance_custom" {
  for_each = { for vm in var.vms : vm.name => vm if try(vm.use_simple_image, null) == false && try(vm.use_simple_image_with_plan, null) == false && length(vm.plan) > 0 && try(vm.accept_plan, null) == true && try(vm.use_custom_image, null) == false }

  publisher = lookup(each.value.plan, "publisher", null)
  offer     = lookup(each.value.plan, "product", null)
  plan      = lookup(each.value.plan, "name", null)
}
