# stereOS

stereOS is a Linux based operating system purpose built for AI agents.

---

## Quickstart

1. Enable the development Flake via `direnv allow`
2. Copy your SSH key to `~/.config/ssh-key.pub` to bake into the OS for testing
3. Build a mixtape image:

```sh
make build-qcow2
```

4. Run the image with QEMU:

```sh
make run
```

5. SSH to the VM:

```sh
make ssh-admin
```

## Building Distributions

To build a complete distribution with all formats and a `mixtape.toml` manifest:

```sh
make dist
```

This produces a `result/` directory containing:

- `stereos.img` — raw EFI disk image
- `stereos.qcow2` — QCOW2 disk image  
- `bzImage` — compressed kernel
- `initrd` — initramfs
- `cmdline` — kernel command line
- `init` — NixOS stage-2 init path
- `mixtape.toml` — build manifest with SHA-256 checksums and file sizes
