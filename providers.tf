terraform {
  backend "s3" {}

  # Adicionar versões específicas para todos os providers
  required_providers {
    vsphere = {
      source  = "vmware/vsphere"
      version = "2.14.2"
    }
  }

  # OpenTofu 1.11.6 foi validado com backend S3/Ceph RGW e lockfile nativo.
  required_version = ">= 1.11.6, < 1.12.0"
}

provider "vsphere" {
  vsphere_server       = local.provider_vsphere_server
  user                 = var.username
  password             = var.password
  allow_unverified_ssl = var.vsphere_allow_unverified_ssl
  api_timeout          = 30
  persist_session      = false
}
