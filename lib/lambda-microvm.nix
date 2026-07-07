{ inputs }:

{
  mkLambdaMicrovmSource =
    { pkgs
    , name
    , version ? "0.0.0-dev"
    , agentPackages ? []
    , startPaperd ? false
    , warmAgent ? false
    }:
    let
      paperdEnv = if startPaperd then "ENV STEREOS_START_PAPERD=1\n" else "";

      # When enabled, the lifecycle runs this during the AWS `ready` build hook
      # (as the agent user), so its disk writes land in the image snapshot and
      # every launched MicroVM starts warm. It must not create per-VM-unique or
      # secret state, since the snapshot is shared across all MicroVMs.
      readyCommandEnv =
        if warmAgent then "ENV STEREOS_READY_COMMAND=/usr/local/bin/stereos-warm-agent\n" else "";

      # Pre-populates Claude Code's ~200MB native build (no auth, no `paper`),
      # then pre-seeds onboarding so the first interactive run skips the theme
      # prompt and strips the per-machine ids `claude install` writes so they
      # regenerate per-VM. Failures are non-fatal: a build without network just
      # ships unwarmed rather than failing image creation.
      warmAgentScript = pkgs.writeText "stereos-warm-agent" ''
        #!/bin/sh
        set -u
        command -v claude >/dev/null 2>&1 || { echo "claude not present; skipping warm-up"; exit 0; }
        claude install || echo "claude install failed (no build-time network?); continuing"
        cfg="$HOME/.claude.json"
        if [ -f "$cfg" ] && command -v jq >/dev/null 2>&1; then
          tmp="$(mktemp)"
          jq 'del(.machineID, .userID, .firstStartTime) + {theme: "dark", hasCompletedOnboarding: true}' "$cfg" > "$tmp" \
            && mv "$tmp" "$cfg" || rm -f "$tmp"
        fi
        exit 0
      '';

      # Built from source by Nix using the pinned nixpkgs Rust toolchain (same
      # model as buildGoModule for agentd/stereosd). images.nix builds this
      # natively per target system, so no cross-compilation is involved.
      # doCheck is off because the unit tests exec /bin/bash, which is absent
      # from the build sandbox; `cargo test` runs in the devshell and CI.
      lifecycle = pkgs.rustPlatform.buildRustPackage {
        pname = "lambda-microvm-lifecycle";
        inherit version;
        src = ../lambda-microvm/lifecycle;
        cargoLock.lockFile = ../lambda-microvm/lifecycle/Cargo.lock;
        doCheck = false;
      };

      shellCompat = pkgs.runCommand "stereos-lambda-microvm-shell-compat" {} ''
        mkdir -p "$out/bin"
        ln -s ${pkgs.bash}/bin/bash "$out/bin/sh"
      '';

      agentEnv = pkgs.buildEnv {
        name = "stereos-lambda-microvm-env";
        paths = with pkgs; [
          shellCompat
          bash
          cacert
          coreutils
          curl
          findutils
          git
          gnugrep
          gnused
          jq
          less
          procps
          ripgrep
          openssh
          tree
          which
        ] ++ agentPackages ++ [
          lifecycle
        ];
        pathsToLink = [ "/bin" "/etc" "/lib" "/share" ];
      };

      closure = pkgs.closureInfo { rootPaths = [ agentEnv ]; };

      rootfs = pkgs.runCommand "${name}-lambda-microvm-rootfs" {
        nativeBuildInputs = [ pkgs.gnutar pkgs.coreutils ];
      } ''
        set -eu

        root="$PWD/rootfs"
        mkdir -p "$root"/{etc,root,tmp,run,run/sshd,usr/bin,usr/local/bin,usr/sbin,var/empty}

        # Pre-create the agent home and its XDG tree so the image is ready to go
        # without any runtime mkdir/chown. paperd runs as uid/gid 1000 and writes
        # into these at runtime; ownership is stamped into the tar below.
        mkdir -p \
          "$root/home/agent/workspace" \
          "$root/home/agent/.config" \
          "$root/home/agent/.local/state/paper"

        while IFS= read -r path; do
          mkdir -p "$root$(dirname "$path")"
          cp -a "$path" "$root$path"
        done < ${closure}/store-paths

        ln -s ${agentEnv}/bin "$root/bin"

        cat > "$root/etc/passwd" <<'EOF'
        root:x:0:0:root:/root:/bin/bash
        sshd:x:74:74:SSH privilege separation user:/var/empty:/bin/false
        agent:x:1000:1000:stereOS agent:/home/agent:/bin/bash
        EOF
        cat > "$root/etc/group" <<'EOF'
        root:x:0:
        sshd:x:74:
        agent:x:1000:
        EOF
        cat > "$root/etc/nsswitch.conf" <<'EOF'
        passwd: files
        group: files
        hosts: files dns
        EOF

        chmod 1777 "$root/tmp"
        chmod 0700 "$root/root"
        chmod 0755 "$root/var/empty"
        chmod -R 0755 "$root/home/agent"

        mkdir -p "$root/etc/ssh"
        ${pkgs.openssh}/bin/ssh-keygen -A -f "$root"
        sed -ri 's/^#?PermitRootLogin.*/PermitRootLogin prohibit-password/' "$root/etc/ssh/sshd_config" 2>/dev/null || true
        cat >> "$root/etc/ssh/sshd_config" <<'EOF'
        PermitRootLogin prohibit-password
        PasswordAuthentication no
        ChallengeResponseAuthentication no
        UsePAM no
        PidFile /run/sshd/sshd.pid
        EOF

        ln -s /bin/sshd "$root/usr/sbin/sshd"
        ln -s /bin/echo "$root/usr/bin/echo"
        ln -s /bin/stty "$root/usr/bin/stty"

        ${pkgs.lib.optionalString warmAgent ''
          cp ${warmAgentScript} "$root/usr/local/bin/stereos-warm-agent"
          chmod 0755 "$root/usr/local/bin/stereos-warm-agent"
        ''}

        # Build the tar in two passes so the agent home subtree ships owned by
        # uid/gid 1000 while everything else stays root-owned. tar applies the
        # --owner/--group overrides regardless of the build user, so no
        # privileged chown is needed and the image needs no runtime permission
        # fixups.
        tar --sort=name --numeric-owner --owner=0 --group=0 \
          --exclude=./home/agent \
          -C "$root" -cf "$out" .
        tar --sort=name --numeric-owner --owner=1000 --group=1000 \
          -C "$root" --append -f "$out" \
          ./home/agent
      '';
    in
      pkgs.runCommand "${name}-lambda-microvm-source" {
        inherit version;
        nativeBuildInputs = [ pkgs.zip ];
      } ''
        set -eu

        mkdir -p "$out/src"
        cp ${rootfs} "$out/src/stereos-rootfs.tar"
        cp ${../lambda-microvm/README.md} "$out/src/README.md"

        cat > "$out/src/Dockerfile" <<EOF
        FROM scratch
        ADD stereos-rootfs.tar /
        ENV PATH=/bin \\
            HOME=/home/agent \\
            SSL_CERT_FILE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt \\
            NIX_SSL_CERT_FILE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt \\
            STEREOS_MIXTAPE=${name} \\
            STEREOS_VERSION=${version}
        ${paperdEnv}${readyCommandEnv}
        WORKDIR /home/agent/workspace
        EXPOSE 9000
        ENTRYPOINT ["/bin/lambda-microvm-lifecycle"]
        EOF

        (cd "$out/src" && zip -qr "$out/${name}-lambda-microvm-source.zip" .)
      '';
}
