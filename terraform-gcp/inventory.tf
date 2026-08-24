locals {
  cluster_addresses = {
    for name, instance in google_compute_instance.node : name => instance.network_interface[0].network_ip
    if var.nodes[name].role != "jump"
  }
}

resource "local_file" "inventory" {
  filename        = "${path.module}/../ansible/inventory/hosts.ini"
  file_permission = "0644"

  content = templatefile("${path.module}/templates/inventory.ini.tftpl", {
    controls     = { for name, node in local.controls : name => { cluster = local.cluster_addresses[name] } }
    workers      = { for name, node in local.workers : name => { cluster = local.cluster_addresses[name] } }
    ci_user      = var.ci_user
    jump_name    = local.jump_name
    jump_reach   = google_compute_address.bastion.address
    jump_cluster = google_compute_instance.node[local.jump_name].network_interface[0].network_ip
  })
}
