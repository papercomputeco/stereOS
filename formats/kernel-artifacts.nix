# formats/kernel-artifacts.nix
#
# Direct-kernel boot artifacts.
# Produces system.build.kernelArtifacts — a directory containing the
# kernel (bzImage), initrd, and a cmdline file for direct-kernel boot
# via QEMU (-kernel/-initrd) or Apple Virtualization.framework.
#
# Enables bypassing the UEFI/GRUB boot path entirely, which is the
# primary mechanism for sub-3-second boot.
#
# Build with:
#   nix build .#packages.aarch64-linux.<mixtape-name>-kernel-artifacts --impure
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

{ config, lib, pkgs, ... }:

let
  imageName = "stereos-${config.networking.hostName}";
in
{
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
