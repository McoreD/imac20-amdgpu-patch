#!/usr/bin/env bash
# Add a HW-accel Limine boot entry that drops nomodeset.
# Keep the existing safe nomodeset entry as default.
set -euo pipefail
DROP_IN=/etc/limine-entry-tool.d/imac20-hwaccel.conf
install -d /etc/limine-entry-tool.d
cat > "$DROP_IN" <<'INNER'
# iMac20,1 Navi 14 HW-accel entry: drops nomodeset, keeps the patched amdgpu.
# The safe (nomodeset) entry remains the default; this entry is selected
# manually from the Limine menu until you have confirmed it boots twice.
KERNEL_CMDLINE[imac20-hwaccel]+=" plymouth.enable=0 amdgpu.modeset=1 video=efifb:off"
INNER
limine-mkinitcpio
echo "HW-accel Limine entry installed. Pick 'imac20-hwaccel' from the Limine menu."
echo "Boot it twice successfully, then:"
echo "  sudo sed -i 's/KERNEL_CMDLINE\\[default\\]/KERNEL_CMDLINE[imac20-hwaccel]/' $DROP_IN"
echo "  sudo limine-mkinitcpio"
