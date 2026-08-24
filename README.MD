# Kubernetes Deployment Lab - Teleport
 
## Overview

Lab has been built with two different terraform configurations. One with Proxmox as the base, and the other using libvirt as the base.

The final build is live on both Proxmox and my local Archlinux machine. I have a third *break glass* option in GCP if needed.

I chose to run the latest releases of the components since this is a new deployment and the configured components have referenced using these versions in tandem with the K8s version selected.

I wanted to pick the latest LTS for Ubuntu which had access to all of the latest packages. OpenTofu is used for terraform management. Ansible does majority of the heavy lifing here as I wanted to ensure that I could redeploy easily should things go wrong (and they did).

Cilium was chosen because it takes the place of a number of components and does so efficiently and provides detailed insight into networking since it utilizes eBPF allowing for a number of generally helpful security measures as well as observability through Hubble. It takes the place of kube-proxy and since nginx-ingress is retired it also acts as a capable replacement Load Balancer.

Flux was chosen due to its simplicity. I have used it before with other projects and found it to be a simple and secure GitOps deployment engine. It's customizable and respects RBAC. Everything is policy driven so keeping components locked down while allowing developers the option to deploy complex apps with a few config files is a huge win. It's multi-tenant and has a number of integrations making it the right choice here. Although ArgoCD would have been fine as well.I mainly chose this because i have used it before.

There is a verify.yaml file in the ansible directory that will run validation of all of the requirements.

## Deployment quick start

Use `terraform-proxmox`, `terraform-libvirt`, or `terraform-gcp` as `TF_DIR`.
Copy that directory's `terraform.tfvars.example`, configure the provider and
Ansible values in ansible/group_vars/all.yaml, then run:

```bash
make init TF_DIR=terraform-proxmox
make plan TF_DIR=terraform-proxmox
make apply TF_DIR=terraform-proxmox
make cluster
make rbac
make user
```

The full provider, DNS, GitOps, Teleport, and verification procedure is in
[docs/runbook.md](docs/runbook.md).

## Architecture maps

- [Libvirt network map](docs/architecture/libvirt-network.md)
- [Proxmox network map](docs/architecture/proxmox-network.md)

## Versioning
### Host and Config
- Ubuntu Server - 26.04
- OpenTofu -v1.12.5
  - Telmate/proxmox - v3.0.2-rc09
- Ansible - 2.21.2


### K8s
- Kubernetes - 1.36.2
- Cilium - 1.20.1
- Cert-manager - v1.21.1
- Helm - 3.16.3
- Teleport - 18.10.0
- Flux - 2.9.3

## Requirements
- [x] Deployed Kubernetes cluster using Kubeadm
- [x] Deployed Nginx application on Kubernetes through user access
- [x] Configure K8s RBAC to use Certificate Signing Requests to get access to the
K8s API on the Ngin
- [x] Commit deployment files to Github and share with Teleport team 24 hours
ahead of the interview
- [x] Use Cert Manager for Issuing SSL certs for Nginx site
- [x] The Nginx site must be reachable from your web browser

### Advanced Optional
- [x] Deploy Nginx Application on kubeadm Kubernetes using GitOps
- [x] Deploy Teleport on your Kubernetes Cluster

---
