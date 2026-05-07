# profiles/rpi.nix
#
# Profile for Raspberry Pi mixtapes. Swaps the VM-oriented image format
# (raw EFI, qcow2, kernel artifacts) for an SD card image and applies
# the Pi hardware + bootloader overrides.
#
# Board-agnostic — modules/rpi.nix dispatches on `stereos.rpi.series`.
# The mixtape spec sets the series; this profile defaults to the option
# default ("rpi4") so legacy callers don't need to change.
#
# modules/rpi.nix is imported unconditionally from modules/default.nix
# so the option is always declared; this profile only adds the SD image
# format + first-boot key drop-in.
#
# Include via mkMixtape extraModules alongside a mixtape's feature list.

{ config, lib, pkgs, ... }:

{
  imports = [
    ../formats/rpi-sd-image.nix
    ../modules/rpi.nix
    ../modules/firstboot-keys.nix
  ];
}
