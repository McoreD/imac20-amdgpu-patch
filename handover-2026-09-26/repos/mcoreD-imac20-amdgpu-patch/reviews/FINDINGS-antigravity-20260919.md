# Review of McoreD/imac20-amdgpu-patch

Reviewer: Antigravity (AI agent session 37121541)
Date:     2026-09-19
Repo SHA: 594e8b698a76cc0c313ce2b13ad186d4190b0b3f

## Summary

The repo's README accurately describes its purpose and the patch itself is
correct — it targets the right PCI IDs and sends the SMU messages in the
right order with correct error handling. However, the **scripts in the repo
are stale drafts** that diverge significantly from the scripts that were
actually executed during installation (as recorded in
`~/build/diagnostics/install.log`). Three of the five scripts have bugs
that would cause data loss, silent failure, or bloated initramfs if run
as-is. The stock module backup is compromised (it contains the patched
module). The repo is safe *because the user ran better scripts manually*,
but the scripts checked into the repo are **not safe to run**.

## The four things that matter

### 1. Patch targets the right hardware

✅ **Correct.** The four-tuple in
[`smu_v11_0.c` patch](file:///home/mike/build/linux-t2-patched/src/6001-drm-amd-pm-Fix-boot-problems-in-5300.patch#L26-L28):

| Field | Value | Matches README |
|---|---|---|
| vendor | `0x1002` (AMD) | ✅ |
| device | `0x7340` (Navi 14) | ✅ |
| subsystem_vendor | `0x106B` (Apple) | ✅ |
| subsystem_device | `0x0219` (iMac20,1/20,2) | ✅ |

The messages are sent in the correct order: `SMU_MSG_SetAllowedFeaturesMaskLow`
(`0xABC9AFBB`) first, then `SMU_MSG_SetAllowedFeaturesMaskHigh` (`0xFFFFFD42`).
Both have `if (ret) goto failed;` guards. The `return 0;` early-exits only
after both succeed, preventing the standard negotiation path from overwriting
the hardcoded masks.

### 2. Install procedure has no one-way door

⚠️ **Partially compromised — stock backup is corrupt.**

- The Limine drop-in in
  [`install-limine-hwaccel-entry.sh:11`](file:///home/mike/build/linux-t2-patched/scripts/install-limine-hwaccel-entry.sh#L11)
  correctly uses `KERNEL_CMDLINE[imac20-hwaccel]+=` (scoped, not default). ✅
- The safe entry is preserved and remains the default. ✅
- **However**: the installed backup at `/usr/lib/amdgpu-stock-backup/amdgpu.ko.zst`
  contains the patched magic constant `ABC9AFBB` (verified by binary scan at offset
  3442875 — the patched `smu_v11_0` code path is present in the backup). The backup
  was made **after** the module was already patched. Rolling back with the README's
  "4-second rollback" command would install the *patched* module, not the stock one.
  This is a **one-way door** — the original stock module is lost.

  **Root cause**: [`build-amdgpu-install.sh`](file:///home/mike/build/linux-t2-patched/scripts/build-amdgpu-install.sh)
  calls `build-amdgpu.sh` which patches and rebuilds in-tree, then checks
  `[ ! -f "$BACKUP_DIR/amdgpu.ko.zst" ]` — but the first run's install.log
  shows the magic constant check *failed* on the first attempt (the patch hadn't
  been applied yet). A second run succeeded, but by then the live module was
  already patched from a prior manual step, and the "backup once" guard
  (`[ ! -f ... ]`) saw no existing backup and copied the already-patched module.

### 3. Pacman hook handles kernel upgrade

❌ **Will silently no-op on missing patch.**

[`repatch-amdgpu.sh:9`](file:///home/mike/build/linux-t2-patched/scripts/repatch-amdgpu.sh#L9):
```bash
if ! modinfo "$MODULE_PATH" 2>/dev/null | grep -q 'ABC9AFBB\|FFFFFD42'; then
```

`modinfo` outputs text metadata (description, author, parms, etc.), not binary
module content. The strings `ABC9AFBB` and `FFFFFD42` are **compiled binary
constants** that will never appear in `modinfo` output. This means:

- `modinfo ... | grep -q 'ABC9AFBB'` → always fails (no match)
- `! ...` → always true
- The hook **rebuilds on every upgrade** regardless of whether the patch is present

This is the opposite of what AGENTS.md says ("only then rebuilds") — it always
rebuilds. That's *wasteful but not dangerous* as long as the build prerequisites
exist. But if `~/build/linux-7.2.6/` is deleted (after a kernel version bump),
the rebuild will fail loudly — which is actually the correct behavior.

**Update**: On closer inspection, the condition being always-true means it
always triggers a rebuild. This is noisy but safe. The real danger is the
inverse: if someone "fixes" this grep to work correctly, a kernel upgrade
that replaces the module *without* the patch would be silently ignored.

### 4. Build verification catches real failure modes

❌ **Uses `grep` on binary data instead of `python3 bytes.fromhex`.**

[`build-amdgpu.sh:33-34`](file:///home/mike/build/linux-t2-patched/scripts/build-amdgpu.sh#L33-L34):
```bash
grep -c 'ABC9AFBB\|FFFFFD42' \
  drivers/gpu/drm/amd/amdgpu/amdgpu.ko || { echo "FAIL: magic constants missing"; exit 3; }
```

This searches for the **ASCII strings** `ABC9AFBB` and `FFFFFD42` in the
binary `.ko` file. These constants are compiled as little-endian binary
values (`bbafc9ab` and `42fdffff`), not as ASCII text. `grep` on a binary
file will not find them reliably. AGENTS.md explicitly says:

> use Python `bytes.fromhex` to scan, **not** `strings | grep` — those
> bytes are non-printable ASCII

The install.log confirms this: the first run reported "0 occurrences" and
aborted. The working install used a different script with the correct
Python-based check.

## Seven questions

1. **Kernel bump to 7.3.0**: The patch will not apply if the file
   `smu_v11_0.c` has changed upstream. The build script's `patch --dry-run`
   will catch this and exit 2. The pacman hook will trigger the rebuild,
   which will also fail. However, there is no user notification mechanism —
   the failure is logged to pacman's output, which scrolls past during
   `pacman -Syu`. The user may not notice until the next reboot shows no
   GPU. **Finding: MINOR — add a desktop notification on hook failure.**

2. **Source tree deleted**: `build-amdgpu.sh` line 12 checks
   `test -f "$BUILD/drivers/..."` and exits with a clear error. ✅

3. **Different subsystem_device (e.g. 021A)**: The patch's `if` block
   requires an exact match on all four IDs. A different subsystem device
   falls through to the standard `smu_feature_list_is_empty` path — the
   patch is a strict no-op for non-matching hardware. ✅

4. **`pkexec` not configured**: `build-amdgpu-install.sh` says "Run with
   sudo" in the comment (line 3) but doesn't use `pkexec` at all — it
   assumes the entire script runs as root. If the user runs it without
   sudo, `install -m644` to `/lib/modules/...` will fail with EPERM and
   `set -e` will abort. **This is safe but the comment/AGENTS.md are
   misleading** — AGENTS.md says "Uses `pkexec` once" but the script
   doesn't. **Finding: MINOR — update AGENTS.md or the script.**

5. **Wrong Limine entry picked**: Worst case is black screen + reboot.
   The safe entry remains the default. No data loss path exists — the
   initramfs is the same, only the cmdline differs. ✅

6. **`loglevel=7 ignore_loglevel` and SDDM**: The installed drop-in at
   `/etc/limine-entry-tool.d/imac20-hwaccel.conf` does include
   `loglevel=7 ignore_loglevel`. This will flood the console with kernel
   messages during boot, but SDDM runs on a separate VT. Console spam on
   tty1 doesn't interfere with SDDM on tty2+. After confirming two
   successful boots, the user should remove the debug flags.
   **Finding: NIT — add a TODO comment in the drop-in.**

7. **"Rollback in 4 seconds" claim**: The rollback command includes
   `sudo limine-mkinitcpio`. The install.log shows this step took ~12
   seconds (`[20:17:21]` to `[20:17:33]`). The claim of "4 seconds" is
   inaccurate. **Finding: MINOR — update README to say "under 30 seconds".**

## Findings

### BLOCKER

- **B1: Stock module backup is corrupted** — `/usr/lib/amdgpu-stock-backup/amdgpu.ko.zst`
  contains the patched `ABC9AFBB` constant (verified at binary offset 3442875).
  It is a copy of the patched module, not the stock module. The README's "4-second
  rollback" command copies this file back, which would **not** restore the stock
  module. The user has **no rollback path** to the original unpatched `amdgpu.ko`.

  **Suggested fix**: The true stock module can be recovered from the
  `linux-t2` package: `pacman -S --noconfirm linux-t2` would reinstall
  the stock module. Save it before overwriting:
  ```bash
  sudo cp /lib/modules/$(uname -r)/kernel/drivers/gpu/drm/amd/amdgpu/amdgpu.ko.zst \
          /usr/lib/amdgpu-stock-backup/amdgpu.ko.zst
  ```
  Then re-run the build+install.

### MAJOR

- **M1: `build-amdgpu.sh` uses ASCII `grep` for binary constant check** —
  [`build-amdgpu.sh:33-34`](file:///home/mike/build/linux-t2-patched/scripts/build-amdgpu.sh#L33-L34).
  The check `grep -c 'ABC9AFBB\|FFFFFD42'` searches for ASCII text in a
  compiled ELF binary. The constants are stored as LE binary (`bbafc9ab`,
  `42fdffff`). This check will give false results. Must use the
  `python3 bytes.fromhex` approach specified in AGENTS.md.

- **M2: `build-amdgpu.sh` does not strip the module** — AGENTS.md invariant #3
  requires `strip --strip-debug` before zstd-compressing. The script goes
  directly from `make modules` to `zstd`. Without stripping, the module is
  ~161 MB instead of ~5.3 MB, bloating the initramfs.
  [`build-amdgpu.sh:42-43`](file:///home/mike/build/linux-t2-patched/scripts/build-amdgpu.sh#L42-L43)

- **M3: `build-amdgpu-install.sh` installs from wrong path** —
  [`build-amdgpu-install.sh:21`](file:///home/mike/build/linux-t2-patched/scripts/build-amdgpu-install.sh#L21)
  installs from `$BUILD/drivers/gpu/drm/amd/amdgpu/amdgpu.ko.zst`, but
  `build-amdgpu.sh` writes the compressed file to `$WORKDIR/out/amdgpu.ko.zst`
  (a temp dir that is `rm -rf`'d on exit). The install script would either
  install a stale `.ko.zst` or fail if none exists.

- **M4: `build-amdgpu-install.sh` calls `mkinitcpio -P` not `limine-mkinitcpio`** —
  [`build-amdgpu-install.sh:23`](file:///home/mike/build/linux-t2-patched/scripts/build-amdgpu-install.sh#L23).
  AGENTS.md says "Never edit `/boot/limine.conf` directly. Always use a drop-in
  … and run `limine-mkinitcpio`." `mkinitcpio -P` rebuilds the initramfs but
  does **not** rebuild the UKI or update Limine. The boot image would be stale.

### MINOR

- **m1: `repatch-amdgpu.sh` patch detection uses `modinfo | grep`** —
  [`repatch-amdgpu.sh:9`](file:///home/mike/build/linux-t2-patched/scripts/repatch-amdgpu.sh#L9).
  `modinfo` outputs text metadata, not binary content. The grep for `ABC9AFBB`
  will never match. The condition is always true, so the hook always rebuilds —
  wasteful but safe. Should use `python3 bytes.fromhex` on the decompressed module.

- **m2: `build-amdgpu.sh` patches in-tree without checking if already patched** —
  [`build-amdgpu.sh:17-19`](file:///home/mike/build/linux-t2-patched/scripts/build-amdgpu.sh#L17-L19).
  Running the script twice will fail on the second `patch -p1` because the patch
  is already applied. The `--dry-run` catches this, but the error message
  ("patch does not apply cleanly") is misleading — it should say "patch already
  applied" if that's the case. Use `patch -p1 --reverse --dry-run` to detect
  already-applied patches.

- **m3: AGENTS.md says `build-amdgpu-install.sh` "Uses `pkexec` once"** — the
  script does not use `pkexec` at all. It must be run with `sudo` directly.

- **m4: README "rollback in 4 seconds" is inaccurate** — `limine-mkinitcpio`
  takes ~12 seconds per the install log. Should say "under 30 seconds".

- **m5: Limine drop-in in repo differs from installed version** — the repo's
  [`install-limine-hwaccel-entry.sh`](file:///home/mike/build/linux-t2-patched/scripts/install-limine-hwaccel-entry.sh#L11)
  writes a minimal one-line conf, but the installed version at
  `/etc/limine-entry-tool.d/imac20-hwaccel.conf` has extensive comments and
  includes `loglevel=7 ignore_loglevel console=tty1`. The repo script would
  overwrite the improved installed version with a degraded one.

### NIT

- **n1: `build-amdgpu.sh` writes to `.localversion` file (line 20)** but also
  sets `CONFIG_LOCALVERSION` in `.config` (lines 23-24). These are redundant —
  `.localversion` is concatenated with `CONFIG_LOCALVERSION`, so the suffix
  would be doubled. Only one mechanism should be used.

## What this repo does well

1. **The patch itself is precisely scoped.** The four-ID guard ensures it only
   fires on the exact iMac20 Navi 14 hardware. Other Navi 14 boards fall through
   to the standard path with zero impact. The `goto failed` guards prevent
   half-configured SMU state.

2. **The Limine dual-entry strategy is well-designed.** Keeping the safe
   `nomodeset` entry as default means a bad hwaccel boot is always recoverable
   by rebooting and picking the other entry. This is the right pattern for
   risky driver changes.

3. **The diagnostics directory is excellent.** The audit trail in
   `~/build/diagnostics/` with pre/post snapshots, SHA256 checksums, and
   timestamped install logs is far better than typical kernel module
   install procedures. It made this review possible.
