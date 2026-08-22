.PHONY: help init plan apply cluster rbac user deploy verify destroy lint

help:
	@echo "make init      - terraform init + ansible collections"
	@echo "make plan      - terraform plan"
	@echo "make apply     - create the VMs and write the inventory"
	@echo "make cluster   - preflight + full cluster build"
	@echo "make rbac      - apply tenant Role, bindings, network policy"
	@echo "make user      - issue a client cert for USER (default alice)"
	@echo "make deploy    - apply the app as that user"
	@echo "make verify    - capture evidence to docs/evidence/"
	@echo "make lint      - ansible-lint + terraform validate"
	@echo "make destroy   - tear down the VMs"

USER ?= alice
GROUP ?= app-devs
KUBECONFIG_ADMIN ?= $(HOME)/.kube/config

init:
	cd terraform && tofu init
	cd ansible && ansible-galaxy collection install -r requirements.yml

plan:
	cd terraform && tofu plan

apply:
	cd terraform && tofu apply

cluster:
	cd ansible && ansible-playbook preflight.yml && ansible-playbook site.yml

rbac:
	kubectl apply -f rbac/00-tenant-rbac.yaml \
	              -f rbac/10-flux-tenant.yaml \
	              -f rbac/20-network-policy.yaml

user:
	./rbac/make-user.sh $(USER) $(GROUP)

deploy:
	KUBECONFIG=rbac/out/$(USER).kubeconfig kubectl apply -k gitops/apps/cheesecake/

verify:
	cd ansible && ansible-playbook verify.yml

lint:
	cd terraform && tofu fmt -check -recursive && tofu validate
	cd ansible && ansible-lint site.yml preflight.yml verify.yml || true

destroy:
	cd terraform && tofu destroy
