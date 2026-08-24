.PHONY: help init plan apply cluster rbac user deploy reconcile verify destroy lint

TF_DIR ?= terraform-proxmox

help:
	@echo "make init      - OpenTofu init + ansible collections (default: terraform-proxmox)"
	@echo "make plan      - OpenTofu plan"
	@echo "make apply     - create the VMs and write the inventory"
	@echo "make cluster   - preflight + full cluster build"
	@echo "make rbac      - apply tenant Role, bindings, network policy"
	@echo "make user      - issue a client cert for USER (default alice)"
	@echo "make deploy    - apply the app as the deliberately low-privilege user"
	@echo "make reconcile - ask Flux to reconcile the committed app configuration"
	@echo "make verify    - capture evidence to docs/evidence/"
	@echo "make lint      - ansible-lint + terraform validate"
	@echo "make destroy   - tear down the VMs"

USER := alice
GROUP := app-devs
KUBECONFIG_ADMIN ?= rbac/out/admin/admin.kubeconfig
# Override the API endpoint for a local SSH tunnel or another reachable route.
# When the route hostname is not a certificate SAN, also set KUBE_TLS_SERVER_NAME.
KUBE_API_SERVER ?=
KUBE_TLS_SERVER_NAME ?=
KUBECTL_SERVER = $(if $(KUBE_API_SERVER),--server=$(KUBE_API_SERVER)) $(if $(KUBE_TLS_SERVER_NAME),--tls-server-name=$(KUBE_TLS_SERVER_NAME))

init:
	cd $(TF_DIR) && tofu init
	cd ansible && ansible-galaxy collection install -r requirements.yml

plan:
	cd $(TF_DIR) && tofu plan

apply:
	cd $(TF_DIR) && tofu apply

cluster:
	cd ansible && ansible-playbook preflight.yml && ansible-playbook site.yml

rbac:
	KUBECONFIG=$(KUBECONFIG_ADMIN) kubectl $(KUBECTL_SERVER) apply -f rbac/00-tenant-rbac.yaml \
	              -f rbac/10-flux-tenant.yaml \
	              -f rbac/20-network-policy.yaml \
	              -f gitops/cluster/lab/tenant.yml

user:
	cd ansible && ansible-playbook issue-user.yml -e "rbac_user=$(USER) rbac_group=$(GROUP)" $(if $(KUBE_API_SERVER),-e "rbac_api_server=$(KUBE_API_SERVER)") $(if $(KUBE_TLS_SERVER_NAME),-e "rbac_tls_server_name=$(KUBE_TLS_SERVER_NAME)")

deploy:
	KUBECONFIG=rbac/out/$(USER)/$(USER).kubeconfig kubectl $(KUBECTL_SERVER) apply -k gitops/apps/cheesecake/

reconcile:
	KUBECONFIG=$(KUBECONFIG_ADMIN) kubectl $(KUBECTL_SERVER) -n cheesecake annotate gitrepository cheesecake-app reconcile.fluxcd.io/requestedAt="$$(date -u +%Y-%m-%dT%H:%M:%SZ)" --overwrite
	KUBECONFIG=$(KUBECONFIG_ADMIN) kubectl $(KUBECTL_SERVER) -n cheesecake annotate kustomization cheesecake-app reconcile.fluxcd.io/requestedAt="$$(date -u +%Y-%m-%dT%H:%M:%SZ)" --overwrite

verify:
	cd ansible && ansible-playbook verify.yml

lint:
	cd $(TF_DIR) && tofu fmt -check -recursive && tofu validate
	cd ansible && ansible-lint site.yml preflight.yml verify.yml issue-user.yml

destroy:
	cd $(TF_DIR) && tofu destroy
