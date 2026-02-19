# modules/boot.nix
#
# Boot configuration and boot-time optimizations for stereOS.
#
# aarch64 requires UEFI boot — there is no BIOS on ARM.
#
# Boot optimizations target sub-3-second boot for the stereOS agent
# sandbox image when launched via QEMU (-M microvm) or Apple
# Virtualization.framework.
#
# This module is split into two phases matching the SPEC:
#
#   Phase 1 — High-impact, low-effort
#   Phase 2 — Medium effort (service audit, volatile journal, NSS)
#
# Verification: check /run/stereos-ready for a Unix nanosecond timestamp
# written by the stereos-ready.service unit once multi-user.target is reached.

{ config, lib, pkgs, ... }:

{
  # -- Boot ------------------------------------------------------------------
  # efiInstallAsRemovable puts GRUB at /EFI/BOOT/BOOTAA64.EFI,
  # which is the fallback path QEMU's UEFI firmware searches.
  boot.loader.grub = {
    enable = true;
    efiSupport = true;
    efiInstallAsRemovable = true;
    device = "nodev";  # No MBR install — EFI only
  };

  # Serial console for -nographic QEMU operation.
  # ttyAMA0 is the PL011 UART on QEMU's virt machine (aarch64).
  boot.kernelParams = lib.mkMerge [
    (lib.mkBefore [ "quiet" "loglevel=0" ])
    [ "console=ttyAMA0,115200" "console=tty0" ]
  ];
  boot.growPartition = true;

  # ============================================================
  # Phase 1: High-Impact, Low-Effort
  # ============================================================

  # -- Boot infrastructure ---------------------------------------------------

  # Systemd-based initrd: replaces NixOS's sequential bash stage-1 with a
  # parallelized systemd initrd.  Expected savings: 1-3 s.
  boot.initrd.systemd.enable = true;

  # Silence kernel output — no printk spam on the serial console during boot.
  boot.consoleLogLevel = 0;

  # Restrict initrd to only the kernel modules needed for virtio-backed VMs.
  # This keeps the initrd small and avoids probing irrelevant hardware.
  boot.initrd.availableKernelModules = lib.mkForce [
    "virtio_blk"
    "virtio_pci"
    "virtio_net"
    "virtio_console"
    "virtiofs"
    "ext4"
    "erofs"
    "overlay"
  ];
  # Nothing force-loaded at initrd time — let systemd-udevd handle it.
  boot.initrd.kernelModules = lib.mkForce [];

  # Use systemd-networkd for networking instead of scripted ifup.
  # Pairs with disabling the wait-online stall below.
  networking.useNetworkd = true;
  networking.useDHCP = false;

  # Configure systemd-networkd to DHCP on all ethernet interfaces.
  # When useNetworkd=true and useDHCP=false, explicit .network units are
  # required — without them, networkd ignores all interfaces and the guest
  # has no IP address (breaking SSH, stereosd TCP, and all egress).
  # QEMU's SLIRP stack provides a DHCP server at 10.0.2.2.
  systemd.network.networks."10-ethernet" = {
    matchConfig.Type = "ether";
    networkConfig = {
      DHCP = "yes";
      # Don't wait for DHCP to finish before declaring the link "online".
      # This avoids boot stalls if the DHCP server is slow or unavailable.
      LinkLocalAddressing = "ipv4";
    };
    dhcpV4Config = {
      # Accept the default route from QEMU SLIRP (10.0.2.2)
      UseDomains = true;
    };
  };

  # Do not stall boot waiting for all interfaces to become online.
  # The host's SLIRP/vmnet interface comes up asynchronously; we don't need
  # to block multi-user.target on it.
  systemd.services.systemd-networkd-wait-online.enable = lib.mkForce false;

  # -- Disable unnecessary NixOS defaults ------------------------------------

  # Documentation generation adds significant closure size and build time;
  # an ephemeral agent sandbox has no use for man pages or NixOS manuals.
  documentation.enable = false;
  documentation.man.enable = false;
  documentation.nixos.enable = false;
  documentation.info.enable = false;
  documentation.doc.enable = false;

  # Firewall: isolation is enforced at the VM boundary (the host controls
  # what reaches the VM), not by iptables inside the guest.  Disabling
  # netfilter removes the iptables/nftables rule-loading unit from the boot
  # critical path.
  networking.firewall.enable = lib.mkForce false;

  # polkit is a desktop-policy daemon; stereOS is headless and has no GUI
  # tooling that would use it.
  security.polkit.enable = false;

  # udisks2 auto-mounts removable media — irrelevant inside a VM with a
  # single virtio block device.
  services.udisks2.enable = false;

  # XDG portals are desktop-portal bridges (Flatpak / Wayland); not needed
  # in a headless agent environment.
  xdg.portal.enable = false;

  # command-not-found invokes nix-index on every unknown command, adding
  # latency and requiring a channel database that we don't ship.
  programs.command-not-found.enable = false;

  # Disable nixos-rebuild / nix-channel infrastructure.  We use flakes;
  # there is no channel to update and no reason for the channel cron job.
  nix.channel.enable = false;

  # Immutable user database: no passwd/shadow writes at boot, which removes
  # the activation script step that re-generates those files.
  users.mutableUsers = false;

  # -- Systemd timeouts ------------------------------------------------------

  # Tighten start/stop/device timeouts for the ephemeral sandbox use-case.
  # Default NixOS values are 90 s (start) and 90 s (stop); these are far
  # too long for a VM that should boot and shut down in under 5 s total.
  systemd.settings.Manager = {
    DefaultTimeoutStartSec = "10s";
    DefaultTimeoutStopSec = "3s";
    DefaultDeviceTimeoutSec = "3s";
  };

  # ============================================================
  # Phase 2: Medium Effort
  # ============================================================

  # -- Service audit ---------------------------------------------------------

  # stereOS is headless; there is no interactive login via a TTY or serial
  # console.  Disabling getty removes several units from the boot graph.
  services.getty.autologinUser = lib.mkForce null;
  systemd.services."getty@".enable = lib.mkForce false;
  systemd.services."serial-getty@".enable = lib.mkForce false;
  systemd.services."autovt@".enable = lib.mkForce false;

  # Use a volatile (in-memory) journal.  An ephemeral sandbox VM has no need
  # for persistent logs across reboots, and avoiding disk writes reduces I/O
  # on the boot critical path.
  services.journald.storage = "volatile";
  services.journald.extraConfig = ''
    RuntimeMaxUse=32M
  '';

  # Restrict NSS to local files + DNS only.  Without this, glibc may try
  # LDAP/mDNS/systemd-resolved lookups for passwd and group entries, adding
  # latency to every getpwuid/getgrnam call that services make during startup.
  system.nssDatabases.passwd = lib.mkForce [ "files" ];
  system.nssDatabases.group  = lib.mkForce [ "files" ];
  system.nssDatabases.hosts  = lib.mkForce [ "files" "dns" ];

  # ============================================================
  # Verification: boot complete marker
  # ============================================================

  # This oneshot unit writes a Unix nanosecond timestamp to /run/stereos-ready
  # once multi-user.target (and stereosd.service) have been reached.
  # Compare the value against the kernel boot timestamp in /proc/uptime to
  # measure total time-to-ready.
  systemd.services.stereos-ready = {
    description = "StereOS boot complete marker";
    wantedBy = [ "multi-user.target" ];
    after = [ "stereosd.service" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${pkgs.coreutils}/bin/sh -c '${pkgs.coreutils}/bin/date +%s%N > /run/stereos-ready'";
    };
  };
}
