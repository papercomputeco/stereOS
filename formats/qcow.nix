# formats/qcow.nix
#
# QCOW2 image format — derived from the raw image.
# Produces system.build.qcow2 for QEMU and KVM/libvirt backends.
#
# Build with:
#   nix build .#packages.aarch64-linux.<mixtape-name>-qcow2 --impure

{ config, lib, pkgs, ... }:

let
  imageName = "stereos-${config.networking.hostName}";
in
{
  system.build.qcow2 = pkgs.runCommand "${imageName}-qcow2" {
    nativeBuildInputs = [ pkgs.qemu ];
  } ''
    mkdir -p $out
    qemu-img convert -f raw -O qcow2 -c \
      ${config.system.build.raw}/stereos.img \
      $out/stereos.qcow2
  '';
}
