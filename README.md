# linux-t2-patched — iMac20,1 Navi 14 SMU init fix

Rebuild of `amdgpu.ko` for `linux-t2 7.2.6.arch2-1` (Watanare build) with the
t2linux 6001 patch applied. The patch hardcodes SMU feature masks derived from
macOS ioreg reads for the iMac20,1 / iMac20,2 Radeon Pro 5300/5500 (PCI
1002:7340, subsystem 106b:0219). With it, amdgpu SMU init succeeds and the
5K panel modesets; without it, amdgpu aborts during boot with
`hw_init of IP block <smu> failed -62`.

Upstream patch: t2linux/linux-t2-patches@main, 6001-drm-amd-pm-Fix-boot-problems-in-5300.patch
Target hardware: Apple iMac20,1 / iMac20,2 (2020 27" 5K, Navi 14)
Omarchy PR:      omacom/omarchy#12203 (safe fallback installer)
