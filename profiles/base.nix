# profiles/base.nix
#
# Shared foundation profile imported by all mixtapes.
# This is the "glue" that every mixtape gets — it's intentionally thin
# since the real configuration lives in modules/.
#
# Currently a pass-through; as stereOS grows, shared profile-level
# configuration (e.g., default locale overrides, common environment
# variables, etc.) goes here rather than in the module tree.

{ config, lib, pkgs, ... }:

{
  # All mixtapes include the image format modules so that
  # system.build.raw, system.build.qcow2, and
  # system.build.kernelArtifacts are always available.
  imports = [
    ../formats/raw-efi.nix
    ../formats/qcow.nix
    ../formats/kernel-artifacts.nix
  ];
}
