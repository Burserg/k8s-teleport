output "node_addresses" {
  description = "Address per node, static or agent-reported"
  value       = local.cluster_addresses
}

output "vm_ids" {
  value = { for name, vm in proxmox_vm_qemu.node : name => vm.vmid }
}

output "jump_host" {
  description = "Bastion address, if one is defined"
  value       = local.jump_reach
}

output "next_steps" {
  value = <<-EOT

    Inventory written to ansible/Inventory/hosts.ini
    Kubernetes nodes are reachable only through the bastion.

      cd ../ansible
      ansible-galaxy collection install -r requirements.yml
      ansible-playbook preflight.yml
      ansible-playbook site.yml
  EOT
}
