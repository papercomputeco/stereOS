# stereOS Versioning

stereOS uses unified [calendar versioning (CalVer)](https://calver.org/)
with mixtape specific OCI registry streams.

All mixtapes share a common base (the `modules/`, `lib/`, `profiles/`, etc.)
and share one version derived from a git tag.
Each mixtape carries their own individual packages and features specific to a use case.
Each mixtape gets rebuilt on each tag in order to align on the common base.

## Format

```
YYYY.0M.DD.N
```

- **YYYY** — four-digit year
- **0M** — zero-padded monthly
- **0D** - zero-padded day
- **N** — release counter for that day, starting at 0

Examples: `2026.03.01.0`, `2077.11.21.9`, `2030.01.01.100`

To see exactly what changed between two releases, compare the commit tags:

```bash
git log 2026.03.1.0..2026.03.1.99
```

## OCI mixtape format

Individual mixtape images are available in the `download.stereos.ai/mixtapes` OCI registry.
Each mixtape gets its own channel with a few utility tags available:

```
download.stereos.ai/mixtapes/coder:latest
download.stereos.ai/mixtapes/coder:nightly
download.stereos.ai/mixtapes/coder:2026.03.01.0
```

* `latest` always points to the most recent tagged release.
* `nightly` are unstable nightly builds. CI/CD selectively builds nightly releases
based on what's changed for a mixtape's packages, modules, profiles, etc.
Use at your own risk.

## Upstream NixOS

stereOS core system components follows stable NixOS releases. These update every 6 months
(typically at the end of May and November).

Other non-system-critical packages (like coding agents) follow nixpkgs-unstable.
These are much more frequently updated.
