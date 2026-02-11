# stereos/modules/agentd.nix
#
# Systemd unit for agentd (agent daemon) — starts, supervises, and stops
# configured agent harnesses (Claude Code, OpenCode, etc.).
#
# agentd manages tmux sessions for the agent user, allowing admin to
# "tmux attach [session]" to introspect running agents.
#
# Depends on mbd for:
#   - Unix socket communication (/run/stereos/mbd.sock)
#   - Secret injection (/run/stereos/secrets/)

{ config, lib, pkgs, ... }:

let
  # Build the agentd binary from the Go source in this repo.
  agentdBin = pkgs.buildGoModule {
    pname = "agentd";
    version = "0.1.0";
    src = ../../.;
    subPackages = [ "cmd/agentd" ];
    vendorHash = null;
  };
in
{
  config = {
    # -- agentd systemd service ----------------------------------------------
    systemd.services.agentd = {
      description = "StereOS Agent Daemon";
      wantedBy = [ "multi-user.target" ];

      # agentd starts AFTER mbd — it depends on mbd for secrets and
      # the control plane unix socket.
      after = [ "mbd.service" ];
      requires = [ "mbd.service" ];

      serviceConfig = {
        Type = "simple";
        ExecStart = "${agentdBin}/bin/agentd";
        Restart = "on-failure";
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
