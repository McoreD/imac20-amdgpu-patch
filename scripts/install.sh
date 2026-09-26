#!/usr/bin/env bash
# One-shot, idempotent setup of the two-path (safe / hwaccel) boot on an
# iMac20,1 / iMac20,2. Run with sudo from the repo checkout:
#   sudo scripts/install.sh
#
# - installs /usr/local/sbin/imac20-hwaccel and the patches (deferred-UCLK
#   fix, plus 6001 so it can be reverted from the source tree)
# - installs the pacman hook (linux-t2 / linux-t2-headers upgrades)
# - moves the amdgpu flags out of Limine [default] so the normal entry is SAFE
# - sets PATCH_AMDGPU=1 and builds the deferred-UCLK amdgpu for the newest
#   linux-t2, then both UKIs
set -euo pipefail
[[ $EUID -eq 0 ]] || exec sudo "$0" "$@"
REPO=$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)

install -Dm755 "$REPO/scripts/imac20-hwaccel" /usr/local/sbin/imac20-hwaccel
for p in 6001-drm-amd-pm-Fix-boot-problems-in-5300.patch amdgpu-defer-uclk-5300.patch; do
  install -Dm644 "$REPO/src/$p" "/usr/local/share/imac20-hwaccel/$p"
done

if [[ ! -f /etc/imac20-hwaccel.conf ]]; then
  user=${SUDO_USER:-mike}
  cat > /etc/imac20-hwaccel.conf <<EOF
# Who builds the module (unprivileged) and where kernel sources live.
BUILD_USER=$user
BUILD_ROOT=$(getent passwd "$user" | cut -d: -f6)/build
EOF
fi
# The package amdgpu (PATCH_AMDGPU=0) fails SMU init intermittently; see the tool header.
if grep -q '^PATCH_AMDGPU=' /etc/imac20-hwaccel.conf; then
  sed -i 's/^PATCH_AMDGPU=.*/PATCH_AMDGPU=1/' /etc/imac20-hwaccel.conf
else
  echo 'PATCH_AMDGPU=1' >> /etc/imac20-hwaccel.conf
fi

# Old hook / script names from earlier versions of this repo.
rm -f /etc/pacman.d/hooks/zz-repatch-amdgpu.hook /usr/local/sbin/repatch-amdgpu.sh
install -d /etc/pacman.d/hooks
cat > /etc/pacman.d/hooks/zz-imac20-hwaccel.hook <<'EOF'
[Trigger]
Operation = Install
Operation = Upgrade
Type = Package
Target = linux-t2
Target = linux-t2-headers

[Action]
Description = iMac20 hwaccel: rebuild the deferred-UCLK amdgpu and UKIs
When = PostTransaction
Exec = /usr/local/sbin/imac20-hwaccel hook
EOF

# amdgpu flags must NOT be in [default]: that is the safe path (and snapshots).
sed -i -e '/^# Added 2026-09-26: HW-accel flags/,/^KERNEL_CMDLINE\[default\]+=" amdgpu.modeset=1 video=efifb:off"$/d' \
       -e '/^KERNEL_CMDLINE\[default\]+=" amdgpu.modeset=1 video=efifb:off"$/d' /etc/default/limine
rm -f /etc/limine-entry-tool.d/imac20-hwaccel.conf

/usr/local/sbin/imac20-hwaccel repatch
/usr/local/sbin/imac20-hwaccel status
