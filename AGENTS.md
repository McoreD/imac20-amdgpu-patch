# AGENTS.md — instructions for AI coding agents

## What this repo is

Downstream glue that gives an Apple iMac20,1 / iMac20,2 (Navi 14, `1002:7340`, subsystem `106b:0219`) reliable GPU acceleration on `linux-t2` (arch-mact2) with Omarchy, LUKS and Limine UKIs.
It rebuilds only `amdgpu.ko` with `src/amdgpu-defer-uclk-5300.patch`, which replaces t2linux 6001, and manages a two-entry Limine boot (hwaccel / safe).
Full methodology: `docs/PATCHING.md`. Human overview: `README.md`.

## Files

| Path | Role | Edit? |
|---|---|---|
| `src/amdgpu-defer-uclk-5300.patch` | Deferred-UCLK SMU fix (Atharva Tiwari, t2linux/wiki#743). | Only to track upstream |
| `src/6001-drm-amd-pm-Fix-boot-problems-in-5300.patch` | Verbatim t2linux 6001. Used only to **revert** it from the source tree. | No |
| `scripts/imac20-hwaccel` | The tool: `status`, `repatch`, `rebuild-uki`, `unpatch`, `disable`, `ab-*`, `hook`. Installed to `/usr/local/sbin/`. | Yes |
| `scripts/install.sh` | Idempotent installer: tool, patches, conf (`PATCH_AMDGPU=1`), pacman hook, then `repatch`. | Yes |
| `docs/PATCHING.md` | Boot paths, build method, adapting to new kernels, userspace rules. | Yes |

## Critical invariants

1. **The built module must carry the deferred-UCLK fix and not 6001.** `has_magic` checks for the string `Unable to apply late quirks` and the *absence* of the 6001 LOW constant (bytes `bb af c9 ab`, scanned with Python, not `strings`). Abort the install if this fails.
2. **Vermagic must match the target krel exactly.** The tool sets `LOCALVERSION` from the krel, disables `LOCALVERSION_AUTO` and checks `make kernelrelease`.
3. **Install only to `/usr/lib/modules/<krel>/updates/`.** Never overwrite the package module under `kernel/`.
4. **The safe entry must always boot without amdgpu** (`nomodeset modprobe.blacklist=amdgpu`), including snapshot entries.
5. **The pacman hook must never fail the transaction.** On failure it removes the hwaccel entry.

## Safety expectations

- **Never** push to `arch-mact2/linux-t2` or `t2linux/*`. This repo is downstream.
- **Never** edit `/boot/limine.conf` by hand except through the tool; cmdline changes go through `/etc/limine-entry-tool.d/` + `limine-mkinitcpio`.
- **Never** signal, restart or kill the session bus (`dbus-broker`, `dbus-broker-launch --scope user`), `uwsm`, Hyprland or `systemd --user` on this machine. On 2026-09-27 an agent's `kill -USR1 <session dbus-broker>` ended the whole desktop session. Test D-Bus activation with `dbus-run-session`.
- Use `pkexec` for root (sudo needs a TTY password). Batch root steps into one call.

## Common tasks

| Task | What to do |
|---|---|
| Install / reinstall | `pkexec scripts/install.sh` |
| Rebuild after a kernel upgrade | Automatic (pacman hook); manual: `sudo imac20-hwaccel repatch` |
| Check state | `sudo imac20-hwaccel status` |
| Verify HW acceleration | `journalctl -k -b \| grep 'SMU is initialized'`, `grep DPM_UCLK /sys/bus/pci/devices/0000:03:00.0/pp_features`, `vulkaninfo --summary` |
| Logs from a failed hwaccel boot | Boot the safe entry, then `journalctl -b -1 -k \| grep -E 'amdgpu 0000:03'` |
| Retire the rebuild once linux-t2 ships the fix | Set `PATCH_AMDGPU=0` in `/etc/imac20-hwaccel.conf`, run `sudo imac20-hwaccel unpatch` |
