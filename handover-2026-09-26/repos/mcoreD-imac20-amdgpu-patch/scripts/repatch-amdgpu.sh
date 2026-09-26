#!/usr/bin/env bash
# /usr/local/sbin/repatch-amdgpu.sh
# Keeps the t2linux 6001 SMU-init patch applied to amdgpu.ko after every
# linux-t2 upgrade, AND rebuilds the imac20-hwaccel Limine UKI so it
# bundles the new kernel image.
#
# Invoked from /etc/pacman.d/hooks/zz-repatch-amdgpu.hook (runs as root
# via alpm). Can be run manually via `pkexec /usr/local/sbin/repatch-amdgpu.sh`.
set -euo pipefail
shopt -s nullglob

# If run as a normal user, re-exec via pkexec so the rest of the script
# can assume root. Avoids the redirect-permission awkwardness of mixing
# user and root file writes.
if [[ $EUID -ne 0 ]]; then
  exec pkexec "$0" "$@"
fi

KREL=$(uname -r)
LIVE="/lib/modules/$KREL/kernel/drivers/gpu/drm/amd/amdgpu/amdgpu.ko.zst"
HWACCEL_EFI="/boot/EFI/Linux/omarchy_linux-t2-hwaccel.efi"
DEFAULT_EFI="/boot/EFI/Linux/omarchy_linux-t2.efi"
DROP_IN="/etc/limine-entry-tool.d/imac20-hwaccel.conf"
BUILD_TREE="/home/mike/build/linux-7.2.6"
PATCH_FILE="/home/mike/build/linux-t2-patched/src/6001-drm-amd-pm-Fix-boot-problems-in-5300.patch"
STATE_DIR="/var/lib/amdgpu-6001-state"
MARKER="$STATE_DIR/last-rebuild"

last_rebuilt_krel() { [[ -f "$MARKER" ]] && cat "$MARKER" || echo ""; }
record_rebuild()   { mkdir -p "$STATE_DIR" && echo "$KREL" > "$MARKER"; }
needs_rebuild() { [[ "$(last_rebuilt_krel)" != "$KREL" ]]; }

rebuild_module() {
  echo "amdgpu: rebuilding module against $KREL"

  cd "$BUILD_TREE"
  zcat /proc/config.gz > .config
  sed -i 's|^CONFIG_LOCALVERSION=.*|CONFIG_LOCALVERSION="-arch2-Watanare-T2-4-t2"|' .config
  sed -i 's|^CONFIG_LOCALVERSION_AUTO=y|# CONFIG_LOCALVERSION_AUTO is not set|' .config
  echo "-arch2-Watanare-T2-4-t2" > .localversion
  rm -f include/config/kernel.release .version
  make prepare0 >/dev/null
  cat include/config/kernel.release

  if ! grep -q '0xABC9AFBB' drivers/gpu/drm/amd/pm/swsmu/smu11/smu_v11_0.c; then
    echo "amdgpu: applying 6001 patch"
    patch -p1 < "$PATCH_FILE"
  fi

  make -j"$(nproc)" M=drivers/gpu/drm/amd/amdgpu modules
  strip --strip-debug drivers/gpu/drm/amd/amdgpu/amdgpu.ko
  zstd -T0 -f -q -o /tmp/amdgpu-patched.ko.zst \
    drivers/gpu/drm/amd/amdgpu/amdgpu.ko

  install -m644 /tmp/amdgpu-patched.ko.zst "$LIVE"
  depmod -a
  rm -f /tmp/amdgpu-patched.ko.zst
}

rebuild_hwaccel_uki() {
  [[ -f "$DEFAULT_EFI" ]] || { echo "amdgpu: default UKI not present, skipping hwaccel rebuild"; return; }
  [[ -f "$DROP_IN"    ]] || { echo "amdgpu: drop-in $DROP_IN not present, skipping hwaccel rebuild"; return; }

  echo "amdgpu: rebuilding hwaccel UKI"
  # Omarchy's limine-mkinitcpio does not understand profile-specific cmdline
  # in UKI mode. Build a second UKI by temporarily putting the hwaccel
  # cmdline into [default], regen, copy out, then restore.
  local orig
  orig=$(mktemp)
  cp "$DROP_IN" "$orig"

  cat > "$DROP_IN" <<'UKIEOF'
# one-shot: rebuild hwaccel UKI with the patched amdgpu
KERNEL_CMDLINE[default]+=" plymouth.enable=0 loglevel=7 ignore_loglevel console=tty1 amdgpu.modeset=1 video=efifb:off"
UKIEOF
  limine-mkinitcpio >/dev/null 2>&1
  cp "$DEFAULT_EFI" "$HWACCEL_EFI"
  mv "$orig" "$DROP_IN"
  limine-mkinitcpio >/dev/null 2>&1
}

if needs_rebuild; then
  rebuild_module
  rebuild_hwaccel_uki
  record_rebuild
  echo "amdgpu: 6001 patch re-applied and hwaccel UKI rebuilt"
else
  echo "amdgpu: 6001 patch already up to date for $KREL"
fi
