# modules/default.nix
#
# Aggregator — imports all stereOS NixOS sub-modules.
# Consumers (mixtapes, profiles) import this single path to get everything.

{
  imports = [
    ./base.nix
    ./boot.nix
    ./services/stereosd.nix
    ./services/agentd.nix
    ./rpi-options.nix
    ./rpi-radios.nix
    ./users/agent.nix
    ./users/admin.nix
  ];
}
