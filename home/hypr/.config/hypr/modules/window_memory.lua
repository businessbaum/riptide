-- Windows remember their size and position, like on a Mac.
--
-- When the LAST window of an app closes, its frame is stored: position on its screen,
-- size, and whether it was zoomed or snapped to an edge (then also the size the green
-- button brings back). The next time the app opens a window while it has no other window
-- open, that window gets the frame back – on the screen the pointer is on, where you
-- clicked the app in the dock – zoomed again if it was. Dialogs next to a main window are
-- left alone.
--
-- Stored per app (window class) in ~/.local/state/macos/window-frames.tsv, one line per
-- app: class, x, y (from the screen's top left corner), width, height, snap ("-" = none),
-- and for a snapped window its old x, y, width, height. It survives restarts.
-- (Older lines have only class and x, y, w, h on the whole desktop; they are converted.)

local snapping = require("modules.snapping")

local DIR  = os.getenv("HOME") .. "/.local/state/macos"
local FILE = DIR .. "/window-frames.tsv"

local frames = {}


-----------------
---- HELPERS ----
-----------------

-- The screen a point lies on (nil if on none)
local function monitor_at(x, y)
    for _, m in ipairs(hl.get_monitors()) do
        if x >= m.x and x < m.x + m.width and y >= m.y and y < m.y + m.height then
            return m
        end
    end
end

-- Other open windows of the same app (not counting `w` itself)
local function others(w)
    local n = 0
    for _, o in ipairs(hl.get_windows()) do
        if o.address ~= w.address and o.class == w.class and o.mapped then n = n + 1 end
    end
    return n
end

local function remembers(w)
    -- fullscreen is a number (0 = not fullscreen); in Lua even 0 counts as true
    local fullscreen = w and (w.fullscreen == true or (tonumber(w.fullscreen) or 0) ~= 0)
    return w and w.class and w.class ~= "" and w.floating and not fullscreen
end


-----------------
---- STORAGE ----
-----------------

local converted = false

local function load()
    local f = io.open(FILE, "r")
    if not f then return end
    for line in f:lines() do
        local fields = {}
        for field in line:gmatch("[^\t]+") do fields[#fields + 1] = field end
        local class = fields[1]
        local n = {}
        for i = 2, #fields do n[i] = tonumber(fields[i]) end
        if class and n[2] and n[3] and n[4] and n[5] then
            local r = { x = n[2], y = n[3], w = n[4], h = n[5] }
            if #fields == 5 then
                -- old line: on the whole desktop → from its screen's corner
                local m = monitor_at(r.x + r.w / 2, r.y + r.h / 2)
                if m then r.x, r.y = r.x - m.x, r.y - m.y end
                converted = true
            elseif fields[6] ~= "-" then
                r.kind = fields[6]
                if n[10] then r.old = { x = n[7], y = n[8], w = n[9], h = n[10] } end
            end
            frames[class] = r
        end
    end
    f:close()
end

local function save()
    local f = io.open(FILE, "w")
    if not f then
        os.execute("mkdir -p '" .. DIR .. "'")
        f = io.open(FILE, "w")
        if not f then return end
    end
    for class, r in pairs(frames) do
        local line = string.format("%s\t%d\t%d\t%d\t%d\t%s", class, r.x, r.y, r.w, r.h, r.kind or "-")
        if r.old then
            line = line .. string.format("\t%d\t%d\t%d\t%d", r.old.x, r.old.y, r.old.w, r.old.h)
        end
        f:write(line .. "\n")
    end
    f:close()
end

load()
if converted then save() end


----------------
---- EVENTS ----
----------------

hl.on("window.close", function(w)
    if not remembers(w) or others(w) > 0 then return end
    local m = monitor_at(w.at.x + w.size.x / 2, w.at.y + w.size.y / 2) or w.monitor
    if not m then return end
    local r = { x = w.at.x - m.x, y = w.at.y - m.y, w = w.size.x, h = w.size.y }
    local kind, old = snapping.snapped(w)
    if kind then
        r.kind = kind
        r.old = { x = old.x - m.x, y = old.y - m.y, w = old.w, h = old.h }
    end
    frames[w.class] = r
    save()
end)

hl.on("window.open", function(w)
    if not remembers(w) or others(w) > 0 then return end
    local r = frames[w.class]
    local m = hl.get_monitor_at_cursor()
    if not r or not m then return end
    if r.kind then
        -- first its normal size (what the green button brings back), then zoomed/snapped
        local old = r.old and { x = m.x + r.old.x, y = m.y + r.old.y, w = r.old.w, h = r.old.h }
        if old then
            hl.dispatch(hl.dsp.window.resize({ window = w, x = old.w, y = old.h }))
            hl.dispatch(hl.dsp.window.move({ window = w, x = old.x, y = old.y }))
        end
        snapping.snap(hl.get_window("address:" .. w.address) or w, r.kind, old)
        return
    end
    hl.dispatch(hl.dsp.window.resize({ window = w, x = r.w, y = r.h }))
    hl.dispatch(hl.dsp.window.move({ window = w, x = m.x + r.x, y = m.y + r.y }))
end)
