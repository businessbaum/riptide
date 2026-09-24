-- At Hyprland startup: theme, plugins, wallpaper, menu bar, dock, notifications, control center, clipboard history.

local S = require("modules.settings")

hl.on("hyprland.start", function()
    -- First the theme: writes the colour files that menu bar, notifications, rofi and
    -- kitty import (apps/desktop_shell/theme.py). Everything else starts after it.
    hl.exec_cmd("desktop-theme; " ..
        "waybar -c ~/.config/waybar/menubar.jsonc -s ~/.config/waybar/menubar.css & " ..
        "swaync &")

    -- Load plugins one after another (each one triggers a config reload):
    --   hyprbars        title bars with traffic lights (settings in titlebars.lua)
    --   window-buttons  drag/minimize/zoom for apps with their own title bar
    -- If loading fails, the error appears as a notification.
    hl.exec_cmd([[for p in hyprbars window-buttons; do
        a=$(hyprctl plugin load /etc/hypr/plugins/$p.so)
        [ "$a" = ok ] || { sleep 3; notify-send -a System -i dialog-warning -u critical "Plugin „$p“ konnte nicht geladen werden" "$a"; }
    done]])

    -- Wallpaper: first the default from hyprpaper.conf, then the image from the settings
    hl.exec_cmd("hyprpaper")
    local image = S.appearance.wallpaper
    if image then
        for _, m in ipairs(hl.get_monitors()) do
            hl.exec_cmd(string.format("sleep 1; hyprctl hyprpaper wallpaper '%s, %s, cover'", m.name, image))
        end
    end

    -- Dock and control center (our own apps, see nixos-config/apps).
    -- The control center waits invisibly, so it appears instantly when clicked.
    hl.exec_cmd("dock")
    hl.exec_cmd("control-center --background")
    hl.exec_cmd("switcher --background") -- panel for ⌥Tab / ⌘Tab (switcher.lua)
    hl.exec_cmd("osd --background")      -- volume display for the volume keys (keys.lua)

    -- Clipboard history for SUPER+V (scripts/clipboard.sh): remember text and images
    hl.exec_cmd("wl-paste --type text --watch cliphist store")
    hl.exec_cmd("wl-paste --type image --watch cliphist store")

    -- Password dialog for actions that need administrator rights (e.g. firewall)
    -- Started by Hyprland itself, not as a systemd user service: polkit only accepts a
    -- dialog that runs inside our login session, and user services run outside of it.
    hl.exec_cmd("soteria")
    hl.exec_cmd("hyprctl setcursor macOS " .. S.mouse.cursor_size)
end)
