# stereOS Makefile
# "$ make help" to see available targets
#
# Based around the auto-documented Makefile:
# http://marmelab.com/blog/2016/02/29/auto-documented-makefile.html

MIXTAPE  ?= opencode-mixtape
ARCH     ?= aarch64-linux
SSH_PORT ?= 2222

# -- Image builds ------------------------------------------------------------

.PHONY: dist
dist: ## Build all formats and assemble dist/ for publishing
	nix build .#packages.$(ARCH).$(MIXTAPE)-dist --impure

.PHONY: build
build: ## Build the default base mixtape (raw image)
	nix build .#packages.$(ARCH).$(MIXTAPE) --impure

.PHONY: build-qcow2
build-qcow2: ## Build the default mixtape (qcow2 image)
	nix build .#packages.$(ARCH).$(MIXTAPE)-qcow2 --impure

.PHONY: build-kernel
build-kernel: ## Build kernel artifacts for kernel boot
	nix build .#packages.$(ARCH).$(MIXTAPE)-kernel-artifacts --impure

# -- VM development operations ------------------------------------------------

.PHONY: run
run: ## Launch the built qcow2 image in QEMU (auto-builds kernel artifacts for direct boot)
	@if [ ! -f result/stereos.qcow2 ]; then \
		echo "No qcow2 image found. Building..."; \
		$(MAKE) build-qcow2; \
	fi
	@if [ ! -f result-kernel/bzImage ]; then \
		echo "No kernel artifacts found. Building for direct boot..."; \
		$(MAKE) build-kernel; \
	fi
	./scripts/run-vm.sh result/stereos.qcow2 $(SSH_PORT)

.PHONY: ssh-admin
ssh-admin: ## SSH into the running VM as admin
	ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -p $(SSH_PORT) admin@localhost

.PHONY: ssh-agent
ssh-agent: ## SSH into the running VM as agent
	ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -p $(SSH_PORT) agent@localhost

# -- Dagger -------------------------------------------------------------------

.PHONY: dagger-check
dagger-check: ## Run Dagger CI checks
	dagger check

# -- Utilities ----------------------------------------------------------------

.PHONY: help
.DEFAULT_GOAL := help
help: ## Show this help message
	@echo "stereOS development targets:"
	@echo ""
	@grep -E '^[a-zA-Z0-9_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-30s\033[0m %s\n", $$1, $$2}'
	@echo ""
	@echo "Build development env variables:"
	@echo "  MIXTAPE=$(MIXTAPE)"
	@echo "  ARCH=$(ARCH)"
	@echo "  SSH_PORT=$(SSH_PORT)"

define print-target
    @printf "Executing target: \033[36m$@\033[0m\n"
endef
