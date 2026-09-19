#!/usr/bin/env bash
# /usr/local/sbin/repatch-amdgpu.sh
# Re-applies the t2linux 6001 patch to amdgpu.ko after linux-t2 upgrades.
# Invoked from /etc/pacman.d/hooks/zz-repatch-amdgpu.hook.
set -euo pipefail
MODULE_PATH="/lib/modules/$(uname -r)/kernel/drivers/gpu/drm/amd/amdgpu/amdgpu.ko.zst"
BACKUP_DIR="/usr/lib/amdgpu-stock-backup"

if ! modinfo "$MODULE_PATH" 2>/dev/null | grep -q 'ABC9AFBB\|FFFFFD42'; then
  echo "amdgpu: 6001 patch missing after upgrade; rebuilding (this can take 10-15 min)"
  /home/mike/build/linux-t2-patched/scripts/build-amdgpu-install.sh
fi
