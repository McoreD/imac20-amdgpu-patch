#!/usr/bin/env bash
# One-shot, idempotent setup of the two-path (safe / hwaccel) boot on an
# iMac20,1 / iMac20,2. Run with sudo from the repo checkout:
#   sudo scripts/install.sh
#
# - installs /usr/local/sbin/imac20-hwaccel and the 6001 patch
# - installs the pacman hook (linux-t2 / linux-t2-headers upgrades)
# - moves the amdgpu flags out of Limine [default] so the normal entry is SAFE
# - builds the patched amdgpu for the newest linux-t2 and both UKIs
set -euo pipefail
[[ $EUID -eq 0 ]] || exec sudo "$0" "$@"
REPO=$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)

install -Dm755 "$REPO/scripts/imac20-hwaccel" /usr/local/sbin/imac20-hwaccel
install -Dm644 "$REPO/src/6001-drm-amd-pm-Fix-boot-problems-in-5300.patch" \
  /usr/local/share/imac20-hwaccel/6001-drm-amd-pm-Fix-boot-problems-in-5300.patch

if [[ ! -f /etc/imac20-hwaccel.conf ]]; then
  user=${SUDO_USER:-mike}
  cat > /etc/imac20-hwaccel.conf <<EOF
# Who builds the module (unprivileged) and where kernel sources live.
BUILD_USER=$user
BUILD_ROOT=$(getent passwd "$user" | cut -d: -f6)/build
EOF
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
Description = iMac20 hwaccel: re-apply t2linux 6001 amdgpu patch and rebuild UKIs
When = PostTransaction
Exec = /usr/local/sbin/imac20-hwaccel hook
EOF

# amdgpu flags must NOT be in [default]: that is the safe path (and snapshots).
sed -i -e '/^# Added 2026-09-26: HW-accel flags/,/^KERNEL_CMDLINE\[default\]+=" amdgpu.modeset=1 video=efifb:off"$/d' \
       -e '/^KERNEL_CMDLINE\[default\]+=" amdgpu.modeset=1 video=efifb:off"$/d' /etc/default/limine
rm -f /etc/limine-entry-tool.d/imac20-hwaccel.conf

/usr/local/sbin/imac20-hwaccel repatch
/usr/local/sbin/imac20-hwaccel status
