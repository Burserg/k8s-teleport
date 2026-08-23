terraform {
  required_version = ">= 1.6.0"

  required_providers {
    libvirt = {
      source = "dmacvicar/libvirt"
      # 0.9.x is a ground-up rewrite that mirrors raw libvirt domain XML —
      # this config is written against that schema. Do not drop back to
      # 0.8.x without rewriting vms.tf/volumes.tf/cloudinit.tf.
      version = "0.9.8"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.5"
    }
  }
}
