#!/usr/bin/env bash
# Rebuild amdgpu.ko with the iMac20,1 SMU fix.
# Run as a normal user; only the install step needs sudo.
set -euo pipefail

BUILD=${BUILD:-"$HOME/build/linux-7.2.6"}
KREL=$(uname -r)
SRC=${SRC:-"$(dirname "$(readlink -f "$0")")/../src"}
PATCH="$SRC/6001-drm-amd-pm-Fix-boot-problems-in-5300.patch"
MODULE="drivers/gpu/drm/amd/amdgpu/amdgpu.ko"

test -f "$BUILD/drivers/gpu/drm/amd/pm/swsmu/smu11/smu_v11_0.c" || {
  echo "error: $BUILD not a built kernel source tree"; exit 1; }

cd "$BUILD"

# Apply patch (skip if already applied)
if patch -p1 --reverse --dry-run < "$PATCH" >/dev/null 2>&1; then
  echo "== patch already applied, skipping =="
elif patch -p1 --dry-run < "$PATCH" >/dev/null 2>&1; then
  echo "== applying t2linux 6001 patch =="
  patch -p1 < "$PATCH"
else
  echo "error: patch does not apply cleanly (and is not already applied)"
  exit 2
fi

echo "== ensuring CONFIG_LOCALVERSION matches =="
sed -i 's|^CONFIG_LOCALVERSION=.*|CONFIG_LOCALVERSION="-arch2-Watanare-T2-1-t2"|' .config
grep -q '^CONFIG_LOCALVERSION_AUTO=y' .config && \
  sed -i 's|^CONFIG_LOCALVERSION_AUTO=y|# CONFIG_LOCALVERSION_AUTO is not set|' .config

echo "== rebuilding smu_v11_0.o (where the patch lives) =="
rm -f drivers/gpu/drm/amd/pm/swsmu/smu11/smu_v11_0.o
make -j"$(nproc)" M=drivers/gpu/drm/amd/amdgpu modules

echo "== verifying patch landed (binary scan) =="
python3 -c "
d = open('$MODULE', 'rb').read()
low = d.count(bytes.fromhex('bbafc9ab'))
high = d.count(bytes.fromhex('42fdffff'))
if low < 1:
    raise SystemExit('FAIL: ABC9AFBB (LE bbafc9ab) not found in $MODULE')
if high < 1:
    raise SystemExit('FAIL: FFFFFD42 (LE 42fdffff) not found in $MODULE')
print(f'OK: ABC9AFBB={low}, FFFFFD42={high}')
"

echo "== verifying vermagic =="
PATCHED_VM=$(modinfo -F vermagic "$MODULE")
echo "  patched: $PATCHED_VM"
LIVE_VM=$(modinfo -F vermagic "/lib/modules/$KREL/kernel/drivers/gpu/drm/amd/amdgpu/amdgpu.ko.zst" 2>/dev/null || true)
echo "  live:    $LIVE_VM"

echo "== stripping debug symbols =="
strip --strip-debug "$MODULE"
ls -la "$MODULE"

echo "== compressing =="
OUTDIR=$(mktemp -d)
trap 'rm -rf "$OUTDIR"' EXIT
zstd -T0 -f -o "$OUTDIR/amdgpu.ko.zst" "$MODULE"
echo "== built artifact =="
ls -la "$OUTDIR/amdgpu.ko.zst"
sha256sum "$OUTDIR/amdgpu.ko.zst"

# Export path for install script to pick up
echo "$OUTDIR/amdgpu.ko.zst"
