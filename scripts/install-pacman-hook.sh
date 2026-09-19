#!/usr/bin/env bash
# Install the pacman hook that re-applies the patch on linux-t2 upgrades.
set -euo pipefail
HOOK=/etc/pacman.d/hooks/zz-repatch-amdgpu.hook
install -d /etc/pacman.d/hooks
cat > "$HOOK" <<'INNER'
[Trigger]
Operation = Install
Operation = Upgrade
Type = Package
Target = linux-t2

[Action]
Description = Re-apply t2linux 6001 Navi 14 SMU patch to amdgpu
When = PostTransaction
Exec = /usr/local/sbin/repatch-amdgpu.sh
INNER
install -m755 "$HOME/build/linux-t2-patched/scripts/repatch-amdgpu.sh" /usr/local/sbin/
echo "Pacman hook installed at $HOOK"
