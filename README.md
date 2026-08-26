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

| Mixtape | Agent binaries | API key |
|---------|----------------|---------|
| `base` | none | — |
| `coder` | `claude`, `codex`, `gemini`, `opencode`, `pi` | see below |

`base` is the bare hardened system that everything else extends. `coder` adds
the coding agents:

| Binary | Package | API key |
|--------|---------|---------|
| `claude` | `pkgs-unstable.claude-code` | `ANTHROPIC_API_KEY` |
| `codex` | `pkgs-unstable.codex` | `OPENAI_API_KEY` |
| `gemini` | `pkgs-unstable.gemini-cli` | `GEMINI_API_KEY` or `GOOGLE_API_KEY` |
| `opencode` | `pkgs-unstable.opencode` | `ANTHROPIC_API_KEY` or `OPENAI_API_KEY` |
| `pi` | [`lib/pi-bin.nix`](lib/pi-bin.nix) | resolved per model by pi's own registry |

Each mixtape appends its agent packages to `stereos.agent.extraPackages`, which
adds the binaries to the agent user's restricted PATH. That option also feeds
the gVisor sandbox closure manifest (`lib/default.nix:mkSandboxManifest`) and
the Lambda MicroVM bundle's `agentPackages` (`flake/images.nix`), so a package
added there reaches every artifact. The `-dev` variant of each mixtape includes
`profiles/dev.nix` for local SSH key injection.

`pi` is not in nixpkgs; `lib/pi-bin.nix` builds it from the published npm
tarball, the same local-derivation pattern `lib/paper-bin.nix` uses for the
Paper CLI. Bumping its version requires refreshing the tarball hash, the
`npmDepsHash`, and the six pi-mono sibling integrity hashes together.

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
| Lambda MicroVM source | `packages.<system>.<mixtape>-lambda-microvm-source` | Dockerfile source zip | AWS Lambda MicroVM image creation |

The Lambda MicroVM source bundle is not a full stereOS VM image. It packages
stereOS userspace into a Dockerfile-based rootfs bundle because AWS Lambda
MicroVM images are created from Dockerfile application sources, not custom
kernel or disk artifacts.

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
| `nixpkgs` | `nixos-26.05` | Base packages |
| `dagger` | `github:dagger/nix` | CI engine |
