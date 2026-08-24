# GCP deployment (optional)

Use this OpenTofu configuration instead of `../terraform-proxmox/` or
`../terraform-libvirt/` for a lab. It creates a custom VPC, private Kubernetes
nodes, Cloud NAT, a public bastion, and a regional external passthrough Network
Load Balancer.

The Network Load Balancer sends TCP 80 and 443 to the worker nodes. Cilium's
host-network Envoy accepts those connections, and the Gateway terminates TLS.
Responses use direct server return, so the firewall permits web client ranges
and the GCP health-check probers.

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
its TCP/22 firewall rule. Every other node receives packages through Cloud NAT
and Ansible reaches it with SSH ProxyJump. The startup script creates
`ci_user`, installs the supplied public keys, and grants the deployment user
passwordless sudo. GCE uses this startup script instead of the NoCloud seed
disk used by the Proxmox and libvirt configurations.

`tofu apply` writes `../ansible/inventory/hosts.ini`. The inventory places the
Kubernetes nodes in the `gcp` group, which selects `network_profile:
hostnetwork`. That disables Cilium L2 announcements and enables a host-network
Gateway on the workers. Cilium receives `NET_BIND_SERVICE`, allowing Envoy to
listen on TCP 80 and 443.

After the cluster build, point the DNS A record for `app_hostname` at the
`gateway_public_ip` output. Keep the Kubernetes API private. Tunnel it through
the bastion when running the post-deployment commands. Substitute the configured
`ci_user` if it is not `ubuntu`:

```bash
CONTROL_IP="$(tofu output -json node_addresses | jq -r '.\"ctrl-01\"')"
ssh -N -L 6443:${CONTROL_IP}:6443 ubuntu@"$(tofu output -raw bastion_public_ip)"
```

Then use the same endpoint override consistently. `make user` creates Alice's
CSR on the control plane, retrieves the signed bundle into
`rbac/out/alice/`, and verifies it through the tunnel:

```bash
make rbac KUBE_API_SERVER=https://127.0.0.1:6443 KUBE_TLS_SERVER_NAME="${CONTROL_IP}"
make user KUBE_API_SERVER=https://127.0.0.1:6443 KUBE_TLS_SERVER_NAME="${CONTROL_IP}"
make deploy KUBE_API_SERVER=https://127.0.0.1:6443 KUBE_TLS_SERVER_NAME="${CONTROL_IP}"
```
