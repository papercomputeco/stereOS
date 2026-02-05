# StereOS

StereOS is a Linux based operating system purpose built for AI agents.

---

## Quickstart

1. Enable the development Flake via `direnv allow`
2. Copy your `./ssh-key.pub` to bake into the OS
3. Build the QCOW2 image for a mixtape:

```sh
nix build .#packages.aarch64-linux.opencode-mixtape
```

4. Run the image with QEMU (warning: MacOS requires the QEUM UEFI firmware for non BIOS boot)

```sh
qemu-system-aarch64 \
  -drive if=virtio,format=qcow2,file="./result/nixos.qcow2" \
  # ... etc. etc.
```

5. SSH to the VM:

```sh
ssh -p 2222 admin@localhost
```
