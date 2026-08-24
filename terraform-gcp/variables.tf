variable "project_id" {
  type        = string
  description = "Google Cloud project ID that owns the VPC, instances, and load balancer."
}

variable "region" {
  type        = string
  description = "Region for the subnet, Cloud NAT, static addresses, and regional Network Load Balancer."
}

variable "zone" {
  type        = string
  description = "Zone for all lab instances. It must belong to var.region."
}

variable "allowed_admin_ssh_cidrs" {
  type        = list(string)
  description = "IPv4 CIDRs allowed to SSH to the public bastion. Keep this limited to trusted administrator networks."

  validation {
    condition     = length(var.allowed_admin_ssh_cidrs) > 0 && alltrue([for cidr in var.allowed_admin_ssh_cidrs : can(cidrhost(cidr, 0))])
    error_message = "allowed_admin_ssh_cidrs must contain at least one valid CIDR."
  }
}

variable "subnet_cidr" {
  type        = string
  description = "Preferred RFC1918 IPv4 range for the GCP VPC subnet. It must not overlap any VPC, on-premises, VPN, or peered range."
  default     = "10.75.30.0/24"

  validation {
    condition     = can(cidrhost(var.subnet_cidr, 0)) && tonumber(element(split("/", var.subnet_cidr), 1)) >= 16 && tonumber(element(split("/", var.subnet_cidr), 1)) <= 29
    error_message = "subnet_cidr must be a valid IPv4 CIDR with a prefix between /16 and /29."
  }
}

variable "name_prefix" {
  type        = string
  description = "Lowercase prefix for every GCP resource created by this stack."
  default     = "k8s-teleport"

  validation {
    condition     = can(regex("^[a-z]([-a-z0-9]{0,61}[a-z0-9])?$", var.name_prefix))
    error_message = "name_prefix must be a lowercase GCP-compatible resource name."
  }
}

variable "ci_user" {
  type        = string
  description = "Linux user created by the GCE startup script. Ansible connects as this user."
  default     = "ubuntu"
}

variable "admin_ssh_public_keys" {
  type        = list(string)
  description = "Public keys authorized for ci_user on the bastion and all private cluster nodes. No private key is stored in Terraform state."

  validation {
    condition     = length(var.admin_ssh_public_keys) > 0
    error_message = "Provide at least one administrator SSH public key."
  }
}

variable "source_image" {
  type        = string
  description = "Ubuntu x86_64 source image or image family for Compute Engine."
  default     = "projects/ubuntu-os-cloud/global/images/family/ubuntu-2604-lts-amd64"
}

variable "boot_disk_type" {
  type        = string
  description = "Compute Engine persistent-disk type for boot volumes."
  default     = "pd-balanced"
}

variable "default_disk_size_gb" {
  type        = number
  description = "Default boot-volume size in GiB. Nodes may override it individually."
  default     = 60

  validation {
    condition     = var.default_disk_size_gb >= 20
    error_message = "default_disk_size_gb must be at least 20 GiB."
  }
}

variable "allowed_web_cidrs" {
  type        = list(string)
  description = "IPv4 client CIDRs allowed to reach the public Gateway on TCP 80 and 443. The default deliberately publishes the site."
  default     = ["0.0.0.0/0"]

  validation {
    condition     = length(var.allowed_web_cidrs) > 0 && alltrue([for cidr in var.allowed_web_cidrs : can(cidrhost(cidr, 0))])
    error_message = "allowed_web_cidrs must contain at least one valid CIDR."
  }
}

variable "nodes" {
  description = "Lab instances. Exactly one jump host is required; controls and workers remain private. memory is in MiB."
  type = map(object({
    cores             = number
    memory            = number
    role              = string
    machine_type      = optional(string)
    disk_size_gb      = optional(number)
    etcd_disk_size_gb = optional(number)
  }))

  validation {
    condition     = alltrue([for node in var.nodes : contains(["control", "worker", "jump"], node.role)])
    error_message = "Each node role must be control, worker, or jump."
  }

  validation {
    condition     = length([for node in var.nodes : node if node.role == "jump"]) == 1
    error_message = "Exactly one jump node is required."
  }

  validation {
    condition     = length([for node in var.nodes : node if node.role == "control"]) > 0 && length([for node in var.nodes : node if node.role == "worker"]) > 0
    error_message = "At least one control node and one worker node are required."
  }

  validation {
    condition     = alltrue([for node in var.nodes : node.cores > 0 && node.memory >= 1024])
    error_message = "Each node needs at least one vCPU and 1024 MiB of memory."
  }
}
