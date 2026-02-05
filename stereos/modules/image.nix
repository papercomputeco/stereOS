# stereos/modules/image.nix
#
# Adds system.build.qcow2 — a derivation that produces a bootable
# QCOW2 disk image for the current NixOS configuration.
#
# Build with:
#   nix build .#packages.aarch64-linux.<mixtape-name>
#
# The result is a directory containing:
#   result/nixos.qcow2

{ config, lib, pkgs, modulesPath, ... }:

{
  system.build.qcow2 = import "${modulesPath}/../lib/make-disk-image.nix" {
    inherit lib config pkgs;

    # Derivation name — affects the output directory name in /nix/store
    name = "stereos-${config.networking.hostName}";

    # Disk sizing: "auto" calculates the minimum size needed for the
    # closure, then adds additionalSpace on top.
    diskSize = "auto";
    additionalSpace = "4096M";  # 4GB free space for agent work

    # Output format
    format = "qcow2";

    # aarch64 requires EFI partition table (GPT + ESP)
    partitionTableType = "efi";

    # Don't copy the Nix channel into the image — we use flakes
    copyChannel = false;
  };
}
