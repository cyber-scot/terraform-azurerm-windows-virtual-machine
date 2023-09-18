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
  random_zone    = tostring(random_integer.zone.result)
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
  source       = "cyber-scot/windows-virtual-machine-os-sku-calculator/azurerm"
  count        = try(var.use_simple_image, null) == true ? 1 : 0
  vm_os_simple = var.vm_os_simple
}

module "os_calculator_with_plan" {
  source       = "cyber-scot/windows-virtual-machine-os-sku-with-plan-calculator/azurerm"
  count        = try(var.use_simple_image_with_plan, null) == true ? 1 : 0
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
