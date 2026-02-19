# Based around the auto-documented Makefile:
# http://marmelab.com/blog/2016/02/29/auto-documented-makefile.html
#
# StereOS Makefile
# "$ make help" to see available targets

MIXTAPE ?= opencode-mixtape
ARCH    ?= aarch64-linux
SSH_PORT ?= 2222

# -- Image builds ------------------------------------------------------------

.PHONY: build
build: ## Build the default mixtape (raw image)
	nix build .#packages.$(ARCH).$(MIXTAPE) --impure

.PHONY: build-qcow2
build-qcow2: ## Build the default mixtape (qcow2 image)
	nix build .#packages.$(ARCH).$(MIXTAPE)-qcow2 --impure

.PHONY: build-kernel
build-kernel: ## Build kernel artifacts for direct-kernel boot (bzImage, initrd, cmdline)
	nix build .#packages.$(ARCH).$(MIXTAPE)-kernel-artifacts --impure -o result-kernel

.PHONY: build-all
build-all: ## Build all mixtapes (raw images)
	nix build .#packages.$(ARCH).opencode-mixtape --impure -o result-opencode
	nix build .#packages.$(ARCH).claude-code-mixtape --impure -o result-claude-code
	nix build .#packages.$(ARCH).gemini-cli-mixtape --impure -o result-gemini-cli
	nix build .#packages.$(ARCH).full-mixtape --impure -o result-full

.PHONY: install-mixtape
install-mixtape: ## Build qcow2 + kernel artifacts and install to ~/.config/mb/mixtapes/
	@echo "Building qcow2 image..."
	nix build .#packages.$(ARCH).$(MIXTAPE)-qcow2 --impure
	@echo "Building kernel artifacts..."
	nix build .#packages.$(ARCH).$(MIXTAPE)-kernel-artifacts --impure -o result-kernel
	@echo "Installing to ~/.config/mb/mixtapes/$(MIXTAPE)/"
	mkdir -p ~/.config/mb/mixtapes/$(MIXTAPE)/kernel-artifacts
	cp result/nixos.qcow2 ~/.config/mb/mixtapes/$(MIXTAPE)/nixos.qcow2
	cp result-kernel/bzImage ~/.config/mb/mixtapes/$(MIXTAPE)/kernel-artifacts/bzImage
	cp result-kernel/initrd ~/.config/mb/mixtapes/$(MIXTAPE)/kernel-artifacts/initrd
	cp result-kernel/cmdline ~/.config/mb/mixtapes/$(MIXTAPE)/kernel-artifacts/cmdline
	@echo "Done. Mixtape installed at ~/.config/mb/mixtapes/$(MIXTAPE)/"
	@echo "  qcow2:   ~/.config/mb/mixtapes/$(MIXTAPE)/nixos.qcow2"
	@echo "  kernel:  ~/.config/mb/mixtapes/$(MIXTAPE)/kernel-artifacts/"

# -- VM development operations ------------------------------------------------

.PHONY: run
run: ## Launch the built qcow2 image in QEMU (auto-builds kernel artifacts for direct boot)
	@if [ ! -f result/nixos.qcow2 ]; then \
		echo "No qcow2 image found. Building..."; \
		$(MAKE) build-qcow2; \
	fi
	@if [ ! -f result-kernel/bzImage ]; then \
		echo "No kernel artifacts found. Building for direct boot..."; \
		$(MAKE) build-kernel; \
	fi
	./scripts/run-vm.sh result/nixos.qcow2 $(SSH_PORT)

.PHONY: ssh-admin
ssh-admin: ## SSH into the running VM as admin
	ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -p $(SSH_PORT) admin@localhost

.PHONY: ssh-agent
ssh-agent: ## SSH into the running VM as agent
	ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -p $(SSH_PORT) agent@localhost

# -- Utilities ----------------------------------------------------------------

.PHONY: help
.DEFAULT_GOAL := help
help: ## Show this help message
	@echo "StereOS development targets:"
	@echo ""
	@grep -E '^[a-zA-Z0-9_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-30s\033[0m %s\n", $$1, $$2}'
	@echo ""
	@echo "Build development env variables:"
	@echo "  MIXTAPE=$(MIXTAPE)"
	@echo "  ARCH=$(ARCH)"
	@echo "  SSH_PORT=$(SSH_PORT)"

.PHONY: clean
clean: ## Remove build artifacts
	$(call print-target)
	rm -rf result result-* bin/

define print-target
    @printf "Executing target: \033[36m$@\033[0m\n"
endef
