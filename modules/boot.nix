# modules/boot.nix
#
# Boot configuration and boot-time optimizations for stereOS.
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

let
  isAarch64 = pkgs.system == "aarch64-linux";

  # VM-target gate. Real hardware images (the RPi4 SD image) enable the
  # generic extlinux-compatible loader, so we use that as the signal that
  # this build is NOT a QEMU / Apple-VF guest and should skip the virtio-
  # only initrd, vsock wiring, and other VM-only optimizations below.
  isVmTarget = !config.boot.loader.generic-extlinux-compatible.enable;
in
{
  # -- Boot ------------------------------------------------------------------
  # efiInstallAsRemovable=true puts GRUB at /EFI/BOOT/BOOTAA64.EFI (aarch64)
  # or /EFI/BOOT/BOOTX64.EFI (x86_64), which is the fallback path
  # QEMU's UEFI firmware searches. The correct filename is determined by grub-install.
  boot.loader.grub = lib.mkIf isVmTarget {
    enable = true;
    efiSupport = true;
    efiInstallAsRemovable = true;
    device = "nodev";  # No MBR install — EFI only
  };

  # Serial console for headless operation.
  # The kernel accepts multiple console= parameters and writes output to all
  # of them, but only the *last* one becomes /dev/console (used by init and
  # systemd for stdin/stdout). We list the primary console last.
  #
  # aarch64:
  #   ttyAMA0  — PL011 UART on QEMU's virt machine (aarch64 -serial)
  #   hvc0     — virtio console on Apple Virtualization.framework
  #   tty0     — virtual terminal (active when a display is attached)
  #
  # x86_64:
  #   ttyS0    — COM1 serial port on QEMU standard PC
  #   tty0     — virtual terminal
  #
  # With this ordering, hvc0/ttyS0 is /dev/console.
  # quiet + loglevel=0 silence the kernel for fast/clean VM boots — on real
  # RPi4 hardware we want the messages on HDMI + serial so a hung or failing
  # boot is diagnosable.
  boot.kernelParams = lib.mkMerge [
    (lib.mkIf isVmTarget (lib.mkBefore [ "quiet" "loglevel=0" ]))
    (if isAarch64
      then [ "console=tty0" "console=ttyAMA0,115200" "console=hvc0" ]
      else [ "console=tty0" "console=ttyS0,115200" ])
  ];
  # VM disk images grow on first boot via cloud-utils growpart. The RPi4
  # sd-image build already handles partition expansion via sdImage.expandOnBoot,
  # so growpart only runs (and only makes sense) on the VM target.
  boot.growPartition = lib.mkIf isVmTarget true;

  # ============================================================
  # Phase 1: High-Impact, Low-Effort
  # ============================================================

  # -- Boot infrastructure ---------------------------------------------------

  # Systemd-based initrd: replaces NixOS's sequential bash stage-1 with a
  # parallelized systemd initrd.  Expected savings: 1-3 s.
  boot.initrd.systemd.enable = true;

  # Silence kernel output — no printk spam on the serial console during boot.
  # Real hardware needs the printk stream visible (HDMI + UART) so failures
  # can be diagnosed.
  boot.consoleLogLevel = lib.mkIf isVmTarget 0;

  # Restrict initrd to only the kernel modules needed for virtio-backed VMs.
  # This keeps the initrd small and avoids probing irrelevant hardware.
  # Real-hardware builds (RPi4) fall through to nixpkgs' all-hardware.nix
  # defaults (pulled in by sd-image.nix) and must not be narrowed here.
  boot.initrd.availableKernelModules = lib.mkIf isVmTarget (lib.mkForce [
    "virtio_blk"
    "virtio_pci"
    "virtio_net"
    "virtio_console"
    "virtiofs"

    # vsock: host-guest control plane for stereosd.
    "vsock"
    "vmw_vsock_virtio_transport"
    "vmw_vsock_virtio_transport_common"

    "ext4"
    "erofs"
    "overlay"
  ]);
  # Nothing force-loaded at initrd time — let systemd-udevd handle it.
  boot.initrd.kernelModules = lib.mkIf isVmTarget (lib.mkForce []);

  # Force-load vsock transport in the real root so it is available before
  # stereosd starts. udev does not automatically load vsock modules because
  # the virtio-socket device doesn't trigger a modalias match for the
  # transport layer. Without this, stereosd's VsockTransportAvailable()
  # check fails and it falls back to TCP.
  boot.kernelModules = lib.mkIf isVmTarget [ "vmw_vsock_virtio_transport" ];

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
    linkConfig = {
      # RequiredForOnline=routable means wait-online only succeeds when
      # the link has a routable DHCP/static address — NOT when IPv4LL
      # has assigned 169.254.x.x.  On VM targets this is moot (wait-
      # online is disabled below); on rpi4 it's the difference between
      # network-online.target firing at the link-local mark (seconds
      # after boot) vs firing only when a real DHCP lease is in hand
      # (30-50s later, thanks to BCM54213 PHY negotiation).  Services
      # that need actual internet — openclaw-bootstrap, for example —
      # depend on this target being honest.
      RequiredForOnline = "routable";
    };
    networkConfig = {
      DHCP = "yes";
      # VM targets lean on IPv4LL as a "don't block boot if DHCP is
      # unreachable" fallback.  Real-hardware targets live on a LAN
      # with a real DHCP server; turning off IPv4LL means the only
      # address the interface ever gets is the routable one, and the
      # console banner / `ip addr` never shows a misleading 169.254.
      LinkLocalAddressing = if isVmTarget then "ipv4" else "no";
    };
    dhcpV4Config = {
      # Accept the default route from QEMU SLIRP (10.0.2.2)
      UseDomains = true;
    };
  };

  # VM targets boot on SLIRP/vmnet which comes up asynchronously — we
  # don't want to block multi-user.target on it.  Real-hardware targets
  # (rpi4) need the opposite: hold off services like openclaw-bootstrap
  # until a real DHCP lease is in hand, otherwise npm install will run
  # against link-local-only connectivity and fail intermittently.
  systemd.services.systemd-networkd-wait-online.enable = lib.mkForce (!isVmTarget);

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
  # Real hardware (RPi4) needs the defaults back — the SD/MMC controller
  # typically takes ~3s to enumerate the FIRMWARE partition's by-label
  # symlink, so DefaultDeviceTimeoutSec=3s races and intermittently loses,
  # cascading into "Dependency failed for /boot/firmware".
  systemd.settings.Manager = lib.mkIf isVmTarget {
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
  # On real hardware (RPi4) we keep getty so the user can log in via HDMI +
  # keyboard or via UART.
  services.getty.autologinUser = lib.mkIf isVmTarget (lib.mkForce null);
  systemd.services."getty@".enable = lib.mkIf isVmTarget (lib.mkForce false);
  systemd.services."serial-getty@".enable = lib.mkIf isVmTarget (lib.mkForce false);
  systemd.services."autovt@".enable = lib.mkIf isVmTarget (lib.mkForce false);

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
    description = "stereOS boot complete marker";
    wantedBy = [ "multi-user.target" ];
    after = [ "stereosd.service" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${pkgs.bash}/bin/sh -c '${pkgs.coreutils}/bin/date > /run/stereos-ready'";
    };
  };
}
