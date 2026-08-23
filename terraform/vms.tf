locals {
  controls = { for k, v in var.nodes : k => v if v.role == "control" }
  workers  = { for k, v in var.nodes : k => v if v.role == "worker" }
  jumps    = { for k, v in var.nodes : k => v if v.role == "jump" }

  sshkeys = join("\n", [for k in var.admin_ssh_public_keys : trimspace(k)])
}

resource "proxmox_vm_qemu" "node" {
    for_each = var.nodes

    name = each.key
    vmid = each.value.vmid
    target_node = var.target_node
    description = "Managed by Terraform - ${each.value.role}"
    tags = "terraform,lab"
    clone = var.template_name
    full_clone = true

    bios = var.bios
    scsihw = var.scsihw
    boot = "order=${var.os_disk_slot}"

    dynamic "efidisk" {
      for_each = var.bios == "ovmf" ? [1] : []
      content {
        storage = coalesce(each.value.storage, var.storage)
        efitype = "4m"
        pre_enrolled_keys = var.efi_pre_enrolled_keys
      }
    }

    cpu {
      cores = each.value.cores
      sockets = 1
      type = var.cpu_type
    }

    memory = each.value.memory
    agent = var.qemu_agent ? 1 : 0
    agent_timeout = 120
    start_at_node_boot = true

    disk {
        slot = var.cloudinit_slot
        type = "cloudinit"
        storage = coalesce(each.value.storage, var.storage)
    }

    disk {
      slot = var.os_disk_slot
      type = "disk"
      storage = coalesce(each.value.storage, var.storage)
      size = coalesce(each.value.disk_size, var.disk_size)
      discard = var.disk_discard
      iothread = var.disk_iothread
    }
    
    dynamic "disk" {
        for_each = each.value.etcd_disk_size == null ? [] : [1]
        content {
          slot = "scsi2"
          type = "disk"
          storage = each.value.etcd_disk_storage
          size = each.value.etcd_disk_size
          discard = var.disk_discard
          iothread = var.disk_iothread
        }
    }

    dynamic "serial" {
        for_each = var.serial_console ? [1] : []
        content {
          id = 0
          type = "socket"
        }
    }

    dynamic "vga" {
        for_each = var.serial_console ? [1] : []
        content {
          type = "serial0"
        }
    }

    network {
      id = 0
      model = "virtio"
      bridge = var.network_bridge
      tag = var.vlan_tag
      firewall = false
    }

    dynamic "network" {
      for_each = each.value.mgmt_ip == null ? [] : [1]
      content {
        id = 1
        model = "virtio"
        bridge = var.mgmt_network_bridge
        tag = var.mgmt_vlan_tag
        firewall = false
      }
    }

    os_type = "cloud-init"
    ciuser = var.ci_user
    sshkeys = local.sshkeys
    nameserver = var.nameserver
    searchdomain = var.searchdomain
    ciupgrade = true
    skip_ipv6 = true

    ipconfig0 = each.value.ip == null ? "ip=dhcp" : (
        each.value.role == "jump" && var.mgmt_gateway != ""
        ? "ip=${each.value.ip}/${var.subnet_prefix}"
        : "ip=${each.value.ip}/${var.subnet_prefix},gw=${var.gateway}"
        )

    ipconfig1 = each.value.mgmt_ip == null ? null : (
        var.mgmt_gateway == ""
        ? "ip=${each.value.mgmt_ip}/${var.mgmt_subnet_prefix}"
        : "ip=${each.value.mgmt_ip}/${var.mgmt_subnet_prefix},gw=${var.mgmt_gateway}"
        )
        
    define_connection_info = false

    lifecycle {
      ignore_changes = [qemu_os]
    }
}
