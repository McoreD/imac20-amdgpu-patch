# Commit `8a81051` — KovaForge/workspace (Vladislava agent)

- **Repo**: <https://github.com/KovaForge/workspace>
- **Author**: Vladislava Kova <274343239+vladislava-kova-kf@users.noreply.github.com>
- **Date**: Sat Sep 26 10:59:40 2026 +0800
- **Branch**: main
- **Pushed**: 10:59 AWST (via `gh auth` HTTPS fallback — `git-vladislava` wrapper points at `KovaForge/skills`, not `KovaForge/workspace`)

## Message

> hypr: option A — Omarchy bind modules + shell autostart (228 binds, no deadlock)

## Changes

```
 devices/imac-2020/hypr-config/autostart.lua | 17 ++++++
 devices/imac-2020/hypr-config/hyprland.lua  | 91 +++++++++++++++++++++++++++++
 2 files changed, 108 insertions(+)
```

## What it changed

Mirrored the two Hyprland configs from `~/.config/hypr/` into the workspace repo at `devices/imac-2020/hypr-config/`. The configs themselves are the actual Option A fix — verbatim copies of what's live on the box:

- **`hyprland.lua`** (4043 bytes): Omarchy default bind modules loaded explicitly (`default.hypr.bindings.media/clipboard/tiling/utilities` + optional `voxtype/applications`), `default.hypr.windows`, anti-deadlock flags before any `hl.config()` call. Skip `default.hypr.omarchy` and `default.hypr.looknfeel` (deadlock trigger).
- **`autostart.lua`** (793 bytes): Adds `omarchy-launch-shell`, `udiskie --automount --no-notify --no-tray`, `omarchy-hyprland-monitor-watch`, `gtk-launch Discord`, and `systemctl --user start scansnap-button.service`.

## Verification at the time

- Bind count: 71 (anti-deadlock minimal) → **228** (Option A). Omarchy media/clipboard/tiling/utilities + windows all loaded. No deadlock, no config errors. Full Omarchy target is 481 binds; missing 253 are from `default.hypr.looknfeel` (intentionally skipped).
- `hyprctl configerrors` empty.
- No new coredumps after applying.

## Why this commit matters

Without this commit, the only Hyprland configs that exist in version control are the anti-deadlock minimal ones (which give you 71 binds and no standard Omarchy keybindings). Option A is the workable middle ground — load the safe parts of Omarchy's defaults (binds, windows, autostart) explicitly, skip the deadlock-trigger modules. Anyone picking up this box fresh can `git pull` and get a working session without rediscovering the deadlock.
