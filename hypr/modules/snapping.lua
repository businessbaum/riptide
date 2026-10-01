-- Snap windows to screen edges (like macOS Sequoia / Windows):
--   drag to the top edge            → whole screen (without menu bar and dock)
--   drag to the left/right edge     → half screen
--   drag into a corner              → quarter
--   drag a snapped window away      → its old size comes back
-- Also, no window may disappear under the menu bar.
--
-- The end of a drag is reported by the title bar (option on_drag_end, our own patch
-- in patches/), for ⌘ + mouse drags by the mouse button itself.
-- The functions live in the global table "macos" so that hyprctl can call them:
--   hyprctl dispatch 'macos.drag_ended()'

macos = macos or {}

local S = require("modules.settings")
local csd_apps = require("modules.csd_apps")

local TITLEBAR_HEIGHT = 30          -- height of our title bar (see titlebars.lua)
local GAP             = S.windows.gap -- distance to edges, menu bar, dock and between windows
local ZONE            = 6           -- how close (px) the pointer must be to the edge
local CORNER          = 0.2         -- top/bottom fifth of a side edge counts as a corner
local DOCK_HEADROOM   = 40          -- transparent room above the dock plate (Quickshell dock)

-- Height of the bar above the window content: 0 for apps with their own title bar
local function titlebar(w)
    return csd_apps.matches(w) and 0 or TITLEBAR_HEIGHT
end

-- Size and position before snapping, so it can come back – kept in a file as well: a
-- config reload (e.g. a change in System Settings) starts Lua afresh, and zoomed windows
-- must not forget that they are zoomed (they would reopen with a margin, see below)
local before = {}
local STATE = (os.getenv("XDG_RUNTIME_DIR") or "/tmp") .. "/riptide/snapped.tsv"

local function save_before()
    local f = io.open(STATE, "w")
    if not f then
        os.execute("mkdir -p '" .. STATE:match("(.*)/") .. "'")
        f = io.open(STATE, "w")
        if not f then return end
    end
    for address, b in pairs(before) do
        f:write(string.format("%s\t%s\t%d\t%d\t%d\t%d\n", address, b.kind or "-", b.x, b.y, b.w, b.h))
    end
    f:close()
end

local function load_before()
    local f = io.open(STATE, "r")
    if not f then return end
    for line in f:lines() do
        local address, kind, x, y, w, h = line:match("^(%S+)\t(%S+)\t(-?%d+)\t(-?%d+)\t(%d+)\t(%d+)$")
        if address and hl.get_window("address:" .. address) then -- windows still open only
            before[address] = { kind = kind ~= "-" and kind or nil, x = tonumber(x), y = tonumber(y), w = tonumber(w), h = tonumber(h) }
        end
    end
    f:close()
end


-----------------
---- HELPERS ----
-----------------

-- Usable area of a monitor: without menu bar at the top and dock at the bottom
local function usable_area(m)
    local top, bottom = 0, 0
    for _, l in ipairs(hl.get_layers()) do
        if (l.namespace == "menubar" or l.namespace == "dock") and l.x >= m.x and l.x < m.x + m.width then
            if l.y == m.y then
                top = math.max(top, l.h)
            elseif l.y + l.h >= m.y + m.height - 20 then
                local plate_top = l.y + (l.namespace == "dock" and DOCK_HEADROOM or 0)
                bottom = math.max(bottom, m.y + m.height - plate_top)
            end
        end
    end
    return { x = m.x, y = m.y + top, w = m.width, h = m.height - top - bottom }
end

-- Is there another monitor at this point? Then it is not an outer edge.
-- (hl.get_monitor_at also returns the nearest monitor for points outside all
-- monitors, so we check ourselves whether the point really lies on one.)
local function monitor_at(x, y)
    for _, m in ipairs(hl.get_monitors()) do
        if x >= m.x and x < m.x + m.width and y >= m.y and y < m.y + m.height then
            return true
        end
    end
    return false
end

-- Target rectangle for the window content (the title bar sits above it)
local function target(kind, a, bar)
    local half_w = math.floor((a.w - 3 * GAP) / 2)
    local half_h = math.floor((a.h - 3 * GAP) / 2)
    local left   = a.x + GAP
    local right  = a.x + 2 * GAP + half_w
    local top    = a.y + GAP
    local bottom = a.y + 2 * GAP + half_h

    local r = ({
        -- maximized ("Zoom"): edge to edge – menu bar, screen sides and dock, no gap
        full        = { a.x, a.y, a.w, a.h },
        left        = { left, top, half_w, a.h - 2 * GAP },
        right       = { right, top, half_w, a.h - 2 * GAP },
        topleft     = { left, top, half_w, half_h },
        topright    = { right, top, half_w, half_h },
        bottomleft  = { left, bottom, half_w, half_h },
        bottomright = { right, bottom, half_w, half_h },
    })[kind]
    -- leave room for the title bar: content starts `bar` pixels lower
    return { x = r[1], y = r[2] + bar, w = r[3], h = r[4] - bar }
end

local function place(w, r)
    hl.dispatch(hl.dsp.window.resize({ window = w, x = r.w, y = r.h }))
    hl.dispatch(hl.dsp.window.move({ window = w, x = r.x, y = r.y }))
end

-- Tell the app whether it is zoomed ("maximized" in Wayland's words) – Hyprland itself
-- changes nothing. Apps with their own title bar (Discord, Finder) switch their own green
-- button by it; without it they asked to be maximized on every click and never came back.
local function tell_app(w, zoomed)
    if not w or w.fullscreen ~= 0 then return end
    hl.dispatch(hl.dsp.window.fullscreen_state({ window = w, internal = 0, client = zoomed and 1 or 0 }))
end

-- `old`: the size to come back to, when it is not the window's current one (a window
-- that reopens zoomed, window_memory.lua)
local snap_old -- (defined below: fills_screen, default_frame)
local function snap(w, kind, old)
    if not before[w.address] then
        before[w.address] = old or snap_old(w)
    end
    before[w.address].kind = kind
    save_before()
    local m = w.monitor or hl.get_monitor_at_cursor()
    place(w, target(kind, usable_area(m), titlebar(w)))
    tell_app(w, kind == "full")
end

local function unsnap(w)
    local old = before[w.address]
    before[w.address] = nil
    save_before()
    tell_app(w, false)
    return old
end

-- The frame of a zoomed window on its screen
local function full_frame(w)
    local m = w.monitor or hl.get_monitor_at_cursor()
    return m and target("full", usable_area(m), titlebar(w))
end

-- Does the window fill its screen like a zoomed one (to a pixel or two: Electron apps
-- sit one pixel off)?
local function fills_screen(w)
    local r = full_frame(w)
    return r ~= nil and math.abs(w.at.x - r.x) <= 2 and math.abs(w.at.y - r.y) <= 2
        and math.abs(w.size.x - r.w) <= 2 and math.abs(w.size.y - r.h) <= 2
end

-- The size the green button brings back for a window that was never smaller: a good
-- size in the middle of its screen
local function default_frame(w)
    local m = w.monitor or hl.get_monitor_at_cursor()
    local a, bar = usable_area(m), titlebar(w)
    local width, height = math.floor(a.w * 0.7), math.floor((a.h - bar) * 0.75)
    return { x = a.x + math.floor((a.w - width) / 2), y = a.y + bar + math.floor((a.h - bar - height) / 2), w = width, h = height }
end

-- The size to come back to when a window is snapped: its current one – unless it fills
-- the screen already (then coming back would change nothing)
snap_old = function(w)
    if fills_screen(w) then return default_frame(w) end
    return { x = w.at.x, y = w.at.y, w = w.size.x, h = w.size.y }
end

-- A window may not go under the menu bar
local function keep_below_menubar(w)
    local m = w.monitor or hl.get_monitor_at_cursor()
    local min_y = usable_area(m).y + titlebar(w)
    if w.at.y < min_y then
        hl.dispatch(hl.dsp.window.move({ window = w, x = w.at.x, y = min_y }))
    end
end


----------------------
---- AFTER A DRAG ----
----------------------

function macos.drag_ended()
    local w = hl.get_active_window()
    if not w or not w.floating or w.fullscreen ~= 0 then return hl.dsp.no_op() end
    if not S.windows.snapping then return hl.dsp.no_op() end

    local c = hl.get_cursor_pos()
    local m = hl.get_monitor_at_cursor()
    if not c or not m then return hl.dsp.no_op() end
    local a = usable_area(m)

    local at_left  = c.x <= m.x + ZONE and not monitor_at(m.x - 10, c.y)
    local at_right = c.x >= m.x + m.width - 1 - ZONE and not monitor_at(m.x + m.width + 10, c.y)
    local at_top   = c.y < a.y + ZONE and not monitor_at(c.x, m.y - 10)

    local kind
    if at_left or at_right then
        local side = at_left and "left" or "right"
        if c.y < a.y + a.h * CORNER then
            kind = "top" .. side
        elseif c.y > a.y + a.h * (1 - CORNER) then
            kind = "bottom" .. side
        else
            kind = side
        end
    elseif at_top then
        kind = "full"
    end

    if kind then
        snap(w, kind)
    else
        -- A snapped window was dragged away: old size, under the mouse pointer
        local old = unsnap(w)
        if old then
            local x = math.floor(c.x - old.w / 2)
            local y = math.floor(c.y + titlebar(w) / 2)
            place(w, { x = x, y = y, w = old.w, h = old.h })
            w = hl.get_active_window() or w
        end
        keep_below_menubar(w)
    end
    return hl.dsp.no_op()
end


------------------------------------------------
---- GREEN BUTTON / DOUBLE-CLICK: ZOOM ----
------------------------------------------------

-- Like "Zoom" on a Mac: fills the screen, the second time back to the old size.
-- Only for what the user does (title bar double-click, green button); the reason must be
-- given – an older riptide-wm called it for apps' own maximize requests, which zoomed
-- whatever window was active (e.g. the terminal).
function macos.zoom(reason)
    if not reason then return hl.dsp.no_op() end
    local w = hl.get_active_window()
    if not w or not w.floating then return hl.dsp.no_op() end
    local old = unsnap(w)
    if old then
        place(w, old)
    elseif fills_screen(w) then
        place(w, default_frame(w)) -- filled the screen already (by itself): a smaller size
        tell_app(w, false)
    else
        snap(w, "full")
    end
    return hl.dsp.no_op()
end

-- An app asks to be maximized or not (its own green button, or restoring its last state;
-- riptide-wm window_buttons.cpp): that window fills the screen or goes back, as asked.
-- Asking twice changes nothing.
function macos.maximize_request(address, on)
    local w = hl.get_window("address:" .. address)
    if not w or not w.floating or w.fullscreen ~= 0 then return hl.dsp.no_op() end
    local zoomed = before[w.address] ~= nil
    if on and not zoomed then
        snap(w, "full")
    elseif not on and zoomed then
        local old = unsnap(w)
        if old then place(w, old) end
    else
        tell_app(w, zoomed) -- asked for what it is already: it just did not know
    end
    return hl.dsp.no_op()
end

-- A window that window_memory.lua reopened in full screen: while it starts, it may ask
-- to leave it – Zen restores its saved "maximized" and GTK Firefox first leaves full screen
-- for that. That is the app setting itself up, not the user: for a few seconds it stays in
-- full screen and hears so again.
local reopened_full = {}
local function hold_fullscreen(w)
    local address = w.address
    reopened_full[address] = true
    hl.timer(function() reopened_full[address] = nil end, { timeout = 4000, type = "oneshot" })
end

-- An app asks for full screen or back (F11 in the browser, a video; riptide-wm
-- window_buttons.cpp). Not left to Hyprland: once tell_app() has told an app it is zoomed,
-- Hyprland passes such a request on to the app only and the window keeps its size.
-- Back from full screen, the window has its old frame again and the app learns whether
-- that is a zoomed one.
function macos.fullscreen_request(address, on)
    local w = hl.get_window("address:" .. address)
    if not w then return hl.dsp.no_op() end
    if not on and reopened_full[w.address] then
        hl.dispatch(hl.dsp.window.fullscreen_state({ window = w, internal = 2, client = 2 }))
        return hl.dsp.no_op()
    end
    if on then
        hl.dispatch(hl.dsp.window.fullscreen_state({ window = w, internal = 2, client = 2 }))
    else
        local zoomed = before[w.address] ~= nil and before[w.address].kind == "full"
        hl.dispatch(hl.dsp.window.fullscreen_state({ window = w, internal = 0, client = zoomed and 1 or 0 }))
    end
    return hl.dsp.no_op()
end

function macos.arrange(kind)
    return function()
        local w = hl.get_active_window()
        if not w or not w.floating then return end
        if kind == "restore" then
            local old = unsnap(w)
            if old then place(w, old) end
        else
            snap(w, kind)
        end
    end
end


------------------------------
---- DRAGGING WITH ⌘ + MOUSE ----
------------------------------

-- A ⌘ + left mouse drag has no title bar that reports its end. So we remember the
-- position of the active window on press and check on release whether it moved.
local drag_start

hl.bind("mouse:272", function()
    local w = hl.get_active_window()
    drag_start = w and { address = w.address, x = w.at.x, y = w.at.y } or nil
end, { non_consuming = true, ignore_mods = true })

hl.bind("mouse:272", function()
    local w = hl.get_active_window()
    if w and drag_start and drag_start.address == w.address
        and (w.at.x ~= drag_start.x or w.at.y ~= drag_start.y) then
        macos.drag_ended()
    end
    drag_start = nil
end, { non_consuming = true, ignore_mods = true, release = true })


------------------
---- SHORTCUTS ----
------------------

-- Like "Window > Move & Resize" on a Mac: ⌃⌥ + arrow keys
hl.bind("CTRL + ALT + left",  macos.arrange("left"))
hl.bind("CTRL + ALT + right", macos.arrange("right"))
hl.bind("CTRL + ALT + up",    macos.arrange("full"))
hl.bind("CTRL + ALT + down",  macos.arrange("restore"))

------------------------------
---- NEW WINDOWS FIT ON SCREEN ----
------------------------------

-- Some apps open larger than the screen (then the title bar is out of reach). A moment
-- after a window opens – when the app has chosen its size and window_memory.lua has
-- restored a remembered frame – shrink it to the free area and move it fully onto it.
local function fit_on_screen(address)
    local w = hl.get_window("address:" .. address)
    if not w or not w.floating or w.fullscreen ~= 0 then return end
    if before[address] then return end -- reopened zoomed or snapped: placed exactly
    if fills_screen(w) then
        -- opened filling the screen (by itself, or remembered so): that is zoomed, not
        -- too big – no margin; the green button brings a smaller size
        before[address] = default_frame(w)
        before[address].kind = "full"
        save_before()
        tell_app(w, true)
        return
    end
    local m = w.monitor or hl.get_monitor_at_cursor()
    if not m then return end
    local a, bar = usable_area(m), titlebar(w)

    local width  = math.min(w.size.x, a.w - 2 * GAP)
    local height = math.min(w.size.y, a.h - 2 * GAP - bar)
    local x = math.max(a.x + GAP, math.min(w.at.x, a.x + a.w - GAP - width))
    local y = math.max(a.y + GAP + bar, math.min(w.at.y, a.y + a.h - GAP - height))

    if width ~= w.size.x or height ~= w.size.y or x ~= w.at.x or y ~= w.at.y then
        place(w, { x = x, y = y, w = width, h = height })
    end
end

hl.on("window.open", function(w)
    if not w or not w.address then return end
    local address = w.address
    hl.timer(function() fit_on_screen(address) end, { timeout = 150, type = "oneshot" })
end)

-- Forget closed windows – a moment later, after window_memory.lua has read whether the
-- window was zoomed (its close handler runs after this one)
hl.on("window.close", function(w)
    if not w then return end
    local address = w.address
    hl.timer(function()
        before[address] = nil
        save_before()
    end, { timeout = 50, type = "oneshot" })
end)

load_before()

-- For window_memory.lua
return {
    -- how the window is snapped ("full" = zoomed, "left" …) and the size it had before
    snapped = function(w)
        local b = before[w.address]
        if not b and fills_screen(w) then return "full", default_frame(w) end
        return b and b.kind, b
    end,
    -- snap a reopened window again; `old` is the size the green button brings back
    snap = function(w, kind, old) snap(w, kind, old) end,
    -- a reopened window goes back to full screen (and stays there while it starts)
    fullscreen = function(w)
        hold_fullscreen(w)
        hl.dispatch(hl.dsp.window.fullscreen_state({ window = w, internal = 2, client = 2 }))
    end,
}
