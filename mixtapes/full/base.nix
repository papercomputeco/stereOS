# mixtapes/full/base.nix
#
# Full mixtape — includes all available AI coding agents.
# Imports each individual mixtape's base.nix to compose them together.

{ config, lib, pkgs, ... }:

{
  imports = [
    ../opencode/base.nix
    ../claude-code/base.nix
    ../gemini-cli/base.nix
  ];
}
