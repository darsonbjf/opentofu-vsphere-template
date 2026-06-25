# Build New VM
locals {
  workspace     = terraform.workspace
  is_production = var.environment == "prod"

  effective_zones         = var.zones
  provider_vsphere_server = local.effective_zones[var.default_zone].vsphere_server

  vm_zones = {
    for vm_key, vm_config in var.vm : vm_key => coalesce(vm_config.zone, var.default_zone)
  }

  vm_networks = {
    for vm_key, vm_config in var.vm : vm_key => local.effective_zones[local.vm_zones[vm_key]].networks[vm_config.network]
  }

  vm_effective_folders = {
    for vm_key, vm_config in var.vm : vm_key => try([
      for cidr, folder in local.vm_folder_by_cidr : folder if cidrcontains(cidr, vm_config.ipv4_address)
    ][0], "")
  }

  vm_name_prefixes = {
    for vm_key, vm_config in var.vm : vm_key => trimspace(try(local.effective_zones[local.vm_zones[vm_key]].vm_name_prefix, ""))
  }

  vm_names = {
    for vm_key, vm_config in var.vm : vm_key => (
      local.vm_name_prefixes[vm_key] != ""
      ? "${local.workspace}-${local.vm_name_prefixes[vm_key]}-${vm_config.name}-${vm_config.ipv4_address}"
      : "${local.workspace}-${vm_config.name}-${vm_config.ipv4_address}"
    )
  }

  environment_folder = local.environment_folder_by_name[var.environment]
  production_vms     = local.is_production ? var.vm : {}
  non_production_vms = local.is_production ? {} : var.vm
  managed_vms        = merge(vsphere_virtual_machine.vm, vsphere_virtual_machine.vm_nonprod)
}

data "vsphere_datacenter" "zone" {
  for_each = local.effective_zones
  name     = each.value.data_center
}

data "vsphere_datastore" "zone" {
  for_each      = local.effective_zones
  name          = each.value.data_store
  datacenter_id = data.vsphere_datacenter.zone[each.key].id
}

data "vsphere_virtual_machine" "template" {
  for_each      = local.effective_zones
  name          = var.vm_template
  datacenter_id = data.vsphere_datacenter.zone[each.key].id
}

data "vsphere_compute_cluster" "zone" {
  for_each      = local.effective_zones
  name          = each.value.cluster
  datacenter_id = data.vsphere_datacenter.zone[each.key].id
}

data "vsphere_resource_pool" "pool" {
  for_each      = var.vm
  name          = format("%s%s", data.vsphere_compute_cluster.zone[local.vm_zones[each.key]].name, "/Resources")
  datacenter_id = data.vsphere_datacenter.zone[local.vm_zones[each.key]].id
}

data "vsphere_network" "vm_network" {
  for_each      = var.vm
  name          = local.vm_networks[each.key].name
  datacenter_id = data.vsphere_datacenter.zone[local.vm_zones[each.key]].id
}

resource "vsphere_virtual_machine" "vm" {
  for_each                   = local.production_vms
  name                       = local.vm_names[each.key]
  resource_pool_id           = data.vsphere_resource_pool.pool[each.key].id
  datastore_id               = data.vsphere_datastore.zone[local.vm_zones[each.key]].id
  folder                     = local.vm_effective_folders[each.key]
  num_cpus                   = each.value.cpus
  memory                     = each.value.memory
  guest_id                   = coalesce(each.value.guest_id, var.guest_id)
  firmware                   = var.firmware
  wait_for_guest_net_timeout = each.value.wait_for_guest_net_timeout
  wait_for_guest_ip_timeout  = each.value.wait_for_guest_net_timeout
  enable_disk_uuid           = true

  # Configuração de rede - Gerenciada completamente pelo OpenTofu
  # IP estático, gateway, DNS e máscara são definidos via vSphere customization
  network_interface {
    network_id     = data.vsphere_network.vm_network[each.key].id
    adapter_type   = var.net_adapter_type
    use_static_mac = false
  }

  clone {
    template_uuid = data.vsphere_virtual_machine.template[local.vm_zones[each.key]].id
    linked_clone  = false

    customize {
      timeout = 20

      linux_options {
        host_name    = each.value.hostname
        domain       = var.domain
        hw_clock_utc = true
      }

      network_interface {
        ipv4_address = each.value.ipv4_address
        ipv4_netmask = local.vm_networks[each.key].netmask
      }

      ipv4_gateway    = local.vm_networks[each.key].gateway
      dns_server_list = local.vm_networks[each.key].dns_server_list
      dns_suffix_list = [local.vm_networks[each.key].domain_name]
    }
  }

  extra_config = {
    # Configurações para melhorar a detecção de rede
    "tools.syncTimeWithHost"       = "TRUE"
    "time.synchronize.continue"    = "TRUE"
    "time.synchronize.restore"     = "TRUE"
    "time.synchronize.resume.host" = "TRUE"
    "time.synchronize.shrink"      = "TRUE"
  }

  disk {
    label            = "disk0"
    size             = each.value.disk_size
    thin_provisioned = var.thin_provisioned
    unit_number      = 0
  }

  dynamic "disk" {
    for_each = each.value.disk_size_data != null ? [each.value.disk_size_data] : []
    content {
      label            = "disk1"
      size             = disk.value
      thin_provisioned = var.thin_provisioned
      unit_number      = 1
    }
  }

  lifecycle {
    ignore_changes = [
      extra_config,
      annotation
    ]
    prevent_destroy = true

    precondition {
      condition     = local.vm_effective_folders[each.key] != ""
      error_message = "A VM ${each.key} deve usar IP de uma faixa conhecida de folder. Consulte a tabela CIDR -> folder em docs/INFRASTRUCTURE_ZONES.md."
    }

    precondition {
      condition     = local.vm_effective_folders[each.key] == local.environment_folder
      error_message = "A VM ${each.key} deve usar IP do folder ${local.environment_folder} no ambiente ${var.environment}."
    }
  }

  annotation = jsonencode({
    created_at  = timestamp()
    created_by  = "terraform"
    environment = var.environment
    zone        = local.vm_zones[each.key]
    network     = each.value.network
    workspace   = local.workspace
  })

}

resource "vsphere_virtual_machine" "vm_nonprod" {
  for_each                   = local.non_production_vms
  name                       = local.vm_names[each.key]
  resource_pool_id           = data.vsphere_resource_pool.pool[each.key].id
  datastore_id               = data.vsphere_datastore.zone[local.vm_zones[each.key]].id
  folder                     = local.vm_effective_folders[each.key]
  num_cpus                   = each.value.cpus
  memory                     = each.value.memory
  guest_id                   = coalesce(each.value.guest_id, var.guest_id)
  firmware                   = var.firmware
  wait_for_guest_net_timeout = each.value.wait_for_guest_net_timeout
  wait_for_guest_ip_timeout  = each.value.wait_for_guest_net_timeout
  enable_disk_uuid           = true

  # Configuração de rede - Gerenciada completamente pelo OpenTofu
  # IP estático, gateway, DNS e máscara são definidos via vSphere customization
  network_interface {
    network_id     = data.vsphere_network.vm_network[each.key].id
    adapter_type   = var.net_adapter_type
    use_static_mac = false
  }

  clone {
    template_uuid = data.vsphere_virtual_machine.template[local.vm_zones[each.key]].id
    linked_clone  = false

    customize {
      timeout = 20

      linux_options {
        host_name    = each.value.hostname
        domain       = var.domain
        hw_clock_utc = true
      }

      network_interface {
        ipv4_address = each.value.ipv4_address
        ipv4_netmask = local.vm_networks[each.key].netmask
      }

      ipv4_gateway    = local.vm_networks[each.key].gateway
      dns_server_list = local.vm_networks[each.key].dns_server_list
      dns_suffix_list = [local.vm_networks[each.key].domain_name]
    }
  }

  extra_config = {
    # Configurações para melhorar a detecção de rede
    "tools.syncTimeWithHost"       = "TRUE"
    "time.synchronize.continue"    = "TRUE"
    "time.synchronize.restore"     = "TRUE"
    "time.synchronize.resume.host" = "TRUE"
    "time.synchronize.shrink"      = "TRUE"
  }

  disk {
    label            = "disk0"
    size             = each.value.disk_size
    thin_provisioned = var.thin_provisioned
    unit_number      = 0
  }

  dynamic "disk" {
    for_each = each.value.disk_size_data != null ? [each.value.disk_size_data] : []
    content {
      label            = "disk1"
      size             = disk.value
      thin_provisioned = var.thin_provisioned
      unit_number      = 1
    }
  }

  lifecycle {
    ignore_changes = [
      extra_config,
      annotation
    ]

    precondition {
      condition     = local.vm_effective_folders[each.key] != ""
      error_message = "A VM ${each.key} deve usar IP de uma faixa conhecida de folder. Consulte a tabela CIDR -> folder em docs/INFRASTRUCTURE_ZONES.md."
    }

    precondition {
      condition     = local.vm_effective_folders[each.key] == local.environment_folder
      error_message = "A VM ${each.key} deve usar IP do folder ${local.environment_folder} no ambiente ${var.environment}."
    }
  }

  annotation = jsonencode({
    created_at  = timestamp()
    created_by  = "terraform"
    environment = var.environment
    zone        = local.vm_zones[each.key]
    network     = each.value.network
    workspace   = local.workspace
  })

}
