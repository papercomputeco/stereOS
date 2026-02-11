# stereos/modules/image.nix
#
# Produces bootable disk images for the current NixOS configuration.
#
# Two formats are available:
#
#   system.build.raw    — Raw disk image (canonical artifact).
#                         Used by Apple Virtualization.framework
#                         and as the base for OCI distribution.
#
#   system.build.qcow2  — QCOW2 image derived from the raw image.
#                         Used by QEMU and KVM/libvirt backends.
#
# Build with:
#   nix build .#packages.aarch64-linux.<mixtape-name>         # → raw
#   nix build .#packages.aarch64-linux.<mixtape-name>-qcow2   # → qcow2
#

{ config, lib, pkgs, modulesPath, ... }:

let
  imageName = "stereos-${config.networking.hostName}";
in
{
  # -- Raw disk image (canonical) --------------------------------------------
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

  # -- QCOW2 image (derived from raw) ---------------------------------------
  system.build.qcow2 = pkgs.runCommand "${imageName}-qcow2" {
    nativeBuildInputs = [ pkgs.qemu ];
  } ''
    mkdir -p $out
    qemu-img convert -f raw -O qcow2 \
      ${config.system.build.raw}/nixos.img \
      $out/nixos.qcow2
  '';
}
