-- Apps that draw their own title bar ("client-side decorations"): GNOME/GTK4 apps
-- like Finder, our own apps, browsers, Electron apps like Claude and Discord. They get no second
-- bar from hyprbars. Their traffic lights come from our theme (GTK: gtk4.css,
-- Zen: userChrome.css – see apps/desktop_shell/theme.py); Claude and Discord draw their own buttons,
-- which cannot be restyled. Dragging/minimizing/zooming is done by our plugin
-- window-buttons (plugins/window-buttons).
-- Add more such apps here (class name: hyprctl clients).

local M = {}

-- As a regular expression for Hyprland's window rules
M.regex = "^(org\\.gnome\\..*|org\\.riptide\\..*|firefox|chromium-browser|google-chrome)$"

-- The same as a check function for Lua
local patterns = { "^org%.gnome%.", "^org%.riptide%.", "^firefox$", "^chromium%-browser$", "^google%-chrome$" }

function M.matches(w)
    if not w or not w.class then return false end
    for _, p in ipairs(patterns) do
        if w.class:match(p) then return true end
    end
    return false
end

return M
