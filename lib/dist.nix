# lib/dist.nix

{ inputs }:

let
  inherit (inputs.nixpkgs) lib;
in
{
  # -- mkDist ----------------------------------------------------------------
  #
  # Assemble a publish-ready distribution directory from pre-built artifacts.
  # Returns a single derivation containing:
  #
  #   stereos.img        — raw EFI disk image
  #   stereos.img.zst    — zstd-compressed raw image
  #   stereos.qcow2      — QCOW2 disk image
  #   stereos.qcow2.zst  — zstd-compressed QCOW2 image
  #   bzImage            — compressed kernel
  #   initrd             — initramfs
  #   cmdline            — kernel command line
  #   init               — NixOS stage-2 init path
  #   mixtape.toml       — build manifest with checksums for all artifacts
  #
  # Usage:
  #   mkDist {
  #     name    = "opencode-mixtape";
  #     version = "0.1.0";
  #     system  = "aarch64-linux";
  #     raw     = self.packages.aarch64-linux.opencode-mixtape;
  #     qcow2   = self.packages.aarch64-linux.opencode-mixtape-qcow2;
  #     kernel  = self.packages.aarch64-linux.opencode-mixtape-kernel-artifacts;
  #   }
  #
  mkDist = { pkgs, name, version ? "0.0.0-dev", system ? "aarch64-linux", raw, qcow2, kernel }:
    pkgs.runCommand "${name}-dist" {
      inherit version;
      mixtape = name;
      arch = system;
      nativeBuildInputs = [ pkgs.zstd ];
    } ''
      mkdir -p $out

      # -- Copy artifacts ------------------------------------------------------
      cp -L ${raw}/stereos.img      $out/
      cp -L ${qcow2}/stereos.qcow2  $out/
      cp -L ${kernel}/bzImage        $out/
      cp -L ${kernel}/initrd         $out/
      cp -L ${kernel}/cmdline        $out/
      cp -L ${kernel}/init           $out/

      # -- Compress disk images with zstd --------------------------------------
      zstd -19 -T0 $out/stereos.img   -o $out/stereos.img.zst
      zstd -19 -T0 $out/stereos.qcow2 -o $out/stereos.qcow2.zst

      # -- Checksums and sizes -------------------------------------------------
      # Compute SHA-256 digests and file sizes at build time so downstream
      # consumers (Dagger, CI) never need to re-hash or stat multi-GB files.

      # Raw image (uncompressed + compressed)
      raw_sha256=$(sha256sum $out/stereos.img | cut -d' ' -f1)
      raw_size=$(stat -c%s $out/stereos.img)
      raw_zst_sha256=$(sha256sum $out/stereos.img.zst | cut -d' ' -f1)
      raw_zst_size=$(stat -c%s $out/stereos.img.zst)

      # QCOW2 (uncompressed + compressed)
      qcow2_sha256=$(sha256sum $out/stereos.qcow2 | cut -d' ' -f1)
      qcow2_size=$(stat -c%s $out/stereos.qcow2)
      qcow2_zst_sha256=$(sha256sum $out/stereos.qcow2.zst | cut -d' ' -f1)
      qcow2_zst_size=$(stat -c%s $out/stereos.qcow2.zst)

      # Kernel artifacts
      bzimage_sha256=$(sha256sum $out/bzImage | cut -d' ' -f1)
      bzimage_size=$(stat -c%s $out/bzImage)
      initrd_sha256=$(sha256sum $out/initrd | cut -d' ' -f1)
      initrd_size=$(stat -c%s $out/initrd)
      cmdline_sha256=$(sha256sum $out/cmdline | cut -d' ' -f1)
      cmdline_size=$(stat -c%s $out/cmdline)
      init_sha256=$(sha256sum $out/init | cut -d' ' -f1)
      init_size=$(stat -c%s $out/init)

      # -- Generate mixtape.toml -----------------------------------------------
      cat > $out/mixtape.toml <<EOF
      name = "$mixtape"
      version = "$version"
      arch = "$arch"

      [artifacts.raw]
      file = "stereos.img"
      sha256 = "$raw_sha256"
      size = $raw_size
      compressed_file = "stereos.img.zst"
      compressed_sha256 = "$raw_zst_sha256"
      compressed_size = $raw_zst_size

      [artifacts.qcow2]
      file = "stereos.qcow2"
      sha256 = "$qcow2_sha256"
      size = $qcow2_size
      compressed_file = "stereos.qcow2.zst"
      compressed_sha256 = "$qcow2_zst_sha256"
      compressed_size = $qcow2_zst_size

      [artifacts.kernel.bzimage]
      file = "bzImage"
      sha256 = "$bzimage_sha256"
      size = $bzimage_size

      [artifacts.kernel.initrd]
      file = "initrd"
      sha256 = "$initrd_sha256"
      size = $initrd_size

      [artifacts.kernel.cmdline]
      file = "cmdline"
      sha256 = "$cmdline_sha256"
      size = $cmdline_size

      [artifacts.kernel.init]
      file = "init"
      sha256 = "$init_sha256"
      size = $init_size
      EOF
    '';
}
