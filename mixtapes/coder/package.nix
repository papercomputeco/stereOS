# mixtapes/coder/package.nix
#
# Coder mixtape — all AI coding agents.
#
# Includes:
#   - Claude Code (Anthropic) — pkgs.claude-code
#   - Codex (OpenAI)          — pkgs.codex
#   - Gemini CLI (Google)     — pkgs.gemini-cli
#   - OpenCode                — pkgs.opencode
#   - pi                      — lib/pi-bin.nix (not in nixpkgs)
#
# Required environment variables at runtime (depending on provider):
#   ANTHROPIC_API_KEY, OPENAI_API_KEY, GEMINI_API_KEY / GOOGLE_API_KEY
#
# pi resolves credentials through its own model registry, so it reads whichever
# provider key matches the model it is asked for.

{ config, lib, pkgs, pkgs-unstable, ... }:

let
  # pi is not packaged in nixpkgs. Built from the published npm tarball,
  # following the same local-derivation pattern as lib/paper-bin.nix.
  pi = import ../../lib/pi-bin.nix { inherit pkgs; };

  agents = [
    pkgs-unstable.claude-code
    pkgs-unstable.codex
    pkgs-unstable.gemini-cli
    pkgs-unstable.opencode
    pi
  ];
in
{
  # Allow unfree packages required by this mixtape
  nixpkgs.config.allowUnfreePredicate = pkg:
    builtins.elem (lib.getName pkg) [
      "claude-code"
    ];

  # Add all coding agents to the agent's restricted PATH.
  # This list also feeds mkSandboxManifest (the gVisor closure manifest) and
  # flake/images.nix's Lambda MicroVM bundle, so both pick pi up for free.
  stereos.agent.extraPackages = agents;

  # Also make them available system-wide (for admin use)
  environment.systemPackages = agents;

  # Claude Code: disable auto-updater (belt-and-suspenders; Nix package sets this too)
  environment.variables.DISABLE_AUTOUPDATER = "1";

  # OpenCode: seed a default configuration file for the agent user
  environment.etc."skel/.config/opencode/config.json".text = builtins.toJSON {
    "$schema" = "https://opencode.ai/config.json";
  };
}
