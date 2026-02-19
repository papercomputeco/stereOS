# modules/users/agent.nix
#
# Creates the agent user with appropriate user level isolation.
# The agent user can run programs from /nix/store (e.g., opencode, git)
# but CANNOT invoke nix, nixos-rebuild, nix-env, or any nix tooling.
#
# Filesystem layout:
#   /workspace  — agent's working directory (owned by agent, writable)
#   /tmp, /run  — tmpfs (ephemeral, never persisted to disk)
#
# Also declares the shared stereos.ssh and stereos.agent options used
# by both the agent and admin user modules.

{ config, lib, pkgs, ... }:

let
  # -- Curated set of binaries the agent can access -------------------------
  # This is the ONLY thing on the agent's PATH.
  # Add packages here as needed — but never add nix tools.
  agentPackages = with pkgs; [
    # Core POSIX utilities
    coreutils
    gnugrep
    gnused
    gawk
    findutils
    diffutils
    less
    which

    # Development essentials
    git
    curl
    wget
    jq
    ripgrep
    tree
    file
    unzip
    gnumake
    gcc

    # Editors
    vim

    # Terminal multiplexer
    tmux

    # Process inspection (safe subset)
    htop
    procps  # ps, top, etc.

    # Networking
    openssh  # ssh client for agent-to-agent or git-over-ssh
    cacert   # TLS certificates
  ];

  # Build a single directory containing symlinks to all approved binaries
  agentEnv = pkgs.buildEnv {
    name = "stereos-agent-env";
    paths = agentPackages;
    pathsToLink = [ "/bin" "/lib" "/share" "/etc" ];
  };

  # Build secondary env from feature module packages
  extraEnv = pkgs.buildEnv {
    name = "stereos-agent-extra-env";
    paths = config.stereos.agent.extraPackages;
    pathsToLink = [ "/bin" ];
  };

  # Restricted shell: sets PATH to only the curated environment,
  # unsets all Nix-related variables, then execs bash.
  agentShell = pkgs.writeShellScriptBin "stereos-agent-shell" ''
    # Set PATH to only approved binaries + feature tool binaries
    export PATH="${agentEnv}/bin:${extraEnv}/bin"

    # Ensure TLS certificates work
    export SSL_CERT_FILE="${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"
    export NIX_SSL_CERT_FILE="$SSL_CERT_FILE"

    # Nuke all Nix-related environment variables
    unset NIX_PATH NIX_REMOTE NIX_CONF_DIR NIX_USER_CONF_FILES
    unset NIX_PROFILES NIX_STORE

    # Default working directory to /workspace
    if [ -d /workspace ]; then
      cd /workspace
    fi

    # Exec into a clean bash session
    exec ${pkgs.bash}/bin/bash --login "$@"
  '';

in
{
  # -- Options ---------------------------------------------------------------
  options.stereos = {
    ssh.authorizedKeys = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      description = "SSH public keys authorized for both admin and agent users.";
    };

    agent.extraPackages = lib.mkOption {
      type = lib.types.listOf lib.types.package;
      default = [];
      description = ''
        Additional packages to make available on the agent's PATH.
        Feature modules (opencode.nix, claude-code.nix, etc.) append to this.
      '';
    };
  };

  config = {
    # Register the custom shell so NixOS accepts it as a valid login shell
    environment.shells = [ "${agentShell}/bin/stereos-agent-shell" ];

    # -- Agent user (restricted) ---------------------------------------------
    users.users.agent = {
      isNormalUser = true;
      home = "/workspace";
      createHome = false;  # We create /workspace via systemd-tmpfiles
      shell = "${agentShell}/bin/stereos-agent-shell";
      extraGroups = [];  # No wheel, no special groups
      openssh.authorizedKeys.keys = config.stereos.ssh.authorizedKeys;
    };

    # -- /workspace: the agent's writable working directory ------------------
    # Created at boot, owned by the agent user.  In production, this may
    # be a mount point for a virtio-fs or 9p shared directory from the
    # host (configured via jcard.toml [[shared]] entries).
    systemd.tmpfiles.rules = [
      "d /workspace 0755 agent agent -"
    ];

    # -- Layer 3: Explicit sudo denial ---------------------------------------
    security.sudo = {
      enable = true;
      extraConfig = ''
        # Explicitly deny ALL sudo access for the agent user.
        # This must come BEFORE any permissive rules.
        agent ALL=(ALL:ALL) !ALL
      '';
    };
  };
}
