locals {
  # Address Kubernetes binds to. Static IPs come from tfvars; the 0.9.x
  # provider no longer exposes lease addresses on the domain (that would be
  # wait_for_ip plumbing on the interface), so static is required here.
  cluster_addresses = {
    for name, vm in libvirt_domain.node :
    name => coalesce(
      try(var.nodes[name].ip, null),
      "UNRESOLVED"
    )
  }

  jump_name    = try(one(keys(local.jumps)), "")
  jump_cluster = local.jump_name == "" ? "" : local.cluster_addresses[local.jump_name]

  # 192.168.2.0/24 is flat and directly routable from the control machine,
  # so the dual-homed bastion / ProxyJump machinery from the Proxmox VLAN
  # topology is gone. The bastion remains a bastion for humans, not a
  # mandatory hop for automation.
  jump_reach = local.jump_cluster
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
