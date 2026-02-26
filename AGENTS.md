# AGENTS.md

### Project Overview

`stereOS` is a Linux based operating system purpose built for AI agents.

### Architecture

```
stereos/
├── flake.nix                       # Thin entry point — delegates to flake/ modules (flake-parts)
├── flake.lock
├── flake/                          # flake-parts module files (split flake.nix logic)
│   ├── devshell.nix                # Per-system: toolchains, developer shell for direnv
│   ├── images.nix                  # Per-system: image build targets (raw, qcow2, kernel-artifacts)
│   └── checks.nix                  # Per-system: CI verification builds
│
├── modules/                        # NixOS modules — the core of the OS
│   ├── default.nix                 # Aggregator (imports all sub-modules)
│   ├── base.nix                    # Core OS: filesystem, SSH, nix settings, packages, hardening
│   ├── boot.nix                    # Boot config + boot-time optimizations (sub-3s boot target)
│   ├── services/
│   │   ├── stereosd.nix            # stereosd service overrides (tmpfiles, firewall, DynamicUser)
│   │   └── agentd.nix              # agentd service overrides (ordering, DynamicUser)
│   └── users/
│       ├── agent.nix               # Agent user: restricted shell, ~/workspace, sudo denial, options
│       └── admin.nix               # Admin user: wheel/admin group, passwordless sudo
│
├── profiles/                       # Composable configuration presets
│   ├── base.nix                    # Shared foundation (imports all image formats)
│   └── dev.nix                     # Dev-only: SSH key injection, debug tools
│
├── mixtapes/                       # Mixtapes — spins with specific packages/configs
│   ├── opencode/
│   │   └── base.nix                # OpenCode AI coding agent
│   ├── claude-code/
│   │   └── base.nix                # Claude Code (Anthropic CLI)
│   ├── gemini-cli/
│   │   └── base.nix                # Gemini CLI (Google)
│   └── full/
│       └── base.nix                # All agents combined
│
├── formats/                        # Image format definitions
│   ├── raw-efi.nix                 # Raw EFI disk image (canonical artifact)
│   ├── qcow.nix                    # QCOW2 image (for QEMU/KVM)
│   └── kernel-artifacts.nix        # Direct-kernel boot (bzImage + initrd + cmdline)
│
├── lib/                            # Shared Nix helper functions
│   └── default.nix                 # mkMixtape helper
│
├── scripts/
│   └── run-vm.sh                   # QEMU VM launcher
├── Makefile                        # Build command runner (make help for targets)
└── .envrc                          # direnv integration for nix flake dev shell
```

### mkMixtape

Every mixtape is assembled by `lib/default.nix:mkMixtape`, which calls
`nixpkgs.lib.nixosSystem` with:

1. External flake modules (`agentd`, `stereosd`) + their overlays
2. The stereOS module tree (`modules/`)
3. The shared base profile (`profiles/base.nix`)
4. Mixtape-specific feature modules (e.g. `mixtapes/opencode/base.nix`)
5. Optional extra modules (e.g. `profiles/dev.nix` for dev builds)

```nix
mkMixtape {
  name     = "opencode-mixtape";
  features = [ ./mixtapes/opencode/base.nix ];
  # extraModules = [ ./profiles/dev.nix ];  # dev builds only
}
```

### Do

- When writing Go, always use the Ginkgo/Gomega testing frameworks
- Always use `make` operations for development: use `make help` to understand the various operations available.
- Follow idiomatic Go and prefer using the `func NewExampleStruct() *ExampleStruct`
  paradigm throughout.
