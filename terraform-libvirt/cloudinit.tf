# NoCloud seed ISO per node, replacing Proxmox's ciuser/sshkeys/ipconfig0
# attributes.
resource "libvirt_cloudinit_disk" "seed" {
  for_each = var.nodes

  name = "${each.key}-seed"

  meta_data = <<-EOT
    instance-id: ${each.key}
    local-hostname: ${each.key}
  EOT

  user_data = templatefile("${path.module}/templates/user_data.yml.tftpl", {
    hostname     = each.key
    searchdomain = var.searchdomain
    ci_user      = var.ci_user
    ssh_keys     = [for k in var.admin_ssh_public_keys : trimspace(k)]
  })

  network_config = templatefile("${path.module}/templates/network_config.yml.tftpl", {
    ip           = each.value.ip
    prefix       = var.subnet_prefix
    gateway      = var.gateway
    nameserver   = var.nameserver
    searchdomain = var.searchdomain
  })
}

resource "libvirt_volume" "seed" {
  for_each = var.nodes

  name = "${each.key}-seed.iso"
  pool = var.pool

  target = {
    format = {
      type = "iso"
    }
  }

  create = {
    content = {
      url = libvirt_cloudinit_disk.seed[each.key].path
    }
  }
}
