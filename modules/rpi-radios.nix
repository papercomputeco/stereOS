# modules/rpi-radios.nix
#
# Turn off the Pi 4's onboard Bluetooth and WiFi by blacklisting the
# Broadcom kernel modules.  The BCM43455 combo chip's firmware load is
# slow (~10s) and occasionally times out outright on our hardware —
# dmesg fills with:
#
#   Bluetooth: hci0: BCM: failed to write update baudrate (-110)
#   Bluetooth: hci0: Failed to set baudrate
#   Bluetooth: hci0: command tx timeout
#   Bluetooth: hci0: BCM: Reset failed (-110)
#
# None of those matter for the openclaw appliance (which uses the
# gigabit ethernet only), but they run in parallel with the network
# stack coming up and dirty the boot logs.  Defaulting to `false`
# keeps the appliance boot clean.  Flip the option to `true` if/when
# we want BT or WiFi working.
#
# This blacklist is Pi-4-specific. The Pi 5 uses a different combo
# chip (Cypress/Infineon CYW43455 variant on RP1) and the BCM firmware
# timeouts that motivated the blacklist may not occur — the gate
# (stereos.rpi.series == "rpi4") keeps the blacklist off Pi 5 builds
# until/unless we observe the same dmesg pattern there.

{ config, lib, ... }:

let
  isPiHardware = config.boot.loader.generic-extlinux-compatible.enable;
  isRpi4 = isPiHardware && config.stereos.rpi.series == "rpi4";
  cfg = config.stereos.rpi.radios;
in {
  options.stereos.rpi.radios.enable = lib.mkOption {
    type = lib.types.bool;
    default = false;
    description = ''
      Whether the Pi's onboard Bluetooth and WiFi kernel modules
      should be loaded.  Default `false` — the openclaw appliance
      uses gigabit ethernet only and the BCM firmware load adds
      ~10s of boot time plus noisy timeouts in dmesg.  Set to `true`
      to re-enable the radios.

      Today the blacklist that this option drives is Pi-4-specific
      (BCM43455 module names). Pi 5 builds do not blacklist anything
      regardless of this option; the radios just come up.
    '';
  };

  config = lib.mkIf (isRpi4 && !cfg.enable) {
    boot.blacklistedKernelModules = [
      "brcmfmac"      # Broadcom FullMAC WiFi driver
      "brcmutil"      # shared utilities for brcm80211 family
      "hci_uart"      # UART transport for Bluetooth HCI
      "btbcm"         # Broadcom Bluetooth firmware / init glue
    ];
  };
}
