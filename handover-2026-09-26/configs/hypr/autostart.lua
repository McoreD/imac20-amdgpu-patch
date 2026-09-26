-- Omarchy taskbar / Quickshell. Skipped from `default.hypr.autostart`
-- (which would re-load `default.hypr.omarchy` -> gatherer-trigger), so
-- we start it manually here. Safe because Quickshell is QML-based and
-- doesn't touch libhyprgraphics / Hyprland decoration assets.
o.exec_on_start("omarchy-launch-shell")

-- Auto-mounter tray (was in default.hypr.autostart; added manually here).
o.exec_on_start("udiskie --automount --no-notify --no-tray")

-- Monitor hot-plug watcher (was in default.hypr.autostart).
o.exec_on_start("omarchy-hyprland-monitor-watch")

-- Discord web app (stock Omarchy Discord.desktop).
o.exec_on_start("gtk-launch Discord")

-- ScanSnap S1100 hardware button watcher (also a user systemd service).
hl.exec_cmd("systemctl --user start scansnap-button.service")
