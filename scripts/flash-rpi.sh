#!/usr/bin/env bash
#
# Flash a stereOS Raspberry Pi SD image to an SD card.
#
# Supports macOS and Linux. Auto-discovers removable disks, prompts for
# confirmation, and optionally injects an SSH public key onto the
# FIRMWARE FAT partition so the Pi accepts SSH on first boot.
#
# Usage:
#   ./scripts/flash-rpi.sh [--board rpi4|rpi5] [--image <path>] [--ssh-key <path>]
#
# Options:
#   --board <rpi4|rpi5>  Scope auto-detection to one board's result dir.
#                        Without it, both result-rpi4/ and result-rpi5/ are
#                        searched. The Makefile passes this so flash-rpi4
#                        and flash-rpi5 never confuse one for the other.
#   --image <path>       Path to the .img file (default: auto-detected
#                        under result-rpi4/sd-image/ and/or result-rpi5/sd-image/)
#   --ssh-key <path>     Path to an SSH .pub key to inject into the
#                        FIRMWARE partition's ssh_authorized_keys.txt
#   -h, --help           Show this help message
#
# Environment variable fallbacks:
#   STEREOS_IMAGE      Same as --image
#   STEREOS_SSH_KEY    Same as --ssh-key
#
# Examples:
#   ./scripts/flash-rpi.sh
#   ./scripts/flash-rpi.sh --ssh-key ~/.ssh/id_ed25519.pub
#   make flash-rpi4 SSH_KEY=~/.ssh/id_ed25519.pub
#
set -euo pipefail

# -- Helpers -----------------------------------------------------------------

die() {
  echo "ERROR: $*" >&2
  exit 1
}

usage() {
  cat <<'EOF'
Usage:
  ./scripts/flash-rpi.sh [--board rpi4|rpi5] [--image <path>] [--ssh-key <path>]

Options:
  --board <rpi4|rpi5>  Scope auto-detection to that board's result dir.
                       Without it, both result-rpi4/ and result-rpi5/ are
                       searched.
  --image <path>       Path to the .img file (default: auto-detected
                       under result-rpi4/sd-image/ and/or result-rpi5/sd-image/)
  --ssh-key <path>     Path to an SSH .pub key to inject into the
                       FIRMWARE partition's ssh_authorized_keys.txt
  -h, --help           Show this help message

Environment variable fallbacks:
  STEREOS_IMAGE      Same as --image
  STEREOS_SSH_KEY    Same as --ssh-key

Examples:
  ./scripts/flash-rpi.sh
  ./scripts/flash-rpi.sh --board rpi5 --ssh-key ~/.ssh/id_ed25519.pub
  make flash-rpi5 SSH_KEY=~/.ssh/id_ed25519.pub
EOF
}

# -- Argument parsing --------------------------------------------------------

IMAGE=""
SSH_KEY=""
BOARD=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --image)
      [[ -n "${2:-}" ]] || die "--image requires a path"
      IMAGE="$2"; shift 2 ;;
    --ssh-key)
      [[ -n "${2:-}" ]] || die "--ssh-key requires a path"
      SSH_KEY="$2"; shift 2 ;;
    --board)
      [[ "${2:-}" =~ ^rpi[45]$ ]] || die "--board requires rpi4 or rpi5"
      BOARD="$2"; shift 2 ;;
    -h|--help)
      usage; exit 0 ;;
    *)
      die "Unknown argument: $1" ;;
  esac
done

# Env-var fallbacks
IMAGE="${IMAGE:-${STEREOS_IMAGE:-}}"
SSH_KEY="${SSH_KEY:-${STEREOS_SSH_KEY:-}}"

# -- Find image --------------------------------------------------------------

find_image() {
  if [[ -n "$IMAGE" ]]; then
    [[ -f "$IMAGE" ]] || die "Image not found: $IMAGE"
    return
  fi
  # Auto-detect. With --board, scope to that board's result dir only; without
  # it, look in both. nullglob so an empty result dir expands to nothing
  # rather than the literal pattern.
  shopt -s nullglob
  local candidates
  case "$BOARD" in
    rpi4) candidates=( result-rpi4/sd-image/stereos-*.img ) ;;
    rpi5) candidates=( result-rpi5/sd-image/stereos-*.img ) ;;
    "")   candidates=( result-rpi4/sd-image/stereos-*.img result-rpi5/sd-image/stereos-*.img ) ;;
  esac
  shopt -u nullglob
  if [[ ${#candidates[@]} -eq 0 ]]; then
    if [[ -n "$BOARD" ]]; then
      die "No Raspberry Pi image found under result-${BOARD}/sd-image/
Build one first:
  make build-${BOARD} MIXTAPE=<mixtape>"
    else
      die "No Raspberry Pi image found under result-rpi4/sd-image/ or result-rpi5/sd-image/
Build one first:
  make build-rpi4 MIXTAPE=<mixtape>
  make build-rpi5 MIXTAPE=<mixtape>"
    fi
  fi
  if [[ ${#candidates[@]} -gt 1 ]]; then
    echo "Multiple images found:" >&2
    printf "  %s\n" "${candidates[@]}" >&2
    die "Specify one with --image <path> (or --board rpi4|rpi5)"
  fi
  IMAGE="${candidates[0]}"
}

# -- OS detection ------------------------------------------------------------

OS=""

detect_os() {
  case "$(uname -s)" in
    Darwin) OS=macos ;;
    Linux)  OS=linux ;;
    *)      die "Unsupported OS: $(uname -s). macOS and Linux supported." ;;
  esac
}

# -- Disk discovery ----------------------------------------------------------

DISK_IDS=()

list_removable_disks() {
  if [[ "$OS" == "macos" ]]; then
    list_removable_disks_macos
  else
    list_removable_disks_linux
  fi
  if [[ ${#DISK_IDS[@]} -eq 0 ]]; then
    die "No removable disks found. Insert an SD card and try again."
  fi
}

list_removable_disks_macos() {
  local line disk
  while IFS= read -r line; do
    disk=$(echo "$line" | awk '{print $1}')
    [[ -n "$disk" ]] && DISK_IDS+=("$disk")
  done < <(diskutil list external physical 2>/dev/null | grep "^/dev/disk" || true)
}

list_removable_disks_linux() {
  local name
  while IFS= read -r name; do
    [[ -n "$name" ]] && DISK_IDS+=("/dev/$name")
  done < <(lsblk -d -n -o NAME,RM,TYPE | awk '$2 == 1 && $3 == "disk" {print $1}' || true)
}

# -- Device selection --------------------------------------------------------

TARGET_DEVICE=""

prompt_device() {
  echo ""
  echo "Available removable disks:"
  echo ""

  local i disk
  for i in "${!DISK_IDS[@]}"; do
    disk="${DISK_IDS[$i]}"
    if [[ "$OS" == "macos" ]]; then
      local size model
      size=$(diskutil info "$disk" | grep "Disk Size" | awk -F: '{print $2}' | xargs)
      model=$(diskutil info "$disk" | grep "Media Name" | awk -F: '{print $2}' | xargs)
      printf "  [%d]  %s\n" "$((i+1))" "$disk"
      printf "       %s — %s\n" "${model:-unknown}" "${size:-unknown}"
    else
      local info
      info=$(lsblk -d -n -o SIZE,MODEL "$disk" 2>/dev/null | xargs)
      printf "  [%d]  %s  %s\n" "$((i+1))" "$disk" "$info"
    fi
  done

  echo ""
  local choice
  if [[ ${#DISK_IDS[@]} -eq 1 ]]; then
    read -rp "Use ${DISK_IDS[0]}? [y/N] " choice
    [[ "$choice" =~ ^[Yy]$ ]] || die "Aborted."
    TARGET_DEVICE="${DISK_IDS[0]}"
  else
    read -rp "Enter disk number [1-${#DISK_IDS[@]}]: " choice
    [[ "$choice" =~ ^[0-9]+$ ]] || die "Invalid selection."
    local idx=$((choice - 1))
    (( idx >= 0 && idx < ${#DISK_IDS[@]} )) || die "Selection out of range."
    TARGET_DEVICE="${DISK_IDS[$idx]}"
  fi
}

# -- Confirmation gate -------------------------------------------------------

confirm_flash() {
  local dev_size=""
  if [[ "$OS" == "macos" ]]; then
    dev_size=$(diskutil info "$TARGET_DEVICE" | grep "Disk Size" | awk -F: '{print $2}' | xargs)
  else
    dev_size=$(lsblk -d -n -o SIZE "$TARGET_DEVICE" 2>/dev/null | xargs)
  fi
  local img_size
  img_size=$(du -h "$IMAGE" | awk '{print $1}')

  echo ""
  echo "══════════════════════════════════════════════════════════"
  echo "  WARNING: All data on the target device will be erased!"
  echo ""
  echo "  Image:       $IMAGE ($img_size)"
  echo "  Device:      $TARGET_DEVICE"
  echo "  Device size: ${dev_size:-unknown}"
  if [[ -n "$SSH_KEY" ]]; then
  echo "  SSH key:     $SSH_KEY"
  fi
  echo "══════════════════════════════════════════════════════════"
  echo ""
  local confirm
  read -rp "Type 'yes' to flash: " confirm
  [[ "$confirm" == "yes" ]] || die "Aborted."
}

# -- Flash -------------------------------------------------------------------

flash_image() {
  if [[ "$OS" == "macos" ]]; then
    flash_image_macos
  else
    flash_image_linux
  fi
}

flash_image_macos() {
  local raw_dev="${TARGET_DEVICE/disk/rdisk}"
  echo ""
  echo "Unmounting $TARGET_DEVICE..."
  diskutil unmountDisk "$TARGET_DEVICE"
  echo "Flashing $IMAGE -> $raw_dev (this may take a few minutes)..."
  sudo dd if="$IMAGE" of="$raw_dev" bs=4M status=progress
  sync
  echo "Flash complete."
}

flash_image_linux() {
  echo ""
  echo "Unmounting partitions on $TARGET_DEVICE..."
  local part
  for part in "${TARGET_DEVICE}"*; do
    if mount | grep -q "^$part "; then
      sudo umount "$part" 2>/dev/null || true
    fi
  done
  echo "Flashing $IMAGE -> $TARGET_DEVICE (this may take a few minutes)..."
  sudo dd if="$IMAGE" of="$TARGET_DEVICE" bs=4M status=progress conv=fsync
  sync
  echo "Flash complete."
}

# -- SSH key injection -------------------------------------------------------

inject_ssh_key() {
  [[ -n "$SSH_KEY" ]] || return 0

  echo ""
  echo "Injecting SSH key..."

  if [[ "$OS" == "macos" ]]; then
    inject_ssh_key_macos
  else
    inject_ssh_key_linux
  fi
}

inject_ssh_key_macos() {
  echo "Mounting $TARGET_DEVICE..."
  diskutil mountDisk "$TARGET_DEVICE" >/dev/null 2>&1 || true
  # Give macOS a moment to mount volumes
  sleep 2

  local fw_path="/Volumes/FIRMWARE"
  if [[ ! -d "$fw_path" ]]; then
    echo "WARNING: FIRMWARE partition not mounted at $fw_path" >&2
    echo "You can add the key manually later by editing" >&2
    echo "ssh_authorized_keys.txt on the FIRMWARE partition." >&2
    return 0
  fi

  local keys_file="$fw_path/ssh_authorized_keys.txt"
  if [[ ! -f "$keys_file" ]]; then
    # Template not present — create it
    touch "$keys_file"
  fi

  cat "$SSH_KEY" >> "$keys_file"
  echo "Key appended to $keys_file"
  diskutil eject "$TARGET_DEVICE" >/dev/null 2>&1 || true
}

inject_ssh_key_linux() {
  sudo partprobe "$TARGET_DEVICE" 2>/dev/null || true
  sleep 1

  local mount_point="/tmp/stereos-firmware"
  sudo mkdir -p "$mount_point"

  # Partition naming: /dev/sdX1 vs /dev/mmcblk0p1
  local part1
  if [[ "$TARGET_DEVICE" == *mmcblk* || "$TARGET_DEVICE" == *nvme* ]]; then
    part1="${TARGET_DEVICE}p1"
  else
    part1="${TARGET_DEVICE}1"
  fi

  if ! sudo mount "$part1" "$mount_point" 2>/dev/null; then
    echo "WARNING: Failed to mount FIRMWARE partition ($part1)" >&2
    echo "You can add the key manually later by editing" >&2
    echo "ssh_authorized_keys.txt on the FIRMWARE partition." >&2
    return 0
  fi

  local keys_file="$mount_point/ssh_authorized_keys.txt"
  if [[ ! -f "$keys_file" ]]; then
    sudo touch "$keys_file"
  fi

  sudo tee -a "$keys_file" < "$SSH_KEY" > /dev/null
  echo "Key appended to $keys_file"
  sudo umount "$mount_point"
  sudo eject "$TARGET_DEVICE" 2>/dev/null || true
}

# -- Summary -----------------------------------------------------------------

print_summary() {
  echo ""
  echo "══════════════════════════════════════════════════════════"
  echo "  stereOS Raspberry Pi image flashed successfully"
  echo ""
  echo "  Image:   $IMAGE"
  echo "  Device:  $TARGET_DEVICE"
  if [[ -n "$SSH_KEY" ]]; then
  echo "  SSH key: $(basename "$SSH_KEY") (injected)"
  fi
  echo ""
  echo "  Insert the SD card into your Raspberry Pi and power on."
  if [[ -n "$SSH_KEY" ]]; then
  echo "  SSH:     ssh admin@<rpi-ip>"
  else
  echo "  To add SSH keys, mount the FIRMWARE partition and"
  echo "  edit ssh_authorized_keys.txt, or reflash with:"
  echo "    make flash-rpi4 SSH_KEY=~/.ssh/id_ed25519.pub"
  fi
  echo "══════════════════════════════════════════════════════════"
}

# -- Main --------------------------------------------------------------------

main() {
  find_image
  detect_os

  # Validate SSH key early
  if [[ -n "$SSH_KEY" ]]; then
    [[ -f "$SSH_KEY" ]] || die "SSH key file not found: $SSH_KEY"
    if ! grep -qE '^(ssh-ed25519|ssh-rsa|ssh-dss|ecdsa-sha2-|sk-ssh-|sk-ecdsa-)' "$SSH_KEY"; then
      die "File does not look like an SSH public key: $SSH_KEY"
    fi
  fi

  echo "══════════════════════════════════════════════════════════"
  echo "  stereOS Raspberry Pi SD card flasher"
  echo ""
  echo "  Image:  $IMAGE"
  echo "  OS:     $OS"
  if [[ -n "$SSH_KEY" ]]; then
  echo "  SSH key: $SSH_KEY"
  fi
  echo "══════════════════════════════════════════════════════════"

  list_removable_disks
  prompt_device
  confirm_flash
  flash_image
  inject_ssh_key
  print_summary
}

main "$@"
