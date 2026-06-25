environment = "prod"

// Configurações do ambiente de produção
vm_template = "templates/ubuntu_24_04_template"

default_zone = "primary-zone"

zones = {
  primary-zone = {
    vsphere_server = "vcenter.example.com"
    data_center    = "Example-Datacenter"
    cluster        = "Example-Cluster"
    data_store     = "Example-Datastore"
    vm_name_prefix = "prd"
    networks = {
      "PROD-APP" = {
        name            = "PROD-APP"
        gateway         = "203.0.113.1"
        netmask         = 25
        dns_server_list = ["203.0.113.53", "203.0.113.54"]
        domain_name     = "prod.example.internal"
      }
      "PROD-DATA" = {
        name            = "PROD-DATA"
        gateway         = "203.0.113.129"
        netmask         = 25
        dns_server_list = ["203.0.113.53", "203.0.113.54"]
        domain_name     = "prod.example.internal"
      }
    }
  }
}

vm = {
  vm1 = {
    name         = "PRODUCTION1"
    hostname     = "prod1"
    cpus         = 1
    memory       = 2024
    disk_size    = 30
    network      = "PROD-APP"
    ipv4_address = "203.0.113.11"
    folder       = "PRODUCTION"
  }
}
