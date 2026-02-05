# stereos/modules/base.nix
#
# Core stereOS system configuration.
# Provides: boot, filesystem, SSH, nix settings, essential packages.

{ config, lib, pkgs, modulesPath, ... }:

{
  imports = [
    # Loads virtio kernel modules, QEMU guest agent, etc.
    "${modulesPath}/profiles/qemu-guest.nix"
  ];

  # NixOS system version to track
  system.stateVersion = "24.11";

  # -- stereOS system identity -----------------------------------------------
  # Override /etc/os-release so tools like hostnamectl show stereOS
  environment.etc."os-release".text = lib.mkForce ''
    NAME="StereOS"
    ID=stereos
    ID_LIKE=nixos
    VERSION="${config.system.nixos.version}"
    VERSION_ID="${config.system.nixos.version}"
    PRETTY_NAME="stereOS (${config.networking.hostName})"
    HOME_URL="https://github.com/paper-compute-co"
  '';

  users.motd = ''
      _____ _                  ____  _____
     / ____| |                / __ \/ ____|
    | (___ | |_ ___ _ __ ___| |  | | (___
     \___ \| __/ _ \ '__/ _ \ |  | |\___ \
     ____) | ||  __/ | |  __/ |__| |____) |
    |_____/ \__\___|_|  \___|\____/|_____/

    Mixtape: ${config.networking.hostName}

  '';

  # -- Boot ------------------------------------------------------------------
  # aarch64 requires UEFI boot — there is no BIOS on ARM.
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
  boot.kernelParams = [ "console=ttyAMA0,115200" "console=tty0" ];
  boot.growPartition = true;

  # -- Filesystem -------------------------------------------------------------
  fileSystems."/" = {
    device = "/dev/disk/by-label/nixos";
    fsType = "ext4";
    autoResize = true;  # Grow root partition on first boot
  };

  # -- SSH --------------------------------------------------------------------
  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = false;
      PermitRootLogin = "no";
      KbdInteractiveAuthentication = false;
    };
  };

  # -- Nix settings ----------------------------------------------------------
  nix.settings = {
    experimental-features = [ "nix-command" "flakes" ];
    auto-optimise-store = true;

    # CRITICAL: Only root and wheel can talk to the Nix daemon.
    # The 'agent' user is explicitly excluded — this is the primary
    # mechanism that prevents the AI agent from using nix tooling.
    allowed-users = [ "root" "@wheel" ];
    trusted-users = [ "root" ];
  };

  # -- System packages -------------------------------------------------------
  environment.systemPackages = with pkgs; [
    git
    vim
    curl
    wget
    jq
    ripgrep
    htop
    tmux
    tree
    file
    unzip
  ];

  # -- Locale and timezone ---------------------------------------------------
  time.timeZone = "UTC";
  i18n.defaultLocale = "en_US.UTF-8";

  # -- Firewall --------------------------------------------------------------
  networking.firewall = {
    enable = true;
    allowedTCPPorts = [ 22 ];  # SSH only
  };

  # -- Kernel configs and hardening ------------------------------------------
  boot.kernel.sysctl = {
    # Restrict process tracing (blocks ptrace-based attacks)
    "kernel.yama.ptrace_scope" = 2;

    # Hide kernel pointers from non-root
    "kernel.kptr_restrict" = 2;

    # Restrict dmesg to root
    "kernel.dmesg_restrict" = 1;

    # Disable core dumps via pipe
    "kernel.core_pattern" = "|/bin/false";

    # Network hardening
    "net.ipv4.conf.all.accept_redirects" = 0;
    "net.ipv4.conf.default.accept_redirects" = 0;
    "net.ipv6.conf.all.accept_redirects" = 0;
    "net.ipv4.conf.all.send_redirects" = 0;
  };
}
