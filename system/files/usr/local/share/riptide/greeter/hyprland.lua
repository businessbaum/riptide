-- Hyprland for riptide's login screen (greetd, user "greeter"): nothing but our login
-- window (Quickshell, layer surfaces). Started by /usr/local/lib/riptide/greeter/start.

hl.monitor({ output = "", mode = "preferred", position = "auto", scale = "auto" })

local function read(path)
    local f = io.open(path, "r")
    if not f then return nil end
    local text = f:read("a")
    f:close()
    return text
end

-- Mouse and keyboard as in the session of the person who logged in last: their session
-- leaves the values here (hypr/modules/greeter.lua). Only checked numbers and a layout
-- name are taken – the file belongs to that person, this runs as "greeter".
local input = {
    kb_layout = "de",
    numlock_by_default = true,
    -- no ⌃⌥F1 … F12: there are no text consoles to switch to
    kb_options = "srvrkeys:none",
}
local cursor_size = 22
local function clamp(n, lo, hi) return math.max(lo, math.min(hi, n)) end
local last = (read("/var/lib/riptide/greeter/last-user") or ""):match("^%s*([%w._-]+)%s*$")
if last then
    for line in (read("/var/lib/riptide/greeter/users/" .. last .. "/input.conf") or ""):gmatch("[^\n]+") do
        local key, value = line:match("^([%w_]+)=(.*)$")
        local n = tonumber(value)
        if key == "sensitivity" and n then input.sensitivity = clamp(n, -1, 1)
        elseif key == "scroll_factor" and n then input.scroll_factor = clamp(n, 0.1, 10)
        elseif key == "natural_scroll" then input.natural_scroll = value == "true"
        elseif key == "kb_layout" and value:match("^[%a,]+$") and #value < 40 then input.kb_layout = value
        elseif key == "repeat_rate" and n then input.repeat_rate = math.floor(clamp(n, 1, 100))
        elseif key == "repeat_delay" and n then input.repeat_delay = math.floor(clamp(n, 100, 2000))
        elseif key == "cursor_size" and n then cursor_size = math.floor(clamp(n, 16, 96))
        end
    end
end

hl.config({
    input = input,
    general = { border_size = 0, gaps_in = 0, gaps_out = 0 },
    decoration = { rounding = 0, shadow = { enabled = false }, blur = { enabled = false } },
    misc = {
        background_color = "rgb(1b2a4a)",
        disable_hyprland_logo = true,
        disable_splash_rendering = true,
        disable_autoreload = true,
        -- started without start-hyprland on purpose: our start script watches it
        disable_watchdog_warning = true,
    },
    ecosystem = { no_update_news = true, no_donation_nag = true },
    -- the cursor is not written to GNOME's settings (there is no session bus: start)
    cursor = { sync_gsettings_theme = false },
})

-- the login window fades in, nothing else moves
hl.curve("smooth", { type = "bezier", points = { {0.25, 0.1}, {0.25, 1} } })
hl.animation({ leaf = "global", enabled = false })
hl.animation({ leaf = "fadeLayersIn", enabled = true, speed = 4, bezier = "smooth" })

hl.on("hyprland.start", function()
    hl.exec_cmd("hyprctl setcursor capitaine-cursors " .. cursor_size)
    hl.exec_cmd("/usr/local/lib/riptide/greeter/run")
end)

-- Emergency: ⌃⌥F1 … F6 end the login window; the start script then offers the text login
-- (with a shell for repairs). There are no text consoles to switch to (srvrkeys:none).
for i = 1, 6 do
    hl.bind("CTRL + ALT + F" .. i, hl.dsp.exit())
end
