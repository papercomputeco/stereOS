# modules/rpi.nix
#
# Raspberry Pi hardware overrides (Pi 4 + Pi 5).
#
# Board-aware via `stereos.rpi.series`. The Nix-level differences between
# Pi 4 and Pi 5 are small enough to live in one module: a few config.txt
# lines (UART/BT routing differs because Pi 5 puts UART behind RP1) and,
# in companion modules, a kernel-module blacklist that's BCM43455-specific.
# Everything else (root-fs label, redistributable firmware, kernel-console
# fixup) is identical across both boards.
#
# modules/boot.nix gates its VM-only tweaks (virtio-restricted initrd,
# GRUB EFI bootloader, vsock wiring) behind
# `!boot.loader.generic-extlinux-compatible.enable`, so enabling extlinux
# (done by formats/rpi-sd-image.nix via nixpkgs' sd-image-aarch64) is
# enough to skip them. nixpkgs' sd-image imports profiles/all-hardware.nix
# which brings the full initrd module set we need on real SBCs.
#
# Pulled in by profiles/rpi.nix alongside formats/rpi-sd-image.nix. Only
# imported on Pi builds because the `config` block sets sdImage.* options
# that nixpkgs only declares when sd-image-aarch64.nix is loaded.
# The board-series option lives in modules/rpi-options.nix so it is
# readable from VM builds too (modules/rpi-radios.nix consults it).

{ config, lib, pkgs, ... }:

let
  cfg = config.stereos.rpi;
in
{
  options.stereos.rpi.serialConsole.enable = lib.mkOption {
    type = lib.types.bool;
    default = true;
    description = ''
      Route the PL011 UART to GPIO 14/15 (physical pins 8/10) and use
      it as the kernel console + login getty, so a USB-serial adapter
      plugged into the GPIO header gives a diagnostic shell.

      On Pi 4 enabling this also disables on-board Bluetooth: the Pi
      4B wires PL011 to the BT radio by default, and
      dtoverlay=disable-bt moves it to the GPIO header. The mini-UART
      alternative preserves BT but its baud rate tracks the core clock
      and drifts without pinning — we don't offer it here.

      On Pi 5 UART routing goes through the RP1 southbridge and the
      Pi-4-shaped disable-bt overlay does not apply; only enable_uart
      is written to config.txt.

      Set to false to keep BT (Pi 4) or to skip the config.txt write
      entirely (Pi 5). You keep the HDMI console either way; you only
      lose the UART login.
    '';
  };

  config = {
    # -- FAT firmware partition size ----------------------------------------
    # nixpkgs sd-image defaults to 30 MiB. Pi 4 fits (bootcode.bin + fixup*.dat
    # + start*.elf + bcm2711-* dtbs ≈ 25 MiB). Pi 5 adds kernel_2712.img on
    # top of that — sd-image-aarch64.nix copies the *entire* raspberrypifw
    # boot/ tree, so the Pi 4 blobs are still present too — and that pushes
    # the FAT past 30 MiB and the build fails with "Disk full" during the
    # firmware-population step. 128 MiB gives comfortable headroom for
    # future overlays without being wasteful.
    sdImage.firmwareSize = lib.mkIf (cfg.series == "rpi5") 128;

    # -- Root filesystem -----------------------------------------------------
    # modules/base.nix sets the root to label "nixos"; the sd-image build
    # labels the root partition "NIXOS_SD". Override to match — mkForce beats
    # the normal-priority definition in base.nix and the one sd-image.nix
    # contributes from its own fileSystems block.
    fileSystems."/" = lib.mkForce {
      device = "/dev/disk/by-label/NIXOS_SD";
      fsType = "ext4";
      autoResize = true;
    };

    # -- Hardware ------------------------------------------------------------
    # Redistributable firmware covers Broadcom wireless + GPU blobs. The
    # sd-image module already copies the RPi bootloader firmware to the
    # FIRMWARE partition.
    hardware.enableRedistributableFirmware = true;

    # -- Debug: allow emergency shell without password ---------------------
    # The Pi 5 firmware-direct boot path is still being shaken out, so when
    # the initrd drops into emergency mode (e.g. /sysroot/run mount fails)
    # we need to be able to log in and run `systemctl status` to see what
    # actually went wrong. Default sulogin policy is "root account is
    # locked" with no console access, which is useless for debugging.
    # Scoped to Pi 5 only — Pi 4 production images should not expose a
    # passwordless emergency root shell on UART/HDMI.
    # TODO: remove once Pi 5 boot is stable.
    boot.initrd.systemd.emergencyAccess = lib.mkIf (cfg.series == "rpi5") true;

    # -- Kernel console ------------------------------------------------------
    # modules/boot.nix's aarch64 branch ends the console list with hvc0 —
    # correct for Apple Virtualization.framework guests, but a phantom on
    # real Pi hardware. The kernel makes the *last* console= into
    # /dev/console, so without an override anything init writes directly
    # (emergency shell, early panics) goes nowhere. mkForce rebuilds the
    # list with real terminals only; serialConsole.enable adds the right
    # device as the last entry so it becomes /dev/console.
    #
    # On both Pi 4 and Pi 5 the GPIO 14/15 UART enumerates as ttyAMA0
    # — Pi 4 directly (PL011), Pi 5 via the RP1 southbridge once the
    # uart0-pi5 dtoverlay routes RP1 UART0 to those GPIOs. ttyAMA10 on
    # Pi 5 is a *different* UART that goes to the dedicated 3-pin debug
    # header on the board, not the GPIO header.
    boot.kernelParams = lib.mkForce (
      [ "console=tty0" ]
      ++ lib.optional cfg.serialConsole.enable "console=ttyAMA0,115200"
    );

    # -- RPi firmware partition ---------------------------------------------
    # nixpkgs' installer/sd-card/sd-image-aarch64.nix populates the FAT
    # firmware partition with Pi 0/3/4 boot blobs (start4.elf, fixup4.dat,
    # bcm2711-rpi-4-b.dtb, ...) plus U-Boot extlinux. That is everything
    # the Pi 4 needs.
    #
    # The Pi 5 boots from its on-board EEPROM (no GPU-side bootcode.bin,
    # no fixup*.dat) and the firmware partition needs different content:
    #
    #   • bcm2712-rpi-5-b.dtb              — Pi 5 device tree
    #   • kernel_2712.img                  — rpi-vendor kernel image
    #   • a [pi5] section in config.txt    — tells the EEPROM to boot it
    #
    # pkgs.raspberrypifw at our pinned nixpkgs revision (1.20250430) ships
    # all of the above. We append them here; the [all] terminator after
    # the [pi5] block stops the filter bleeding into subsequent lines.
    #
    # populateFirmwareCommands is types.lines, so this concatenates with
    # the block in formats/rpi-sd-image.nix that drops in the SSH-keys
    # template.
    #
    # On Pi 4 the PL011 is wired to the on-board BT radio by default;
    # dtoverlay=disable-bt frees it onto GPIO 14/15 (pins 8/10). On Pi 5
    # UART routing is through the RP1 southbridge and the disable-bt
    # overlay does not apply — only enable_uart is written.
    sdImage.populateFirmwareCommands = ''
      # sd-image-aarch64.nix copies config.txt from a /nix/store path
      # (mode 0444), so any cat >> append below would hit Permission
      # denied. Make it writable before we touch it. install -m 644 the
      # Pi 5 blobs we drop in, for the same reason — keeps the FAT
      # partition contents at sane modes.
      chmod u+w firmware/config.txt

      ${lib.optionalString (cfg.series == "rpi5") ''
        # Pi 5: ship the full bcm2712 dtb set + entire overlays tree from
        # raspberrypifw, plus the *NixOS-built* kernel and initrd as
        # kernel_2712.img / initrd. The EEPROM reads them directly.
        #
        # Why the full dtb + overlays set:
        #
        # The Pi 5 ships in two SoC steppings — C1 (4/8/16 GB models) and
        # D0 (newer 2 GB boards + rev-1.1 reworks). D0 needs
        # bcm2712d0-rpi-5-b.dtb plus the overlays/bcm2712d0.dtbo "C0->D0
        # differences" overlay to describe pinctrl correctly. The EEPROM
        # auto-selects the right dtb + overlay when both are present.
        # Ship only one and D0 panics during pinctrl-bcm2712 probe with
        # an Asynchronous SError. bcm2712*.dtb covers Pi 5, Pi 500,
        # CM5, CM5L variants; shipping the full overlays/ tree is the
        # nvmd/nixos-raspberrypi pattern.
        install -m 0644 ${pkgs.raspberrypifw}/share/raspberrypi/boot/bcm2712*.dtb firmware/
        mkdir -p firmware/overlays
        install -m 0644 ${pkgs.raspberrypifw}/share/raspberrypi/boot/overlays/*.dtbo firmware/overlays/

        # NixOS-built kernel + initrd on the FAT partition.
        #
        # Why we do NOT use raspberrypifw's prebuilt kernel_2712.img:
        # it's a different version (e.g. 6.12.25-v8-16k+ in fw 1.20250430)
        # than the kernel nixos-hardware builds (linux-rpi 6.12.75-1+rpt1).
        # Loading the firmware kernel makes /lib/modules/6.12.75/ unusable —
        # modprobe fails, kernel-module-dependent userspace breaks, and the
        # kernel boots with the firmware's Pi-OS-shaped cmdline.txt
        # (root=/dev/mmcblk0p2 etc.) which has nothing to do with NixOS.
        #
        # nixpkgs at our pinned rev has no ubootRaspberryPi5_64bit, so the
        # standard sd-image-aarch64 U-Boot+extlinux flow is unavailable on
        # Pi 5 — we install our kernel + initrd directly under the names
        # the EEPROM looks for. cmdline.txt below points at the NixOS
        # init via the profile symlink and mounts root by-label so the
        # same image works whether flashed to SD or USB.
        #
        # kernel_2712.img must be gzip-compressed — the Pi 5 EEPROM
        # detects the gzip magic and decompresses on load. nixos-hardware's
        # linuxPackages_rpi5 only installs the raw Image, so we gzip it
        # ourselves. (raspberrypifw's prebuilt kernel_2712.img is gzipped
        # too — verified with `file` against 1.20250430.)
        gzip -n9 -c ${config.boot.kernelPackages.kernel}/Image > firmware/kernel_2712.img
        chmod 0644 firmware/kernel_2712.img
        install -m 0644 ${config.system.build.initialRamdisk}/initrd firmware/initrd

        # Don't set root= / rootfstype= / rootwait on the kernel cmdline:
        # systemd-initrd reads the new root from /etc/fstab in the initrd,
        # generated from fileSystems."/". Setting root= as well makes
        # systemd-fstab-generator create sysroot.mount twice, fails the
        # second creation, and the boot drops to emergency mode with
        # "Failed to create unit file '/run/systemd/generator/sysroot.mount',
        # as it already exists. Duplicate entry in '...-initrd-fstab'?".
        # NixOS extlinux APPEND deliberately omits root= for the same reason.
        #
        # init= must be the *explicit* /nix/store toplevel path, not the
        # /nix/var/nix/profiles/system symlink — that symlink is only
        # created by activation, which runs post-switch_root, so on the
        # very first boot the profile path doesn't exist yet and
        # initrd-find-nixos-closure fails with
        # "Failed to canonicalize /nix/var/nix/profiles/system/init:
        # No such file or directory". NixOS extlinux bakes the explicit
        # toplevel into APPEND for exactly this reason; we mirror that
        # here so first boot works. Trade-off: nixos-rebuild switch
        # doesn't update cmdline.txt automatically — kernel/initrd/init
        # path are baked at image-build time.
        cat > firmware/cmdline.txt <<EOF
        init=${config.system.build.toplevel}/init ${lib.concatStringsSep " " config.boot.kernelParams}
        EOF
      ''}

      ${lib.optionalString cfg.serialConsole.enable ''
        cat >> firmware/config.txt <<'EOF'

        # stereos: serial console on GPIO 14/15 (PL011, 115200 8N1).
        # On Pi 4 this disables on-board Bluetooth. To restore BT and
        # give up the serial console, set
        # stereos.rpi.serialConsole.enable = false.
        enable_uart=1
        ${lib.optionalString (cfg.series == "rpi4") "dtoverlay=disable-bt"}
        EOF
      ''}

      ${lib.optionalString (cfg.series == "rpi5") ''
        cat >> firmware/config.txt <<'EOF'

        # stereos: tell the Pi 5 EEPROM to boot the rpi-vendor kernel
        # we just dropped into the FAT partition, and route the GPIO
        # 14/15 UART (RP1 UART0) onto pins 8/10 so the serial console
        # comes out where the user is plugging the USB-serial adapter.
        #
        # enable_uart=1 (above, in the [all] section) starts the
        # firmware-side UART. dtparam=uart0=on alone is NOT sufficient
        # on Pi 5 — it doesn't pinmux RP1 UART0 to GPIO 14/15. The
        # uart0-pi5 dtoverlay does that pinmux. Ship config.txt without
        # it and tio sees nothing on pins 8/10 even with enable_uart.
        #
        # initramfs initrd followkernel tells the EEPROM to load our
        # NixOS-built initrd from FAT after the kernel, since we're
        # bypassing extlinux/U-Boot entirely.
        # [all] closes the [pi5] filter so subsequent appends apply
        # unconditionally again.
        [pi5]
        kernel=kernel_2712.img
        initramfs initrd followkernel
        arm_64bit=1
        dtoverlay=uart0-pi5
        [all]
        EOF
      ''}
    '';
  };
}
