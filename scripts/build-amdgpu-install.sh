#!/usr/bin/env bash
# Build + install amdgpu.ko with the 6001 patch.
# Run with sudo.
set -euo pipefail
BUILD="$HOME/build/linux-7.2.6"
KREL=$(uname -r)
MODULE_PATH="/lib/modules/$KREL/kernel/drivers/gpu/drm/amd/amdgpu/amdgpu.ko.zst"
BACKUP_DIR="/usr/lib/amdgpu-stock-backup"

# 1. Rebuild
"$HOME/build/linux-t2-patched/scripts/build-amdgpu.sh"

# 2. Backup current module once
if [ ! -f "$BACKUP_DIR/amdgpu.ko.zst" ]; then
  install -d "$BACKUP_DIR"
  cp "$MODULE_PATH" "$BACKUP_DIR/"
  echo "Backed up stock module to $BACKUP_DIR"
fi

# 3. Install patched module
install -m644 "$BUILD/drivers/gpu/drm/amd/amdgpu/amdgpu.ko.zst" "$MODULE_PATH"
depmod -a
mkinitcpio -P
echo "Patched module installed. Reboot to use it."
