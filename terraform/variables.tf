# Proxmox Connection
variable "proxmox_endpoint" {
    type = string
    description = "Proxmox API full URL https://example.local:8006/api2/json"
}

variable "proxmox_api_token" {
    type = string
    sensitive = true
    description = "Proxmox API Token ID. Probably best to export it via PM_API_TOKEN_ID"
    default = ""
}

variable "proxmox_api_secret" {
    type = string
    sensitive = true
    description = "Proxmox API Token Secret. Probably best to export it via PM_API_TOKEN_SECRET"
    default = ""
}

variable "proxmox_tls_insecure" {
    type = bool
    default = true
    description = "Accept self-signed Proxmox certificates"
}

variable "target_node" {
    type = string
    description = "Proxmox node name"
}

# Template vars

variable "template_name" {
    type = string
    description = "Name of the cloud-init template to clone"
}

variable "storage" {
    type = string
    description = "Define the storage pool for the cloned disk"
}

variable "bios" {
    type = string
    description = "Must match the template bios type or VMs will not boot"
    default = "ovmf"
    
    validation {
      condition = contains(["seabios", "ovmf"], var.bios)
      error_message = "bios must be seabios or ovmf."
    }
}

variable "machine" {
    type = string
    description = "'q35' or 'i440fx' Use q35 for modern features, i440fx for compat"
    default = "q35"

    validation {
      condition = contains(["q35", "i440fx"], var.machine)
      error_message = "machine must be q35 or i440fx."
    }
}

variable "efi_pre_enrolled_keys" {
    type = bool
    default = false
    description = "Secure Boot keys should be pre-enrolled. Used when bios = ovmf"
}

variable "scsihw" {
    type = string
    default = "virtio-scsi-single"
    description = "SCSI controller. Must match the VM template"
}

variable "serial_console" {
    type = bool
    default = true
    description = "Add serial0 (socket) and sets the display to serial0 for cloud-init images."
}

variable "cloudinit_slot" {
    type = string
    default = "scsi1"
    description = "Slot holding the cloud-init drive. Normally ide2 or scsi1. Look at VM template config"
}

variable "os_disk_slot" {
    type = string
    default = "scsi0"
    description = "Slot holding the OS disk, normally scsi0 of scsi1. Look at VM template config"
}

variable "disk_size" {
    type = string
    default = "40G"
    description = "OS disk size. Must be >= templated VM disk. If larger, will auto grow."
}

variable "disk_discard" {
    type = bool
    default = true
    description = "Pass TRIM to the datastore. Recommended on ZFS / LVM-thin datastores."
}

variable "disk_iothread" {
    type = bool
    default = true
    description = "Asls the host to wait for an IO complete on a different thread. Lowers latency. See https://kb.blockbridge.com/technote/proxmox-aio-vs-iouring/"
}

variable "cpu_type" {
    type = string
    default = "host"
    description = "Set based on the target node architecture. See https://pve.proxmox.com/pve-docs/pve-admin-guide.html#_cpu_type"
}

variable "qemu_agent" {
    type = bool
    default = false
    description = "Set to true if the qemu-guest-agent is installed. If set to true and agent is not installed, VM will hang."
}

# Network

variable "network_bridge" {
    type = string
    default = "vmbr0"
    description = "Network bridge that the VM is attached to"
}

variable "vlan_tag" {
    type = number
    default = 0
    description = "802.1q VLAN tag. 0 is untagged. If VLANs are not trunked, use 0."
}

variable "subnet_prefix" {
    type = number
    default = 24
    description = "Number of mask bits in the network. Example: 192.168.1.0/(24)"
}

variable "gateway" {
    type = string
    default = "" 
    description = "Default gateway. Ignored for DHCP nodes."
}

variable "nameserver" {
    type = string
    default = ""
    description = "DNS server(s), space separated. Leave empty to pull from DHCP."
}

variable "searchdomain" {
    type = string
    default = ".local"
    description = "DNS search domain"
}

# Management network

variable "mgmt_network_bridge" {
    type = string
    default = "vmbr0"
    description = "Network bridge that the VM is attached to"
}

variable "mgmt_vlan_tag" {
    type = number
    default = 0
    description = "802.1q VLAN tag. 0 is untagged. If VLANs are not trunked, use 0."
}

variable "mgmt_subnet_prefix" {
    type = number
    default = 24
    description = "Number of mask bits in the network. Example: 192.168.1.0/(24)"
}

variable "mgmt_gateway" {
    type = string
    default = "" 
    description = <<-EOT
        Leave empty unless you want the default route to leave via mgmt interface.
        A node with two default routes can black-hole return traffic. Use mgmt_static_routes instead.
    EOT
}

variable "mgmt_nameserver" {
    type = string
    default = ""
    description = "DNS server(s), space separated. Leave empty to pull from DHCP."
}

# Identity

variable "ci_user" {
    type = string
    default = "ubuntu"
    description = "Cloud-init default user. Ansible will connect as this account."
}

variable "admin_ssh_public_keys" {
    type = list(string)
    description = <<-EOT
        Public key authorized for ci_user. These are the keys that you will use to connect
        to the VM.
    EOT
}

# Nodes

variable "nodes" {
  description = "Defines a single node that will be deployed"
  type = map(object({
    vmid = number
    ip = optional(string)
    cores = number
    memory = number
    role = string
    storage = optional(string)
    disk_size = optional(string)
    etcd_disk_size = optional(string)
    etcd_disk_storage = optional(string)
    mgmt_ip = optional(string)
    proxy_jump = optional(bool, false)
  }))

  validation {
    condition = alltrue([
      for name, node in var.nodes :
      node.mgmt_ip != null && trimspace(coalesce(node.mgmt_ip, "")) != ""
      if coalesce(node.proxy_jump, false)
    ])
    error_message = format(
      "Nodes with proxy_jump must also set mgmt_ip. Offending nodes: %s",
      join(", ", [
        for name, node in var.nodes : name
        if coalesce(node.proxy_jump, false) && trimspace(coalesce(node.mgmt_ip, "")) == ""
      ])
    )
  }

  validation {
    condition = alltrue([for n in var.nodes : contains(["control", "worker", "jump"], n.role)])
    error_message = "Each node role must be 'control', 'worker', 'jump'."
  }

  validation {
    condition = alltrue([
      for n in var.nodes :
      (n.etcd_disk_size == null) == (n.etcd_disk_storage == null)
    ])
    error_message = "etcd_disk_size and etcd_disk_storage must be set together."
  }
}