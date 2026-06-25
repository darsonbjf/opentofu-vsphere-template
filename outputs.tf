locals {
  # Template único para exibir informações da VM
  vm_info_format = <<-EOT
  📊 VM: %s
  ┌────────────────────────────────────────
  │ 🖥️  Nome:    %s
  │ 🌐 IP:      %s
  │ ⚡ Estado:   %s
  │ 📡 IPs:     %s
  │ ⏱️  Uptime:   %s
  └────────────────────────────────────────
  EOT

  # Formatar todas as VMs usando o template unificado
  all_vms_info = join("\n", [
    for k, v in local.managed_vms : format(
      local.vm_info_format,
      k,
      v.name,
      try(v.default_ip_address, "N/A"),
      try(v.power_state, "N/A"),
      try(join(", ", coalesce(v.guest_ip_addresses, [])), "N/A"),
      try("${v.boot_delay} segundos", "N/A")
    )
  ])
}

# Saídas complexas (usar com: tofu output ou tofu output -json)
output "vm_ip" {
  description = "IP addresses of provisioned VMs (JSON encoded)"
  value = jsonencode({
    for k, v in local.managed_vms : k => v.default_ip_address
  })
}

output "vm_names" {
  description = "Names of created VMs (JSON encoded)"
  value = jsonencode({
    for k, v in local.managed_vms : k => v.name
  })
}

output "vm_info_json" {
  description = "Todas as informações das VMs em formato JSON"
  value = {
    ips = {
      for k, v in local.managed_vms : k => v.default_ip_address
    }
    names = {
      for k, v in local.managed_vms : k => v.name
    }
    details = {
      for k, v in local.managed_vms : k => {
        name       = v.name
        ip         = v.default_ip_address
        status     = v.power_state
        cpus       = v.num_cpus
        memory     = v.memory
        guest_id   = v.guest_id
        network    = var.vm[k].network
        network_id = v.network_interface[0].network_id
        zone       = local.vm_zones[k]
        folder     = local.vm_effective_folders[k]
        health = {
          uptime             = v.boot_delay
          guest_ip_addresses = v.guest_ip_addresses
        }
      }
    }
  }
}

# Saídas simples (usar com: tofu output -raw)
output "primary_vm_ip" {
  description = "IP da VM principal"
  value       = try(local.managed_vms["vm1"].default_ip_address, "")
}

output "primary_vm_name" {
  description = "Nome da VM principal"
  value       = try(local.managed_vms["vm1"].name, "")
}

output "primary_vm_status" {
  description = "Status da VM principal"
  value       = try(local.managed_vms["vm1"].power_state, "")
}

output "vm_summary" {
  description = "Resumo formatado das informações das VMs"
  value       = local.all_vms_info
}

output "vm_details" {
  value = join("\n\n", [
    for k, vm in local.managed_vms : <<-EOT
    📊 Detalhes da VM: ${k}
    ┌────────────────────────────────────────
    │ 🖥️  Nome:     ${vm.name}
    │ 🌐 IP:       ${vm.default_ip_address}
    │ 💻 CPU:      ${vm.num_cpus}
    │ 🧮 Memória:  ${vm.memory} MB
    └────────────────────────────────────────
    EOT
  ])
}
