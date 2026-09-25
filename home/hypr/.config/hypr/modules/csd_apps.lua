-- Apps that draw their own title bar ("client-side decorations"): GNOME/GTK4 apps
-- like Finder, our Vorschau, browsers, Electron apps like Claude and Discord. They get no
-- second bar from riptide-wm. Their traffic lights come from our theme (GTK: gtk.css from
-- desktop-theme); Claude and Discord draw their own buttons, which cannot be restyled.
-- Not here: System Settings (Quickshell, no title bar of its own), kitty. Dragging/minimizing/zooming is done by our plugin
-- riptide-wm (plugins/riptide-wm/window_buttons.cpp).
-- Add more such apps here (class name: hyprctl clients).

local M = {}

-- As a regular expression for Hyprland's window rules
M.regex = "^(org\\.gnome\\..*|io\\.missioncenter\\..*|org\\.riptide\\.Preview|firefox|zen|app\\.zen_browser\\.zen|chromium-browser|google-chrome|discord|[Cc]laude|com\\.anthropic\\.Claude|thunderbird|org\\.mozilla\\.[Tt]hunderbird)$"

-- The same as a check function for Lua
local patterns = { "^org%.gnome%.", "^io%.missioncenter%.", "^org%.riptide%.Preview$", "^firefox$", "^zen$",
                   "^app%.zen_browser%.zen$", "^chromium%-browser$", "^google%-chrome$", "^discord$", "^[Cc]laude$", "^com%.anthropic%.Claude$",
                   "^thunderbird$", "^org%.mozilla%.[Tt]hunderbird$" }

function M.matches(w)
    if not w or not w.class then return false end
    for _, p in ipairs(patterns) do
        if w.class:match(p) then return true end
    end
    return false
end

return M
