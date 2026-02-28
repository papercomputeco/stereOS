# mixtapes/openclaw/service.nix
#
# OpenClaw Gateway systemd service for stereOS.
#
# Runs the Gateway daemon as a dedicated 'openclaw' system user with state
# in /var/lib/openclaw.  The agent user interacts with the Gateway over its
# WebSocket API (ws://127.0.0.1:18789) or via the `openclaw` CLI.
#
# This module uses the NixOS service options from the nix-openclaw flake
# (services.openclaw-gateway.*) which handles:
#   - System user/group creation
#   - State directory tmpfiles rules
#   - Config file generation from Nix attrsets
#   - systemd service definition with logging
#
# Secret injection:
#   API keys and channel tokens are injected at boot by stereosd into
#   /run/stereos/secrets/.  The service loads them via EnvironmentFile.
#   Example secrets file (/run/stereos/secrets/openclaw.env):
#     ANTHROPIC_API_KEY=sk-ant-...
#     TELEGRAM_BOT_TOKEN=123456:ABC-...
#     OPENCLAW_GATEWAY_TOKEN=<gateway-auth-token>

{ config, lib, pkgs, ... }:

{
  services.openclaw-gateway = {
    enable = true;
    port = 18789;

    user = "openclaw";
    group = "openclaw";
    stateDir = "/var/lib/openclaw";

    # Gateway configuration — generates /etc/openclaw/openclaw.json
    config = {
      gateway = {
        mode = "local";
        bind = "loopback";
      };

      # Memory uses SQLite with FTS5 + sqlite-vec for search.
      # Embedding model auto-selects: local GGUF -> OpenAI -> Gemini -> BM25.
      # No additional config needed — defaults are sensible.
    };

    # Load secrets from stereosd-injected environment file.
    # The leading '-' tells systemd to silently skip if the file is absent
    # (e.g. during first boot before stereosd has injected secrets).
    environmentFiles = [
      "-/run/stereos/secrets/openclaw.env"
    ];

    # Extra packages available to the Gateway process at runtime
    servicePath = with pkgs; [
      git
      curl
    ];
  };

  # -- Service ordering: start after stereosd has injected secrets -----------
  systemd.services.openclaw-gateway = {
    after = [ "stereosd.service" ];
    wants = [ "stereosd.service" ];
  };

  # -- Firewall: Gateway is loopback-only, no ports to open -----------------
  # The WebSocket endpoint (127.0.0.1:18789) is only reachable from within
  # the VM.  If remote access is needed in the future, a reverse proxy
  # (Caddy/nginx) with TLS should front the Gateway.
}
