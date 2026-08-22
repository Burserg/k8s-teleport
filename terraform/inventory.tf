locals {
  # Address Kubernetes binds to: always the cluster VLAN.
    cluster_addresses = {
        for name, vm in proxmox_vm_qemu.node :
        name => coalesce(
            try(var.nodes[name].ip, null),
            try(vm.default_ipv4_address, null),
            "UNRESOLVED"
        )
    }
    jump_name = try(one(keys(local.jumps)), "")
    jump_cluster = local.jump_name == "" ? "" : local.cluster_addresses[local.jump_name]

    # Bastion is available via its management address
    jump_reach = local.jump_name == "" ? "" : coalesce(
        try(var.nodes[local.jump_name].mgmt_ip, null),
        local.jump_cluster
    )

    needs_proxy_jump = local.jump_name != "" && try(var.nodes[local.jump_name].proxy_jump, null)
}

resource "local_file" "inventory" {
    filename = "${path.module}/../ansible/inventory/hosts.ini"
    file_permission = "0644"

    content = templatefile("${path.module}/templates/inventory.ini.tftpl", {
        controls = { for k, v in local.controls : k => { cluster = local.cluster_addresses[k] } }
        workers = { for k, v in local.workers : k => { cluster = local.cluster_addresses[k] } }
        ci_user = var.ci_user
        jump_name = local.jump_name
        jump_reach = local.jump_reach
        jump_cluster = local.jump_cluster
        proxy_jump = local.needs_proxy_jump
    })
}