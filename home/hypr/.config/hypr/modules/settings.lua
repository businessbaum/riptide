-- The single source of truth for everything the user can change.
--
--   ~/.config/macos/settings.json   user choices (written by the System Settings app)
--   ~/.config/macos/theme.json      design tokens (colours, radii, fonts) for light and dark
--
-- Both live in nixos-config/dotfiles/macos. The dock, control center, system settings,
-- menu bar, notifications, rofi and kitty read the same files (see apps/desktop_shell/theme.py),
-- so a change such as light/dark mode reaches every part of the desktop at once.
--
-- Returns the settings table with an extra field `theme`: the tokens of the active mode,
-- merged with the shared tokens (font, radius, accent).

local DEFAULTS = {
    appearance = { mode = "dark" },
    dock       = { size = 50, pinned = {} },
    windows    = { snapping = true, gap = 8, corner_radius = 12 },
    mouse      = { natural_scroll = false, speed = 0.0, cursor_size = 22 },
    keyboard   = { layout = "de", cmd_shortcuts = true, repeat_delay = 600, repeat_rate = 25 },
    monitors   = {},
}

---------------------------------------------
---- minimal JSON reader (enough for our files)
---------------------------------------------

local function parse_json(text)
    local pos = 1
    local value

    local function skip() pos = text:find("[^ \t\r\n]", pos) or #text + 1 end
    local function fail(what) error(what .. " at character " .. pos) end

    local function str()
        local parts = {}
        pos = pos + 1
        while true do
            local c = text:sub(pos, pos)
            if c == "" then fail("unterminated string") end
            if c == '"' then pos = pos + 1; return table.concat(parts) end
            if c == "\\" then
                local n = text:sub(pos + 1, pos + 1)
                local repl = ({ ['"'] = '"', ["\\"] = "\\", ["/"] = "/", n = "\n", t = "\t", r = "\r", b = "\b", f = "\f" })[n]
                if n == "u" then
                    repl = utf8.char(tonumber(text:sub(pos + 2, pos + 5), 16)); pos = pos + 4
                end
                if not repl then fail("unknown escape \\" .. n) end
                parts[#parts + 1] = repl; pos = pos + 2
            else
                parts[#parts + 1] = c; pos = pos + 1
            end
        end
    end

    function value()
        skip()
        local c = text:sub(pos, pos)
        if c == "{" then
            local t = {}; pos = pos + 1; skip()
            if text:sub(pos, pos) == "}" then pos = pos + 1; return t end
            while true do
                skip(); if text:sub(pos, pos) ~= '"' then fail("key expected") end
                local k = str(); skip()
                if text:sub(pos, pos) ~= ":" then fail("':' expected") end
                pos = pos + 1; t[k] = value(); skip()
                local s = text:sub(pos, pos); pos = pos + 1
                if s == "}" then return t end
                if s ~= "," then fail("',' or '}' expected") end
            end
        elseif c == "[" then
            local t = {}; pos = pos + 1; skip()
            if text:sub(pos, pos) == "]" then pos = pos + 1; return t end
            while true do
                t[#t + 1] = value(); skip()
                local s = text:sub(pos, pos); pos = pos + 1
                if s == "]" then return t end
                if s ~= "," then fail("',' or ']' expected") end
            end
        elseif c == '"' then return str()
        elseif text:sub(pos, pos + 3) == "true" then pos = pos + 4; return true
        elseif text:sub(pos, pos + 4) == "false" then pos = pos + 5; return false
        elseif text:sub(pos, pos + 3) == "null" then pos = pos + 4; return nil
        else
            local num = text:match("^-?%d+%.?%d*[eE]?[-+]?%d*", pos)
            if not num or num == "" then fail("unexpected character") end
            pos = pos + #num
            return tonumber(num)
        end
    end

    return value()
end

local function fill_defaults(target, defaults)
    for k, v in pairs(defaults) do
        if target[k] == nil then
            target[k] = v
        elseif type(v) == "table" and type(target[k]) == "table" then
            fill_defaults(target[k], v)
        end
    end
    return target
end

local DIR = os.getenv("HOME") .. "/.config/macos/"

local function read(name)
    local f = io.open(DIR .. name, "r")
    if not f then return nil, name .. " not found" end
    local text = f:read("a"); f:close()
    local ok, data = pcall(parse_json, text)
    if not ok or type(data) ~= "table" then return nil, name .. ": " .. tostring(data) end
    return data
end

local settings, err = read("settings.json")
if not settings then
    require("modules.notifications").show("Einstellungen fehlerhaft", "Es gelten die Standardwerte.\n" .. err, true)
    settings = {}
end
fill_defaults(settings, DEFAULTS)

local theme = read("theme.json") or { modes = { dark = {}, light = {} } }
local active = {}
for k, v in pairs(theme.modes[settings.appearance.mode] or theme.modes.dark or {}) do active[k] = v end
active.font, active.radius, active.accent = theme.font, theme.radius, theme.accent
active.traffic_lights = theme.traffic_lights or {}
settings.theme = active

return settings
