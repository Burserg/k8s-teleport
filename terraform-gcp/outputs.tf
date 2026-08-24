output "node_addresses" {
  description = "Private address per Kubernetes node."
  value       = local.cluster_addresses
}

output "bastion_public_ip" {
  description = "Public SSH address for the bastion."
  value       = google_compute_address.bastion.address
}

output "gateway_public_ip" {
  description = "Regional external passthrough Network Load Balancer address. Point the application DNS record here."
  value       = google_compute_address.gateway.address
}

output "next_steps" {
  value = <<-EOT

    Inventory written to ansible/inventory/hosts.ini
    Cluster nodes are private and Ansible reaches them through the bastion.

      cd ../ansible
      ansible-galaxy collection install -r requirements.yml
      ansible-playbook preflight.yml
      ansible-playbook site.yml

    Point the DNS A record for app_hostname at gateway_public_ip before
    requesting a production ACME certificate.
  EOT
}
