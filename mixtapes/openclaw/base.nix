# mixtapes/openclaw/base.nix
#
# OpenClaw mixtape — self-hosted, open-source personal AI assistant.
#
# OpenClaw routes messages from 15+ chat platforms through a local Gateway
# to any LLM backend, executing real-world tasks autonomously.  The entire
# runtime is a single long-lived Node.js process (the Gateway) listening on
# ws://127.0.0.1:18789 by default.
#
# Package: from github:openclaw/nix-openclaw flake (overlay: pkgs.openclaw-gateway)
# Binary:  openclaw (Gateway daemon + CLI)
# Service: openclaw-gateway.service (systemd, runs as dedicated 'openclaw' user)
#
# Required environment variables at runtime:
#   ANTHROPIC_API_KEY or OPENAI_API_KEY (depending on configured provider)
#   Plus channel tokens as needed (TELEGRAM_BOT_TOKEN, DISCORD_BOT_TOKEN, etc.)
#
# Secrets are injected at boot by stereosd into /run/stereos/secrets/ and
# loaded via the systemd EnvironmentFile mechanism.

{ config, lib, pkgs, ... }:

{
  imports = [
    ./service.nix
  ];

  # Add the openclaw CLI to the agent's restricted PATH so the agent can
  # interact with the running Gateway over WebSocket.
  stereos.agent.extraPackages = [ pkgs.openclaw-gateway ];

  # Also make it available system-wide (for admin use / debugging)
  environment.systemPackages = [ pkgs.openclaw-gateway ];

  # Disable auto-update and self-mutation flows — Nix manages the package.
  # When this is set, openclaw skips update checks and shows Nix-specific
  # remediation messages in the Control UI.
  environment.variables.OPENCLAW_NIX_MODE = "1";
}
