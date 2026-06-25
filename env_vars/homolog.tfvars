environment = "homolog"

// Configurações do ambiente de homologação
vm_template = "templates/ubuntu_24_04_template"

default_zone = "primary-zone"

zones = {
  primary-zone = {
    vsphere_server = "vcenter.example.com"
    data_center    = "Example-Datacenter"
    cluster        = "Example-Cluster"
    data_store     = "Example-Datastore"
    vm_name_prefix = "stg"
    networks = {
      "STAGING-APP" = {
        name            = "STAGING-APP"
        gateway         = "198.51.100.1"
        netmask         = 24
        dns_server_list = ["198.51.100.53", "198.51.100.54"]
        domain_name     = "staging.example.internal"
      }
      "STAGING-DATA" = {
        name            = "STAGING-DATA"
        gateway         = "198.51.100.129"
        netmask         = 25
        dns_server_list = ["198.51.100.53", "198.51.100.54"]
        domain_name     = "staging.example.internal"
      }
    }
  }
}

vm = {
  vm1 = {
    name         = "HOMOLOG1"
    hostname     = "homolog1"
    cpus         = 1
    memory       = 2024
    disk_size    = 30
    network      = "STAGING-APP"
    ipv4_address = "198.51.100.76"
    folder       = "STAGING"
  }
}
