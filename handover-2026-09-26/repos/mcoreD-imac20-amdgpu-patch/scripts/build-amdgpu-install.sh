#!/usr/bin/env bash
# Build + install amdgpu.ko with the 6001 patch.
# Run with sudo (or pkexec for the install steps).
set -euo pipefail
BUILD="${BUILD:-$HOME/build/linux-7.2.6}"
KREL=$(uname -r)
MODULE_PATH="/lib/modules/$KREL/kernel/drivers/gpu/drm/amd/amdgpu/amdgpu.ko.zst"
BACKUP_DIR="/usr/lib/amdgpu-stock-backup"
SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
MODULE="$BUILD/drivers/gpu/drm/amd/amdgpu/amdgpu.ko"

# 1. Backup current (stock) module BEFORE rebuilding, so the backup is
#    guaranteed to be the unpatched version.
if [ ! -f "$BACKUP_DIR/amdgpu.ko.zst" ]; then
  echo "== backing up stock module =="
  install -d "$BACKUP_DIR"
  cp "$MODULE_PATH" "$BACKUP_DIR/"
  sha256sum "$BACKUP_DIR/amdgpu.ko.zst"
  echo "Backed up stock module to $BACKUP_DIR"
else
  echo "== stock backup already exists, skipping =="
fi

# 2. Rebuild (this applies patch, verifies constants, strips, compresses)
"$SCRIPT_DIR/build-amdgpu.sh"

# 3. Find the compressed artifact — build-amdgpu.sh prints the path on
#    its last line of output. Since we already ran it, re-compress here.
echo "== compressing patched module =="
TMPKO=$(mktemp)
trap 'rm -f "$TMPKO"' EXIT
strip --strip-debug "$MODULE"
zstd -T0 -f -o "$TMPKO" "$MODULE"
sha256sum "$TMPKO"

# 4. Install patched module
echo "== installing patched module =="
install -m644 "$TMPKO" "$MODULE_PATH"
sha256sum "$MODULE_PATH"

# 5. Regenerate module deps and boot image
depmod -a
limine-mkinitcpio
echo "Patched module installed. Reboot to use it."
