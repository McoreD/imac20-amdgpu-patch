# iMac20,1 (T2) + amdgpu + Hyprland — Handover Bundle

**Author of bundle**: Vladislava (agent) with Mike / McoreD
**Date of bundle**: 2026-09-26 11:30 AWST (Perth, GMT+8)
**Session**: Discord `#imac-2020` thread
**Purpose**: pick-up-and-run documentation for whoever takes over the iMac20,1 / Navi 14 / Hyprland stack after Mike's session.

If you're reading this because you're the next person on this box, **start with `20260926-imac20-amdgpu-hwaccel-postmortem.md`** — it's the full timeline + problems + approaches + lessons for the multi-hour debugging session that produced this handover. Then come back here for the file map.

---

## What this box is

- **Hardware**: Apple iMac20,1 (mid-2020 27" 5K, T2 coprocessor). GPU = Radeon Pro 5500 XT (Navi 14, PCI `1002:7340` / subsystem `106B:0219`). eDP-1 panel at 3840×2160@59.997, scale 1.25.
- **OS**: Arch Linux, LUKS-encrypted root on btrfs, Limine bootloader (UKI), SDDM greeter, Hyprland compositor with Omarchy layered on top.
- **Kernel**: `7.2.6-arch2-Watanare-T2-4-t2` (linux-t2 from `arch-mact2`). Patched `amdgpu.ko` baked in with the upstream t2linux 6001 SMU-init fix — without it, the Navi 14 SMU never finishes init and the panel stays dark.
- **Display stack**: amdgpu KMS active (`amdgpu.modeset=1 video=efifb:off` on cmdline), `/dev/dri/card1` is amdgpu, `/dev/dri/renderD128` is the render node.
- **Compositor**: Hyprland 0.56.2 with the Lua-config Omarchy layer (`/usr/share/omarchy/default/hypr/...`).
- **Workaround**: `LIBGL_ALWAYS_SOFTWARE=1` + `MESA_LOADER_DRIVER_OVERRIDE=llvmpipe` live in `/etc/environment` — forces Mesa to software rendering to dodge a libhyprgraphics deadlock (see postmortem P1, upstream issue `hyprwm/hyprgraphics#51`). Without it, every Hyprland session SIGABRTs during `initServer`.

---

## File map

```
~/Work/imac20-amdgpu-handover-2026-09-26/
├── README.md                                                ← you are here
├── 20260926-imac20-amdgpu-hwaccel-postmortem.md             ← start here
├── configs/
│   └── hypr/
│       ├── hyprland.lua                                     ← Option A config (live, 4043 bytes)
│       ├── autostart.lua                                    ← autostart overrides (live, 793 bytes)
│       └── bindings.lua                                     ← user bind overrides (live, 4010 bytes)
├── environment/
│   ├── etc-environment                                      ← /etc/environment (llvmpipe workaround)
│   ├── etc-default-limine                                   ← /etc/default/limine (kernel cmdline)
│   ├── etc-limine-entry-tool.d-imac20-hwaccel.conf          ← /etc/limine-entry-tool.d/imac20-hwaccel.conf (root, mode 600)
│   ├── etc-limine-entry-tool.d-omarchy-defaults.conf        ← /etc/limine-entry-tool.d/omarchy-defaults.conf
│   ├── etc-limine-entry-tool.d-resume.conf                  ← /etc/limine-entry-tool.d/resume.conf
│   └── etc-limine-entry-tool.d-t2-mac.conf                  ← /etc/limine-entry-tool.d/t2-mac.conf
├── repos/
│   └── mcoreD-imac20-amdgpu-patch/                          ← mirror of https://github.com/McoreD/imac20-amdgpu-patch.git
│       ├── AGENTS.md                                        ← file inventory + critical invariants
│       ├── README.md                                        ← user-facing intent + quick start
│       ├── .gitignore
│       ├── scripts/
│       │   ├── build-amdgpu.sh
│       │   ├── build-amdgpu-install.sh
│       │   ├── install-limine-hwaccel-entry.sh
│       │   ├── install-pacman-hook.sh
│       │   └── repatch-amdgpu.sh
│       ├── src/
│       │   └── 6001-drm-amd-pm-Fix-boot-problems-in-5300.patch
│       └── reviews/
│           ├── REVIEW-INSTRUCTIONS.md
│           └── FINDINGS-antigravity-20260919.md
├── issues/
│   ├── hyprgraphics-issue-51-body.md                        ← our upstream issue (libhyprgraphics deadlock)
│   └── hyprland-issue-15917-related.md                      ← closed related Hyprland issue
└── commits/
    ├── 87d46fc-mcoreD-imac20-amdgpu-patch.md                ← commit on McoreD repo (kernel localversion + KMS flags)
    └── 8a81051-kovaforge-workspace.md                       ← commit on KovaForge/workspace (Option A configs)
```

---

## What's NOT in the bundle and why

### `/etc/limine-entry-tool.d/imac20-hwaccel.conf` — included, but still the old version

- Located at `environment/etc-limine-entry-tool.d-imac20-hwaccel.conf` (1324 bytes).
- Created by the pre-`87d46fc` install script. Still contains the **old** debug-flag cmdline (`loglevel=7 ignore_loglevel console=tty1 plymouth.enable=0 amdgpu.modeset=1 video=efifb:off`) — it's the pre-`87d46fc` artifact, not the new minimal form.
- The new install script (post-`87d46fc`) only writes `KERNEL_CMDLINE[imac20-hwaccel]+=" plymouth.enable=0"` and puts the KMS flags in `[default]`. To regenerate on disk:
  ```bash
  sudo rm /etc/limine-entry-tool.d/imac20-hwaccel.conf
  cd /home/mike/Projects/McoreD/imac20-amdgpu-patch
  sudo scripts/install-limine-hwaccel-entry.sh
  sudo limine-mkinitcpio
  ```
- Cosmetic only — doesn't block anything. The KMS flags are still effective because they were moved to `[default]` in commit `87d46fc`.

### `KovaForge/workspace` mirror of the live configs

Commit `8a81051` is on `https://github.com/KovaForge/workspace` under `devices/imac-2020/hypr-config/`. The bundle has the live configs verbatim — anyone running this box can `cp configs/hypr/*.lua ~/.config/hypr/` and end up in the same state.

### `~/Work/omarchy/` and the Omarchy source tree

`~/Work/omarchy/` is a local mirror of `https://github.com/omacom/omarchy.git` — used for diffing against the system-installed `/usr/share/omarchy/`. Not included in the bundle; it's a 2 MB+ git checkout and the relevant changes (`default/hypr/hyprland.lua`, `default/hypr/bindings.lua`, `default/hypr/autostart.lua`) are already summarized in the postmortem.

---

## Current system state at handover time

| Component | State |
|-----------|-------|
| Kernel | `7.2.6-arch2-Watanare-T2-4-t2` (linux-t2, patched amdgpu.ko) |
| Bootloader | Limine UKI, default entry = hwaccel (`amdgpu.modeset=1 video=efifb:off plymouth.enable=0`) |
| Greeter | SDDM with minimal 4-line greeter config (`/usr/share/sddm/hyprland.lua`) |
| Compositor | Hyprland 0.56.2, mike session at PID 12569 (since 11:11 AWST post-SDDM-logout) |
| libhyprgraphics | `0.5.1-4` — deadlock trigger; not fixed upstream |
| Mesa | `26.2.2-1`, **forced to llvmpipe** via `/etc/environment` |
| Bind count | 228 (Option A: Omarchy media/clipboard/tiling/utilities + windows, full Omarchy target = 481) |
| Quickshell taskbar | **Not up** (env propagation from Hyprland's IPC context fails when launched from outside; see postmortem P5 + TODO T1) |
| amdgpu | loaded, refcount > 0, `/dev/dri/card1` + `/dev/dri/renderD128` present |

---

## Open TODOs (from the postmortem, sorted by leverage)

1. **T1 (highest leverage)**: Run `dbus-update-activation-environment --systemd WAYLAND_DISPLAY=wayland-1 XDG_SESSION_TYPE=wayland` and then `omarchy-launch-shell` from a user terminal. Likely gets Quickshell taskbar up without rebooting.
2. **T2**: Bisect libhyprgraphics — try `downgrade libhyprgraphics` to `0.5.1-3` (or earlier), remove llvmpipe env vars, log whether deadlock still fires. If a non-deadlocking version is found, drop the workaround.
3. **T3**: Regenerate `/etc/limine-entry-tool.d/imac20-hwaccel.conf` with the post-`87d46fc` install script (file is already in the handover, but it's the old pre-`87d46fc` version — see "What's NOT in the bundle" above).
4. **T4**: Add README note to `McoreD/imac20-amdgpu-patch` explaining "every Limine entry is real hwaccel by design" intent.
5. **T5**: Watch upstream `hyprwm/hyprgraphics#51` for replies. If maintainers ask for a bisect, T2 is the path.
6. **T6 (verification)**: Once T1 is done, verify SUPER+Q (close), SUPER+Enter (terminal), SUPER+E (files), SUPER+D (launcher) all work — these are what was missing before Option A.

---

## Things to NOT do (anti-patterns from this session)

- **`systemctl --user restart` on a graphical session** — cancels the service unit, bounces user to SDDM greeter. Use `pkill -TERM Hyprland` to clear safe-mode instead.
- **Trust `bind count` as proof your config loaded** — always check `ps -eo args | grep Hyprland` for `--safe-mode` flag first.
- **Spawn GUI apps from OpenClaw exec** — env vars don't propagate. Either run from a user terminal or use `dbus-update-activation-environment`.
- **Reboot as a config-tweak fix** — too heavy. Try `dbus` propagation, inotify reload (Hyprland hot-reloads configs), or `pkill -TERM Hyprland` first.
- **Remove llvmpipe workaround** before upstream fix lands — every Hyprland session will SIGABRT during initServer.

---

## References

- **Upstream issue**: <https://github.com/hyprwm/hyprgraphics/issues/51>
- **Related**: <https://github.com/hyprwm/Hyprland/issues/15917> (closed, not-planned)
- **Patched amdgpu patch source**: <https://github.com/t2linux/linux-t2-patches/blob/main/6001-drm-amd-pm-Fix-boot-problems-in-5300.patch>
- **McoreD repo**: <https://github.com/McoreD/imac20-amdgpu-patch.git>
- **KovaForge/workspace**: <https://github.com/KovaForge/workspace> (configs under `devices/imac-2020/hypr-config/`)
- **Omarchy**: <https://github.com/omacom/omarchy>
- **Hyprland**: <https://github.com/hyprwm/Hyprland>
- **libhyprgraphics**: <https://github.com/hyprwm/hyprgraphics>

---

## Contact / context

- **Mike / McoreD** (user): Discord `mcored`, GitHub `McoreD`, email `mcored@gmail.com`.
- **Vladislava** (agent that built this bundle): KovaForge COO role, this is one of multiple agents. USER.md and SOUL.md at `~/.openclaw/workspace/vladislava/` document the agent's preferences and reasoning style if you need to consult them.
