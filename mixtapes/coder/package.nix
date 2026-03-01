# mixtapes/coder/package.nix
#
# Coder mixtape — all AI coding agents.
#
# Includes:
#   - Claude Code (Anthropic) — pkgs.claude-code
#   - Codex (OpenAI)          — pkgs.codex
#   - Gemini CLI (Google)     — pkgs.gemini-cli
#   - OpenCode                — pkgs.opencode
#
# Required environment variables at runtime (depending on provider):
#   ANTHROPIC_API_KEY, OPENAI_API_KEY, GEMINI_API_KEY / GOOGLE_API_KEY

{ config, lib, pkgs, ... }:

{
  # Allow unfree packages required by this mixtape
  nixpkgs.config.allowUnfreePredicate = pkg:
    builtins.elem (lib.getName pkg) [
      "claude-code"
    ];

  # Add all coding agents to the agent's restricted PATH
  stereos.agent.extraPackages = [
    pkgs.claude-code
    pkgs.codex
    pkgs.gemini-cli
    pkgs.opencode
  ];

  # Also make them available system-wide (for admin use)
  environment.systemPackages = [
    pkgs.claude-code
    pkgs.codex
    pkgs.gemini-cli
    pkgs.opencode
  ];

  # Claude Code: disable auto-updater (belt-and-suspenders; Nix package sets this too)
  environment.variables.DISABLE_AUTOUPDATER = "1";

  # OpenCode: seed a default configuration file for the agent user
  environment.etc."skel/.config/opencode/config.json".text = builtins.toJSON {
    "$schema" = "https://opencode.ai/config.json";
  };
}
