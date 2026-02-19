# formats/raw-efi.nix
#
# Raw EFI disk image format.
# Produces system.build.raw — the canonical StereOS image artifact.
#
# Used by Apple Virtualization.framework and as the base for OCI
# distribution and QCOW2 conversion.
#
# Build with:
#   nix build .#packages.aarch64-linux.<mixtape-name> --impure

{ config, lib, pkgs, modulesPath, ... }:

let
  imageName = "stereos-${config.networking.hostName}";
in
{
  system.build.raw = import "${modulesPath}/../lib/make-disk-image.nix" {
    inherit lib config pkgs;

    name = imageName;

    # Disk sizing: "auto" calculates the minimum size needed for the
    # closure, then adds additionalSpace on top.
    diskSize = "auto";
    additionalSpace = "4096M";  # 4 GB free space for agent work

    # Raw format — uncompressed, required by VZDiskImageStorageDeviceAttachment
    format = "raw";

    # aarch64 requires EFI partition table (GPT + ESP)
    partitionTableType = "efi";

    # Don't copy the Nix channel into the image — we use flakes
    copyChannel = false;
  };
}
