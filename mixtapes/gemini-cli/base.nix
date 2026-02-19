# mixtapes/gemini-cli/base.nix
#
# Gemini CLI mixtape — includes Google's AI coding agent.
#
# Package: pkgs.gemini-cli (nixpkgs-unstable)
# Binary: gemini
#
# Required environment variable at runtime:
#   GEMINI_API_KEY or GOOGLE_API_KEY

{ config, lib, pkgs, ... }:

{
  # Add gemini-cli to the agent's restricted PATH
  stereos.agent.extraPackages = [ pkgs.gemini-cli ];

  # Also make it available system-wide (for admin use)
  environment.systemPackages = [ pkgs.gemini-cli ];
}
