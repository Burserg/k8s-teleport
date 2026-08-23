output "node_addresses" {
  description = "Address per node"
  value       = local.cluster_addresses
}

output "jump_host" {
  description = "Bastion address, if one is defined"
  value       = local.jump_reach
}

output "next_steps" {
  value = <<-EOT

    Inventory written to ansible/inventory/hosts.ini

      cd ../ansible
      ansible-galaxy collection install -r requirements.yml
      ansible-playbook preflight.yml
      ansible-playbook site.yml
  EOT
}
