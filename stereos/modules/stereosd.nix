# stereos/modules/stereosd.nix
#
# StereOS-specific overrides for the stereosd service.
#
# The base service definition and `services.stereosd.*` options come from
# the external stereosd flake (stereosd.nixosModules.default).  This
# module enables the service and layers on StereOS-specific configuration:
#
#   - tmpfiles rules for /run/stereos (unix socket + secrets)
#   - PATH additions (util-linux for mount/umount, coreutils)
#   - Security hardening appropriate for a VM control-plane daemon
#
# stereosd provides:
#   - Lifecycle signaling over virtio-vsock (CID:3, port 1024)
#   - Shared directory mounting (virtio-fs / 9p)
#   - Secret injection to tmpfs-backed paths
#   - Graceful shutdown coordination
#   - Unix socket for agentd communication (/run/stereos/stereosd.sock)
#
# agentd depends on stereosd (After=stereosd.service).

{ config, lib, pkgs, ... }:

{
  config = {
    # Enable the stereosd service from the external flake module.
    services.stereosd.enable = true;

    # -- Runtime directories (tmpfs-backed) ----------------------------------
    systemd.tmpfiles.rules = [
      "d /run/stereos 0755 root root -"
      "d /run/stereos/secrets 0700 root root -"
    ];

    # -- StereOS-specific service overrides ----------------------------------
    systemd.services.stereosd = {
      # mount and umount are needed for shared directory mounting
      path = [ pkgs.util-linux pkgs.coreutils ];

      serviceConfig = {
        # Override: stereosd needs to run as root in StereOS because it must:
        #   - Bind to AF_VSOCK sockets
        #   - Mount/unmount shared filesystems (CAP_SYS_ADMIN)
        #   - Write secrets to /run/stereos/secrets (root-owned)
        #   - Initiate system poweroff during shutdown
        DynamicUser = lib.mkForce false;

        Restart = lib.mkForce "on-failure";
        RestartSec = 5;

        # Security hardening (what we *can* lock down while still
        # allowing mount operations and vsock)
        ProtectHome = true;
        PrivateTmp = true;
        NoNewPrivileges = true;

        # stereosd needs write access to /run/stereos for the unix socket
        # and secrets, plus mount points under /workspace and similar
        ReadWritePaths = [ "/run/stereos" "/workspace" ];
      };
    };
  };
}
