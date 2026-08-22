terraform {
  required_version = ">= 1.6.0"

  required_providers {
    proxmox = {
        source = "Telmate/proxmox"
        version = "3.0.2-rc09"
    }
    local = {
        source = "hashicorp/local"
        version = "~> 2.5"
    }
  }
}