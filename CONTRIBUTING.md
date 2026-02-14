# Contributing

### `gh` auth session activation

In order to let Nix evaluate the flake and enter the dev shell,
you may need to pull down private GitHub repos. Do this via the `access-token`
Nix config and `gh auth login`. Set the following in your RC of choice:

```bash
if command -v gh &>/dev/null && gh auth status &>/dev/null 2>&1; then
  export NIX_CONFIG="access-tokens = github.com=$(gh auth token)"
fi
```
