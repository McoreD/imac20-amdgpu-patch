#!/usr/bin/env bash
# Add a HW-accel Limine boot entry that drops nomodeset.
# Keep the existing safe nomodeset entry as default.
set -euo pipefail
DROP_IN=/etc/limine-entry-tool.d/imac20-hwaccel.conf
install -d /etc/limine-entry-tool.d

# Only write the drop-in if it doesn't already exist (preserve manual edits)
if [ -f "$DROP_IN" ]; then
  echo "== $DROP_IN already exists, not overwriting =="
  echo "   To regenerate, remove it first: sudo rm $DROP_IN"
else
  cat > "$DROP_IN" <<'INNER'
# iMac20,1 / iMac20,2 (2020 27" 5K, Navi 14) HW-accel entry.
#
# Safe entry (default) keeps plymouth.enable=0 nomodeset and the stock amdgpu.
# This entry drops nomodeset and uses the patched amdgpu.ko (with the
# t2linux 6001 SMU init fix baked in). The patched module is currently
# installed at /lib/modules/$(uname -r)/.../amdgpu.ko.zst and the pacman
# hook re-applies the patch after every linux-t2 upgrade.
#
# Debug flags:
#   plymouth.enable=0   no Plymouth splash hiding messages
#   loglevel=7          print every kernel message to console
#   ignore_loglevel     printk without loglevel prefix also visible
#   console=tty1        console on TTY1 (default but explicit)
#   amdgpu.modeset=1    per-module override in case global KMS is off
#   video=efifb:off     release the EFI framebuffer so amdgpu can take over
#
# TODO: After two successful hwaccel boots, remove loglevel=7 and
# ignore_loglevel to reduce console spam during boot.
#
# If the panel goes black on this entry, reboot into the safe entry and run:
#   sudo journalctl -b -1 --no-pager | grep -iE 'amdgpu|smu|dpm' | tail -100
KERNEL_CMDLINE[imac20-hwaccel]+=" plymouth.enable=0 loglevel=7 ignore_loglevel console=tty1 amdgpu.modeset=1 video=efifb:off"
INNER
  echo "HW-accel Limine drop-in written to $DROP_IN"
fi

limine-mkinitcpio
echo "HW-accel Limine entry installed. Pick 'imac20-hwaccel' from the Limine menu."
echo "Boot it twice successfully, then:"
echo "  sudo sed -i 's/KERNEL_CMDLINE\\[default\\]/KERNEL_CMDLINE[imac20-hwaccel]/' $DROP_IN"
echo "  sudo limine-mkinitcpio"
