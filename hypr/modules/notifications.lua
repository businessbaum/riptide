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
-- Every error is also appended to ~/.local/state/macos/hyprland-errors.log (with time),
-- so it can still be read after the notification is gone.
local function check(delay)
    hl.exec_cmd("sleep " .. delay .. [=[; f=$(hyprctl configerrors | sed '/^[[:space:]]*$/d'); [ -n "$f" ] && { ]=]
        .. [=[mkdir -p ~/.local/state/macos; printf '%s\n%s\n\n' "$(date '+%F %T')" "$f" >> ~/.local/state/macos/hyprland-errors.log; ]=]
        .. notify_cmd(quote("Fehler in der Hyprland-Konfiguration"), [["$f"]], true) .. "; }")
end

hl.on("hyprland.start", function() check(3) end)
hl.on("config.reloaded", function() check(1) end)


-- Errors while running (in a key binding, an event handler, a timer) would show up as
-- Hyprland's own box and be gone once dismissed. Every function handed to hl.bind,
-- hl.on and hl.timer is therefore wrapped: an error becomes a notification (kept in the
-- notification centre) and a line in the error log, and the handler just stops.
local function report(where, err)
    local text = tostring(err):gsub("^[^\n]*/hypr/", "")
    hl.exec_cmd("mkdir -p ~/.local/state/macos; printf '%s\\n%s\\n\\n' \"$(date '+%F %T')\" " .. quote(where .. ": " .. text)
        .. " >> ~/.local/state/macos/hyprland-errors.log")
    M.show("Fehler in der Hyprland-Konfiguration", where .. ": " .. (text:match("^[^\n]*") or text), true)
end

local function guard(fn, where)
    if type(fn) ~= "function" then return fn end
    return function(...)
        local result = table.pack(xpcall(fn, debug.traceback, ...))
        if not result[1] then
            report(where, result[2])
            return nil
        end
        return table.unpack(result, 2, result.n)
    end
end

local raw_bind, raw_on, raw_timer = hl.bind, hl.on, hl.timer
hl.bind = function(keys, action, opts) return raw_bind(keys, guard(action, "Tastenkürzel " .. keys), opts) end
hl.on = function(event, fn) return raw_on(event, guard(fn, "Ereignis " .. event)) end
hl.timer = function(fn, opts) return raw_timer(guard(fn, "Timer"), opts) end

return M
