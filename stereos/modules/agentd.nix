# stereos/modules/agentd.nix
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

    # -- StereOS-specific service overrides ----------------------------------
    systemd.services.agentd = {
      # agentd starts AFTER stereosd — it depends on stereosd for secrets
      # and the control plane unix socket.
      after = [ "stereosd.service" ];
      requires = [ "stereosd.service" ];

      serviceConfig = {
        # Override: disable DynamicUser in favour of StereOS's own user model
        DynamicUser = lib.mkForce false;

        Restart = lib.mkForce "on-failure";
        RestartSec = 5;

        # Security hardening
        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;
        NoNewPrivileges = true;

        # agentd needs read access to secrets and write access to /workspace
        # for agent session management
        ReadWritePaths = [ "/run/stereos" "/workspace" ];
      };
    };
  };
}
