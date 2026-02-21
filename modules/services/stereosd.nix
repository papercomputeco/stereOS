# modules/services/stereosd.nix
#
# stereOS-specific overrides for the stereosd service.
#
# The base service definition and `services.stereosd.*` options come from
# the external stereosd flake (stereosd.nixosModules.default).  This
# module enables the service and layers on stereOS-specific configuration:
#
#   - tmpfiles rules for /run/stereos (unix socket + secrets)
#   - PATH additions (util-linux for mount/umount, coreutils)
#   - Firewall opening for TCP control plane fallback
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
    # /run/stereos is group-owned by admin so the admin user can access
    # daemon sockets (stereosd.sock, agentd.sock, agentd-tmux.sock).
    # Secrets stay root-only — admin cannot read injected secrets.
    systemd.tmpfiles.rules = [
      "d /run/stereos 0750 root admin -"
      "d /run/stereos/secrets 0700 root root -"
    ];

    # -- Firewall: allow TCP 1024 for the control plane TCP fallback ---------
    # When AF_VSOCK is unavailable (macOS/HVF + QEMU user-mode networking),
    # stereosd listens on TCP port 1024 and the host reaches it via SLIRP
    # port forwarding.
    networking.firewall.allowedTCPPorts = [ 1024 ];

    # -- stereOS-specific service overrides ----------------------------------
    systemd.services.stereosd = {
      # mount and umount are needed for shared directory mounting
      path = [ pkgs.util-linux pkgs.coreutils ];

      # Ensure kernel modules (including vmw_vsock_virtio_transport) are
      # loaded before stereosd starts. Without this, stereosd's
      # VsockTransportAvailable() check races against module loading and
      # may fall back to TCP even when a vsock transport is present.
      after = [ "systemd-modules-load.service" ];

      serviceConfig = {
        # Override: stereosd needs to run as root in stereOS because it must:
        #   - Bind to AF_VSOCK sockets
        #   - Mount/unmount shared filesystems (CAP_SYS_ADMIN)
        #   - Write secrets to /run/stereos/secrets (root-owned)
        #   - Initiate system poweroff during shutdown
        DynamicUser = lib.mkForce false;

        Restart = lib.mkForce "on-failure";
        RestartSec = 5;
      };
    };
  };
}
