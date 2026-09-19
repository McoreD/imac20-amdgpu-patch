# Review instructions

This file tells an AI coding agent (or a human reviewer) how to do a
**focused, useful review** of this repo — not just a once-over.

README.md and AGENTS.md give context and usage instructions. This file
gives you a review brief: **what to look at, what risks to focus on, what
not to bikeshed, and how to report**.

## Pre-read (in this order)

1. `README.md` — what this is and why (5 min)
2. `AGENTS.md` — file inventory and the critical invariants (10 min)
3. `src/6001-drm-amd-pm-Fix-boot-problems-in-5300.patch` — the patch itself,
   line by line (10 min)
4. `scripts/*.sh` — every script, in execution order:
   `build-amdgpu.sh` → `build-amdgpu-install.sh` → `install-pacman-hook.sh` →
   `install-limine-hwaccel-entry.sh` (20 min)
5. *(optional, for context)* the install audit trail in
   `~/build/diagnostics/install.log` and `~/build/diagnostics/post-install/summary.txt`

Total: ~45 minutes of reading before you write a single finding.

## The four things that matter

These are the only things that would change whether this repo is **safe to
use right now**. Focus your effort here.

### 1. Does the patch target the right hardware?

Read `src/6001-drm-amd-pm-Fix-boot-problems-in-5300.patch`. Confirm:

- The four-tuple in the `if` (vendor, device, subsystem vendor, subsystem
  device) matches the README's claim of "Apple iMac20,1 / iMac20,2 5K
  Navi 14". Reference: `lspci -vvs 03:00.0 | grep -iE 'vendor|device'`
  on the actual target hardware.
- The two magic constants (`0xABC9AFBB` and `0xFFFFFD42`) are sent via the
  right SMU messages (`SMU_MSG_SetAllowedFeaturesMaskLow` and `High`).
  If they were swapped, the patch would be a no-op or actively break
  things.
- The early `return 0;` is reached only after both messages succeed.
  A wrong order or missing `goto failed` would silently leave the SMU in a
  half-configured state.

### 2. Does the install procedure have a one-way door?

The plan deliberately keeps the safe Limine entry as default so the user
can always reboot into the stock module. Verify:

- `scripts/build-amdgpu-install.sh` does **not** remove the safe entry
- The Limine drop-in in `scripts/install-limine-hwaccel-entry.sh` uses
  `KERNEL_CMDLINE[imac20-hwaccel]+=` (additive, scoped to the new entry)
  not `KERNEL_CMDLINE[default]+=` (would change the default's cmdline)
- The stock backup at `/usr/lib/amdgpu-stock-backup/amdgpu.ko.zst` is
  written **before** the live module is overwritten
- `depmod -a` and `limine-mkinitcpio` run only after the live module is
  in place, so a partially-installed state is still bootable

Read these four lines of code and confirm. If any of them is wrong, the
install is a one-way door and the repo is unsafe to use.

### 3. Does the pacman hook handle a kernel upgrade correctly?

`scripts/repatch-amdgpu.sh` is invoked after every `pacman -Syu linux-t2`.
Verify:

- It detects when the patch is missing (`grep -q ABC9AFBB` or similar) and
  only then rebuilds. A rebuild on every upgrade is wasteful but harmless;
  no rebuild on missing patch is dangerous.
- It uses the right source tree path. If `~/build/linux-7.2.6/` no longer
  exists (after a major version bump), it should fail loudly with a
  useful error, not silently no-op.
- It re-runs `depmod -a` and `limine-mkinitcpio` after installing the
  patched module, so the boot image is consistent.

### 4. Does the build verification actually catch failure modes?

The build script's pre-install check verifies two things: vermagic match
and magic constants present. Verify:

- The vermagic check would catch a mismatch if the user accidentally
  built against a different `.config` or different kernel headers.
- The magic-constant check actually finds the right bytes. The patch's
  LE-encoded constants are non-printable ASCII, so a `strings | grep`
  check would silently pass on a build that didn't apply the patch. The
  build script uses `python3 ... bytes.fromhex(...)`. Confirm the bytes
  are correct: `bbafc9ab` for `0xABC9AFBB` and `42fdffff` for `0xFFFFFD42`.

## The seven questions

If you can't answer each of these with confidence after reading the repo,
that's a finding.

1. If a user runs `pacman -Syu linux-t2` and linux-t2 bumps to 7.3.0,
   what happens? Does the patch still apply? Does the pacman hook catch
   the failure?
2. If the source tree at `~/build/linux-7.2.6/` is deleted, what does
   each script do? Does it fail with a clear error or silently produce a
   broken module?
3. If the user's hardware has a different subsystem_device (e.g. 021A
   instead of 0219), what happens at boot? Does amdgpu fall through to
   the standard feature negotiation, or does the patched module assume
   the iMac20,1 mask applies to all Navi 14 boards?
4. If `pkexec` is not configured for passwordless polkit auth, does
   `build-amdgpu-install.sh` still work, or does the user get stuck
   halfway through with a half-installed module?
5. If the user has two Limine boot entries (safe and hwaccel) and
   accidentally picks the wrong one, what's the worst case? (Should be:
   black screen, reboot, pick the other one — but verify there's no
   silent data loss path.)
6. The Limine drop-in sets `loglevel=7 ignore_loglevel`. On a successful
   hwaccel boot, does this produce so much console output that it
   interferes with SDDM? If yes, is there a way to make debug flags
   conditional on a sysrq or boot-time toggle?
7. The README claims "rollback in 4 seconds". Verify this is accurate
   given that `limine-mkinitcpio` is part of the rollback — that step
   alone can take 10+ seconds on slow disks.

## Severity rubric

Use these when reporting findings.

| Severity | Definition | Example |
|---|---|---|
| **BLOCKER** | Don't use this repo until fixed. Would lose user data or brick the system. | Install overwrites the only copy of the stock module; Limine drop-in accidentally flips the default |
| **MAJOR** | Repo works for the current user but is unsafe for general distribution. | Pacman hook silently no-ops on a major kernel bump; rollback takes much longer than 4 seconds |
| **MINOR** | Repo works but has a rough edge that should be smoothed. | Script lacks `set -e`; one script reads a path that's hardcoded to `/home/mike/build/...` |
| **NIT** | Style / preference / future-proofing. | Naming; shebang line; missing `local` in shell function |

A good review has **at most one BLOCKER, zero to three MAJORs**, and the
rest MINOR/NIT. If you find more than three BLOCKERs, you may be
misreading the repo — escalate to the author instead of writing a wall
of blockers.

## Output format

Report findings as a single Markdown file at
`reviews/FINDINGS-<your-name-or-session-id>.md` with this structure:

```markdown
# Review of McoreD/imac20-amdgpu-patch

Reviewer: <name or session>
Date:     <YYYY-MM-DD>
Repo SHA: <commit SHA you reviewed>

## Summary
<one paragraph: does this repo do what README.md claims, safely?>

## The four things that matter
### 1. Patch targets the right hardware
<your findings, with file:line references>

### 2. Install procedure has no one-way door
...

### 3. Pacman hook handles kernel upgrade
...

### 4. Build verification catches real failure modes
...

## Seven questions
<numbered list, one to two sentences each>

## Findings
### BLOCKER
- <id>: <title> — file:line, what, why, suggested fix

### MAJOR
...

### MINOR
...

### NIT
...

## What this repo does well
<two or three concrete positives — not flattery, things that would be
missed if removed>
```

## What NOT to bikeshed

Skip these — they will not change the verdict:

- Shell script style (`set -euo pipefail` vs `set -e` alone, etc.) unless
  it changes behaviour
- Whether the patch should be upstreamed (it explicitly cannot be)
- Whether to use `pkexec` vs `sudo` for privilege escalation
- AGENTS.md wording, as long as the invariants are stated correctly
- README formatting / link style
- Whether the install script should be written in Python instead of bash

## When to escalate instead of reviewing

If you encounter any of these, stop and tell the maintainer:

- The patch's magic constants don't match the macOS ioreg source
- The build script installs before verifying vermagic (silent risk)
- The stock module backup is overwritten on subsequent runs (silent loss)
- The Limine drop-in modifies `/boot/limine.conf` directly (bypasses
  the drop-in system)
- The pacman hook runs `depmod -a` and `limine-mkinitcpio` *before* the
  patched module is installed (would invalidate the boot image)
