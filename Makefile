.PHONY: help init plan apply cluster rbac user deploy reconcile verify destroy lint

TF_DIR ?= terraform

help:
	@echo "make init      - OpenTofu init + ansible collections (TF_DIR=terraform-gcp selects GCP)"
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
	KUBECONFIG=$(KUBECONFIG_ADMIN) kubectl apply -f rbac/00-tenant-rbac.yaml \
	              -f rbac/10-flux-tenant.yaml \
	              -f rbac/20-network-policy.yaml \
	              -f gitops/cluster/lab/tenant.yml

user:
	KUBECONFIG=$(KUBECONFIG_ADMIN) ./rbac/make-user.sh $(USER) $(GROUP)

deploy:
	KUBECONFIG=rbac/out/$(USER)/$(USER).kubeconfig kubectl apply -k gitops/apps/cheesecake/

reconcile:
	KUBECONFIG=$(KUBECONFIG_ADMIN) kubectl -n cheesecake annotate gitrepository cheesecake-app reconcile.fluxcd.io/requestedAt="$$(date -u +%Y-%m-%dT%H:%M:%SZ)" --overwrite
	KUBECONFIG=$(KUBECONFIG_ADMIN) kubectl -n cheesecake annotate kustomization cheesecake-app reconcile.fluxcd.io/requestedAt="$$(date -u +%Y-%m-%dT%H:%M:%SZ)" --overwrite

verify:
	cd ansible && ansible-playbook verify.yml

lint:
	cd $(TF_DIR) && tofu fmt -check -recursive && tofu validate
	cd ansible && ansible-lint site.yml preflight.yml verify.yml

destroy:
	cd $(TF_DIR) && tofu destroy
