locals {
  # Address Kubernetes binds to. Static IPs come from tfvars.
  cluster_addresses = {
    for name, vm in libvirt_domain.node :
    name => coalesce(
      try(var.nodes[name].ip, null),
      "UNRESOLVED"
    )
  }

  jump_name    = try(one(keys(local.jumps)), "")
  jump_cluster = local.jump_name == "" ? "" : local.cluster_addresses[local.jump_name]
  jump_reach   = local.jump_cluster
}

resource "local_file" "inventory" {
  filename        = "${path.module}/../ansible/inventory/hosts.ini"
  file_permission = "0644"

  content = templatefile("${path.module}/templates/inventory.ini.tftpl", {
    controls     = { for k, v in local.controls : k => { cluster = local.cluster_addresses[k] } }
    workers      = { for k, v in local.workers : k => { cluster = local.cluster_addresses[k] } }
    ci_user      = var.ci_user
    jump_name    = local.jump_name
    jump_reach   = local.jump_reach
    jump_cluster = local.jump_cluster
    proxy_jump   = false
  })
}
