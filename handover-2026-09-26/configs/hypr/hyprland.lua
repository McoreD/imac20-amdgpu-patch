-- Minimal Hyprland config for iMac20,1 (T2) with amdgpu KMS.
--
-- Workaround for a libhyprgraphics + amdgpu deadlock in
-- CAsyncResourceGatherer::asyncAssetSpinLock that hits during
-- CCompositor::initServer. The greeter's minimal config
-- (/usr/share/sddm/hyprland.lua) does NOT deadlock — it's just
-- 4 lines that disable the splash, logo, wallpaper, and animations,
-- all of which trigger async asset loading.
--
-- As of 2026-09-26 we boot with `amdgpu.modeset=1 video=efifb:off`
-- on the kernel cmdline so amdgpu drives /dev/dri/card1, but
-- libhyprgraphics 0.5.1-4 still deadlocks when it tries to gather
-- decoration / splash / wallpaper assets async. The cleanest fix
-- is to skip those assets entirely.
--
-- The verified deadlock trigger is `default.hypr.looknfeel` (decoration
-- engine + theme assets loaded asynchronously via the asset gatherer).
-- Everything else in `default.hypr.omarchy` is safe to load directly
-- — bind modules are pure `hl.bind()` calls, and `default.hypr.windows`
-- is just window rules + per-app tags (no asset loading either).
-- So we load those explicitly here and skip the gatherer-trigger
-- loader. User overrides (`hypr.bindings`, `hypr.autostart`) come last
-- so they take precedence on conflicts.
--
-- If `default.hypr.looknfeel` is fixed upstream, replace all the
-- `default.hypr.*` require lines below with a single
-- `require("default.hypr.omarchy")` to get full Omarchy defaults.

-- MUST come before any require("hypr.*") calls. Omarchy's bootstrap
-- sets up package.path so require("hypr.envs") resolves to
-- ~/.config/hypr/envs.lua. Without it, Hyprland trips emergency mode
-- with "module 'hypr.envs' not found".
dofile((os.getenv("OMARCHY_PATH") or "/usr/share/omarchy") .. "/default/hypr/bootstrap.lua")

-- Add ~/.config/hypr/?.lua to package.path so require("hypr.envs"),
-- require("hypr.bindings"), etc. resolve to the right files. The Omarchy
-- default config (require("default.hypr.omarchy")) normally does this, but
-- we're skipping that to avoid the libhyprgraphics deadlock.
package.path = (os.getenv("HOME") or "") .. "/.config/hypr/?.lua;" .. package.path

-- Load Omarchy's `o` helper module (defines o.bind, o.exec_on_start, etc).
-- This is what user bindings.lua / autostart.lua rely on. helpers.lua
-- itself does NOT trigger the libhyprgraphics deadlock (it's pure Lua
-- using hl.* built-ins), so it's safe to load directly even without
-- default.hypr.omarchy.
dofile((os.getenv("OMARCHY_PATH") or "/usr/share/omarchy") .. "/default/hypr/helpers.lua")

-- Anti-deadlock: must be the first hl.config() call so the splash
-- path is disabled before libhyprgraphics tries to load assets.
hl.config({
  misc = {
    disable_hyprland_logo = true,
    disable_splash_rendering = true,
    force_default_wallpaper = 0,
  },
  animations = {
    enabled = false,
  },
})

-- Per-session env (amdgpu card path, no llvmpipe — real hwaccel now).
require("hypr.envs")

-- Monitor layout (eDP-1 2560x1440 @ 1.25 scale, like before).
require("hypr.monitors")

-- Input (touchpad, keyboard).
require("hypr.input")

-- Omarchy default binds (pure hl.bind calls — no asset loading).
-- Loaded before hypr.bindings so user overrides take precedence.
require("default.hypr.bindings.media")
require("default.hypr.bindings.clipboard")
require("default.hypr.bindings.tiling")
require("default.hypr.bindings.utilities")
local require_optional = require("default.hypr.require_optional")
require_optional.module("default.hypr.bindings.voxtype")
require_optional.module("default.hypr.bindings.applications")

-- Omarchy window rules (per-app tags + opacity — no asset loading).
require("default.hypr.windows")

-- User bindings (overrides — come after Omarchy defaults so user wins).
require("hypr.bindings")

-- Skip looknfeel (Omarchy decoration + animations — deadlock trigger).
-- require("hypr.looknfeel")

-- Autostart: keep essential session services but skip the
-- `omarchy-launch-shell` path that pulls a lot of assets.
require("hypr.autostart")
