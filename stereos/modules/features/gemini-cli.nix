# stereos/modules/features/gemini-cli.nix
#
# Adds Gemini CLI (Google's AI coding agent) to the stereOS image.
#
# Package: pkgs.gemini-cli (nixpkgs-unstable)
# Binary: gemini
#
# Required environment variable at runtime:
#   GEMINI_API_KEY or GOOGLE_API_KEY
#
{ config, lib, pkgs, ... }:

{
  # Add gemini-cli to the agent's restricted PATH
  stereos.agent.extraPackages = [ pkgs.gemini-cli ];

  # Also make it available system-wide (for admin use)
  environment.systemPackages = [ pkgs.gemini-cli ];
}
