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

    hl.exec_cmd("hyprctl setcursor Adwaita " .. S.mouse.cursor_size)

    -- Plugins, one after another (each load triggers a config reload – that is why this
    -- happens here and never in the config itself):
    --   hyprbars        title bars with traffic lights (titlebars.lua)
    --   window-buttons  drag/minimize/zoom for apps with their own title bar
    -- Built by ~/dotfiles/plugins/build.sh for one Hyprland version; after an update they
    -- are not loaded (would crash) and a notification asks for a rebuild.
    hl.exec_cmd([[dir=~/.local/lib/hyprland-plugins
        running=$(hyprctl version -j | jq -r .tag | sed 's/^v//; s/-.*//')
        if [ "$(cat "$dir/built-for" 2>/dev/null)" != "$running" ]; then
            sleep 3
            notify-send -a System -i dialog-warning -u critical "Titelleisten fehlen" "Die Plugins passen nicht zu Hyprland $running. Neu bauen: ~/dotfiles/plugins/build.sh, dann ab- und wieder anmelden."
            exit 0
        fi
        for p in hyprbars window-buttons; do
            a=$(hyprctl plugin load "$dir/$p.so")
            [ "$a" = ok ] || { sleep 3; notify-send -a System -i dialog-warning -u critical "Plugin „$p“ konnte nicht geladen werden" "$a"; }
        done]])
end)
