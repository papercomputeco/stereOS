# flake/checks.nix
#
# Per-system: CI verification builds.
# Ensures critical flake outputs (like devShells) evaluate on every
# supported system and provides a place for future NixOS VM integration
# tests.

{ self, ... }:

{
  perSystem = { system, pkgs, ... }: {
    checks = {
      # Verify the default devShell evaluates without error.
      # This catches missing packages, broken shellHooks, and the
      # "flake does not provide attribute devShells.<system>.default"
      # regression that occurs when Darwin systems are accidentally
      # dropped from the systems list.
      devshell = self.devShells.${system}.default;
    };
  };
}
