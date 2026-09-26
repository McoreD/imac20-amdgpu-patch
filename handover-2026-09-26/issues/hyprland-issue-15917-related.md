# Related: hyprwm/Hyprland#15917 (CLOSED, not-planned)

- **URL**: <https://github.com/hyprwm/Hyprland/issues/15917>
- **State**: CLOSED (closed_at 2026-08-20T20:42:41Z, state_reason: `not_planned`)
- **Title**: "System-wide freeze after closing any video player — AMDGPU RX 550 (Polaris 12) — processes stuck in D state, REISUB required"
- **Author**: carlosmera24 (user 32177971)
- **Closed by**: github-actions[bot]

## Why this matters for the handover

This is the closest documented "amdgpu+Hyprland deadlock" we could find, and it was closed by Hyprland maintainers as `not_planned`. The reporter's stack (`amdgpu` driver, kernel `D`-state lockups after video playback, REISUB to recover) is structurally similar to our case (`libhyprgraphics 0.5.1-4` userland deadlock during `initServer`) but the trigger is different:

- **#15917**: kernel-side deadlock in DRM/GBM teardown after closing a video player. Polaris 12 (`0x1002:0x699F`). Affects Hyprland users on RX 550 class cards.
- **#51** (our issue): userland deadlock in `CAsyncResourceGatherer::asyncAssetSpinLock` during compositor init. Navi 14 (`0x1002:0x7340` / `0x106B:0x0219`). Affects Hyprland users on iMac20,1/20,2.

Both are amdgpu + Hyprland. Both can deadlock the system. #15917 was triaged and closed as `not_planned` (no upstream action), so a precedent exists for "this is not a Hyprland bug, it's amdgpu / libhyprgraphics / Mesa".

## Issue body (verbatim, abbreviated)

### Description

When running any video application (VLC, Stremio Flatpak, Stremio Enhanced, MPV) under Hyprland, closing the application triggers a system-wide degradation. The process enters uninterruptible sleep (`D` state), `kill -9` has no effect, and the system requires a hard reboot via REISUB.

### Steps to Reproduce

1. Boot into Hyprland (Wayland) session.
2. Open any video player.
3. Play video for a few seconds (hardware decoding initializes).
4. Close the application.
5. Observe: process enters D state, system becomes progressively unresponsive.
6. Only `Alt+SysRq+REISUB` recovers the system.

### Isolation evidence

| Configuration | Result |
|--------------|--------|
| Kernel 7.1.8-arch1-3 + Hyprland 0.56.2 | ❌ Freeze |
| Kernel 6.18.45-1-lts + Hyprland 0.56.2 | ❌ Freeze |
| TTY (no compositor) + `mpv --vo=drm` | ✅ Works, closes cleanly |
| X11 session (i3) + VLC / Stremio | ✅ Works, closes cleanly |

### Environment

- **GPU**: AMD Radeon RX 550 / 550 Series (Polaris 12, `0x1002:0x699F`)
- **CPU**: Intel Core i7-3770
- **RAM**: 16 GB
- **Kernel**: 6.18.45-1-lts and 7.1.8-arch1-3
- **Mesa**: 26.1.7-arch1.1
- **Hyprland**: 0.56.2

### Workaround

Use a pure X11 session (e.g., `i3` + `xinit`) for video playback. No freeze occurs under X11.

## Takeaway

If maintainers of `hyprgraphics#51` say "this is Hyprland's problem, not ours," point them at `Hyprland#15917` for precedent — same triage outcome (not a compositor bug, environment-driven).
