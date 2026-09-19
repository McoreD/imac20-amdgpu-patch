#!/usr/bin/env bash
# /usr/local/sbin/repatch-amdgpu.sh
# Re-applies the t2linux 6001 patch to amdgpu.ko after linux-t2 upgrades.
# Invoked from /etc/pacman.d/hooks/zz-repatch-amdgpu.hook.
set -euo pipefail
MODULE_PATH="/lib/modules/$(uname -r)/kernel/drivers/gpu/drm/amd/amdgpu/amdgpu.ko.zst"

# Check if the patched magic constants are present in the installed module.
# The constants are binary (LE-encoded), so we must scan the raw bytes —
# `modinfo` and `strings` will not find them.
PATCH_PRESENT=$(python3 -c "
import subprocess, sys
d = subprocess.run(['zstd', '-d', '-c', '$MODULE_PATH'],
                   capture_output=True, check=True).stdout
if d.count(bytes.fromhex('bbafc9ab')) >= 1:
    print('yes')
else:
    print('no')
" 2>/dev/null || echo "error")

if [ "$PATCH_PRESENT" != "yes" ]; then
  echo "amdgpu: 6001 patch missing after upgrade; rebuilding (this can take 10-15 min)"
  /home/mike/build/linux-t2-patched/scripts/build-amdgpu-install.sh
fi
