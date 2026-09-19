#!/usr/bin/env bash
# Rebuild amdgpu.ko with the iMac20,1 SMU fix.
# Run as a normal user; only the install step needs sudo.
set -euo pipefail

BUILD=${BUILD:-"$HOME/build/linux-7.2.6"}
KREL=$(uname -r)
SRC=${SRC:-"$(dirname "$(readlink -f "$0")")/../src"}
WORKDIR=$(mktemp -d)
trap 'rm -rf "$WORKDIR"' EXIT

test -f "$BUILD/drivers/gpu/drm/amd/pm/swsmu/smu11/smu_v11_0.c" || {
  echo "error: $BUILD not a built kernel source tree"; exit 1; }

cd "$BUILD"
echo "== applying t2linux 6001 patch =="
patch -p1 --dry-run < "$SRC/6001-drm-amd-pm-Fix-boot-problems-in-5300.patch" \
  || { echo "patch does not apply cleanly"; exit 2; }
patch -p1 < "$SRC/6001-drm-amd-pm-Fix-boot-problems-in-5300.patch"
echo "-arch2-Watanare-T2-1-t2" > .localversion

echo "== ensuring CONFIG_LOCALVERSION matches =="
grep -q '^CONFIG_LOCALVERSION=""' .config && \
  sed -i 's|^CONFIG_LOCALVERSION=.*|CONFIG_LOCALVERSION="-arch2-Watanare-T2-1-t2"|' .config
grep -q '^CONFIG_LOCALVERSION_AUTO=y' .config && \
  sed -i 's|^CONFIG_LOCALVERSION_AUTO=y|# CONFIG_LOCALVERSION_AUTO is not set|' .config

echo "== rebuilding smu_v11_0.o (where the patch lives) =="
rm -f drivers/gpu/drm/amd/pm/swsmu/smu11/smu_v11_0.o
make -j"$(nproc)" M=drivers/gpu/drm/amd/amdgpu modules

echo "== verifying patch landed =="
grep -c 'ABC9AFBB\|FFFFFD42' \
  drivers/gpu/drm/amd/amdgpu/amdgpu.ko || { echo "FAIL: magic constants missing"; exit 3; }

echo "== verifying vermagic =="
modinfo -F vermagic drivers/gpu/drm/amd/amdgpu/amdgpu.ko
modinfo -F vermagic "/lib/modules/$KREL/kernel/drivers/gpu/drm/amd/amdgpu/amdgpu.ko.zst" \
  || true

mkdir -p "$WORKDIR/out"
zstd -T0 -f -o "$WORKDIR/out/amdgpu.ko.zst" \
  drivers/gpu/drm/amd/amdgpu/amdgpu.ko
echo "== built artifact =="
ls -la "$WORKDIR/out/amdgpu.ko.zst"
