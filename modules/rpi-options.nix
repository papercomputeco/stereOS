# modules/rpi-options.nix
#
# Always-declared Raspberry Pi option surface.
#
# `stereos.rpi.series` needs to be readable from any module — including
# modules/rpi-radios.nix, which is imported on every build (VM and Pi
# alike). modules/rpi.nix sets `sdImage.*` options that only exist when
# nixpkgs' sd-image-aarch64.nix is imported, so it can't be imported on
# VM builds. This file holds just the option *declarations* (no `config`
# block), so it's safe to import unconditionally from modules/default.nix.
#
# The `config` block that consumes these options lives in modules/rpi.nix,
# which is pulled in only via profiles/rpi.nix.

{ lib, ... }:

{
  options.stereos.rpi = {
    series = lib.mkOption {
      type = lib.types.enum [ "rpi4" "rpi5" ];
      default = "rpi4";
      description = ''
        Which Raspberry Pi board this image targets. Drives the small
        set of board-specific knobs that differ between Pi 4 (BCM2711)
        and Pi 5 (BCM2712 + RP1 southbridge): the dtoverlay used to
        free the UART, and the BCM43455 radio-blacklist heuristic.

        Default is "rpi4" so the legacy build target keeps working.
        Pi 5 mixtape specs override this to "rpi5".
      '';
    };
  };
}
