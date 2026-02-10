# flake.nix
{
  description = "Paper Compute Co. — stereOS development environment";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    dagger.url = "github:dagger/nix";
    dagger.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = { self, nixpkgs, flake-utils, dagger }:
    let
      # ------------------------------------------------------------------
      # stereOS mixtape factory
      # ------------------------------------------------------------------
      #
      # Every mixtape shares:
      #   base.nix        — boot, filesystem, SSH, nix settings
      #   agent-user.nix  — restricted agent user (no nix access)
      #   image.nix       — QCOW2 image derivation
      #
      # Features are added per-mixtape via the `features` list.
      #
      baseModules = [
        ./stereos/modules/base.nix
        ./stereos/modules/agent-user.nix
        ./stereos/modules/image.nix
      ];

      # -- POC-only: per-developer SSH key -----------------------------------
      # Each developer creates ~/.config/stereos/ssh-key.pub with their
      # public key.  The build fails with a clear message if missing.
      #
      # Setup: mkdir -p ~/.config/stereos && cp ~/.ssh/id_ed25519.pub ~/.config/stereos/ssh-key.pub
      #
      sshKeyPath = builtins.getEnv "HOME" + "/.config/stereos/ssh-key.pub";
      sshKey = let
        raw = builtins.readFile sshKeyPath;
      in
        nixpkgs.lib.removeSuffix "\n" raw;

      mkMixtape = { name, features, system ? "aarch64-linux" }:
        nixpkgs.lib.nixosSystem {
          inherit system;
          modules = baseModules ++ features ++ [
            {
              networking.hostName = name;

              # -- POC-only: baked-in SSH access -----------------------------
              # Reads from ./ssh-key.pub (gitignored, per-developer).
              # In production, keys are injected at VM launch time by mb.
              stereos.ssh.authorizedKeys = [ sshKey ];
            }
          ];
        };
    in

    # -- Per-system outputs (devShells for Go development) -------------------
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs { inherit system; };
      in
      {
        devShells.default = pkgs.mkShell {
          buildInputs = [
            pkgs.gnumake
            pkgs.qemu
            dagger.packages.${system}.dagger
          ];

          shellHook = ''
            echo "Go version: $(go version)"
            export STEREOS_EFI_CODE="${pkgs.qemu}/share/qemu/edk2-aarch64-code.fd"
          '';
        };
      }
    )
    //
    # -- stereOS outputs (NixOS configurations + image packages) -------------
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

      # Expose QCOW2 images as packages.
      # Build with: nix build .#packages.aarch64-linux.opencode-mixtape
      # Result lands at: ./result/nixos.qcow2
      packages.aarch64-linux = builtins.mapAttrs
        (_name: cfg: cfg.config.system.build.qcow2)
        self.nixosConfigurations;
    };
}
