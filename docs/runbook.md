# Deployment and GitOps runbook

Pick one provider stack for a lab. It writes the Ansible inventory, then the
same cluster, DNS, RBAC, GitOps, and Teleport steps apply.

## 1. Prerequisites

Install OpenTofu, Ansible, `kubectl`, the Flux CLI, OpenSSH, `rsync`, OpenSSL,
and `jq` on the workstation. The supplied site workflow also needs GitHub CLI
and an authenticated `gh` session. Cloudflare DNS needs a token with `Zone:Read`
and `DNS:Edit` for the application and Teleport zone.

Use one provider directory per deployment. It writes
`ansible/inventory/hosts.ini`.

| Provider | Directory | Input template |
| --- | --- | --- |
| Proxmox | `terraform-proxmox` | `terraform-proxmox/terraform.tfvars.example` |
| Libvirt | `terraform-libvirt` | `terraform-libvirt/terraform.tfvars.example` |
| GCP | `terraform-gcp` | `terraform-gcp/terraform.tfvars.example` |
> [!CAUTION]
> Do not commit `terraform.tfvars`, kubeconfigs, private keys, Cloudflare API
> tokens, or the `rbac/out/` directory!


## 2. Prepare a fork for GitOps

Fork the repository and clone your fork before creating the Flux
`GitRepository`. Flux needs to point at the fork from the first reconcile.

1. Pick a branch that Flux will follow. The current manifests and workflow use
   `main`.
2. Change the Flux source in `gitops/cluster/lab/tenant.yml`:

   ```yaml
   spec:
     url: https://github.com/<your-lowercase-owner>/<your-repository>
     ref:
       branch: main
   ```

3. Change the application image in
   `gitops/apps/cheesecake/deployment.yaml` to the same lower-case owner:

   ```yaml
   image: ghcr.io/<your-lowercase-owner>/cheesecake-site:latest
   ```

4. In the fork's GitHub settings, allow workflows **Read and write** repository
   permissions. The `build-site` workflow commits the build revision and pushes
   the image to GHCR. A protected `main` branch also needs to permit the
   workflow to push, or Flux must watch a separate release branch.
5. Commit and push these two manifest changes. Run the build workflow once to
   publish the first image:

   ```bash
   gh workflow run build-site.yml
   gh run watch
   ```

   A push to `main` under `site/**` also runs the workflow. It publishes
   `latest` and an immutable SHA tag, then commits the SHA annotation to the
   Deployment. Flux sees that commit and rolls the workload.
6. Make the resulting `ghcr.io/<owner>/cheesecake-site` package public. The
   supplied Deployment has no image-pull secret, so a private package will
   leave the pods in `ImagePullBackOff`.

### Private fork alternative

For a private Git repository, create a read-only GitHub fine-grained token
with access to that repository. After the cluster exists, create the Flux
secret in the same namespace as the `GitRepository` and add `secretRef` to
`gitops/cluster/lab/tenant.yml`. Commit the manifest change but never commit
the token:

```bash
export KUBECONFIG=rbac/out/admin/admin.kubeconfig
flux create secret git cheesecake-source \
  --namespace=cheesecake \
  --url=https://github.com/<owner>/<repository> \
  --username=<github-user> \
  --password=<fine-grained-token> \
  --export | kubectl apply -f -
```

```yaml
spec:
  secretRef:
    name: cheesecake-source
```

The package still must be public unless you also add a registry pull secret
and `imagePullSecrets` to the Deployment.

## 3. Set deployment values and DNS

Copy the chosen template to `terraform.tfvars`. Replace every sample address,
credential, SSH key, and node definition. Libvirt needs a bridge on the
physical cluster VLAN. `virbr0` will not work for this lab.

Before cluster installation, review `ansible/group_vars/all.yml` and set:

- `app_hostname`, `acme_email`, and `cloudflare_api_token`.
- `gitops_repo` and `gitops_branch` for clarity alongside the Flux manifest
  change above. The deployed Flux source is the URL in
  `gitops/cluster/lab/tenant.yml`.
- Cilium LoadBalancer addresses appropriate for the L2 network. Reserve the
  whole configured pool outside the router's DHCP range.
- `teleport_cluster_name`. Libvirt overrides this in
  `ansible/group_vars/libvirt.yml` as `teleport.example.com`.

Keep the Cloudflare token out of Git. Ansible Vault is the sensible place for
a long-lived value. The DNS-01 issuer cannot issue either certificate until
the token is available to Ansible.

For the current libvirt layout:

- Point `cheesecake.example.com` at the Cilium Gateway VIP (`192.168.1.100`),
  or publish it through a Cloudflare Tunnel to that HTTPS origin.
- Point `teleport.example.com` at the UniFi public address as a
  DNS-only record and forward WAN TCP/443 to `192.168.1.101`. Teleport is in
  multiplex mode, so its web, SSH, Kubernetes, database, and tunnel traffic
  share port 443.

## 4. Provision the nodes and build Kubernetes

From the repository root, use the chosen provider directory for every command:

```bash
export TF_DIR=terraform-libvirt # or terraform-proxmox, or terraform-gcp
make init TF_DIR="$TF_DIR"
make plan TF_DIR="$TF_DIR"
make apply TF_DIR="$TF_DIR"
make cluster
```

`make apply` builds the infrastructure and writes `ansible/inventory/hosts.ini`.
`make cluster` handles preflight and installs kubeadm, Cilium, cert-manager,
Flux, the Gateway, and Teleport. It also writes the administrator kubeconfig
to `rbac/out/admin/admin.kubeconfig`.

For GCP, the API is private. Follow the SSH-tunnel instructions in
`terraform-gcp/README.md`, then add both `KUBE_API_SERVER` and
`KUBE_TLS_SERVER_NAME` to the commands below.

## 5. Create tenant access and bootstrap Flux

Run these only after the admin kubeconfig has been exported:

```bash
make rbac
make user USER=alice GROUP=app-devs
```

`make rbac` creates the tenant namespace, Alice's group binding, the Flux
ServiceAccount, the Cilium tenant policy, and the Flux `GitRepository` and
`Kustomization`. `make user` creates Alice's Kubernetes CSR on the control
plane and retrieves the signed, short-lived credential bundle here:

```text
rbac/out/alice/alice.kubeconfig
```

For GCP with a local API tunnel, use the same overrides for every Kubernetes
operation:

```bash
make rbac KUBE_API_SERVER=https://127.0.0.1:6443 KUBE_TLS_SERVER_NAME="$CONTROL_IP"
make user KUBE_API_SERVER=https://127.0.0.1:6443 KUBE_TLS_SERVER_NAME="$CONTROL_IP"
make deploy KUBE_API_SERVER=https://127.0.0.1:6443 KUBE_TLS_SERVER_NAME="$CONTROL_IP"
```

`make deploy` is a quick proof that Alice can apply the application with her
limited permissions. Day-to-day changes go through GitOps. Commit under
`gitops/apps/cheesecake/` or `site/` on the branch Flux watches. Flux applies
them as the `app-deployer` ServiceAccount.

## 6. Confirm GitOps and release changes

Use the admin kubeconfig to check that Flux read the fork and applied it:

```bash
export KUBECONFIG=rbac/out/admin/admin.kubeconfig
flux get sources git -A
flux get kustomizations -A
kubectl -n cheesecake get deploy,pods,svc,httproute
```

If a Git push needs immediate reconciliation, run:

```bash
make reconcile
```

For a site change, commit under `site/` and push to `main`. GitHub Actions
builds the GHCR image and writes the build SHA annotation. Flux then rolls the
Deployment. A manifest-only change goes under `gitops/apps/cheesecake/` and
does not need an image build.

## 7. Prepare Teleport access

The deployment installs Teleport Auth and Proxy. It does not create people or
enroll SSH nodes. The reviewed resources live in `teleport/access/` and wait
for an operator to apply them:

- `roles.yaml` defines `lab-admin` (the `ubuntu` login on all labelled nodes)
  and `lab-developer` (the `dev-user` login on jump nodes only).
- `admin-user.yaml` assigns `admin-user` the `access`, `editor`, and
  `lab-admin` roles.
- `dev-user.yaml` assigns `dev-user` only `access` and `lab-developer`.

`dev-user` is a locked, non-sudo Linux account on `jump-01`. It is absent from
the control plane and workers. That keeps the developer account away from node
shutdown and other host-level Kubernetes actions.

After reviewing the files, apply them through the running Auth Service and
generate one-time signup links. Confirm the Auth Deployment name first and
substitute it if it differs:

```bash
export KUBECONFIG=rbac/out/admin/admin.kubeconfig
kubectl -n teleport get deploy,pods
kubectl -n teleport exec -i deploy/teleport-auth -- tctl create -f - < teleport/access/roles.yaml
kubectl -n teleport exec -i deploy/teleport-auth -- tctl create -f - < teleport/access/admin-user.yaml
kubectl -n teleport exec -i deploy/teleport-auth -- tctl create -f - < teleport/access/dev-user.yaml
kubectl -n teleport exec deploy/teleport-auth -- tctl users reset admin-user --ttl=1h
kubectl -n teleport exec deploy/teleport-auth -- tctl users reset dev-user --ttl=1h
```

Keep invitation URLs private. Enroll each host through Teleport's SSH Service,
then label it for the matching role. The developer role needs
`teleport.dev/role=jump` and applies to the jump host only.

## 8. Verify and troubleshoot

Capture the evidence transcript once the application and certificates are
ready:

```bash
make verify
```

The transcript is written to `docs/evidence/transcript.md` and includes Flux
readiness, Alice's CSR, the Gateway certificate, TLS connectivity, and
Teleport status.

Common failures:

| Symptom | Check |
| --- | --- |
| `GitRepository` is not Ready | Confirm the fork URL/branch, public visibility or `secretRef`, then run `make reconcile`. |
| Pods are `ImagePullBackOff` | Confirm the Deployment GHCR owner matches the fork and make the GHCR package public. |
| Workflow cannot push its revision | Enable read/write workflow permissions and permit the workflow to push to the watched branch. |
| Certificate remains Pending | Check the Cloudflare API token, DNS zone, `CertificateRequest`, and `ClusterIssuer` events. |
| Gateway has no VIP | Confirm the L2 pool is outside DHCP, its interface regex matches the worker NIC, and a worker holds the Cilium lease. |
| Alice cannot deploy | Re-run `make user`. The issued client certificate is deliberately short-lived. |

## 9. Tear down

Use the same provider directory used for provisioning:

```bash
make destroy TF_DIR="$TF_DIR"
```

An issued client certificate remains valid until it expires. Remove local
`rbac/out/` credentials when retiring the lab.
