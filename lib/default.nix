# lib/default.nix
#
# Shared Nix helper functions for stereOS.

{ inputs, self }:

let
  # -- stereOS version -------------------------------------------------------
  #
  # CI sets STEREOS_VERSION to the git tag (e.g. "2026.03.01.0") before
  # building with --impure.  Local dev builds fall back to a commit-based
  # string so every image always carries *some* identity.
  #
  # Resolution order:
  #   1. $STEREOS_VERSION env var     (CI — requires --impure)
  #   2. "dev-<shortRev>"             (clean git worktree)
  #   3. "dev-<dirtyShortRev>"        (dirty git worktree)
  #   4. "dev-<lastModifiedDate>"     (path: input with no git context)
  #
  # Note: when consuming stereOS via --override-input, prefer
  # "git+file:" over "path:" to preserve git revision metadata.
  #
  envVersion = builtins.getEnv "STEREOS_VERSION";

  stereosVersion =
    if envVersion != "" then envVersion
    else if self ? shortRev then "dev-${self.shortRev}"
    else if self ? dirtyShortRev then "dev-${self.dirtyShortRev}"
    else "dev-${self.lastModifiedDate or "unknown"}";

  # Git revision for system.configurationRevision
  gitRevision = self.rev or self.dirtyRev or "unknown";
in

rec {
  # Expose the computed version so other flake modules can use it
  # (e.g. flake/images.nix passes it to mkDist for mixtape.toml).
  inherit stereosVersion;

  # -- mkSandboxManifest -----------------------------------------------------
  #
  # Returns a NixOS module that pre-computes the Nix store closure for the
  # gVisor sandbox profile at build time. The closure manifest is installed
  # to /etc/stereos/sandbox-closure.txt, which agentd reads as the fast path
  # when it boots up sandboxes (instead of running `nix-store -qR` at runtime).
  #
  # The manifest includes the base agent packages (the same curated set
  # from the agent user) plus whatever config.stereos.agent.extraPackages the
  # mixtape injects. mkMixtape auto-includes this module, so every
  # mixtape gets a manifest that is specific to its own package set.
  mkSandboxManifest =
    { }:
    { config, lib, pkgs, ... }:
    let
      # Combine base agent package options with mixtape package options.
      allPackages = config.stereos.agent.basePackages
        ++ config.stereos.agent.extraPackages;

      # Build a single environment from all packages.
      sandboxProfile = pkgs.buildEnv {
        name = "stereos-sandbox-profile";
        paths = allPackages;
        pathsToLink = [ "/bin" "/lib" "/share" "/etc" ];
      };

      # Use closureInfo to compute the full /nix/store closure at build time.
      closureManifest = pkgs.closureInfo { rootPaths = [ sandboxProfile ]; };
    in
    {
      # Install the closure manifest to a well-known path that agentd reads.
      environment.etc."stereos/sandbox-closure.txt" = {
        source = "${closureManifest}/store-paths";
        mode = "0444";
      };
    };

  # -- mkMixtape -------------------------------------------------------------
  #
  # Build a complete NixOS system configuration ("mixtape") from:
  #   - The shared stereOS module tree (modules/)
  #   - A profile (profiles/base.nix)
  #   - External flake modules (agentd, stereosd) + overlays
  #   - Mixtape-specific feature modules
  #   - The sandbox closure manifest (auto-included)
  #
  # For dev builds, include profiles/dev.nix via extraModules to get
  # SSH key injection and debug tooling.  Production builds should NOT
  # include the dev profile.
  #
  # Usage:
  #   mkMixtape {
  #     name     = "opencode-mixtape";
  #     system   = "aarch64-linux";
  #     features = [ ../modules/features/opencode.nix ];
  #   }
  #
  mkMixtape = { name, features ? [], system ? "aarch64-linux", extraModules ? [] }:
    inputs.nixpkgs.lib.nixosSystem {
      inherit system;
      specialArgs = {
        inherit stereosVersion gitRevision;
        pkgs-unstable = import inputs.nixpkgs-unstable {
          inherit system;
          config.allowUnfree = true;
        };
      };
      modules = [
        # External flake NixOS modules -- provide services.agentd and
        # services.stereosd options + baseline systemd units.
        inputs.agentd.nixosModules.default
        inputs.stereosd.nixosModules.default

        # Apply overlays so pkgs.agentd and pkgs.stereosd are available.
        ({ ... }: {
          nixpkgs.overlays = [
            inputs.agentd.overlays.default
            inputs.stereosd.overlays.default
          ];
        })

        # stereOS module tree (aggregator imports all sub-modules)
        ../modules

        # Shared base profile
        ../profiles/base.nix

        # Pre-computed sandbox closure manifest (per-mixtape)
        (mkSandboxManifest { })

        # Mixtape identity
        {
          networking.hostName = name;
        }
      ] ++ features ++ extraModules;
    };
}
