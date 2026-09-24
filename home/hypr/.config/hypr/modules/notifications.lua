-- Errors and notices appear like on a Mac: as a notification in the top right
-- (our notification server in Quickshell) instead of Hyprland's own error bar.
-- As long as no notification server runs, Hyprland's small built-in notice
-- (hyprctl notify) is used instead, never the error bar.
--   Errors stay until clicked away (urgent = true), notices disappear after a few seconds.

local M = {}

-- Turn off Hyprland's own error bar – we show errors ourselves below
hl.config({ debug = { suppress_errors = true } })

local function quote(text)
    return "'" .. (tostring(text or ""):gsub("'", "'\\''")) .. "'"
end

-- Shell command: notify-send, or Hyprland's own notice if no notification server
-- runs. `title` and `text` must already be shell words (quoted or "$var").
local function notify_cmd(title, text, urgent)
    return string.format([[notify-send -a System -i %s %s %s %s 2>/dev/null || hyprctl notify %d 10000 0 %s": "%s >/dev/null]],
        urgent and "dialog-warning" or "dialog-information", urgent and "-u critical" or "",
        title, text, urgent and 0 or 1, title, text)
end

function M.show(title, text, urgent)
    hl.exec_cmd(notify_cmd(quote(title), quote(text), urgent))
end

-- After every (re)load of the config: are there errors? Then show them as a notification.
-- At startup wait a moment until the notification server is running.
local function check(delay)
    hl.exec_cmd("sleep " .. delay .. [=[; f=$(hyprctl configerrors | sed '/^[[:space:]]*$/d'); [ -n "$f" ] && { ]=] ..
        notify_cmd(quote("Fehler in der Hyprland-Konfiguration"), [["$f"]], true) .. "; }")
end

hl.on("hyprland.start", function() check(3) end)
hl.on("config.reloaded", function() check(1) end)

return M
