# modules/rpi5-kernel-overlay.nix
#
# Pi-5-only overlay: tell makeModulesClosure to skip modules listed in
# boot.initrd.availableKernelModules that are absent from the rpi-vendor
# kernel's /lib/modules tree.
#
# Why this is needed: nixpkgs' installer/sd-card/sd-image-aarch64.nix
# transitively imports profiles/all-hardware.nix, which sets a giant
# boot.initrd.availableKernelModules list (dw_hdmi, drm_kms_helper,
# pwm-bcm2835, …). The rpi-vendor 6.12.x kernel built with
# bcm2712_defconfig compiles many of those as =y — they live in vmlinuz
# rather than as separate .ko files, so modprobe errors out with
#
#   modprobe: FATAL: Module dw-hdmi not found in directory ...
#
# during the `modules-shrunk` (makeModulesClosure) derivation, killing
# the SD-image build before it assembles the initrd.
#
# Skipping them in the closure is safe because they're already linked
# into the kernel image and auto-loaded by the kernel; there is no
# corresponding action for the initrd to take.
#
# This is the canonical pattern: nvmd/nixos-raspberrypi applies the same
# overlay unconditionally for every Pi variant. We scope it to Pi 5
# builds (Pi 4 still uses the standard sd-image-aarch64 kernel and works
# without the override).
#
# Refs:
#   https://github.com/NixOS/nixpkgs/issues/154163
#   https://discourse.nixos.org/t/cannot-build-raspberry-pi-sdimage-module-dw-hdmi-not-found/71804
#   https://github.com/nvmd/nixos-raspberrypi/blob/master/modules/raspberrypi.nix

{ ... }:

{
  nixpkgs.overlays = [
    (final: super: {
      makeModulesClosure = args:
        super.makeModulesClosure (args // { allowMissing = true; });
    })
  ];
}
