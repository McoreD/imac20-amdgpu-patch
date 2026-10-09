# iMac20,1 hardware acceleration: boot paths, patching and recovery

Machine: Apple iMac20,1 (2020 27" 5K, T2), Radeon Pro 5500 XT (Navi 14, `1002:7340`, subsystem `106B:0219`).
OS: Omarchy (Arch) + `linux-t2` (arch-mact2), LUKS + btrfs, Limine with UKIs.
Last verified: 2026-09-27 on `7.2.6-arch2-Watanare-T2-4-t2`.

Canonical code: <https://github.com/McoreD/imac20-amdgpu-patch> (`/home/mike/Projects/McoreD/imac20-amdgpu-patch`).
This folder has the knowledge and a snapshot of the tool (`imac20-hwaccel`).

---

## 1. The two boot paths

| Limine entry | Kernel cmdline adds | GPU | Use it when |
|---|---|---|---|
| **imac20-hwaccel** (default) | `amdgpu.modeset=1 video=efifb:off` | rebuilt `amdgpu` with the deferred-UCLK fix: radeonsi GL, RADV Vulkan | normal use |
| **Omarchy › linux-t2** (and every snapshot entry) | `nomodeset modprobe.blacklist=amdgpu` | none: `simpledrm` firmware framebuffer, software rendering | hwaccel broken (black panel, crash loop) or repatching |

- Both are UKIs in `/boot/EFI/Linux/`: `omarchy_linux-t2.efi` (safe) and `omarchy_linux-t2-hwaccel.efi`.
  Each carries its own embedded `.cmdline`. Secure Boot is off.
- The safe path never loads amdgpu, so it works even when the module is stock, missing or mismatched.
  It ran for days on this machine before hwaccel existed.
- Snapshot entries (limine-snapper-sync) use the safe cmdline, so a rollback never depends on the patch.

### Recovery when hwaccel breaks
1. Reboot. In the Limine menu pick **Omarchy › linux-t2** (safe).
2. Log in, open a terminal: `sudo imac20-hwaccel status` then `sudo imac20-hwaccel repatch`.
3. Reboot into **imac20-hwaccel** (it's the default again after a successful repatch).

If `repatch` fails, see §4 ("Adapting to a new kernel").

---

## 2. Why a patch is needed at all

Stock `amdgpu` can't reliably finish SMU (System Management Unit) init on the iMac20's Navi 14 (Apple subsystem `106B:0219`). When it fails, the panel stays dark:

```
amdgpu 0000:03:00.0: SMU: No response msg_reg: 6 resp_reg: 0
amdgpu 0000:03:00.0: Failed to enable requested dpm features!
amdgpu 0000:03:00.0: hw_init of IP block <smu> failed -62
```

Message `6` is `EnableAllSmuFeatures`.
[t2linux/wiki#743](https://github.com/t2linux/wiki/issues/743) bisected the feature mask one bit at a time and isolated the hang to **`FEATURE_DPM_UCLK` (LOW bit 3, `0x08`)**: with it in the initial enable, init fails intermittently (10/10 failures in that bit test). Enabled after init, it works.

- `linux-t2` ships t2linux `6001-drm-amd-pm-Fix-boot-problems-in-5300.patch`, which hardcodes the macOS feature masks (`0xABC9AFBB` / `0xFFFFFD42`). Those still include UCLK, so the package module fails **intermittently**.
  On this machine it booted fine for a day (cold boots and some warm reboots), then failed on two warm reboots in a row on 2026-09-27. Yesterday's "patched module did not reach the desktop" A/B result was very likely the same intermittent failure, not a bad build.
- The fix used here is `src/amdgpu-defer-uclk-5300.patch` (Atharva Tiwari, from wiki#743; passed 10/10 boots on an iMac20,1 `0219`; sent to amd-gfx 2026-09-15). It **replaces** 6001:
  UCLK is left out of the allowed features at init (`navi10_init_allowed_features`), then turned on in `smu_late_init` via `smu_set_pp_feature_mask`, so memory clocks still scale (no MCLK-stuck-at-0 performance loss).
- Identify a correctly built module by the string `Unable to apply late quirks` being present **and** the 6001 LOW constant (bytes `bb af c9 ab`) being absent. That is what `has_magic` checks.
- Evidence of success in `journalctl -k`: `SMU is initialized successfully!`, then `Display Core ... initialized`. Check UCLK afterwards with `cat /sys/bus/pci/devices/0000:03:00.0/pp_features | grep DPM_UCLK` (should say `enabled`).
  Two `Fence fallback timer expired on ring sdma0` lines during init are normal on this machine.

Only `amdgpu.ko` is rebuilt, not the whole kernel.
When `linux-t2` itself carries a deferred-UCLK fix (watch t2linux/linux-t2-patches), set `PATCH_AMDGPU=0` and run `sudo imac20-hwaccel unpatch`.

---

## 3. Patching methodology (what `imac20-hwaccel repatch` does)

The tool automates all of this; do it by hand only when adapting (§4).

1. **Pick the target kernel.** Use the newest `/usr/lib/modules/<krel>/` whose `pkgbase` is `linux-t2`.
   Never `uname -r`: in a pacman hook the running kernel is the *old* one.
2. **Get matching source.** krel `7.2.6-arch2-Watanare-T2-4-t2` → base `7.2.6`, localversion `-arch2-Watanare-T2-4-t2`.
   The vanilla kernel.org tarball `linux-7.2.6.tar.xz` goes into `~/build/linux-7.2.6/`. For an `X.Y.0` kernel the tarball is `linux-X.Y`.
   Vanilla source is enough because neither Arch nor the T2 patchset changes the amdgpu internals this module depends on. The vermagic check below guards the ABI.
3. **Revert 6001 if the tree has it, then apply the deferred-UCLK patch** (`patch -p1`; each step is skipped when a dry-run shows it is already done).
4. **Match the running build exactly.** Copy `.config` and `Module.symvers` from `/usr/lib/modules/<krel>/build/` (the `linux-t2-headers` package).
   Then set `CONFIG_LOCALVERSION=<localversion>`, turn `LOCALVERSION_AUTO` off, and run `make olddefconfig && make modules_prepare`.
   `make kernelrelease` must print the exact krel. `CONFIG_MODVERSIONS` is off on this kernel, so vermagic is the ABI gate.
5. **Build only amdgpu:** `make M=drivers/gpu/drm/amd/amdgpu modules`. This takes 1–2 min on a tree that was built before, longer from scratch.
6. **Verify before installing.** `modinfo -F vermagic` must start with `<krel> `, the deferred-UCLK string must be present and the 6001 constant absent. Abort if either fails.
7. **Strip and compress:** `strip --strip-debug` (161 MB → ~6 MB), then `zstd`.
8. **Install to `/usr/lib/modules/<krel>/updates/amdgpu.ko.zst`, then `depmod -a <krel>`.**
   `updates/` wins over `kernel/` (depmod `search updates extramodules built-in`) and isn't owned by the linux-t2 package.
   So pacman never flags it, and the stock module stays in `kernel/` untouched.
   `modinfo -k <krel> -n amdgpu` must resolve to the `updates/` path.
9. **Rebuild both UKIs.** Omarchy's `limine-mkinitcpio` can't build a UKI per cmdline profile, so the tool:
   - writes the managed drop-in `/etc/limine-entry-tool.d/imac20-gpu-mode.conf` with the HWA flags,
   - runs `limine-mkinitcpio`, copies `omarchy_linux-t2.efi` → `omarchy_linux-t2-hwaccel.efi`,
   - restores the drop-in to the SAFE flags (a trap guarantees this even on failure) and runs `limine-mkinitcpio` again,
   - checks each UKI's embedded `.cmdline` (`objcopy -O binary --only-section=.cmdline`),
   - registers the entry: `limine-entry-tool --add-efi imac20-hwaccel <uki> --overwrite`,
   - sets `default_entry: imac20-hwaccel` (the entry name; Limine matches by name/path) in `/boot/limine.conf`.

**Automation:** `/etc/pacman.d/hooks/zz-imac20-hwaccel.hook` runs `imac20-hwaccel hook` after any `linux-t2` / `linux-t2-headers` install or upgrade.
If anything fails, the hook **removes the hwaccel entry** and prints a banner, so the next boot uses the safe path instead of a black panel. It never fails the pacman transaction.
State: `/var/lib/imac20-hwaccel/status`.

### Files it owns
| Path | What |
|---|---|
| `/usr/local/sbin/imac20-hwaccel` | the tool (`status`, `repatch [krel]`, `rebuild-uki`, `disable`, `hook`) |
| `/usr/local/share/imac20-hwaccel/6001-…patch` | the patch |
| `/etc/imac20-hwaccel.conf` | `BUILD_USER=mike`, `BUILD_ROOT=/home/mike/build` (builds run unprivileged) |
| `/etc/limine-entry-tool.d/imac20-gpu-mode.conf` | managed; always the SAFE flags at rest |
| `/etc/pacman.d/hooks/zz-imac20-hwaccel.hook` | pacman trigger |
| `/usr/lib/modules/<krel>/updates/amdgpu.ko.zst` | the patched module |

Install or reinstall everything from the repo: `sudo scripts/install.sh` (idempotent).

---

### Optional test entry
To try someone else's amdgpu patch without touching the hwaccel entry, set this in `/etc/imac20-hwaccel.conf`:
```bash
TEST_ENTRY_NAME=imac20-5k-test
TEST_ENTRY_PATCHES=(/usr/local/share/imac20-hwaccel/6001-drm-amd-pm-Fix-boot-problems-in-5300.patch /path/to/their.patch)
```
`sudo imac20-hwaccel test-entry` builds amdgpu from the same vanilla tree with those patches applied in order, in place of the deferred-UCLK patch. It overlays that module into a copy of the hwaccel UKI and adds it as a non-default Limine entry.
The pacman hook rebuilds it after each `linux-t2` upgrade. If that fails, the hook removes only the test entry; the hwaccel entry is never affected.
The patches stay wherever the conf points, so a patch whose author hasn't allowed redistribution never enters this repo.
Overlay detail: the UKI initrd ends in a compressed segment, so the appended archive is zero-padded to a 4-byte boundary. Without that, the kernel logs `Initramfs unpacking failed: invalid magic` and silently boots the base module.

## 4. Adapting to a new kernel (when `repatch` fails)

Check `sudo imac20-hwaccel repatch` output for which step failed:

- **"linux-t2-headers for … not installed"**: `sudo pacman -S linux-t2-headers` (it must match `linux-t2`).
- **Download failed**: no network in the hook, or the kernel.org path changed. Put the tarball in `~/build/` and extract it yourself, then rerun.
- **"6001 patch does not apply"**: upstream code moved. Check <https://github.com/t2linux/linux-t2-patches> for a refreshed `6001-*.patch`.
  Copy it to the repo `src/`, rerun `sudo scripts/install.sh`, and commit.
  If t2linux dropped it because it was merged upstream, `grep -n 0xABC9AFBB drivers/gpu/drm/amd/pm/swsmu/smu11/smu_v11_0.c` in the new source.
  If it's there, the stock module already works and the tool isn't needed.
- **"kernelrelease X != krel"**: the localversion scheme changed. Compare `make kernelrelease` with `ls /usr/lib/modules`.
- **"vermagic mismatch"**: same cause as above, or a compiler mismatch. Build with the gcc that built the kernel (`cat /proc/version`).
- **Build errors in amdgpu**: vanilla source no longer matches what arch-mact2 ships. Use their source instead
  (<https://github.com/t2linux/linux-t2-arch>, apply their patch series), then point `BUILD_ROOT` at it.

Manual build (same steps, for debugging):
```bash
K=7.2.6-arch2-Watanare-T2-4-t2; cd ~/build/linux-7.2.6
patch -p1 < /usr/local/share/imac20-hwaccel/6001-drm-amd-pm-Fix-boot-problems-in-5300.patch
cp /usr/lib/modules/$K/build/{.config,Module.symvers} .
scripts/config --set-str LOCALVERSION "${K#7.2.6}" --disable LOCALVERSION_AUTO
make olddefconfig && make modules_prepare && make kernelrelease   # must print $K
make -j$(nproc) M=drivers/gpu/drm/amd/amdgpu modules
modinfo -F vermagic drivers/gpu/drm/amd/amdgpu/amdgpu.ko
```

---

## 5. Userspace rules (Hyprland / Omarchy)

- **Never set `AQ_DRM_DEVICES`.** The GPU is `card0` in safe mode (simpledrm) and `card1` in hwaccel mode.
  A stale `card0` pin caused all of the 2026-09-26 "CBackend::create() failed" crashes. With one GPU, aquamarine picks it on its own.
- **Never force llvmpipe** (`LIBGL_ALWAYS_SOFTWARE`, `MESA_LOADER_DRIVER_OVERRIDE`) in `/etc/environment` or `~/.config/hypr`.
  Safe mode already falls back to software rendering because there's no render node. Forcing it in hwaccel mode made Hyprland SEGV in llvmpipe JIT every 10–15 min.
- `linger` is enabled for mike, so the systemd user manager survives logouts.
  Env changes that came from PAM (`/etc/environment`) only fully clear after a reboot. Until then, override them with `dbus-update-activation-environment --systemd VAR=...`.
- **Agents must never signal the session bus** (`dbus-broker` / `dbus-broker-launch --scope user`). On 2026-09-27 an agent sent `kill -USR1` to it to "reload" service files. dbus-broker has no USR1 handler, so it exited, uwsm lost the bus and the whole desktop session ended ("the iMac froze"). Reload is `busctl --user call org.freedesktop.DBus / org.freedesktop.DBus ReloadConfig`; test activation on a private bus with `dbus-run-session`.
- Crash triage order: `~/.cache/hyprland/hyprlandCrashReport<pid>.txt` (it has a log tail) → `journalctl --user -u wayland-wm@hyprland.desktop` → `coredumpctl info <pid>`.
  A `CAsyncResourceGatherer::asyncAssetSpinLock` thread in `pthread_cond_clockwait` is normal idle and not a deadlock.

- `~/.config/hypr/hyprland.lua` is the **stock Omarchy template** (`require("default.hypr.omarchy")` + personal files). The earlier "Option A" config that skipped Omarchy defaults came from the false deadlock theory; don't bring it back. Validate changes with `Hyprland --verify-config -c ~/.config/hypr/hyprland.lua` and `hyprctl configerrors`.

## 6. Answered: yes, the rebuild is needed (2026-09-27)

The package module (6001 only) booted on 2026-09-26, then failed SMU init on two consecutive warm reboots on 2026-09-27 with the same `msg_reg: 6` timeout.
Both boots were identical up to `EnableAllSmuFeatures`, which rules out flags and the UKI. The cause is the UCLK-at-init race described in §2, so hwaccel now uses the deferred-UCLK rebuild (`PATCH_AMDGPU=1`).
The `ab-test` / `ab-result` / `ab-clean` commands remain for comparing modules on future kernels.

Quick health check in hwaccel mode:
```bash
sudo imac20-hwaccel status
vulkaninfo --summary | grep deviceName      # AMD Radeon Graphics (RADV NAVI14)
grep -c llvmpipe /proc/$(pgrep -x Hyprland)/task/*/comm | grep -v ':0'   # should print nothing
```

History and root-cause analysis: `~/Work/imac20-amdgpu-handover-2026-09-26/20260926-imac20-amdgpu-hwaccel-postmortem.md` (see the Addendum).
