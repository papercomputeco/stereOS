# modules/services/agentd.nix
#
# stereOS-specific overrides for the agentd service.
#
# The base service definition and `services.agentd.*` options come from
# the external agentd flake (agentd.nixosModules.default).  This module
# enables the service and layers on stereOS-specific configuration:
#
#   - Service ordering: agentd starts AFTER and REQUIRES stereosd
#   - Security hardening for the stereOS VM environment
#   - gVisor (runsc) sandbox support
#
# agentd manages agent processes via either:
#   - tmux sessions for "native" agents (admin introspects via tmux attach)
#   - gVisor sandboxes for "sandboxed" agents (admin introspects via runsc exec)
#
# Depends on stereosd for:
#   - Unix socket communication (/run/stereos/stereosd.sock)
#   - Secret injection (/run/stereos/secrets/)

{ config, lib, pkgs, ... }:

{
  config = {
    # Enable the agentd service from the external flake module.
    services.agentd.enable = true;

    # -- Runtime directories -------------------------------------------------
    # /run/agentd:            tmux socket (owned by agent for native mode)
    # /run/agentd/sandboxes:  OCI bundles for gVisor sandboxes
    # /run/agentd/runsc-state: runsc container state
    systemd.tmpfiles.rules = [
      "d /run/agentd 0750 agent admin -"
      "d /run/agentd/sandboxes 0750 root admin -"
      "d /run/agentd/runsc-state 0750 root admin -"
    ];

    # -- stereOS-specific service overrides ----------------------------------
    systemd.services.agentd = {
      # agentd starts AFTER stereosd — it depends on stereosd for secrets
      # and the control plane unix socket.
      after = [ "stereosd.service" ];
      requires = [ "stereosd.service" ];

      # Add gVisor (runsc) and nix-store to the service PATH.
      # runsc: required for sandboxed agent mode.
      # nix: provides resolving nix packages for "extra_packages"
      path = [ pkgs.gvisor pkgs.nix ];

      serviceConfig = {
        # Override: disable DynamicUser in favour of stereOS's own user model.
        # agentd runs as root so it can manage tmux sessions for the agent
        # user (native mode) and runsc containers (sandboxed mode).
        DynamicUser = lib.mkForce false;

        Restart = lib.mkForce "on-failure";
        RestartSec = 5;
      };
    };
  };
}
