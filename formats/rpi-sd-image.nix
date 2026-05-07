# formats/rpi-sd-image.nix
#
# SD card image format for Raspberry Pi.
# Produces system.build.sdImage — an MBR-partitioned raw image with a
# FAT32 /boot partition (U-Boot + kernel + DTB) and an ext4 root.
#
# Build with:
#   nix build .#packages.aarch64-linux.<mixtape-name>-sd --impure
#
# Flash with:
#   zstd -d stereos-<mixtape>-rpi4.img.zst -o stereos.img
#   dd if=stereos.img of=/dev/<sdcard> bs=4M status=progress

{ config, lib, pkgs, modulesPath, ... }:

let
  # User-facing template for the first-boot key drop-in. See
  # modules/firstboot-keys.nix for the service that consumes it.
  authorizedKeysTemplate = pkgs.writeText "ssh_authorized_keys.txt" ''
    # stereOS authorized_keys (first-boot drop-in)
    #
    # Add one SSH public key per line, in the standard OpenSSH
    # authorized_keys format, e.g.
    #
    #   ssh-ed25519 AAAA... matt@laptop
    #   ssh-rsa     AAAAB3... workstation
    #
    # On every boot, stereos-firstboot-keys.service reads this file and
    # appends any new keys to /home/admin/.ssh/authorized_keys before
    # sshd starts. Blank lines and "#" comments are ignored. Duplicate
    # keys are skipped. Safe to leave empty.
    #
    # This file lives on the FAT32 "FIRMWARE" partition of the SD card
    # and can be edited directly from macOS / Windows / Linux with the
    # card plugged into any computer.
  '';
in
{
  imports = [
    # Provides system.build.sdImage, U-Boot extlinux bootloader setup,
    # Raspberry Pi firmware in /boot, and fileSystems entries for
    # NIXOS_SD (root) and FIRMWARE (boot).
    "${modulesPath}/installer/sd-card/sd-image-aarch64.nix"
  ];

  # `sdImage.imageBaseName` was renamed to `image.baseName` in nixpkgs 25.05.
  image.baseName = "stereos-${config.networking.hostName}";

  # Uncompressed — matches raw-efi.nix convention so downstream tools
  # (dd, vm runners) can consume the artifact directly.
  sdImage.compressImage = false;

  # Drop the template onto the FIRMWARE partition. populateFirmwareCommands
  # is declared as types.lines in nixpkgs, so this concatenates with the
  # commands sd-image-aarch64.nix already installs.
  sdImage.populateFirmwareCommands = ''
    cp ${authorizedKeysTemplate} firmware/ssh_authorized_keys.txt
  '';

  # nixpkgs sd-image.nix mounts /boot/firmware with `noauto` because the
  # FAT partition only holds RPi bootloader blobs consumed by the GPU
  # firmware — nothing on the running Linux system needs it. We use it as
  # the drop-in surface for user-editable config (ssh_authorized_keys.txt,
  # future knobs), so override the options to mount it at boot. `nofail`
  # stays so a corrupt/missing FAT doesn't block boot.
  fileSystems."/boot/firmware".options = lib.mkForce [ "nofail" ];

  # Disable fsck on the FIRMWARE partition. systemd auto-generates a
  # systemd-fsck@... unit for every fstab entry with a nonzero passno,
  # and failures there cascade into "Dependency failed for /boot/firmware"
  # on the mount unit. vfat's dirty-bit set by unclean shutdowns is a
  # frequent source; the partition holds small config files we're willing
  # to re-flash if it ever corrupts.
  fileSystems."/boot/firmware".noCheck = true;

  # The sd-image build populates ./files/boot/... into the ext4 root, so
  # /boot exists on the installed system but /boot/firmware does NOT —
  # and systemd won't mount onto a missing path (nofail then swallows the
  # error). systemd-tmpfiles runs after local-fs.target, so tmpfiles rules
  # can't create the mount point in time. Instead bake the empty directory
  # into the root filesystem at image build time.
  # populateRootCommands is types.lines, so this concatenates with the
  # sd-image-aarch64.nix block that writes extlinux.conf.
  sdImage.populateRootCommands = ''
    mkdir -p ./files/boot/firmware
  '';
}
