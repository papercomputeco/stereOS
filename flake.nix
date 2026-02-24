{
  description = "stereOS — a NixOS-based operating system for AI agents";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
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

  outputs = inputs@{ flake-parts, ... }:
    let
      stereos-lib = import ./lib { inherit inputs; };
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
        nixosConfigurations = {
          # -- Production configurations --------------------------------------
          opencode-mixtape = stereos-lib.mkMixtape {
            name = "opencode-mixtape";
            features = [ ./mixtapes/opencode/base.nix ];
          };

          claude-code-mixtape = stereos-lib.mkMixtape {
            name = "claude-code-mixtape";
            features = [ ./mixtapes/claude-code/base.nix ];
          };

          gemini-cli-mixtape = stereos-lib.mkMixtape {
            name = "gemini-cli-mixtape";
            features = [ ./mixtapes/gemini-cli/base.nix ];
          };

          full-mixtape = stereos-lib.mkMixtape {
            name = "full-mixtape";
            features = [ ./mixtapes/full/base.nix ];
          };

          # -- Dev configurations (SSH key injection) --------------------------
          opencode-mixtape-dev = stereos-lib.mkMixtape {
            name = "opencode-mixtape";
            features = [ ./mixtapes/opencode/base.nix ];
            extraModules = [ ./profiles/dev.nix ];
          };

          claude-code-mixtape-dev = stereos-lib.mkMixtape {
            name = "claude-code-mixtape";
            features = [ ./mixtapes/claude-code/base.nix ];
            extraModules = [ ./profiles/dev.nix ];
          };

          gemini-cli-mixtape-dev = stereos-lib.mkMixtape {
            name = "gemini-cli-mixtape";
            features = [ ./mixtapes/gemini-cli/base.nix ];
            extraModules = [ ./profiles/dev.nix ];
          };

          full-mixtape-dev = stereos-lib.mkMixtape {
            name = "full-mixtape";
            features = [ ./mixtapes/full/base.nix ];
            extraModules = [ ./profiles/dev.nix ];
          };
        };
      };
    };
}
