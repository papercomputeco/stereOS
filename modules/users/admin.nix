# modules/users/admin.nix
#
# Creates the admin user with full system access.
# The admin user has wheel (sudo) and admin group membership.
#
# The admin group controls access to stereosd/agentd sockets and tmux
# sessions.  Privilege hierarchy: root > admin > agent.

{ config, lib, pkgs, ... }:

{
  config = {
    # -- Admin group ---------------------------------------------------------
    users.groups.admin = {};

    # -- Admin user (full access) --------------------------------------------
    users.users.admin = {
      isNormalUser = true;
      extraGroups = [ "wheel" "admin" ];  # wheel = sudo, admin = socket access
      openssh.authorizedKeys.keys = config.stereos.ssh.authorizedKeys;
    };

    # -- Sudo configuration --------------------------------------------------
    security.sudo = {
      enable = true;
      wheelNeedsPassword = false;  # Admin gets passwordless sudo
    };
  };
}
