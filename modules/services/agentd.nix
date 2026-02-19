# modules/services/agentd.nix
#
# StereOS-specific overrides for the agentd service.
#
# The base service definition and `services.agentd.*` options come from
# the external agentd flake (agentd.nixosModules.default).  This module
# enables the service and layers on StereOS-specific configuration:
#
#   - Service ordering: agentd starts AFTER and REQUIRES stereosd
#   - Security hardening for the StereOS VM environment
#
# agentd manages tmux sessions for the agent user, allowing admin to
# "tmux attach [session]" to introspect running agents.
#
# Depends on stereosd for:
#   - Unix socket communication (/run/stereos/stereosd.sock)
#   - Secret injection (/run/stereos/secrets/)

{ config, lib, pkgs, ... }:

{
  config = {
    # Enable the agentd service from the external flake module.
    services.agentd.enable = true;

    # -- Runtime directory for agentd tmux socket ----------------------------
    # Separate from /run/stereos/ (root:admin) so the agent user can create
    # and own the tmux socket. admin group can traverse to attach sessions.
    systemd.tmpfiles.rules = [
      "d /run/agentd 0750 agent admin -"
    ];

    # -- StereOS-specific service overrides ----------------------------------
    systemd.services.agentd = {
      # agentd starts AFTER stereosd — it depends on stereosd for secrets
      # and the control plane unix socket.
      after = [ "stereosd.service" ];
      requires = [ "stereosd.service" ];

      serviceConfig = {
        # Override: disable DynamicUser in favour of StereOS's own user model.
        # agentd runs as root so it can manage tmux sessions for the agent user.
        DynamicUser = lib.mkForce false;

        Restart = lib.mkForce "on-failure";
        RestartSec = 5;
      };
    };
  };
}
