-- The single source of truth for everything the user can change.
--
--   ~/.config/macos/settings.json   user choices (written by the System Settings app)
--   data/theme.json                 design tokens (colours, radii, fonts) for light and dark
--
-- settings.json lives in ~/dotfiles/home/macos, theme.json in ~/dotfiles/data. The dock, control center, system settings,
-- menu bar, notifications, Spotlight and kitty read the same files (theme generator, stage 2),
-- so a change such as light/dark mode reaches every part of the desktop at once.
--
-- Returns the settings table with an extra field `theme`: the tokens of the active mode,
-- merged with the shared tokens (font, radius, accent).

local DEFAULTS = {
    appearance = { mode = "dark", blur = false },
    dock       = { size = 50, pinned = {} },
    windows    = { snapping = true, gap = 8, corner_radius = 12 },
    mouse      = { natural_scroll = false, speed = 0.0, scroll_factor = 1.0, cursor_size = 22,
                   cursor_theme = "capitaine-macos" },
    keyboard   = { layout = "de", cmd_shortcuts = true, repeat_delay = 600, repeat_rate = 25 },
    monitors   = {},
    accessibility = { reduce_motion = false, contrast = false, zoom_keys = false },
}

local json = require("modules.json")

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

local read = json.read

local settings, err = read("settings.json")
if not settings then
    require("modules.notifications").show("Einstellungen fehlerhaft", "Es gelten die Standardwerte.\n" .. err, true)
    settings = {}
end
fill_defaults(settings, DEFAULTS)

local theme = json.read_data("theme.json") or { modes = { dark = {}, light = {} } }
local active = {}
for k, v in pairs(theme.modes[settings.appearance.mode] or theme.modes.dark or {}) do active[k] = v end
active.font, active.radius = theme.font, theme.radius
-- the accent colour chosen in System Settings wins over the theme's
active.accent = (settings.appearance or {}).accent or theme.accent
active.traffic_lights = theme.traffic_lights or {}
settings.theme = active

return settings
