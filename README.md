# imac20-amdgpu-patch

> A rebuilt `amdgpu.ko` for **Apple iMac20,1 / iMac20,2** (Radeon Pro 5300/5500,
> Navi 14) on Arch Linux with the **Watanare** `linux-t2` kernel — with the
> t2linux `6001` SMU init fix baked in, so the 5K panel actually modesets.

This repository is **not** a fork of the Linux kernel. It is a tracking repo
that holds:

1. The upstream `6001-drm-amd-pm-Fix-boot-problems-in-5300.patch` (verbatim)
2. Build and install scripts that turn the patch into a working
   `amdgpu.ko.zst` for an existing `linux-t2` install
3. A pacman hook so the patch survives `pacman -Syu`
4. A Limine boot entry that lets you opt into the patched module without
   losing the safe `nomodeset` fallback

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

and the panel stays dark. With `nomodeset` the kernel boots to a desktop using
the EFI simple-framebuffer (software rendering, no GPU acceleration, what this
machine runs today). The t2linux project has a patch that hardcodes two SMU
feature masks derived from macOS ioreg reads, which makes the SMU respond
correctly. With the patched module, `amdgpu` modesets the 5K panel.

**Target hardware signature** (PCI IDs, matched by the patch):

```
vendor:           1002   (AMD)
device:           7340   (Navi 14 — Baffin / Radeon Pro 5300 / 5500)
subsystem vendor: 106B   (Apple)
subsystem device: 0219   (iMac20,1 / iMac20,2 5K)
```

The macOS-derived values that the patch sends to the SMU are
`SMU_MSG_SetAllowedFeaturesMaskLow = 0xABC9AFBB` and
`SMU_MSG_SetAllowedFeaturesMaskHigh = 0xFFFFFD42`. The patch's commit message
warns that this is *not* upstreamable: Apple does not publish how those values
are derived. They were reverse-engineered from macOS by Atharva Tiwari in the
[t2linux/linux-t2-patches](https://github.com/t2linux/linux-t2-patches) repo.

## The pairing

This repo is **not** the safe-fallback installer for stock Omarchy installs on
iMac20,1. That lives in the user's own Omarchy PR:

* **omacom/omarchy#12203** — "Keep EFI framebuffer on 2020 5K iMacs with Navi 14"
* Files: `bin/omarchy-hw-imac20-navi14`, `install/hardware/apple/fix-imac20-display.sh`,
  `migrations/1789574960.sh`, `test/shell.d/imac20-display-test.sh`
* Local branch: `~/Work/omarchy` on `fix/imac20-navi14-luks-display`
* Local commit: `91fc171`

The two are complementary: the PR keeps new installs bootable (with
`nomodeset`); this repo turns a working `nomarchy` machine into a
hardware-accelerated one.

## Quick start

You already have `linux-t2 7.2.6.arch2-1` (Watanare build) running with
`plymouth.enable=0 nomodeset`. To enable HW acceleration:

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

# 4. Reboot, pick `imac20-hwaccel` from the Limine menu, type LUKS
```

The `build-amdgpu-install.sh` script rebuilds `amdgpu.ko` from a kernel
source tree at `~/build/linux-7.2.6/` (it expects vanilla Linux 7.2.6
unpacked there with `zcat /proc/config.gz > .config` and the patch applied).
If you do not have the source tree, follow the longer rebuild procedure
documented in `scripts/build-amdgpu.sh`.

## Verify it worked

After booting the `imac20-hwaccel` entry:

```bash
lsmod | grep amdgpu                          # refcount > 0 (was 0 before)
ls /dev/dri/                                 # card0 is amdgpu, not simpledrm
vulkaninfo --summary                         # Navi 14 device listed
mpv --vo=gpu /path/to/file.mp4               # "VO: [gpu]" not [wlshm]
coredumpctl list | grep mpv                  # empty / no new crashes
```

If you see all four, HW acceleration is live. Then make it the default:

```bash
sudo sed -i 's/KERNEL_CMDLINE\[default\]/KERNEL_CMDLINE[imac20-hwaccel]/' \
        /etc/limine-entry-tool.d/imac20-hwaccel.conf
sudo limine-mkinitcpio
```

## Roll back

The stock module is preserved at `/usr/lib/amdgpu-stock-backup/amdgpu.ko.zst`.
To revert in seconds:

```bash
sudo cp /usr/lib/amdgpu-stock-backup/amdgpu.ko.zst \
        /lib/modules/$(uname -r)/kernel/drivers/gpu/drm/amd/amdgpu/amdgpu.ko.zst
sudo depmod -a
sudo limine-mkinitcpio
sudo reboot
```

The Limine default is still the safe `nomodeset` entry, so a misbehaving
`imac20-hwaccel` boot never blocks you from getting back to a working desktop.

## Files

```
src/
  6001-drm-amd-pm-Fix-boot-problems-in-5300.patch    verbatim from t2linux

scripts/
  build-amdgpu.sh                  rebuild only amdgpu.ko from source tree
  build-amdgpu-install.sh          rebuild + backup stock + install + mkinitcpio
  repatch-amdgpu.sh                invoked by pacman hook on linux-t2 upgrades
  install-pacman-hook.sh           writes /etc/pacman.d/hooks/zz-repatch-amdgpu.hook
  install-limine-hwaccel-entry.sh  writes /etc/limine-entry-tool.d/imac20-hwaccel.conf

AGENTS.md                          instructions for AI coding agents
```

## Credits

* **Patch author:** Atharva Tiwari (`atharvatiwarilinuxdev@gmail.com`),
  July 9, 2026
* **Patch home:** <https://github.com/t2linux/linux-t2-patches/blob/main/6001-drm-amd-pm-Fix-boot-problems-in-5300.patch>
* **Maintainer of this repo:** @McoreD (`mcored@gmail.com`)
* **Pair project:** omacom/omarchy#12203 — the installer-side safe fallback

## License

The patch is GPL-2.0 (inherited from the Linux kernel). The scripts in this
repo are GPL-2.0-or-later.
