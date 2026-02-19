# mixtapes/opencode/base.nix
#
# OpenCode mixtape — includes the OpenCode terminal AI coding agent.
#
# OpenCode: https://opencode.ai/
# Package: pkgs.opencode (nixpkgs-unstable)
# Binary: opencode
# Config: ~/.config/opencode/config.json
#
# Required environment variable at runtime:
#   ANTHROPIC_API_KEY or OPENAI_API_KEY (depending on provider)

{ config, lib, pkgs, ... }:

{
  # Add opencode to the agent's restricted PATH
  stereos.agent.extraPackages = [ pkgs.opencode ];

  # Also make it available system-wide (for admin use)
  environment.systemPackages = [ pkgs.opencode ];

  # Seed a default configuration file for the agent user
  environment.etc."skel/.config/opencode/config.json".text = builtins.toJSON {
    "$schema" = "https://opencode.ai/config.json";
  };
}
