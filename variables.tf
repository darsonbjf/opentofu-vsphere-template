# Configurações de Hardware
variable "net_adapter_type" {
  default     = "vmxnet3"
  description = "Defina o tipo de adaptador. EX: e1000e, vmxnet3"
  type        = string
  validation {
    condition     = contains(["e1000e", "vmxnet3"], var.net_adapter_type)
    error_message = "O valor do tipo de adaptador deve ser informado."
  }
}

variable "vm_template" {
  description = "Caminho do template da VM"
  type        = string
  validation {
    condition     = length(var.vm_template) > 0
    error_message = "O nome do template deve ser informado."
  }
}

variable "firmware" {
  default     = "efi"
  description = "Defina o firmware. EX: efi"
  type        = string
  validation {
    condition     = contains(["efi", "bios"], var.firmware)
    error_message = "O valor do firmware deve ser efi or bios."
  }
}

# Credenciais vSphere
variable "username" {
  description = "Defina o nome de usuario com acesso ao Vsphere"
  sensitive   = true
  type        = string
  validation {
    condition     = length(var.username) > 0
    error_message = "O nome de usuario do Vsphere deve ser informado."
  }
}

variable "password" {
  description = "Defina a senha de usuário do Vsphere"
  sensitive   = true
  type        = string
  validation {
    condition     = length(var.password) > 0
    error_message = "A senha do usuário do Vsphere deve ser informada."
  }
}

variable "vsphere_allow_unverified_ssl" {
  description = "Permite conexao TLS sem verificacao com o vCenter. Mantido como true por decisao operacional em ambiente controlado."
  type        = bool
  default     = true
}

# Configurações de Storage
variable "thin_provisioned" {
  default     = true
  description = "Defina o thin_provisioned. EX: true"
  type        = bool
}

# Configurações de Rede
locals {
  ipv4_address_pattern = "^((25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9]?[0-9])\\.){3}(25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9]?[0-9])$"
  vm_folder_by_cidr = {
    "192.0.2.0/24"    = "DEVELOPMENT"
    "198.51.100.0/24" = "STAGING"
    "203.0.113.0/24"  = "PRODUCTION"
  }
  environment_folder_by_name = {
    dev     = "DEVELOPMENT"
    homolog = "STAGING"
    prod    = "PRODUCTION"
  }
}

variable "domain" {
  description = "Nome do domínio"
  type        = string
  default     = "example.internal"
  validation {
    condition     = can(regex("^[a-zA-Z0-9][a-zA-Z0-9-\\.]*[a-zA-Z0-9]\\.[a-zA-Z]{2,}$", var.domain))
    error_message = "O domínio deve ser um FQDN válido."
  }
}

variable "default_zone" {
  type        = string
  description = "Zona padrao de infraestrutura usada por VMs que nao definem zone"
  default     = "primary-zone"

  validation {
    condition     = length(trimspace(var.default_zone)) > 0 && contains(keys(var.zones), var.default_zone)
    error_message = "A zona padrao deve ser informada e existir em zones."
  }
}

variable "zones" {
  type = map(object({
    vsphere_server = string
    data_center    = string
    cluster        = string
    data_store     = string
    vm_name_prefix = optional(string, "")
    networks = map(object({
      name            = string
      gateway         = string
      netmask         = number
      dns_server_list = list(string)
      domain_name     = string
    }))
  }))
  description = "Zonas de infraestrutura que decidem vCenter, datacenter, cluster, datastore, redes e prefixo opcional de nome"

  validation {
    condition     = length(var.zones) > 0
    error_message = "Ao menos uma zona de infraestrutura deve ser informada."
  }

  validation {
    condition = alltrue([
      for zone in var.zones : (
        length(zone.vsphere_server) > 0 &&
        length(zone.data_center) > 0 &&
        length(zone.cluster) > 0 &&
        length(zone.data_store) > 0 &&
        length(zone.networks) > 0
      )
    ])
    error_message = "Cada zona deve informar vsphere_server, data_center, cluster, data_store e ao menos uma rede."
  }

  validation {
    condition     = length(distinct([for zone in var.zones : zone.vsphere_server])) <= 1
    error_message = "O projeto usa um unico provider vSphere por execucao. Todas as zonas do ambiente devem apontar para o mesmo vsphere_server."
  }

  validation {
    condition = alltrue(flatten([
      for zone in var.zones : [
        for network in zone.networks : (
          network.netmask >= 1 &&
          network.netmask <= 32 &&
          network.netmask == floor(network.netmask)
        )
      ]
    ]))
    error_message = "Cada rede deve informar netmask IPv4 inteiro entre 1 e 32."
  }

  validation {
    condition = alltrue(flatten([
      for zone in var.zones : [
        for network in zone.networks : (
          can(regex(local.ipv4_address_pattern, network.gateway)) &&
          alltrue([
            for dns_server in network.dns_server_list : can(regex(local.ipv4_address_pattern, dns_server))
          ])
        )
      ]
    ]))
    error_message = "Gateways e DNS das redes devem estar em formato IPv4 valido."
  }
}

# Configurações das VMs
variable "vm" {
  type = map(object({
    ipv4_address               = string
    name                       = string
    hostname                   = string
    network                    = string
    zone                       = optional(string)
    memory                     = number
    cpus                       = number
    disk_size                  = number
    disk_size_data             = optional(number)
    folder                     = optional(string)
    guest_id                   = optional(string)
    wait_for_guest_net_timeout = optional(number, 5)
  }))

  description = "Configuração das máquinas virtuais"

  validation {
    condition = alltrue([
      for vm in var.vm : (
        vm.memory >= 1024 &&
        vm.disk_size >= 20 &&
        vm.cpus >= 1 &&
        (vm.zone == null || length(trimspace(vm.zone)) > 0) &&
        (vm.guest_id == null || length(vm.guest_id) > 0)
      )
    ])
    error_message = "Memoria deve ser >= 1024, disco minimo 20GB, CPUs minimo 1, zone nao pode ser vazia quando informada e guest_id nao pode ser vazio quando informado."
  }

  validation {
    condition = alltrue([
      for vm in var.vm : (
        can(regex(local.ipv4_address_pattern, vm.ipv4_address))
      )
    ])
    error_message = "O IP da VM deve estar em formato IPv4 valido."
  }

  validation {
    condition = alltrue([
      for vm in var.vm : (
        vm.zone == null || contains(keys(var.zones), vm.zone)
      )
    ])
    error_message = "A zone da VM, quando informada, deve existir em zones."
  }

  validation {
    condition = alltrue([
      for vm in var.vm : can(var.zones[coalesce(vm.zone, var.default_zone)].networks[vm.network])
    ])
    error_message = "A network de cada VM deve existir na zona efetiva da VM."
  }

  validation {
    condition = alltrue([
      for vm in var.vm : try(cidrcontains(
        "${var.zones[coalesce(vm.zone, var.default_zone)].networks[vm.network].gateway}/${var.zones[coalesce(vm.zone, var.default_zone)].networks[vm.network].netmask}",
        vm.ipv4_address
      ), false)
    ])
    error_message = "O IP da VM deve pertencer ao CIDR da network declarada na zona efetiva."
  }

  validation {
    condition = alltrue([
      for vm in var.vm : try(length([
        for cidr, folder in local.vm_folder_by_cidr : folder if cidrcontains(cidr, vm.ipv4_address)
      ]) == 1, false)
    ])
    error_message = "O IP da VM deve pertencer a uma faixa conhecida de folder: 192.0.2.0/24 (DEVELOPMENT), 198.51.100.0/24 (STAGING) ou 203.0.113.0/24 (PRODUCTION)."
  }

  validation {
    condition = alltrue([
      for vm in var.vm : try([
        for cidr, folder in local.vm_folder_by_cidr : folder if cidrcontains(cidr, vm.ipv4_address)
      ][0] == local.environment_folder_by_name[var.environment], false)
    ])
    error_message = "O IP da VM deve pertencer a uma faixa compativel com environment: dev=192.0.2.0/24, homolog=198.51.100.0/24, prod=203.0.113.0/24."
  }

  validation {
    condition = alltrue([
      for vm in var.vm : (
        vm.folder == null ||
        try(vm.folder == [
          for cidr, folder in local.vm_folder_by_cidr : folder if cidrcontains(cidr, vm.ipv4_address)
        ][0], false)
      )
    ])
    error_message = "Quando informado, folder deve corresponder ao folder derivado de ipv4_address. Consulte a tabela CIDR -> folder em docs/INFRASTRUCTURE_ZONES.md."
  }
}

# Configurações de Ambiente
variable "environment" {
  type        = string
  description = "Ambiente de deploy (dev, homolog, prod)"

  validation {
    condition     = contains(["dev", "homolog", "prod"], var.environment)
    error_message = "O ambiente deve ser 'dev', 'homolog' ou 'prod'."
  }
}

variable "guest_id" {
  description = "ID padrao do sistema operacional guest usado quando a VM nao define guest_id"
  type        = string
  default     = "ubuntu64Guest"

  validation {
    condition     = length(var.guest_id) > 0
    error_message = "O guest_id padrao deve ser informado."
  }
}
