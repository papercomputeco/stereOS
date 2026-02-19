# lib/default.nix
#
# Shared Nix helper functions for StereOS.

{ inputs }:

let
  inherit (inputs.nixpkgs) lib;
in
{
  # -- mkMixtape -------------------------------------------------------------
  #
  # Build a complete NixOS system configuration ("mixtape") from:
  #   - The shared StereOS module tree (modules/)
  #   - A profile (profiles/base.nix, profiles/dev.nix)
  #   - External flake modules (agentd, stereosd) + overlays
  #   - Mixtape-specific feature modules
  #
  # Usage:
  #   mkMixtape {
  #     name     = "opencode-mixtape";
  #     system   = "aarch64-linux";
  #     features = [ ../modules/features/opencode.nix ];
  #   }
  #
  mkMixtape = { name, features ? [], system ? "aarch64-linux", extraModules ? [] }:
    let
      # -- Dev-only: per-developer SSH key -----------------------------------
      # POC ONLY -- will be replaced by agentd + vsock secret injection.
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
            in [ (lib.removeSuffix "\n" raw) ]
          else
            [];
    in
    inputs.nixpkgs.lib.nixosSystem {
      inherit system;
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

        # StereOS module tree (aggregator imports all sub-modules)
        ../modules

        # Shared base profile
        ../profiles/base.nix

        # Dev profile (SSH key injection)
        ../profiles/dev.nix

        # Mixtape identity
        {
          networking.hostName = name;
          stereos.ssh.authorizedKeys = sshKeys;
        }
      ] ++ features ++ extraModules;
    };
}
