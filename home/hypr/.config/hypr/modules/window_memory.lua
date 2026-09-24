-- Windows remember their size and position, like on a Mac.
--
-- When the LAST window of an app closes, its frame (position + size) is stored. The next
-- time the app opens a window while it has no other window open, that window gets the
-- frame back. Dialogs that open next to a main window are left alone.
-- Frames that are no longer on any screen are ignored (the window opens centred).
--
-- Stored per app (window class) in ~/.local/state/macos/window-frames.tsv, one line per
-- app: class <tab> x <tab> y <tab> width <tab> height. It survives restarts.

local DIR  = os.getenv("HOME") .. "/.local/state/macos"
local FILE = DIR .. "/window-frames.tsv"

local frames = {}


-----------------
---- STORAGE ----
-----------------

local function load()
    local f = io.open(FILE, "r")
    if not f then return end
    for line in f:lines() do
        local class, x, y, w, h = line:match("^(.-)\t(-?%d+)\t(-?%d+)\t(%d+)\t(%d+)$")
        if class then
            frames[class] = { x = tonumber(x), y = tonumber(y), w = tonumber(w), h = tonumber(h) }
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
        f:write(string.format("%s\t%d\t%d\t%d\t%d\n", class, r.x, r.y, r.w, r.h))
    end
    f:close()
end

load()


-----------------
---- HELPERS ----
-----------------

-- Other open windows of the same app (not counting `w` itself)
local function others(w)
    local n = 0
    for _, o in ipairs(hl.get_windows()) do
        if o.address ~= w.address and o.class == w.class and o.mapped then n = n + 1 end
    end
    return n
end

-- Is the middle of the frame on one of the screens?
local function on_screen(r)
    local cx, cy = r.x + r.w / 2, r.y + r.h / 2
    for _, m in ipairs(hl.get_monitors()) do
        if cx >= m.x and cx < m.x + m.width and cy >= m.y and cy < m.y + m.height then
            return true
        end
    end
    return false
end

local function remembers(w)
    -- fullscreen is a number (0 = not fullscreen); in Lua even 0 counts as true
    local fullscreen = w and (w.fullscreen == true or (tonumber(w.fullscreen) or 0) ~= 0)
    return w and w.class and w.class ~= "" and w.floating and not fullscreen
end


----------------
---- EVENTS ----
----------------

hl.on("window.close", function(w)
    if not remembers(w) or others(w) > 0 then return end
    frames[w.class] = { x = w.at.x, y = w.at.y, w = w.size.x, h = w.size.y }
    save()
end)

hl.on("window.open", function(w)
    if not remembers(w) or others(w) > 0 then return end
    local r = frames[w.class]
    if not r or not on_screen(r) then return end
    hl.dispatch(hl.dsp.window.resize({ window = w, x = r.w, y = r.h }))
    hl.dispatch(hl.dsp.window.move({ window = w, x = r.x, y = r.y }))
end)
