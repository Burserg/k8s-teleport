# The base cloud image, fetched into the pool once. Every node's OS disk is
# a qcow2 overlay on top of it - the libvirt equivalent of "full clone from
# template", except the base stays read-only and clones are copy-on-write.
# 0.9.x: `source` became create.content.url (URL or local path, streamed
# into the pool) and capacity is computed from the download.
resource "libvirt_volume" "base" {
  name = "ubuntu-cloudimg-base.qcow2"
  pool = var.pool

  target = {
    format = {
      type = "qcow2"
    }
  }

  create = {
    content = {
      url = var.base_image
    }
  }
}

resource "libvirt_volume" "os" {
  for_each = var.nodes

  name = "${each.key}-os.qcow2"
  pool = coalesce(each.value.pool, var.pool)
  # Overlays can be any size >= the base's virtual size; Ubuntu cloud images
  # run growpart on first boot, so the filesystem expands automatically.
  capacity = coalesce(each.value.disk_size_gb, var.disk_size_gb) * 1024 * 1024 * 1024

  target = {
    format = {
      type = "qcow2"
    }
  }

  # 0.9.x replaces base_volume_id with the raw libvirt backingStore element:
  # the overlay references the base image by host path.
  backing_store = {
    path = libvirt_volume.base.path
    format = {
      type = "qcow2"
    }
  }
}

# Dedicated etcd volume. etcd fsyncs before acknowledging every write, so it
# is the only thing on the control plane that genuinely needs low-latency
# storage. Ansible formats and mounts this at /var/lib/etcd before kubeadm
# init (set etcd_data_device in group_vars/all.yml — /dev/vdb in the guest).
resource "libvirt_volume" "etcd" {
  for_each = { for k, v in var.nodes : k => v if v.etcd_disk_size_gb != null }

  name     = "${each.key}-etcd.qcow2"
  pool     = coalesce(each.value.etcd_disk_pool, each.value.pool, var.pool)
  capacity = each.value.etcd_disk_size_gb * 1024 * 1024 * 1024

  target = {
    format = {
      type = "qcow2"
    }
  }
}
