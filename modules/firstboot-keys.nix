# modules/firstboot-keys.nix
#
# First-boot SSH key drop-in for Raspberry Pi images.
#
# The RPi has no vsock, so the masterblaster-over-vsock key injection used
# in the VM flow doesn't apply. Instead we read a plain text file from the
# FAT /boot/firmware partition (visible on macOS/Windows/Linux the moment
# you plug the SD card in) and append the keys into admin's
# authorized_keys before sshd starts.
#
# This service is intentionally forgiving:
#   - missing file   → skip, exit 0
#   - empty file     → skip, exit 0
#   - no valid keys  → skip, exit 0
#   - malformed line → ignored (valid keys still imported)
#
# It runs on every boot (not just the first) so users can add more keys
# later by editing the file and rebooting.

{ config, lib, pkgs, ... }:

{
  systemd.services.stereos-firstboot-keys = {
    description = "Import SSH authorized_keys from FIRMWARE partition";
    wantedBy = [ "multi-user.target" ];
    before = [ "sshd.service" ];
    after = [ "local-fs.target" ];
    # RequiresMountsFor pulls in boot-firmware.mount on demand and orders
    # our service after it. local-fs.target does NOT auto-pull every fstab
    # entry on NixOS+systemd-initrd, so declaring the dependency here is
    # what guarantees the FAT partition is mounted when the script runs.
    unitConfig.RequiresMountsFor = [ "/boot/firmware" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      set -u
      src=/boot/firmware/ssh_authorized_keys.txt
      dest=/home/admin/.ssh/authorized_keys

      if [ ! -f "$src" ]; then
        echo "firstboot-keys: $src not present, skipping"
        exit 0
      fi

      # Extract plausible key lines: anything starting with a supported
      # OpenSSH key-type prefix. Blank lines and comments drop out.
      keys=$(${pkgs.gnugrep}/bin/grep -E \
        '^[[:space:]]*(ssh-ed25519|ssh-rsa|ssh-dss|ecdsa-sha2-|sk-ssh-|sk-ecdsa-)' \
        "$src" || true)
      if [ -z "$keys" ]; then
        echo "firstboot-keys: no valid keys in $src, skipping"
        exit 0
      fi

      install -d -m 0700 -o admin -g users /home/admin/.ssh
      touch "$dest"
      chown admin:users "$dest"
      chmod 0600 "$dest"

      added=0
      while IFS= read -r line; do
        [ -z "$line" ] && continue
        if ! ${pkgs.gnugrep}/bin/grep -qxF "$line" "$dest"; then
          printf '%s\n' "$line" >> "$dest"
          added=$((added + 1))
        fi
      done <<< "$keys"

      echo "firstboot-keys: imported $added new key(s) from $src"
    '';
  };
}
