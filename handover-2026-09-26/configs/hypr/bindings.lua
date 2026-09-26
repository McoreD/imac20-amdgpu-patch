-- Keep only your personal keybinding overrides here. Add new bindings or
-- unbind defaults before replacing them.

-- MiniMax Code as a first-class Omarchy agent (same chord as Grok's launcher,
-- routed through a user wrapper because packaged omarchy-agent does not know mcode).
-- SUPER + SHIFT + CTRL + A was: Agent (omarchy-agent --pick)
hl.unbind("SUPER + SHIFT + CTRL + A")
o.bind("SUPER + SHIFT + CTRL + A", "Agent", "/home/mike/.local/bin/omarchy-agent-plus --pick")
-- SUPER + SHIFT + ALT + A remains Grok web. MiniMax Agent web is the sibling chord.
o.bind("SUPER + SHIFT + ALT + I", "MiniMax Agent", { webapp = "https://agent.minimax.io" })

-- See current bindings and descriptions:
--   omarchy menu keybindings --print

-- To disable every Omarchy default binding, set this in
-- ~/.config/hypr/hyprland.lua before require("default.hypr.omarchy"), then add
-- only the bindings you want below:
--   omarchy_default_bindings = false

-- To disable all preinstalled app/webapp bindings, set:
--   omarchy_preinstalled_bindings = false

-- Add a new binding.
-- o.bind("SUPER + SHIFT + R", "SSH", "alacritty -e ssh your-server")

-- Change an existing binding by unbinding it first, then binding the key again.
-- This example changes SUPER+SPACE from the launcher to the Omarchy root menu.
-- hl.unbind("SUPER + SPACE")
-- o.bind("SUPER + SPACE", "Omarchy menu", "omarchy-menu toggle root")

-- Disable a default binding without replacing it.
-- hl.unbind("SUPER + SHIFT + B")

-- SUPER + SHIFT + SPACE was: Toggle top bar
hl.unbind("SUPER + SHIFT + SPACE")

-- Screenshot binding: plain F1 is taken by the XerahS portal
-- (xerahs:3 / xerahs:13), so bind Shift+F1 instead.
-- PRINT was: Screenshot (omarchy-capture-screenshot)
hl.unbind("PRINT")
o.bind("SHIFT + F1", "Screenshot", "omarchy-capture-screenshot")

-- Task Manager (omarchy-task-manager): Super+Alt+Delete opens or focuses the
-- floating panel shipped by tcballard/omarchy-task-manager. The shortcut is
-- unassigned in upstream Omarchy bindings and Ctrl+Alt+Delete is already used
-- for "Close all windows". Source build writes this example to
-- /usr/share/omarchy-task-manager/bindings.lua.example.
o.bind("SUPER + ALT + DELETE", "Task Manager", "omarchy-task-manager")

-- Screencast binding: move the default ALT+PRINT trigger to Shift+F8
-- so it sits next to the screenshot key without fighting the PRINT key
-- that XerahS already claims. The wrapper uses wf-recorder because this
-- iMac20,1 boots with nomodeset, so card0 is bound to simple-framebuffer
-- and gpu-screen-recorder cannot create an EGL context (llvmpipe fallback
-- is rejected). wf-recorder uses wlr-screencopy over Wayland directly and
-- needs no GPU access.
-- ALT + PRINT was: Screenrecording (stop-or-toggle)
hl.unbind("ALT + PRINT")
o.bind("SHIFT + F8", "Screencast", "/home/mike/.local/bin/screencast-wfrec")

-- Photon Messages operator console (io.github.kovaforge.photon).
-- SUPER + M was unbound. SUPER + SHIFT + M remains Music.
o.bind("SUPER + M", "Photon messages", [[sh -c '
  photon() { hyprctl clients -j | jq -r ".[] | select(.class == \"org.quickshell\" and (.title | test(\"^Photon( [(][0-9]+[)])?$\"))) | .address" | head -1; }
  a=$(photon)
  if [ -z "$a" ]; then
    omarchy-shell photon app >/dev/null
    for i in 1 2 3 4 5 6 7 8 9 10 11 12; do a=$(photon); [ -n "$a" ] && break; sleep 0.15; done
    [ -n "$a" ] && hyprctl dispatch "hl.dsp.focus({ window = \"address:$a\" })"
  elif [ "$(hyprctl activewindow -j | jq -r .address)" = "$a" ]; then
    hyprctl dispatch "hl.dsp.window.close({ window = \"address:$a\" })"
  else
    hyprctl dispatch "hl.dsp.focus({ window = \"address:$a\" })"
  fi']])
o.bind("SUPER + CTRL + M", "Photon panel", "omarchy-shell shell toggle io.github.kovaforge.photon")

-- Logitech MX Keys examples:
-- o.bind("SUPER + SHIFT + S", nil, "omarchy-capture-screenshot")
-- o.bind("SUPER + H", nil, "voxtype record toggle")
-- o.bind("SUPER + PERIOD", nil, "omarchy-shell shell toggle omarchy.emojis")
