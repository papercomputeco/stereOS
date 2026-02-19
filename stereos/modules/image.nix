# stereos/modules/image.nix
#
# Produces bootable disk images for the current NixOS configuration.
#
# Formats available:
#
#   system.build.raw      — Raw disk image (canonical artifact).
#                           Used by Apple Virtualization.framework
#                           and as the base for OCI distribution.
#
#   system.build.qcow2    — QCOW2 image derived from the raw image.
#                           Used by QEMU and KVM/libvirt backends.
#
#   system.build.kernelArtifacts
#                         — Directory containing the kernel (bzImage),
#                           initrd, and a cmdline file for direct-kernel
#                           boot via QEMU (-kernel/-initrd) or Apple
#                           Virtualization.framework.  Enables bypassing
#                           the UEFI/GRUB boot path entirely, which is
#                           the primary mechanism for sub-3-second boot.
#
# Build with:
#   nix build .#packages.aarch64-linux.<mixtape-name>                  # → raw
#   nix build .#packages.aarch64-linux.<mixtape-name>-qcow2            # → qcow2
#   nix build .#packages.aarch64-linux.<mixtape-name>-kernel-artifacts # → kernel dir
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

  # -- Direct-kernel boot artifacts ------------------------------------------
  #
  # Collect the kernel image, initrd, and kernel command line into a single
  # output directory.  These are used for direct-kernel boot — bypassing the
  # UEFI/GRUB boot path — which is the most reliable path to sub-3-second
  # total boot time.
  #
  # QEMU usage:
  #   qemu-system-aarch64 \
  #     -kernel result-kernel/bzImage \
  #     -initrd result-kernel/initrd \
  #     -append "$(cat result-kernel/cmdline)" \
  #     ...
  #
  # Apple Virtualization.framework usage:
  #   Set VZLinuxBootLoader.kernelURL / initialRamdiskURL / commandLine from
  #   the corresponding files in this directory.
  #
  # Contents:
  #   bzImage   — compressed kernel image
  #   initrd    — initramfs (gzip-compressed cpio archive)
  #   cmdline   — space-separated kernel parameters (one line, no trailing newline)
  #   init      — path to the NixOS stage-2 init inside the Nix store
  #
  system.build.kernelArtifacts = pkgs.runCommand "${imageName}-kernel-artifacts" {} ''
    mkdir -p $out

    # Kernel image (bzImage / Image depending on architecture)
    cp ${config.boot.kernelPackages.kernel}/${config.system.boot.loader.kernelFile} \
       $out/bzImage

    # Initrd — the .gz file produced by NixOS
    cp ${config.system.build.initialRamdisk}/initrd \
       $out/initrd

    # Kernel command line: join the list with spaces, strip trailing newline.
    # We append "init=<toplevel>/init" so the kernel hands off to NixOS
    # stage-2 directly (required for direct-kernel boot without a bootloader).
    printf '%s' "${lib.concatStringsSep " " config.boot.kernelParams} init=${config.system.build.toplevel}/init" \
      > $out/cmdline

    # Convenience symlink: the NixOS stage-2 init path
    echo "${config.system.build.toplevel}/init" > $out/init
  '';
}
