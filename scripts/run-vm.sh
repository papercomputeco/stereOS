#!/usr/bin/env bash
#
# Launch a StereOS image in QEMU on Apple Silicon.
#
# Supports both raw and qcow2 images (auto-detected by extension).
# Raw images are converted to qcow2 on the fly since QEMU prefers
# writable qcow2 for runtime mutations.
#
# Usage:
#   ./scripts/run-vm.sh [path-to-image] [ssh-port]
#
# Defaults:
#   image: ./result/nixos.img (raw) or ./result/nixos.qcow2
#   port:  2222
#
# Requires: nix devShell (provides QEMU and STEREOS_EFI_CODE)
#
set -euo pipefail

# -- Locate image ------------------------------------------------------------
# Try raw first (canonical format), fall back to qcow2
if [ -n "${1:-}" ]; then
  IMAGE="$1"
elif [ -f "./result/nixos.img" ]; then
  IMAGE="./result/nixos.img"
elif [ -f "./result/nixos.qcow2" ]; then
  IMAGE="./result/nixos.qcow2"
else
  echo "ERROR: No image found."
  echo "Build one first:"
  echo "  make build         # → result/nixos.img (raw)"
  echo "  make build-qcow2   # → result/nixos.qcow2"
  exit 1
fi

SSH_PORT="${2:-2222}"

# -- Locate UEFI firmware ----------------------------------------------------
if [ -z "${STEREOS_EFI_CODE:-}" ]; then
  echo "ERROR: STEREOS_EFI_CODE is not set."
  echo "Run this script from inside the nix devShell: nix develop"
  exit 1
fi
if [ ! -f "$STEREOS_EFI_CODE" ]; then
  echo "ERROR: EFI firmware not found at: $STEREOS_EFI_CODE"
  exit 1
fi
EFI_CODE="$STEREOS_EFI_CODE"

# -- Verify the image exists -------------------------------------------------
if [ ! -f "$IMAGE" ]; then
  echo "ERROR: Image not found at: $IMAGE"
  exit 1
fi

# -- Prepare writable working copy ------------------------------------------
WORK_DIR=$(mktemp -d)
trap 'rm -rf "$WORK_DIR"' EXIT

WORK_IMAGE="$WORK_DIR/stereos.qcow2"

# Detect format by extension and convert if needed
case "$IMAGE" in
  *.img|*.raw)
    echo "Converting raw image to qcow2 for QEMU..."
    qemu-img convert -f raw -O qcow2 "$IMAGE" "$WORK_IMAGE"
    ;;
  *.qcow2)
    cp "$IMAGE" "$WORK_IMAGE"
    ;;
  *)
    echo "WARNING: Unknown image extension, assuming qcow2"
    cp "$IMAGE" "$WORK_IMAGE"
    ;;
esac
chmod u+w "$WORK_IMAGE"

# Create writable EFI variable store
EFI_VARS="$WORK_DIR/efi-vars.fd"
dd if=/dev/zero of="$EFI_VARS" bs=1M count=64 2>/dev/null

# -- Vsock support (Linux only) -----------------------------------------------
# vhost-vsock-pci requires the Linux vhost-vsock kernel module (/dev/vhost-vsock)
# and is not available on macOS/HVF. On macOS we skip the device; stereosd inside the
# guest will fail to bind its vsock listener but the VM is still useful for
# development and debugging via SSH.
VSOCK_ARGS=()
if [ "$(uname -s)" = "Linux" ]; then
  VSOCK_ARGS=(-device vhost-vsock-pci,guest-cid=3)
  VSOCK_MSG="CID=3 (stereosd control plane)"
else
  VSOCK_MSG="unavailable (vhost-vsock requires Linux host)"
fi

echo "══════════════════════════════════════════════════════════"
echo "  StereOS VM starting"
echo "  Image:  $IMAGE"
echo "  SSH:    ssh -p $SSH_PORT admin@localhost"
echo "          ssh -p $SSH_PORT agent@localhost"
echo "  Vsock:  $VSOCK_MSG"
echo "  Quit:   Ctrl-A X"
echo "══════════════════════════════════════════════════════════"

qemu-system-aarch64 \
  -machine virt,highmem=on \
  -accel hvf \
  -cpu host \
  -m 4G \
  -smp 4 \
  -drive if=pflash,format=raw,readonly=on,file="$EFI_CODE" \
  -drive if=pflash,format=raw,file="$EFI_VARS" \
  -drive if=virtio,format=qcow2,file="$WORK_IMAGE" \
  -device virtio-net-pci,netdev=net0 \
  -netdev user,id=net0,hostfwd=tcp::${SSH_PORT}-:22 \
  "${VSOCK_ARGS[@]}" \
  -nographic
