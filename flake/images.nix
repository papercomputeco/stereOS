# flake/images.nix
#
# Per-system: Image build targets.
#
# Generates packages from nixosConfigurations:
#   packages.<system>.<mixtape-name>                    (raw)
#   packages.<system>.<mixtape-name>-qcow2              (qcow2)
#   packages.<system>.<mixtape-name>-kernel-artifacts   (direct-kernel boot)
#   packages.<system>.<mixtape-name>-dist               (all formats + mixtape.toml)
#
# Build with:
#   nix build .#packages.aarch64-linux.opencode-mixtape --impure
#   nix build .#packages.aarch64-linux.opencode-mixtape-qcow2 --impure
#   nix build .#packages.aarch64-linux.opencode-mixtape-kernel-artifacts --impure
#   nix build .#packages.aarch64-linux.opencode-mixtape-dist --impure

{ self, inputs, ... }:

let
  stereos-lib = import ../lib/dist.nix { inherit inputs; };
  system = "aarch64-linux";
  pkgs = inputs.nixpkgs.legacyPackages.${system};
in
{
  # Image packages are not per-system in the flake-parts sense — they are
  # always built for the target architecture (aarch64-linux).  We expose
  # them via the top-level `flake` attrset.
  flake = {
    packages.aarch64-linux =
      let
        configs = self.nixosConfigurations;
        mixtapeNames = builtins.attrNames configs;

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
          }) mixtapeNames
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
          }) mixtapeNames
        );
        # Dist directories — all formats assembled into a single output.
        # Build with: nix build .#packages.aarch64-linux.<name>-dist
        distPkgs = builtins.listToAttrs (
          builtins.map (name: {
            name = "${name}-dist";
            value = stereos-lib.mkDist {
              inherit pkgs system;
              name   = name;
              raw    = rawPkgs.${name};
              qcow2  = qcow2Pkgs.${name};
              kernel = kernelArtifactPkgs.${name};
            };
          }) mixtapeNames
        );
      in
        rawPkgs // qcow2Named // kernelArtifactsNamed // distPkgs;
  };
}
