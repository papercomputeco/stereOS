# flake/checks.nix
#
# Ensures critical flake outputs (like devShells) evaluate on every
# supported system.

{ self, ... }:

{
  perSystem = { system, pkgs, ... }: {
    checks = {
      devshell = self.devShells.${system}.default;
    };
  };
}
