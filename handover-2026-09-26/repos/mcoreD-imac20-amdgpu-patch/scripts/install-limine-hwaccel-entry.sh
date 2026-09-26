#!/usr/bin/env bash
# Add a HW-accel Limine boot entry that drops nomodeset, and put the
# KMS-required flags into /etc/default/limine [default] so EVERY entry
# (including the existing safe one) gets real amdgpu KMS.
#
# Why split the cmdline:
#   The safe entry used to be the "no amdgpu" fallback. In practice the
#   user always picks the hwaccel entry, and even the safe entry needs
#   `amdgpu.modeset=1 video=efifb:off` to bind the patched module properly
#   (without them, amdgpu falls back to simpledrm and EGL enumeration
#   silently breaks). So the essential flags live in [default], and the
#   hwaccel entry adds nothing extra beyond the plymouth disable.
set -euo pipefail
DROP_IN=/etc/limine-entry-tool.d/imac20-hwaccel.conf
DEFAULT_LIMINE=/etc/default/limine
install -d /etc/limine-entry-tool.d

# 1. Ensure the KMS-required flags are in /etc/default/limine [default].
#    These are needed regardless of which Limine entry the user picks.
if ! grep -q 'amdgpu.modeset=1' "$DEFAULT_LIMINE" 2>/dev/null; then
  echo "== adding amdgpu.modeset=1 video=efifb:off to /etc/default/limine [default] =="
  # Insert before the last uncommented line so the resulting order stays
  # sane. We append a single new line rather than rewriting the file.
  printf '\nKERNEL_CMDLINE[default]+=" amdgpu.modeset=1 video=efifb:off"\n' \
    >> "$DEFAULT_LIMINE"
else
  echo "== amdgpu.modeset=1 already present in /etc/default/limine =="
fi

# 2. Write the hwaccel drop-in (idempotent — only if missing).
if [ -f "$DROP_IN" ]; then
  echo "== $DROP_IN already exists, not overwriting =="
  echo "   To regenerate, remove it first: sudo rm $DROP_IN"
else
  cat > "$DROP_IN" <<'INNER'
# iMac20,1 / iMac20,2 (2020 27" 5K, Navi 14) HW-accel entry.
#
# This entry uses the patched amdgpu.ko (with the t2linux 6001 SMU init
# fix baked in). The patched module is at
# /lib/modules/$(uname -r)/.../amdgpu.ko.zst and the pacman hook re-applies
# the patch after every linux-t2 upgrade.
#
# Essential KMS flags (amdgpu.modeset=1, video=efifb:off) are inherited
# from /etc/default/limine [default], so this entry only needs the plymouth
# disable (already in [default] too, but adding it here keeps this entry
# self-contained if someone trims [default] later).
#
# If the panel goes black on this entry, reboot into the safe entry and run:
#   sudo journalctl -b -1 --no-pager | grep -iE 'amdgpu|smu|dpm' | tail -100
KERNEL_CMDLINE[imac20-hwaccel]+=" plymouth.enable=0"
INNER
  echo "HW-accel Limine drop-in written to $DROP_IN"
fi

limine-mkinitcpio
echo "HW-accel Limine entry installed. Pick 'imac20-hwaccel' from the Limine menu."
echo "The essential KMS flags now live in /etc/default/limine [default],"
echo "so any Limine entry you pick will get real amdgpu KMS."
