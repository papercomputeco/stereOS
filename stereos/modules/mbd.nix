# stereos/modules/mbd.nix
#
# Systemd unit for mbd (masterblaster daemon) — the control plane bridge
# between the host system and StereOS.
#
# mbd is started early in the boot process and provides:
#   - Lifecycle signaling over virtio-vsock (CID:3, port 1024)
#   - Shared directory mounting (virtio-fs / 9p)
#   - Secret injection to tmpfs-backed paths
#   - Graceful shutdown coordination
#   - Unix socket for agentd communication
#
# agentd depends on mbd (After=mbd.service).

{ config, lib, pkgs, ... }:

let
  # Build the mbd binary from the Go source in this repo.
  # In the future this may come from a separate Nix derivation or
  # be pinned to a release artifact.
  mbdBin = pkgs.buildGoModule {
    pname = "mbd";
    version = "0.1.0";
    src = lib.cleanSource ../../.;
    subPackages = [ "cmd/mbd" ];
    vendorHash = null;
  };
in
{
  config = {
    # -- Runtime directories (tmpfs-backed) ----------------------------------
    systemd.tmpfiles.rules = [
      "d /run/stereos 0755 root root -"
      "d /run/stereos/secrets 0700 root root -"
    ];

    # -- mbd systemd service -------------------------------------------------
    systemd.services.mbd = {
      description = "StereOS Masterblaster Daemon";
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" ];

      # mount and umount are needed for shared directory mounting
      path = [ pkgs.util-linux pkgs.coreutils ];

      serviceConfig = {
        Type = "simple";
        ExecStart = "${mbdBin}/bin/mbd";
        Restart = "on-failure";
        RestartSec = 5;

        # mbd runs as root because it needs to:
        #   - Bind to AF_VSOCK sockets
        #   - Mount/unmount shared filesystems (CAP_SYS_ADMIN)
        #   - Write secrets to /run/stereos/secrets (root-owned)
        #   - Initiate system poweroff during shutdown

        # Security hardening (what we *can* lock down while still
        # allowing mount operations and vsock)
        ProtectHome = true;
        PrivateTmp = true;
        NoNewPrivileges = true;

        # mbd needs write access to /run/stereos for the unix socket
        # and secrets, plus mount points under /workspace and similar
        ReadWritePaths = [ "/run/stereos" "/workspace" ];
      };
    };
  };
}
