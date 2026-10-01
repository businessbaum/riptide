-- At Hyprland startup: background helpers of the session.
--
-- Everything is started through uwsm ("uwsm app --"), so each helper runs in its
-- own systemd scope with the session environment (~/.config/uwsm/env).
-- The shell itself (Quickshell) is started in shell.lua.

local S = require("modules.settings")

hl.on("hyprland.start", function()
    -- Clipboard history for SUPER+V: remember text and images
    hl.exec_cmd("uwsm app -- wl-paste --type text --watch cliphist store")
    hl.exec_cmd("uwsm app -- wl-paste --type image --watch cliphist store")

    -- Pointer theme (built by desktop-theme: black arrow, white hands like macOS)
    hl.exec_cmd("hyprctl setcursor " .. S.mouse.cursor_theme .. " " .. S.mouse.cursor_size)

    -- Our one plugin, riptide-wm (plugin/riptide-wm): title bars with traffic lights
    -- (titlebars.lua) and the macOS window behaviour. Loaded here and never from the
    -- config: loading triggers a config reload.
    -- Built by plugin/build.sh (next to this config folder) for one Hyprland version; after a Hyprland update
    -- it is rebuilt here first (a few seconds, the old build would crash).
    local build = require("modules.json").config_dir .. "/../plugin/build.sh"
    hl.exec_cmd((([[dir=~/.local/lib/hyprland-plugins
        running=$(hyprctl version -j | jq -r .tag | sed 's/^v//; s/-.*//')
        if [ "$(cat "$dir/built-for" 2>/dev/null)" != "$running" ]; then
            "@BUILD@" > ~/.local/state/macos/plugin-build.log 2>&1
            if [ "$(cat "$dir/built-for" 2>/dev/null)" != "$running" ]; then
                sleep 3
                notify-send -a System -i dialog-warning -u critical "Titelleisten fehlen" "Das Plugin ließ sich für Hyprland $running nicht bauen (~/.local/state/macos/plugin-build.log)."
                exit 0
            fi
        fi
        a=$(hyprctl plugin load "$dir/riptide-wm.so")
        if [ "$a" != ok ]; then
            sleep 3
            notify-send -a System -i dialog-warning -u critical "Plugin riptide-wm konnte nicht geladen werden" "$a"
        fi
        # Apply the whole config once more with the plugin present: the reloads it
        # triggers while loading can run before its options exist.
        hyprctl reload >/dev/null]]):gsub("@BUILD@", build)))
end)
