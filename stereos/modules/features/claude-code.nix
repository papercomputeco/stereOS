# stereos/modules/features/claude-code.nix
#
# Adds Claude Code (Anthropic's CLI coding agent) to the stereOS image.
#
# Package: pkgs.claude-code (nixpkgs-unstable)
# Binary: claude
#
# Required environment variable at runtime:
#   ANTHROPIC_API_KEY
#
{ config, lib, pkgs, ... }:

{
  # Add claude-code to the agent's restricted PATH
  stereos.agent.extraPackages = [ pkgs.claude-code ];

  # Also make it available system-wide (for admin use)
  environment.systemPackages = [ pkgs.claude-code ];

  # Disable auto-update (already set by the Nix package, but belt-and-suspenders)
  environment.variables.DISABLE_AUTOUPDATER = "1";
}
