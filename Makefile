# stereOS Makefile
# "$ make help" to see available targets
#
# Based around the auto-documented Makefile:
# http://marmelab.com/blog/2016/02/29/auto-documented-makefile.html

# -- Image builds ------------------------------------------------------------
#
# The "ARCH" env var must be specified for image builds.

MIXTAPE  ?= coder
ARCH     ?=
SSH_PORT ?= 2222
SSH_KEY  ?=

define require-arch
	$(if $(ARCH),,$(error ARCH is required. Use ARCH=aarch64-linux or ARCH=x86_64-linux))
endef

.PHONY: dist
dist: ## Build all formats and assemble dist/ for publishing
	$(call require-arch)
	nix build .#packages.$(ARCH).$(MIXTAPE)-dist --impure

.PHONY: build
build: ## Build the default base mixtape (raw image)
	$(call require-arch)
	nix build .#packages.$(ARCH).$(MIXTAPE) --impure

.PHONY: build-qcow2
build-qcow2: ## Build the default mixtape (qcow2 image)
	$(call require-arch)
	nix build .#packages.$(ARCH).$(MIXTAPE)-qcow2 --impure

.PHONY: build-kernel
build-kernel: ## Build kernel artifacts for kernel boot
	$(call require-arch)
	nix build .#packages.$(ARCH).$(MIXTAPE)-kernel-artifacts --impure

# -- Raspberry Pi image builds -----------------------------------------------
#
# RPi images are aarch64-only and ship as a single SD card image.
# The attr name adds "-rpi4-sd" to the mixtape (e.g. coder → coder-rpi4-sd).

.PHONY: build-rpi4
build-rpi4: ## Build an SD card image for Raspberry Pi 4 (MIXTAPE=coder by default)
	nix build .#packages.aarch64-linux.$(MIXTAPE)-rpi4-sd --impure -o result-rpi4

.PHONY: flash-rpi4
flash-rpi4: ## Flash RPi4 SD image to an SD card (SSH_KEY=~/.ssh/id_ed25519.pub optional)
	@./scripts/flash-rpi.sh --board rpi4 \
		$(if $(SSH_KEY),--ssh-key $(SSH_KEY))

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
	@echo "  SSH_KEY=$(SSH_KEY)"

define print-target
    @printf "Executing target: \033[36m$@\033[0m\n"
endef
