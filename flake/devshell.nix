# flake/devshell.nix
#
# Per-system: Developer shell for direnv integration.
# Provides toolchains, nix formatters, and development utilities.

{ inputs, ... }:

{
  perSystem = { system, pkgs, ... }: {
    devShells.default = pkgs.mkShell {
      buildInputs = [
        pkgs.gnumake
        pkgs.qemu
        pkgs.go
        pkgs.gopls
        pkgs.gotools
        pkgs.hurl
        inputs.dagger.packages.${system}.dagger
      ];

      shellHook = ''
        # Provide Nix with GitHub auth for private flake inputs.
        # Requires `gh auth login` to have been run once.
        if command -v gh &>/dev/null && gh auth status &>/dev/null 2>&1; then
          export NIX_CONFIG="access-tokens = github.com=$(gh auth token)"
        fi

        echo "StereOS dev shell"
        echo "  Go:   $(go version)"
        echo "  QEMU: $(qemu-system-aarch64 --version | head -1)"
        export STEREOS_EFI_CODE="${pkgs.qemu}/share/qemu/edk2-aarch64-code.fd"
      '';
    };
  };
}
