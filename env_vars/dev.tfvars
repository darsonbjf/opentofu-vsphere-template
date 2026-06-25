environment = "dev"

// Configurações do ambiente de desenvolvimento
vm_template = "templates/ubuntu_24_04_template"

default_zone = "primary-zone"

zones = {
  primary-zone = {
    vsphere_server = "vcenter.example.com"
    data_center    = "Example-Datacenter"
    cluster        = "Example-Cluster"
    data_store     = "Example-Datastore"
    vm_name_prefix = "dev"
    networks = {
      "DEV-NET" = {
        name            = "DEV-NET"
        gateway         = "192.0.2.1"
        netmask         = 24
        dns_server_list = ["192.0.2.53", "192.0.2.54"]
        domain_name     = "dev.example.internal"
      }
    }
  }
}

vm = {
  vm1 = {
    name                       = "VM1"
    hostname                   = "dev-srv1"
    cpus                       = 4
    memory                     = 2048
    disk_size                  = 100
    disk_size_data             = 500
    network                    = "DEV-NET"
    ipv4_address               = "192.0.2.10"
    folder                     = "DEVELOPMENT"
    wait_for_guest_net_timeout = 300
  }
}
