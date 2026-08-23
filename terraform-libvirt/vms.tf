locals {
  controls = { for k, v in var.nodes : k => v if v.role == "control" }
  workers  = { for k, v in var.nodes : k => v if v.role == "worker" }
  jumps    = { for k, v in var.nodes : k => v if v.role == "jump" }
}

# 0.9.x mirrors raw libvirt domain XML: type/os/devices instead of the old
# flat machine/firmware/disk/network_interface attributes.
resource "libvirt_domain" "node" {
  for_each = var.nodes

  name        = each.key
  type        = "kvm"
  vcpu        = each.value.cores
  memory      = each.value.memory
  memory_unit = "MiB"
  autostart   = true
  running     = true

  cpu = {
    mode = var.cpu_mode
  }
  
  features = {
    acpi = true
    apic = {}
  }

  os = {
    type         = "hvm"
    type_machine = var.machine
    boot_devices = [{ dev = "hd" }]

    # UEFI: the old firmware=<path> shorthand is now the explicit pflash
    # loader element. libvirt matches the path against its firmware
    # descriptors and creates the per-domain NVRAM from the matching
    # OVMF_VARS template. Empty var = SeaBIOS, same as before.
    loader          = var.uefi_firmware != "" ? var.uefi_firmware : null
    loader_type     = var.uefi_firmware != "" ? "pflash" : null
    loader_readonly = var.uefi_firmware != "" ? "yes" : null
  }

  devices = {
    disks = concat(
      # /dev/vda in the guest.
      [{
        source = {
          volume = {
            pool   = libvirt_volume.os[each.key].pool
            volume = libvirt_volume.os[each.key].name
          }
        }
        target = { dev = "vda", bus = "virtio" }
        driver = { name = "qemu", type = "qcow2" }
      }],
      # /dev/vdb: dedicated etcd volume, only on nodes that declare one.
      each.value.etcd_disk_size_gb == null ? [] : [{
        source = {
          volume = {
            pool   = libvirt_volume.etcd[each.key].pool
            volume = libvirt_volume.etcd[each.key].name
          }
        }
        target = { dev = "vdb", bus = "virtio" }
        driver = { name = "qemu", type = "qcow2" }
      }],
      # NoCloud seed, attached read-only on the q35 SATA bus. The old
      # `cloudinit = <id>` attribute is gone — the seed is just a cdrom now.
      [{
        device    = "cdrom"
        read_only = true
        source = {
          volume = {
            pool   = libvirt_volume.seed[each.key].pool
            volume = libvirt_volume.seed[each.key].name
          }
        }
        target = { dev = "sda", bus = "sata" }
        driver = { name = "qemu", type = "raw" }
      }]
    )

    interfaces = [{
      model = { type = "virtio" }
      source = {
        bridge = { bridge = var.network_bridge }
      }
    }]

    # Ubuntu cloud images direct the console to ttyS0; without this the
    # "display" is blank everywhere — which looks exactly like a failed boot.
    # Attach with: virsh console <name>
    # No source block: the schema's source.pty demands a path, but a console
    # without a type attribute defaults to pty in libvirt and the pty path is
    # runtime-assigned (dmacvicar/terraform-provider-libvirt#1332).
    consoles = [{
      target = { type = "serial", port = 0 }
    }]

    graphics = [{
      vnc = { auto_port = true }
    }]
  }
}
