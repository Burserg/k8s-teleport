# GCP deployment (optional)

This OpenTofu configuration is an alternative to `../terraform/` and
`../terraform-libvirt/`; run only one provider stack for a lab at a time.
It creates a custom VPC, private Kubernetes nodes, Cloud NAT, a public
bastion, and a regional external passthrough Network Load Balancer.

The Network Load Balancer forwards TCP 80 and 443 to the worker nodes. It is
not a TLS proxy: Cilium's host-network Envoy accepts the connections and the
Gateway terminates TLS. Responses use direct server return, so the firewall
allows the actual web client source ranges as well as the GCP health-check
probers.

## Required configuration

Copy the example and provide your project, region, zone, administrator CIDR,
and public key:

```bash
cp terraform.tfvars.example terraform.tfvars
tofu init
tofu plan
tofu apply
```

The provider uses Application Default Credentials. Authenticate before
planning, and ensure the project allows Compute Engine resources:

```bash
gcloud auth application-default login
```

`subnet_cidr` defaults to `10.75.30.0/24`. A preferred RFC1918 CIDR is valid
on GCP, provided it does not overlap a connected VPC, peered network, VPN, or
on-premises range. The validation enforces a GCP-compatible IPv4 prefix, but
it cannot discover external route overlaps.

## Access and deployment

Only the bastion has a public IPv4 address. `allowed_admin_ssh_cidrs` controls
its TCP/22 firewall rule; all other nodes receive packages through Cloud NAT
and are reached by Ansible using SSH ProxyJump. The startup script creates
`ci_user`, installs the supplied public keys, and grants that deployment user
passwordless sudo. This is the GCE-native replacement for the NoCloud seed
disk used by the Proxmox and libvirt configurations.

`tofu apply` writes `../ansible/inventory/hosts.ini`. The inventory places the
Kubernetes nodes in the `gcp` group, which selects `network_profile:
hostnetwork`. That disables Cilium L2 announcements and enables a host-network
Gateway on the workers. Cilium receives `NET_BIND_SERVICE`, allowing Envoy to
listen on TCP 80 and 443.

After the cluster build, point the DNS A record for `app_hostname` at the
`gateway_public_ip` output, then continue with the usual `make rbac`, `make
user`, and `make deploy` workflow.
