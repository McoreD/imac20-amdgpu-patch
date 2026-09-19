# AGENTS.md — instructions for AI coding agents

## What this repo is

A small repo that holds one upstream patch (verbatim from
`t2linux/linux-t2-patches`) plus five shell scripts that turn it into a
working `amdgpu.ko.zst` for an Apple iMac20,1 / iMac20,2 running
`linux-t2 7.2.6.arch2-1` (Watanare build). The scripts assume:

- `/home/mike/build/linux-7.2.6/` is a built (but not necessarily
  installed) Linux 7.2.6 source tree with `.config` from
  `zcat /proc/config.gz` and the 6001 patch applied
- The user has `linux-t2` from the `arch-mact2` repo, with LUKS + Limine
- `bc`, `make`, `gcc`, `python3`, `zstd` are installed
- `pkexec` works without a TTY (use it for one-shot `sudo`)

## Files

| Path | Role | Edit? |
|---|---|---|
| `src/6001-drm-amd-pm-Fix-boot-problems-in-5300.patch` | Verbatim upstream patch. Do not edit. | **No** — refresh from upstream if it changes |
| `scripts/build-amdgpu.sh` | Rebuild only `amdgpu.ko` from a source tree. Idempotent, no install. | Yes, but keep it standalone (no `sudo`) |
| `scripts/build-amdgpu-install.sh` | Rebuild + backup stock + install + `depmod -a` + `limine-mkinitcpio`. Run with `sudo`. Backs up the stock module **before** rebuilding so the backup is always the unpatched version. | Yes |
| `scripts/repatch-amdgpu.sh` | Invoked by the pacman hook after `pacman -Syu linux-t2`. Re-runs the build if the magic constants are missing from the installed module. | Yes |
| `scripts/install-pacman-hook.sh` | Writes `/etc/pacman.d/hooks/zz-repatch-amdgpu.hook` and copies `repatch-amdgpu.sh` into `/usr/local/sbin/`. | Yes |
| `scripts/install-limine-hwaccel-entry.sh` | Writes `/etc/limine-entry-tool.d/imac20-hwaccel.conf` and runs `limine-mkinitcpio`. The safe entry stays the default. | Yes |
| `README.md` | Human-facing intent + quick-start. | Yes |
| `AGENTS.md` | This file. | Yes |

## Critical invariants

If you change anything, preserve these:

1. **Magic constants must remain in the built module.** Before any install,
   the build script must verify `0xABC9AFBB` and `0xFFFFFD42` appear in the
   compiled `amdgpu.ko` (use Python `bytes.fromhex` to scan, **not**
   `strings | grep` — those bytes are non-printable ASCII). If the check
   fails, abort; do not install.
2. **Vermagic must match the running kernel.** Required:
   `7.2.6-arch2-Watanare-T2-1-t2 SMP preempt mod_unload`. Set
   `CONFIG_LOCALVERSION="-arch2-Watanare-T2-1-t2"` in `.config` and
   `CONFIG_LOCALVERSION_AUTO` disabled. After changing `CONFIG_LOCALVERSION`,
   run `make prepare0` to regenerate `include/config/kernel.release` before
   rebuilding.
3. **Strip the module before install.** Use `strip --strip-debug` on the
   built `amdgpu.ko` before zstd-compressing. Without this, the patched
   module is 161 MB (vs 5.3 MB stripped) and bloats the initramfs.
4. **Backup the stock module before overwriting.** Copy to
   `/usr/lib/amdgpu-stock-backup/amdgpu.ko.zst` exactly once. Subsequent
   installs are no-ops on the backup step (check for existing file).
5. **The Limine safe entry stays the default.** The hwaccel entry is a
   separate boot menu item. Only flip the default after the user has
   booted the hwaccel entry twice without issue, and only by editing
   `/etc/limine-entry-tool.d/imac20-hwaccel.conf` (replace
   `KERNEL_CMDLINE[imac20-hwaccel]` with `KERNEL_CMDLINE[default]`).

## Build verification

Run after any change to scripts or build flow:

```bash
# 1. Confirm vermagic
modinfo -F vermagic /home/mike/build/linux-7.2.6/drivers/gpu/drm/amd/amdgpu/amdgpu.ko
# must equal: 7.2.6-arch2-Watanare-T2-1-t2 SMP preempt mod_unload

# 2. Confirm magic constants
python3 -c "
d = open('/home/mike/build/linux-7.2.6/drivers/gpu/drm/amd/amdgpu/amdgpu.ko', 'rb').read()
assert d.count(bytes.fromhex('bbafc9ab')) >= 1, 'ABC9AFBB missing'
assert d.count(bytes.fromhex('42fdffff')) >= 1, 'FFFFFD42 missing'
print('OK')
"
```

## Safety expectations

- **Never** push to `arch-mact2/linux-t2` or `t2linux/linux-t2-patches` —
  those are upstream repos. This repo is a downstream consumer.
- **Never** run `pacman -Syu linux-t2` without verifying the patched module
  survives. The pacman hook will rebuild it, but only if the build
  prerequisites (`bc`, source tree, etc.) are still present.
- **Never** edit `/boot/limine.conf` directly. Always use a drop-in under
  `/etc/limine-entry-tool.d/` and run `limine-mkinitcpio`.
- **Always** read `/home/mike/build/diagnostics/README.md` and
  `/home/mike/build/diagnostics/install.log` before making changes —
  they contain the audit trail of what is installed and why.
- **Always** test with the safe Limine entry first after any change.
  If unsure whether a change is safe, ask before running
  `scripts/install-limine-hwaccel-entry.sh`.

## Common tasks

| Task | What to do |
|---|---|
| Update the patch from upstream | `curl -sL https://github.com/t2linux/linux-t2-patches/raw/main/6001-drm-amd-pm-Fix-boot-problems-in-5300.patch > src/6001-drm-amd-pm-Fix-boot-problems-in-5300.patch`; verify diff is sane; commit |
| Rebuild after a kernel upgrade | Run `scripts/build-amdgpu-install.sh` (the pacman hook also does this, but the script is the manual entry point) |
| Roll back to the stock module | `sudo cp /usr/lib/amdgpu-stock-backup/amdgpu.ko.zst /lib/modules/$(uname -r)/kernel/drivers/gpu/drm/amd/amdgpu/amdgpu.ko.zst && sudo depmod -a && sudo limine-mkinitcpio && sudo reboot` |
| Verify HW acceleration is live | `lsmod \| grep amdgpu` (refcount > 0), `ls /dev/dri/` (`renderD128` exists), `vulkaninfo --summary`, `mpv --vo=gpu file.mp4` |
| Get last hwaccel-boot logs if it hangs | Boot the safe entry, then `sudo journalctl -b -1 --no-pager \| grep -iE 'amdgpu\|smu\|dpm' \| tail -200` |
