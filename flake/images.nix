# flake/images.nix
#
# Per-system: Image build targets.
#
# Generates packages from nixosConfigurations:
#   packages.<system>.<mixtape-name>                    (raw)
#   packages.<system>.<mixtape-name>-qcow2              (qcow2)
#   packages.<system>.<mixtape-name>-kernel-artifacts   (direct-kernel boot)
#
# Build with:
#   nix build .#packages.aarch64-linux.opencode-mixtape --impure
#   nix build .#packages.aarch64-linux.opencode-mixtape-qcow2 --impure
#   nix build .#packages.aarch64-linux.opencode-mixtape-kernel-artifacts --impure

{ self, ... }:

{
  # Image packages are not per-system in the flake-parts sense — they are
  # always built for the target architecture (aarch64-linux).  We expose
  # them via the top-level `flake` attrset.
  flake = {
    packages.aarch64-linux =
      let
        configs = self.nixosConfigurations;
        # Raw images — canonical artifact
        rawPkgs = builtins.mapAttrs
          (_name: cfg: cfg.config.system.build.raw)
          configs;
        # QCOW2 images — derived from raw, for QEMU/KVM
        qcow2Pkgs = builtins.mapAttrs
          (_name: cfg: cfg.config.system.build.qcow2)
          configs;
        # Suffix qcow2 package names with "-qcow2"
        qcow2Named = builtins.listToAttrs (
          builtins.map (name: {
            name = "${name}-qcow2";
            value = qcow2Pkgs.${name};
          }) (builtins.attrNames qcow2Pkgs)
        );
        # Kernel artifacts (bzImage + initrd + cmdline) for direct-kernel boot.
        # Build with: nix build .#packages.aarch64-linux.<name>-kernel-artifacts
        kernelArtifactPkgs = builtins.mapAttrs
          (_name: cfg: cfg.config.system.build.kernelArtifacts)
          configs;
        kernelArtifactsNamed = builtins.listToAttrs (
          builtins.map (name: {
            name = "${name}-kernel-artifacts";
            value = kernelArtifactPkgs.${name};
          }) (builtins.attrNames kernelArtifactPkgs)
        );
      in
        rawPkgs // qcow2Named // kernelArtifactsNamed;
  };
}
