{
  description = "Paper Compute Co. — StereOS: a Linux-based OS for AI agents";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    flake-utils.url = "github:numtide/flake-utils";
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

  outputs = { self, nixpkgs, flake-utils, dagger, agentd, stereosd }:
    let
      # ------------------------------------------------------------------
      # StereOS Mixtape Factory
      # ------------------------------------------------------------------
      #
      # Every mixtape shares:
      #   base.nix        — boot, filesystem, SSH, nix settings, hardening
      #   agent-user.nix  — restricted agent user + /workspace
      #   image.nix       — raw + qcow2 image derivations
      #   stereosd.nix    — StereOS-specific overrides for stereosd service
      #   agentd.nix      — StereOS-specific overrides for agentd service
      #
      # External flake modules (agentd, stereosd) provide the base service
      # definitions and `services.*.enable` options.  Overlays make
      # `pkgs.agentd` and `pkgs.stereosd` available to the entire closure.
      #
      # Features are added per-mixtape via the `features` list.
      #
      baseModules = [
        # External flake NixOS modules — provide services.agentd and
        # services.stereosd options + baseline systemd units.
        agentd.nixosModules.default
        stereosd.nixosModules.default

        # Apply overlays so pkgs.agentd and pkgs.stereosd are available.
        ({ ... }: {
          nixpkgs.overlays = [
            agentd.overlays.default
            stereosd.overlays.default
          ];
        })

        # StereOS base modules
        ./stereos/modules/base.nix
        ./stereos/modules/agent-user.nix
        ./stereos/modules/image.nix

        # StereOS-specific service overrides (ordering, hardening, tmpfiles)
        ./stereos/modules/stereosd.nix
        ./stereos/modules/agentd.nix
      ];

      # -- Dev-only: per-developer SSH key ---------------------------------
      # POC ONLY — will be replaced by agentd + vsock secret injection.
      #
      # Each developer creates ~/.config/stereos/ssh-key.pub with their
      # public key.  If the file is missing, no SSH keys are baked in
      # (the build no longer fails).
      #
      # Setup:
      #   mkdir -p ~/.config/stereos
      #   cp ~/.ssh/id_ed25519.pub ~/.config/stereos/ssh-key.pub
      #
      sshKeyPath = builtins.getEnv "HOME" + "/.config/stereos/ssh-key.pub";
      sshKeys =
        let
          exists = builtins.pathExists sshKeyPath;
        in
          if exists then
            let raw = builtins.readFile sshKeyPath;
            in [ (nixpkgs.lib.removeSuffix "\n" raw) ]
          else
            [];

      mkMixtape = { name, features, system ? "aarch64-linux" }:
        nixpkgs.lib.nixosSystem {
          inherit system;
          modules = baseModules ++ features ++ [
            {
              networking.hostName = name;

              # -- Dev-only: baked-in SSH access ----------------------------
              # In production, keys are injected at VM launch time by stereosd.
              stereos.ssh.authorizedKeys = sshKeys;
            }
          ];
        };
    in

    # -- Per-system outputs (devShells for local development) ----------------
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs { inherit system; };
      in
      {
        devShells.default = pkgs.mkShell {
          buildInputs = [
            pkgs.gnumake
            pkgs.qemu
            pkgs.go
            pkgs.gopls
            pkgs.gotools
            pkgs.hurl
            dagger.packages.${system}.dagger
          ];

          shellHook = ''
            # Provide Nix with GitHub auth for private flake inputs.
            # Requires `gh auth login` to have been run once.
            if command -v gh &>/dev/null && gh auth status &>/dev/null 2>&1; then
              export NIX_CONFIG="access-tokens = github.com=$(gh auth token)"
            fi

            echo "StereOS dev shell"
            echo "  Go:   $(go version)"
            echo "  QEMU: $(qemu-system-aarch64 --version | head -1)"
            export STEREOS_EFI_CODE="${pkgs.qemu}/share/qemu/edk2-aarch64-code.fd"
          '';
        };
      }
    )
    //
    # -- StereOS outputs (NixOS configurations + image packages) -------------
    {
      nixosConfigurations = {
        opencode-mixtape = mkMixtape {
          name = "opencode-mixtape";
          features = [ ./stereos/modules/features/opencode.nix ];
        };

        claude-code-mixtape = mkMixtape {
          name = "claude-code-mixtape";
          features = [ ./stereos/modules/features/claude-code.nix ];
        };

        gemini-cli-mixtape = mkMixtape {
          name = "gemini-cli-mixtape";
          features = [ ./stereos/modules/features/gemini-cli.nix ];
        };

        full-mixtape = mkMixtape {
          name = "full-mixtape";
          features = [
            ./stereos/modules/features/opencode.nix
            ./stereos/modules/features/claude-code.nix
            ./stereos/modules/features/gemini-cli.nix
          ];
        };
      };

      # Expose images as packages.
      #
      # Raw (canonical):
      #   nix build .#packages.aarch64-linux.opencode-mixtape --impure
      #   → result/nixos.img
      #
      # QCOW2 (for QEMU/KVM):
      #   nix build .#packages.aarch64-linux.opencode-mixtape-qcow2 --impure
      #   → result/nixos.qcow2
      #
      packages.aarch64-linux =
        let
          configs = self.nixosConfigurations;
          # Raw images — canonical artifact
          rawPkgs = builtins.mapAttrs
            (_name: cfg: cfg.config.system.build.raw)
            configs;
          # QCOW2 images — derived from raw, for QEMU/KVM
          qcow2Pkgs = builtins.mapAttrs
            (name: cfg: cfg.config.system.build.qcow2)
            configs;
          # Suffix qcow2 package names with "-qcow2"
          qcow2Named = builtins.listToAttrs (
            builtins.map (name: {
              name = "${name}-qcow2";
              value = qcow2Pkgs.${name};
            }) (builtins.attrNames qcow2Pkgs)
          );
        in
          rawPkgs // qcow2Named;
    };
}
