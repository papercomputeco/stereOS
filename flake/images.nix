# flake/images.nix
#
# Per-system image build targets.
#
# Generates packages for each target architecture by constructing
# system-specific nixosConfigurations via mkMixtape:
#   packages.<system>.<mixtape-name>                    (raw)
#   packages.<system>.<mixtape-name>-qcow2              (qcow2)
#   packages.<system>.<mixtape-name>-kernel-artifacts   (direct-kernel boot)
#   packages.<system>.<mixtape-name>-dist               (all formats + mixtape.toml)
#
# Build with:
#   nix build .#packages.aarch64-linux.coder --impure
#   nix build .#packages.x86_64-linux.coder --impure

{ self, inputs, ... }:

let
  stereos-lib = import ../lib/dist.nix { inherit inputs; };
  stereos-lambda = import ../lib/lambda-microvm.nix { inherit inputs; };
  stereos-main = import ../lib { inherit inputs self; };

  # Target architectures to build images for
  targetSystems = [ "aarch64-linux" "x86_64-linux" ];

  # Mixtape definitions — name + feature modules.
  # Each entry produces a full set of image packages per target system.
  # Dev variants include profiles/dev.nix for SSH key injection.
  mixtapeSpecs = [
    { name = "base";      features = [ ../mixtapes/base/package.nix ];  extraModules = []; }
    { name = "coder";     features = [ ../mixtapes/coder/package.nix ]; extraModules = []; }
    { name = "base-dev";  features = [ ../mixtapes/base/package.nix ];  extraModules = [ ../profiles/dev.nix ]; }
    { name = "coder-dev"; features = [ ../mixtapes/coder/package.nix ]; extraModules = [ ../profiles/dev.nix ]; }
  ];

  # Helper to build packages for a given system
  buildSystemImages = system:
    let
      pkgs = inputs.nixpkgs.legacyPackages.${system};
      paper-bin = import ../lib/paper-bin.nix { inherit pkgs; };

      # Build a nixosConfiguration for each mixtape spec, targeting this system.
      configs = builtins.listToAttrs (
        builtins.map (spec: {
          name = spec.name;
          value = stereos-main.mkMixtape {
            inherit system;
            inherit (spec) name features extraModules;
          };
        }) mixtapeSpecs
      );
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
      distPkgs = builtins.listToAttrs (
        builtins.map (name: {
          name = "${name}-dist";
          value = stereos-lib.mkDist {
            inherit pkgs system;
            name    = name;
            version = stereos-main.stereosVersion;
            raw     = rawPkgs.${name};
            qcow2   = qcow2Pkgs.${name};
            kernel  = kernelArtifactPkgs.${name};
          };
        }) mixtapeNames
      );
      # Lambda MicroVM source bundles — Dockerfile + Nix-built rootfs tar,
      # deliberately separate from VM mixtape artifacts.
      lambdaMicrovmPkgs = builtins.listToAttrs (
        builtins.map (name: {
          name = "${name}-lambda-microvm-source";
          value = stereos-lambda.mkLambdaMicrovmSource {
            inherit pkgs;
            name = name;
            version = stereos-main.stereosVersion;
            agentPackages =
              configs.${name}.config.stereos.agent.basePackages
              ++ configs.${name}.config.stereos.agent.extraPackages
              ++ [ paper-bin ];
            startPaperd = true;
            # Warm Claude Code's native build into the snapshot during image
            # creation. A no-op for mixtapes without `claude` on PATH.
            warmAgent = true;
          };
        }) mixtapeNames
      );
    in
      rawPkgs // qcow2Named // kernelArtifactsNamed // distPkgs // lambdaMicrovmPkgs;

  # Build packages for all target systems
  allPackages = builtins.listToAttrs (
    builtins.map (system: {
      name = system;
      value = buildSystemImages system;
    }) targetSystems
  );
in
{
  # Image packages are per-system — they are built for the target architecture.
  flake.packages = allPackages;
}
