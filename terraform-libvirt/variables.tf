##############################################
# Connection
##############################################

variable "libvirt_uri" {
  description = <<-EOT
    Libvirt connection URI.
      Local:  qemu:///system
      Remote: qemu+ssh://<user>@<host>/system?keyfile=<path>&known_hosts_verify=ignore
    The SSH user must be in the 'libvirt' group on the hypervisor.
  EOT
  type        = string
}

##############################################
# Image / storage
##############################################

variable "base_image" {
  description = <<-EOT
    Ubuntu cloud image the node disks overlay. A URL is downloaded into the
    pool once; a path must exist on the machine running tofu. Replaces the
    Proxmox clone-from-template flow — no template VM needed.
  EOT
  type        = string
  default     = "https://cloud-images.ubuntu.com/releases/26.04/release/ubuntu-26.04-server-cloudimg-amd64.img"
}

variable "pool" {
  description = "Storage pool for volumes and cloud-init seeds. Check `virsh pool-list`."
  type        = string
  default     = "default"
}

variable "disk_size_gb" {
  description = "OS disk size in GiB. Must be >= the base image's virtual size (~4G). growpart expands the filesystem on first boot."
  type        = number
  default     = 60
}

##############################################
# Machine
##############################################

variable "machine" {
  description = "QEMU machine type"
  type        = string
  default     = "q35"
}

variable "cpu_mode" {
  description = "'host-passthrough' for best performance on a single hypervisor; a named model only matters for live migration between hosts."
  type        = string
  default     = "host-passthrough"
}

variable "uefi_firmware" {
  description = <<-EOT
    Path to OVMF code on the HYPERVISOR to boot UEFI. On Arch (edk2-ovmf
    package): /usr/share/edk2/x64/OVMF_CODE.4m.fd. Empty = SeaBIOS, which
    Ubuntu cloud images boot fine. The Proxmox template's Secure Boot setup
    is deliberately dropped — nothing in the lab depends on it.
  EOT
  type        = string
  default     = ""
}

##############################################
# Network
##############################################

variable "network_bridge" {
  description = <<-EOT
    Existing Linux bridge on the hypervisor that VMs attach to. The provider
    cannot tag VLANs — if the lab moves back onto a tagged VLAN, build the
    bridge on a VLAN subinterface on the host (e.g. br30 on eno1.30) and name
    it here. On a flat network, a plain bridge enslaving the physical NIC.
    Check with `ip -br link show type bridge` on the hypervisor.
  EOT
  type        = string
  default     = "br0"
}

variable "subnet_prefix" {
  description = "CIDR prefix length. Ignored when a node has ip = null (DHCP)."
  type        = number
  default     = 24
}

variable "gateway" {
  description = "Default gateway. Ignored for DHCP nodes."
  type        = string
  default     = ""
}

variable "nameserver" {
  description = "DNS server. Ignored for DHCP nodes."
  type        = string
  default     = ""
}

variable "searchdomain" {
  description = "DNS search domain"
  type        = string
  default     = "lab.local"
}

##############################################
# Identity
##############################################

variable "ci_user" {
  description = "Cloud-init user. Ansible connects as this account."
  type        = string
  default     = "ubuntu"
}

variable "admin_ssh_public_keys" {
  description = <<-EOT
    Public keys authorized for ci_user. Bring your own - nothing is generated
    here, so no private key ever lands in Terraform state. The cluster's
    internal fan-out key is created later, on the control host, by Ansible.
  EOT
  type        = list(string)
}

##############################################
# Nodes
##############################################

variable "nodes" {
  description = <<-EOT
    VM definitions. Set ip = null for DHCP. pool is an optional per-node
    override of var.pool — use it to put the control plane's etcd on faster
    media than the workers. No vmid: libvirt identifies domains by name.
  EOT
  type = map(object({
    ip     = optional(string)
    cores  = number
    memory = number # MiB
    role   = string
    pool   = optional(string)
    # Per-node disk override. The jump host does not need a Kubernetes-sized
    # disk.
    disk_size_gb = optional(number)
    # Optional dedicated disk, mounted at /var/lib/etcd by Ansible. Attaches
    # as the second virtio disk (/dev/vdb inside the guest).
    etcd_disk_size_gb = optional(number)
    etcd_disk_pool    = optional(string)
  }))

  validation {
    condition     = alltrue([for n in var.nodes : contains(["control", "worker", "jump"], n.role)])
    error_message = "Each node role must be 'control', 'worker', or 'jump'."
  }

  validation {
    condition     = length([for n in var.nodes : n if n.role == "jump"]) <= 1
    error_message = "At most one jump host."
  }
}
