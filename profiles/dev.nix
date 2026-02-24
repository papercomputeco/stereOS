# profiles/dev.nix
#
# Dev-only profile: SSH keys built in, debug tools, etc.
#
# POC ONLY — will be replaced by agentd + vsock secret injection.
# In production, keys are injected at VM launch time by stereosd.
#
# This profile reads a developer's SSH public key from a well-known
# path and bakes it into the image for both admin and agent users.
# If the file is missing, no SSH keys are baked in (the build does
# not fail).
#
# Setup:
#   mkdir -p ~/.config/stereos
#   cp ~/.ssh/id_ed25519.pub ~/.config/stereos/ssh-key.pub
#
# Usage:
#   Include this profile in mkMixtape's extraModules for dev builds.
#   Production builds should NOT include this profile.

{ config, lib, pkgs, ... }:

let
  sshKeyPath = builtins.getEnv "HOME" + "/.config/stereos/ssh-key.pub";
  sshKeys =
    let
      exists = builtins.pathExists sshKeyPath;
    in
      if exists then
        let raw = builtins.readFile sshKeyPath;
        in [ (lib.removeSuffix "\n" raw) ]
      else
        [];
in
{
  stereos.ssh.authorizedKeys = sshKeys;
}
