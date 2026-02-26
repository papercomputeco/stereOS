<h1>
<p align="center">
  stereOS 🧃
</h1>
</p>

<p align="center">
  A Linux based operating system hardened and purpose-built for AI agents.
  <br />
  <a href="https://stereos.ai/">Download</a>
  |
  <a href="https://stereos.ai">Documentation</a>
</p>

<p align="center">
  <img src="https://img.shields.io/github/stars/papercomputeco/stereOS">
</p>

<p align="center">
  <a target="_blank" href="https://discord.gg/T6Y4XkmmV5">
    <img src="https://dcbadge.limes.pink/api/server/https://discord.gg/T6Y4XkmmV5">
  </a>
</p>

## Mixtapes

stereOS produces machine images - called **mixtapes** - that bundle a
hardened, minimal Linux system with specific AI agent harnesses.

| Mixtape | Agent binary | API key |
|---------|-------------|---------|
| `opencode-mixtape` | `opencode` | `ANTHROPIC_API_KEY` or `OPENAI_API_KEY` |

Each mixtape appends its agent package to `stereos.agent.extraPackages`, which
adds the binary to the agent user's restricted PATH. The `-dev` variant of
each mixtape includes `profiles/dev.nix` for local SSH key injection.

## System

The stereOS system is minimal in nature with several orchestration daemons
handling agent lifecycle and acting as a control plane for agent operators:

* `admin` user and group for administrative operations: `/home/admin`
* `agent` user and group for agent to assume: `/home/agent/workspace`
* [`stereosd`](https://github.com/papercomputeco/stereosd) - stereOS system daemon
* [`agentd`](https://github.com/papercomputeco/agentd) - agent management daemon

## Image formats

| Format | Build attribute | Output | Use case |
|--------|----------------|--------|----------|
| Raw EFI | `system.build.raw` | `stereos.img` | Canonical artifact. Apple Virt Framework bootable |
| QCOW2 | `system.build.qcow2` | `stereos.qcow2` | Derived from raw via `qemu-img convert`. QEMU/KVM |
| Kernel artifacts | `system.build.kernelArtifacts` | `bzImage`, `initrd`, `cmdline`, `init` | Direct-kernel boot (bypasses UEFI/GRUB) |

### Distribution (mkDist)

`lib/dist.nix:mkDist` assembles all formats into a publish-ready directory
with zstd-compressed variants (`-19 -T0`) and a `mixtape.toml` manifest
containing SHA-256 checksums and file sizes for every artifact:

```
result/
├── stereos.img          # Raw EFI disk
├── stereos.img.zst      # Zstd-compressed raw
├── stereos.qcow2        # QCOW2 disk
├── stereos.qcow2.zst    # Zstd-compressed QCOW2
├── bzImage              # Kernel
├── initrd               # Init RAM
├── cmdline              # Kernel command line
├── init                 # NixOS stage-2 init path
└── mixtape.toml         # Build manifest with checksums
```

## NixOS options

stereOS declares two custom options:

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `stereos.ssh.authorizedKeys` | `listOf str` | `[]` | SSH public keys for admin and agent users. Useful for development purposes. |
| `stereos.agent.extraPackages` | `listOf package` | `[]` | Packages added to the agent's restricted PATH |

## External dependencies

| Flake input | Repository | Provides |
|-------------|-----------|----------|
| `agentd` | `github:papercomputeco/agentd` | `services.agentd` NixOS module + overlay |
| `stereosd` | `github:papercomputeco/stereosd` | `services.stereosd` NixOS module + overlay |
| `nixpkgs` | `nixpkgs-unstable` | Base packages |
| `dagger` | `github:dagger/nix` | CI engine |
