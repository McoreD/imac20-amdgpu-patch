# imac20-amdgpu-patch

> Reliable GPU acceleration for **Apple iMac20,1 / iMac20,2** (Radeon Pro 5300/5500, Navi 14) on Arch Linux / Omarchy with the `linux-t2` kernel.
> A rebuilt `amdgpu.ko` with the deferred-UCLK SMU fix, plus a two-entry Limine boot (hardware-accelerated / safe) that survives kernel upgrades.

This repository is **not** a fork of the Linux kernel. It holds:

1. `src/amdgpu-defer-uclk-5300.patch`: the SMU init fix (Atharva Tiwari, from [t2linux/wiki#743](https://github.com/t2linux/wiki/issues/743))
2. `src/6001-drm-amd-pm-Fix-boot-problems-in-5300.patch`: t2linux's older fix, kept only so it can be reverted from the source tree
3. `scripts/imac20-hwaccel`: builds the module, builds both UKIs and manages the Limine entries
4. `scripts/install.sh`: installs the tool, the patches and a pacman hook

## The problem

On these iMacs, `amdgpu` intermittently fails to initialise the GPU's SMU, and the panel stays black:

```
amdgpu 0000:03:00.0: SMU: No response msg_reg: 6 resp_reg: 0
amdgpu 0000:03:00.0: Failed to enable requested dpm features!
amdgpu 0000:03:00.0: hw_init of IP block <smu> failed -62
```

The `linux-t2` package already ships t2linux patch 6001, which hardcodes macOS's SMU feature masks. That makes init work *sometimes*.
The remaining failure comes from memory-clock DPM (`FEATURE_DPM_UCLK`) being enabled inside `EnableAllSmuFeatures`: the SMU intermittently stops answering (wiki#743 bisected it to that one bit).
On the machine this repo was built on, the package module booted fine for a day, then failed on two warm reboots in a row.

## The fix

`amdgpu-defer-uclk-5300.patch` replaces 6001. It leaves UCLK out of the features enabled at init, then turns UCLK on in `smu_late_init` once the SMU is up.
Init no longer races, and memory clocks still scale normally (turning UCLK off for good fixes the boot but leaves MCLK stuck at 0 MHz).
It passed 10/10 boots on an iMac20,1 `106b:0219` in wiki#743, and 3/3 so far on the machine this repo was built on (stock 6001 module: 2 failures in 4 boots).

**Upstream status (2026-10-02):** Ed Schofield's v2 covering `0218`/`0219` was applied to `amd-staging-drm-next` on 2026-09-11 and reverted on 2026-09-16 at a developer's request. Atharva Tiwari thinks the root cause is display-core init ordering rather than UCLK, and his own patch went to amd-gfx on 2026-09-15. `linux-t2-patches` closed the downstream PRs (#60, #61) pending upstream. Test data and the request to carry a fix in `linux-t2`: [wiki#743 comment](https://github.com/t2linux/wiki/issues/743#issuecomment-5939929239). Once `linux-t2` carries a fix for `0219`, this repo can be retired.

Only `amdgpu.ko` is rebuilt, from the vanilla kernel.org source for the running `linux-t2` release, using the `linux-t2-headers` `.config` and `Module.symvers`.
It installs to `/usr/lib/modules/<krel>/updates/`, so the package's own module is never touched and pacman never complains.

## Install

```bash
git clone https://github.com/McoreD/imac20-amdgpu-patch.git
cd imac20-amdgpu-patch
sudo scripts/install.sh      # idempotent
```

After install, the Limine menu has:

| Entry | Cmdline adds | GPU |
|---|---|---|
| `imac20-hwaccel` (default) | `amdgpu.modeset=1 video=efifb:off` | rebuilt amdgpu, radeonsi / RADV |
| `Omarchy` (and snapshots) | `nomodeset modprobe.blacklist=amdgpu` | none: firmware framebuffer, software rendering |

The pacman hook (`/etc/pacman.d/hooks/zz-imac20-hwaccel.hook`) rebuilds the module and both UKIs after every `linux-t2` upgrade.
If that fails, it removes the hwaccel entry so the next boot uses the safe path.

## Use

```bash
sudo imac20-hwaccel status     # boot mode, which module each kernel resolves to, UKIs, default entry
sudo imac20-hwaccel repatch    # rebuild module + UKIs for the newest linux-t2
sudo imac20-hwaccel disable    # remove the hwaccel entry
```

Health check in hwaccel mode:

```bash
journalctl -k -b | grep -E 'SMU is initialized|Display Core'
grep DPM_UCLK /sys/bus/pci/devices/0000:03:00.0/pp_features   # enabled
vulkaninfo --summary | grep deviceName                        # AMD Radeon Graphics (RADV NAVI14)
```

If the panel is ever black: power off, pick **Omarchy** in Limine, run `sudo imac20-hwaccel status`, and see [docs/PATCHING.md](docs/PATCHING.md).

## Docs

[docs/PATCHING.md](docs/PATCHING.md) covers the boot paths, the build method step by step, adapting to a new kernel, and userspace rules for Hyprland on this machine.

## The pairing with omacom/omarchy

* **omacom/omarchy#12203** keeps new Omarchy installs on these iMacs bootable (`plymouth.enable=0 nomodeset`).
* **omacom/omarchy#12524** adds an opt-in hardware-acceleration boot entry to Omarchy itself.

## Credits

* **Deferred-UCLK fix:** Atharva Tiwari, tested by Guna R. Bharati ([t2linux/wiki#743](https://github.com/t2linux/wiki/issues/743))
* **6001 patch:** Atharva Tiwari ([t2linux/linux-t2-patches](https://github.com/t2linux/linux-t2-patches/blob/main/6001-drm-amd-pm-Fix-boot-problems-in-5300.patch))
* **Related:** Ed Schofield's delayed-UCLK work for board `0218` ([t2linux/linux-t2-patches#60](https://github.com/t2linux/linux-t2-patches/pull/60))
* **Maintainer of this repo:** @McoreD

## License

The patches are GPL-2.0 (inherited from the Linux kernel). The scripts in this repo are GPL-2.0-or-later.
