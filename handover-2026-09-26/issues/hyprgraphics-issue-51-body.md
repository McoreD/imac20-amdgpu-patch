# Upstream issue: hyprwm/hyprgraphics#51

- **URL**: <https://github.com/hyprwm/hyprgraphics/issues/51>
- **Filed by**: McoreD (user `48652`) on 2026-09-26 02:56:03 UTC (~10:56 AWST)
- **State**: open, no comments, no reactions (as of 11:24 AWST)
- **Issue body** (verbatim from GitHub API):

---

**Environment**

- Hardware: Apple iMac20,1 (T2), Navi 14 (Radeon Pro 5500 XT, PCI `1002:7340` / `106B:0219`)
- Kernel: `linux-t2 7.2.6.arch2-4` (t2linux Watanare build), cmdline includes `amdgpu.modeset=1 video=efifb:off`
- Mesa: `26.2.2-1`
- Hyprland: `0.56.2-2`
- libhyprgraphics: `0.5.1-4` (`/usr/lib/libhyprgraphics.so.4`)

**Symptom**

Hyprland deadlocks during `CCompositor::initServer`. The compositor never reaches a usable state — `hyprctl binds` returns no binds, the screen is black. `coredumpctl list Hyprland` shows 5 SIGABRTs within ~14 minutes in the same session (PIDs 1242, 2751, 1239, 2665, 3192).

**Stack trace** (from coredump of PID 3192):

```
Thread 2 (LWP 3195):
#0  ?? () from /usr/lib/libc.so.6
#1  ?? () from /usr/lib/libc.so.6
#2  pthread_cond_clockwait () from /usr/lib/libc.so.6
#3  Hyprgraphics::CAsyncResourceGatherer::asyncAssetSpinLock() () from /usr/lib/libhyprgraphics.so.4
#4  ?? () from /usr/lib/libstdc++.so.6
#5  ?? () from /usr/lib/libc.so.6
#6  ?? () from /usr/lib/libc.so.6

Thread 1 (LWP 3192):
#0  abort () from /usr/lib/libc.so.6
#1  ?? () from /usr/lib/Hyprland (offset 0x3bc7f4)
#2  <signal handler called>
#3  ?? () from /usr/lib/libc.so.6
#4  raise () from /usr/lib/libc.so.6
#5  abort () from /usr/lib/libc.so.6
#6  ?? () from /usr/lib/libstdc++.so.6
#7  ?? () from /usr/lib/libstdc++.so.6
#8  std::terminate () from /usr/lib/libstdc++.so.6
#9  __cxa_throw () from /usr/lib/libstdc++.so.6
#10 ?? () from /usr/lib/Hyprland (offset 0x236f6b)
#11 CCompositor::initServer(std::string, int) () from /usr/lib/Hyprland
#12 main () from /usr/lib/Hyprland
```

Thread 2 is parked in `asyncAssetSpinLock()` waiting on a `pthread_cond_clockwait`. Thread 1 throws from inside `initServer`, hits `__cxa_throw` → `std::terminate` → `abort`. The deadlock is the gatherer never releasing the condvar that initServer is waiting on (or vice versa) — whichever wakes first would unblock the other, but neither is signalled.

**Reproduction**

The deadlock is **independent of Hyprland config**. I tried:

- Minimal user config (4 lines: `disable_hyprland_logo`, `disable_splash_rendering`, `force_default_wallpaper=0`, `animations.enabled=false`) — still deadlocks
- The sddm greeter config (`/usr/share/sddm/hyprland.lua`, basically the same minimal anti-deadlock flags) — also deadlocks

It happens during `initServer` itself, before any user binding is registered. Reliable on this hardware under amdgpu KMS — 5 crashes in a row during initial bring-up before I applied the workaround.

**Workaround**

Setting these env vars (either in `/etc/environment` or in the Hyprland session via `envs.lua`) makes the deadlock go away completely:

```
LIBGL_ALWAYS_SOFTWARE=1
MESA_LOADER_DRIVER_OVERRIDE=llvmpipe
```

That switches libhyprgraphics to software rendering (llvmpipe), which takes a different code path and avoids the gatherer entirely. The compositor starts cleanly and all binds register normally.

**Notes**

- Mesa RADV (Vulkan) on the same amdgpu is unaffected — `mpv --hwdec=vaapi --vo=gpu` and `vulkaninfo --summary` both work. This is libhyprgraphics-specific.
- The `amdgpu` kernel driver is fine — it binds to the GPU (`lsmod` refcount > 0, `/dev/dri/card1` is amdgpu). Only the libhyprgraphics userland code path is broken.
- I haven't bisected libhyprgraphics versions — happy to try `0.5.1-3` or git HEAD and report back if useful.

Happy to provide more info, test patches, or bisect versions on request.

---

## Status (handover note)

- No reply from maintainers as of 11:24 AWST 2026-09-26.
- Linked Hyprland issue: #15917 (closed-not-planned, RX 550 Polaris 12, different shape but same family of "amdgpu+Hyprland video playback freeze").
- If maintainers ask for a bisect, run `downgrade libhyprgraphics` to `0.5.1-3` from the Arch extra cache, log whether the deadlock still fires without llvmpipe, report back.
