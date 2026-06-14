{
  description = "stereOS — a NixOS-based operating system for AI agents";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";

    # Raspberry Pi 4 / 5 configuration. The Pi 5 module sets
    # boot.kernelPackages to the rpi-vendor 6.12.x kernel (built with
    # bcm2712_defconfig and the RP1-southbridge initrd modules); without
    # this input there is no Pi 5 kernel in nixpkgs at our pinned rev.
    #
    # Pinned to f1b7ff92cdd1 — the last commit before nixos-hardware#1841
    # replaced the kernel's postConfigure sed with `LOCALVERSION = freeform ""`,
    # which expands through nixpkgs' kernel-config emitter as the literal
    # two characters `""`, breaking modDirVersion at build time. Tracked
    # in nixos-hardware#1859; fix in #1860 is open but unmerged. Revisit
    # the pin once #1860 (or any later fix) lands on master.
    nixos-hardware.url = "github:NixOS/nixos-hardware/f1b7ff92cdd1";
    dagger.url = "github:dagger/nix";
    dagger.inputs.nixpkgs.follows = "nixpkgs";

    agentd = {
      url = "github:papercomputeco/agentd";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    stereosd = {
      url = "github:papercomputeco/stereosd";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = inputs@{ self, flake-parts, ... }:
    let
      stereos-lib = import ./lib { inherit inputs self; };
    in
    flake-parts.lib.mkFlake { inherit inputs; } {
      imports = [
        ./flake/devshell.nix
        ./flake/images.nix
        ./flake/checks.nix
      ];

      # Includes Darwin so perSystem outputs (devShells, checks) are
      # available on developer machines.
      systems = [
        "aarch64-darwin"
        "aarch64-linux"
        "x86_64-darwin"
        "x86_64-linux"
      ];

      # System-agnostic outputs
      flake = {
        # NixOS modules (consumers import these)
        nixosModules = {
          default = ./modules;
        };

        # System configurations ("mixtapes")
        #
        # Default configurations are production-ready (no SSH keys baked in).
        # Dev configurations (*-dev) include profiles/dev.nix which injects
        # the developer's SSH key from ~/.config/stereos/ssh-key.pub.
        #
        # These host-native configurations are intended for `nixos-rebuild` use.
        # For image builds (packages.<system>.<name>), see flake/images.nix
        # which generates per-system configurations for all target architectures.
        nixosConfigurations = {
          # -- Production configurations --------------------------------------
          base = stereos-lib.mkMixtape {
            name = "base";
            features = [ ./mixtapes/base/package.nix ];
          };

          coder = stereos-lib.mkMixtape {
            name = "coder";
            features = [ ./mixtapes/coder/package.nix ];
          };

          # -- Dev configurations (SSH key injection) --------------------------
          base-dev = stereos-lib.mkMixtape {
            name = "base";
            features = [ ./mixtapes/base/package.nix ];
            extraModules = [ ./profiles/dev.nix ];
          };

          coder-dev = stereos-lib.mkMixtape {
            name = "coder";
            features = [ ./mixtapes/coder/package.nix ];
            extraModules = [ ./profiles/dev.nix ];
          };
        };
      };
    };
}
