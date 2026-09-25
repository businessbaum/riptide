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

    -- Our one plugin, riptide-wm (plugins/riptide-wm): title bars with traffic lights
    -- (titlebars.lua) and the macOS window behaviour. Loaded here and never from the
    -- config: loading triggers a config reload.
    -- Built by ~/dotfiles/plugins/build.sh for one Hyprland version; after an update it is
    -- not loaded (would crash) and a notification asks for a rebuild.
    -- (Until riptide-wm has proven itself: if it does not load, the two plugins it replaced.)
    hl.exec_cmd([[dir=~/.local/lib/hyprland-plugins
        running=$(hyprctl version -j | jq -r .tag | sed 's/^v//; s/-.*//')
        if [ "$(cat "$dir/built-for" 2>/dev/null)" != "$running" ]; then
            sleep 3
            notify-send -a System -i dialog-warning -u critical "Titelleisten fehlen" "Das Plugin passt nicht zu Hyprland $running. Neu bauen: ~/dotfiles/plugins/build.sh, dann ab- und wieder anmelden."
            exit 0
        fi
        a=$(hyprctl plugin load "$dir/riptide-wm.so")
        if [ "$a" != ok ]; then
            sleep 3
            notify-send -a System -i dialog-warning -u critical "Plugin riptide-wm konnte nicht geladen werden" "$a"
            for p in hyprbars window-buttons; do
                [ -f "$dir/$p.so" ] && hyprctl plugin load "$dir/$p.so" >/dev/null
            done
        fi
        # Apply the whole config once more with the plugin present: the reloads it
        # triggers while loading can run before its options exist.
        hyprctl reload >/dev/null]])
end)
