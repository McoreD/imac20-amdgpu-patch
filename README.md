# imac20-amdgpu-patch

> A rebuilt `amdgpu.ko` for **Apple iMac20,1 / iMac20,2** (Radeon Pro 5300/5500,
> Navi 14) on Arch Linux with the **Watanare** `linux-t2` kernel — with the
> upstream t2linux 6001 SMU-init fix baked in, so the 5K panel actually modesets.

This repository is **not** a fork of the Linux kernel. It holds:

1. The upstream t2linux `6001-drm-amd-pm-Fix-boot-problems-in-5300.patch` (verbatim)
2. Build and install scripts that turn the patch into a working `amdgpu.ko.zst`
3. A pacman hook so the patch survives `pacman -Syu`
4. A Limine boot entry that lets you opt into the patched module without
   losing the safe `nomodeset` fallback

## The honest one-sentence summary

**Stock `amdgpu` + stock Mesa/RADV + one upstream community patch + custom integration glue.** The GPU acceleration itself is the same code every Linux user with a Radeon RX 5500 / 5500 XT gets. Nothing about the GPU stack is custom for this machine. The only thing that's custom for you is the packaging that gets the upstream patch onto your specific install.

## What's stock

| | |
|---|---|
| Linux kernel 7.2.6 (Watanare build) | upstream Arch Linux + t2linux's standard patch series |
| `amdgpu` kernel driver | official AMD/Mesa |
| Mesa 26.2.2 + RADV Vulkan driver | official Mesa |
| mpv + libplacebo | upstream |
| Hyprland, Limine, Omarchy | upstream |

Without the patch, **none of the above binds to the Navi 14 on iMac20,1** because the GPU's SMU never finishes init. With the patch, every stock piece just works.

## What's community / 3rd-party

**Just one patch**, 16 lines, already public:

- **Author:** Atharva Tiwari (`atharvatiwarilinuxdev@gmail.com`)
- **Landed:** Jul 9, 2026
- **Home:** <https://github.com/t2linux/linux-t2-patches/blob/main/6001-drm-amd-pm-Fix-boot-problems-in-5300.patch>
- **What it does:** adds an early-return in `smu_v11_0_set_allowed_mask`
  that sends two hardcoded SMU feature masks (`0xABC9AFBB` and
  `0xFFFFFD42`) before the standard feature negotiation runs, but **only
  when the PCI signature matches exactly**:
  ```
  vendor            0x1002   (AMD)
  device            0x7340   (Navi 14)
  subsystem vendor  0x106B   (Apple)
  subsystem device  0x0219   (iMac20,1 / iMac20,2)
  ```
- **Where the magic constants come from:** reversed out of macOS via `ioreg`
  on a working iMac. Apple's firmware doesn't publish how it derives these
  values, and t2linux's commit message states explicitly: *"This is not
  upstreamable. We currently don't know how macOS derives these values."*

It's the only known fix for this specific failure mode. Once upstream Linux
gets a Navi 14 SMU init bypass (likely AMD's ongoing `smu_v13_0` work), the
patch becomes unnecessary and `arch-mact2/linux-t2` can take the upstream
fix directly. At that point this companion repo can be retired.

## What's actually custom for you

Just the integration glue — five small shell scripts:

- `scripts/build-amdgpu.sh` — compiles `amdgpu.ko` from a kernel source
  tree with the 6001 patch applied (vermagic check + `python3` byte-scan
  for the magic constants, so a build that didn't apply the patch can't
  silently slip through)
- `scripts/build-amdgpu-install.sh` — backs up the stock module to
  `/usr/lib/amdgpu-stock-backup/`, installs the patched one, runs
  `depmod -a` and `limine-mkinitcpio`
- `scripts/install-pacman-hook.sh` — installs `/etc/pacman.d/hooks/zz-repatch-amdgpu.hook`
  so `pacman -Syu linux-t2` doesn't silently overwrite the patch
- `scripts/install-limine-hwaccel-entry.sh` — creates an `imac20-hwaccel`
  Limine menu entry alongside the existing safe `nomodeset` entry
- `scripts/repatch-amdgpu.sh` — does the actual re-application when the
  pacman hook fires after a kernel upgrade

Total: ~250 lines of bash. No kernel code, no driver code.

## Why this exists

Apple's 2020 27" 5K iMacs shipped with a Navi 14 GPU and a customised VBIOS
that does not respond to `amdgpu`'s standard SMU init sequence. Without a
workaround, the kernel logs:

```
amdgpu 0000:03:00.0: SMU: No response msg_reg: 6 resp_reg: 0
amdgpu 0000:03:00.0: Failed to enable requested dpm features!
amdgpu 0000:03:00.0: Failed to setup smc hw!
amdgpu 0000:03:00.0: hw_init of IP block <smu> failed -62
amdgpu 0000:03:00.0: amdgpu_device_ip_init failed
amdgpu 0000:03:00.0: Fatal error during GPU init
```

and the panel stays dark. With `nomodeset` the kernel boots to a desktop
using the EFI simple-framebuffer (software rendering, no GPU acceleration,
what this machine runs by default).

## Verified working state

Captured on the iMac20,1 used to develop this repo:

```
$ lsmod | grep amdgpu
amdgpu              17944576  40          # was 0 (bound to nothing) before the patch

$ vulkaninfo --summary
GPU0: AMD Radeon Graphics (RADV NAVI14)   # was "no devices" before

$ mpv --hwdec=vaapi --vo=gpu file.mp4
Using hardware decoding (vaapi).
VO: [gpu] 3840x2160 vaapi[nv12]           # was [wlshm] (software) before
```

The `vaapi[nv12]` line is the smoking gun: the AMD VCN block is doing the
4K h264 decode, the framebuffer is in the GPU-native NV12 format, zero
CPU pixel-pushing.

## The pairing with omacom/omarchy

This repo is **not** the safe-fallback installer for stock Omarchy installs
on iMac20,1. That lives in the user's own Omarchy PR:

* **omacom/omarchy#12203** — "Keep EFI framebuffer on 2020 5K iMacs with Navi 14"
  (`bin/omarchy-hw-imac20-navi14`, `install/hardware/apple/fix-imac20-display.sh`,
  `migrations/1789574960.sh`, `test/shell.d/imac20-display-test.sh`).
* **omacom/omarchy#12524** — adds the opt-in command
  `omarchy-install-imac20-amdgpu-hwaccel` so a fresh install (or any
  existing install) can turn on HW acceleration with one command.
* Local branches under `~/Work/omarchy`.

The two are complementary: #12203 keeps new installs bootable (with
`nomodeset`); #12524 / this repo turns a working Omarchy machine into a
hardware-accelerated one.

## Quick start (assuming you already have `linux-t2` running)

```bash
# 1. One-time tool check
sudo pacman -S --noconfirm --needed bc

# 2. Clone this repo
git clone https://github.com/McoreD/imac20-amdgpu-patch.git
cd imac20-amdgpu-patch

# 3. Build, install, and stage boot entries (sudo)
./scripts/build-amdgpu-install.sh
./scripts/install-pacman-hook.sh
./scripts/install-limine-hwaccel-entry.sh

# 4. Reboot and pick imac20-hwaccel from the Limine menu
```

The `build-amdgpu-install.sh` script expects a kernel source tree at
`~/build/linux-7.2.6/` — vanilla 7.2.6 unpacked there with `zcat
/proc/config.gz > .config` and the 6001 patch applied. If you don't have
the source tree, see `scripts/build-amdgpu.sh` for the longer procedure.

## Verify HW acceleration after reboot

```bash
lsmod | grep amdgpu                 # refcount > 0 (was 0 before)
ls -la /dev/dri/                    # card1 is amdgpu, renderD128 exists
vulkaninfo --summary                # AMD Radeon Graphics (RADV NAVI14)
mpv --hwdec=vaapi --vo=gpu file.mp4 # "VO: [gpu] ... vaapi[nv12]"
coredumpctl list | grep mpv         # empty / no new crashes
```

If you see all four, HW acceleration is live. The Limine safe entry remains
the default until you manually promote the hwaccel entry.

## Roll back

The stock module is preserved at `/usr/lib/amdgpu-stock-backup/amdgpu.ko.zst`.
To revert:

```bash
sudo cp /usr/lib/amdgpu-stock-backup/amdgpu.ko.zst \
        /lib/modules/$(uname -r)/kernel/drivers/gpu/drm/amd/amdgpu/amdgpu.ko.zst
sudo depmod -a
sudo limine-mkinitcpio
sudo reboot
```

The Limine default is still the safe `nomodeset` entry, so a misbehaving
hwaccel boot never blocks you from getting back to a working desktop.

## Files

```
src/
  6001-drm-amd-pm-Fix-boot-problems-in-5300.patch    verbatim from t2linux

scripts/
  build-amdgpu.sh                  rebuild only amdgpu.ko from source tree
  build-amdgpu-install.sh          rebuild + backup stock + install + limine-mkinitcpio
  repatch-amdgpu.sh                invoked by pacman hook on linux-t2 upgrades
  install-pacman-hook.sh           writes /etc/pacman.d/hooks/zz-repatch-amdgpu.hook
  install-limine-hwaccel-entry.sh  writes /etc/limine-entry-tool.d/imac20-hwaccel.conf

reviews/
  REVIEW-INSTRUCTIONS.md           review brief for external reviewers
  FINDINGS-antigravity-20260919.md first external review (Opus 4.6)

AGENTS.md                          instructions for AI coding agents
```

## Credits

* **Patch author:** Atharva Tiwari, July 9, 2026
* **Patch home:** <https://github.com/t2linux/linux-t2-patches/blob/main/6001-drm-amd-pm-Fix-boot-problems-in-5300.patch>
* **Maintainer of this repo:** @McoreD (`McoreD@users.noreply.github.com`)
* **Pair projects:** omacom/omarchy#12203 (safe fallback), #12524 (opt-in HW accel)

## License

The patch is GPL-2.0 (inherited from the Linux kernel). The scripts in
this repo are GPL-2.0-or-later.
