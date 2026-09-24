-- Errors and notices appear like on a Mac: as a notification in the top right
-- (swaync) instead of Hyprland's own error bar at the screen edge.
--   Errors stay until clicked away (urgent = true), notices disappear after a few seconds.

local M = {}

-- Turn off Hyprland's own error bar – we show errors ourselves below
hl.config({ debug = { suppress_errors = true } })

local function quote(text)
    return "'" .. (tostring(text or ""):gsub("'", "'\\''")) .. "'"
end

function M.show(title, text, urgent)
    hl.exec_cmd(string.format("notify-send -a System -i %s %s %s %s",
        urgent and "dialog-warning" or "dialog-information",
        urgent and "-u critical" or "", quote(title), quote(text)))
end

-- After every (re)load of the config: are there errors? Then show them as a notification.
-- At startup wait a moment until the notification daemon (swaync) is running.
local function check(delay)
    hl.exec_cmd("sleep " .. delay .. [=[; f=$(hyprctl configerrors | sed '/^[[:space:]]*$/d');]=] ..
        [=[ [ -n "$f" ] && notify-send -a System -i dialog-warning -u critical "Fehler in der Hyprland-Konfiguration" "$f"]=])
end

hl.on("hyprland.start", function() check(3) end)
hl.on("config.reloaded", function() check(1) end)

return M
