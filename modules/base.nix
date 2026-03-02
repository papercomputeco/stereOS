# modules/base.nix
#
# Core stereOS system configuration.
# Provides: filesystem, SSH, nix settings, essential packages, hardening.
#
# Boot configuration lives in boot.nix.

{ config, lib, pkgs, modulesPath, stereosVersion, gitRevision, ... }:

{
  imports = [
    # Loads virtio kernel modules, QEMU guest agent, etc.
    "${modulesPath}/profiles/qemu-guest.nix"
  ];

  # NixOS system version to track
  system.stateVersion = "24.11";

  # -- stereOS version identity ----------------------------------------------
  # Label shown by `nixos-version` and in boot entries.
  # e.g. "stereOS-2026.03.01.0-coder" or "stereOS-dev-abc1234-coder"
  system.nixos.label = "stereOS-${stereosVersion}-${config.networking.hostName}";

  # Exact git commit — shows up in `nixos-version --json`.
  system.configurationRevision = gitRevision;

  # -- stereOS system identity -----------------------------------------------
  # Override /etc/os-release so tools like hostnamectl show stereOS
  environment.etc."os-release".text = lib.mkForce ''
    NAME="stereOS"
    ID=stereos
    ID_LIKE=nixos
    VERSION="${stereosVersion}"
    VERSION_ID="${stereosVersion}"
    VERSION_CODENAME="${config.networking.hostName}"
    PRETTY_NAME="stereOS ${stereosVersion} (${config.networking.hostName})"
    HOME_URL="https://github.com/papercomputeco/stereOS"
    NIXOS_VERSION="${config.system.nixos.version}"
  '';

  # "Sub-Zero" ASCII art stereOS logo for ssh splash
  users.motd = ''
  ______   ______  ______   ______   ______   ______   ______
 /\  ___\ /\__  _\/\  ___\ /\  == \ /\  ___\ /\  __ \ /\  ___\
 \ \___  \\/_/\ \/\ \  __\ \ \  __< \ \  __\ \ \ \/\ \\ \___  \
  \/\_____\  \ \_\ \ \_____\\ \_\ \_\\ \_____\\ \_____\\/\_____\
   \/_____/   \/_/  \/_____/ \/_/ /_/ \/_____/ \/_____/ \/_____/

    stereOS ${stereosVersion}
    Mixtape: ${config.networking.hostName}

  '';

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

  # -- User authentication ---------------------------------------------------
  # stereOS images are built without baked-in SSH keys or passwords.
  # SSH authorized keys are ephemerally injected at VM boot time by stereosd
  # over vsock.
  users.allowNoPasswordLogin = true;

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
    jq
    ripgrep
    htop
    tmux
    tree
    file
    unzip
    ghostty.terminfo  # xterm-ghostty terminfo entry
    gvisor            # runsc: gVisor sandbox runtime for sandboxed agents
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

  # -- Ensure /tmp is tmpfs (ephemeral, never written to disk) -------------
  boot.tmp.useTmpfs = true;
}
