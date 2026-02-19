# flake/checks.nix
#
# Per-system: CI verification builds.
# Placeholder for future NixOS VM integration tests and CI checks.

{ ... }:

{
  # Future: add perSystem checks here, e.g.:
  #
  # perSystem = { system, pkgs, ... }: {
  #   checks = {
  #     stereosd-basic = ...;
  #     agent-lifecycle = ...;
  #   };
  # };
}
