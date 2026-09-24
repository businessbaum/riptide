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

-- Size and position before snapping, so it can come back
local before = {}


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

local function snap(w, kind)
    if not before[w.address] then
        before[w.address] = { x = w.at.x, y = w.at.y, w = w.size.x, h = w.size.y }
    end
    local m = w.monitor or hl.get_monitor_at_cursor()
    place(w, target(kind, usable_area(m), titlebar(w)))
end

local function unsnap(w)
    local old = before[w.address]
    before[w.address] = nil
    return old
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

-- Like "Zoom" on a Mac: fills the screen, the second time back to the old size
function macos.zoom()
    local w = hl.get_active_window()
    if not w or not w.floating then return hl.dsp.no_op() end
    local old = unsnap(w)
    if old then
        place(w, old)
    else
        snap(w, "full")
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

-- Forget closed windows
hl.on("window.close", function(w)
    if w then before[w.address] = nil end
end)
