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

{ config, lib, pkgs, ... }:

{
  # The SSH key injection is handled in lib/default.nix (mkMixtape)
  # which sets stereos.ssh.authorizedKeys. This profile exists as
  # the canonical place to add dev-only configuration in the future
  # (e.g., debug tools, verbose logging, etc.)
}
