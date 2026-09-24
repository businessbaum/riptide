-- Switching between windows and apps, like on Windows and on a Mac:
--   ⌥Tab  (ALT + Tab)    all windows, most recently used first   (Windows)
--   ⌘Tab  (SUPER + Tab)  all apps, one entry per app              (Mac)
-- Keep ⌥ / ⌘ held and press Tab again for the next one (⇧Tab: back), release to switch.
-- A quick tap jumps straight to the previous window/app. Esc cancels.
--
-- The logic lives here; the panel with the icons is drawn by the shell
-- (Quickshell, Switcher.qml), which only displays what it is told. Hyprland sends it
-- custom events ("custom>>switcher>>…") over its event socket – no extra process.
-- Minimized windows and windows on other desktops are included and brought back.

macos = macos or {}

local state   -- nil, or { mode = "windows"|"apps", entries = { window, … }, index = n }
local seq = 0 -- numbers every message, so the panel can ignore ones that arrive late


-----------------
---- HELPERS ----
-----------------

local function tell_panel(action, payload)
    seq = seq + 1
    hl.dispatch(hl.dsp.event(string.format("switcher>>%s|%d|%s", action, seq, payload or "")))
end

-- Helper windows that belong to another app (file dialogs, dialogs) – same list
-- as helperPattern in the shell (Apps.qml)
local function helper(w)
    local c = w.class:lower()
    return c:match("^xdg%-desktop%-portal") or c:match("^hyprland%-dialog$")
        or c:match("^hyprland%-run$") or c:match("^org%.quickshell$")
end

-- Windows that can be switched to, most recently used first
local function windows_by_recent_use()
    local list = {}
    for _, w in ipairs(hl.get_windows()) do
        if w.mapped and w.class and w.class ~= "" and not helper(w) then
            list[#list + 1] = w
        end
    end
    table.sort(list, function(a, b) return a.focus_history_id < b.focus_history_id end)
    return list
end

-- One entry per app: its most recently used window
local function apps_by_recent_use()
    local list, seen = {}, {}
    for _, w in ipairs(windows_by_recent_use()) do
        if not seen[w.class] then
            seen[w.class] = true
            list[#list + 1] = w
        end
    end
    return list
end

local function show()
    local addresses = {}
    for i, w in ipairs(state.entries) do addresses[i] = w.address end
    local monitor = hl.get_monitor_at_cursor()
    tell_panel("show", string.format("%s|%d|%s|%s", state.mode, state.index,
        monitor and monitor.name or "", table.concat(addresses, ",")))
end

-- Bring a window to the front – also from the minimized desktop or another desktop
local function bring_to_front(w)
    local ws = w.workspace
    if ws and ws.name and ws.name:match("^special:") then
        local active = hl.get_active_workspace()
        hl.dispatch(hl.dsp.window.move({ window = w, workspace = active and active.id or 1, follow = false }))
    end
    hl.dispatch(hl.dsp.focus({ window = w }))
    hl.dispatch(hl.dsp.window.bring_to_top({ window = w }))
end

local function finish(switch)
    if not state then return end
    local target = switch and state.entries[state.index]
    state = nil
    tell_panel("hide")
    if target then bring_to_front(target) end
end


-----------------------
---- KEY HANDLING ----
-----------------------

-- Which keys count as "⌘ held" / "⌥ held" (names and key codes)
local MOD_KEYS = {
    apps    = { "Super_L", "Super_R", 133, 134 },
    windows = { "Alt_L", "Alt_R", 64, 108 },
}

local function held(mode)
    for _, k in ipairs(MOD_KEYS[mode]) do
        local ok, down = pcall(hl.is_key_down, k)
        if ok and down == true then return true end
    end
    return false
end


local function step(mode, direction)
    return function()
        if not state or state.mode ~= mode then
            local entries = mode == "apps" and apps_by_recent_use() or windows_by_recent_use()
            if #entries == 0 then return end
            -- the first press already selects the previous window/app (entry 1 is the current one)
            state = { mode = mode, entries = entries, index = 1 }
            seen_held = held(mode)
        end
        local n = #state.entries
        state.index = (state.index - 1 + direction) % n + 1
        show()
    end
end

hl.bind("ALT + Tab",           step("windows", 1))
hl.bind("ALT + SHIFT + Tab",   step("windows", -1))
hl.bind("SUPER + Tab",         step("apps", 1))
hl.bind("SUPER + SHIFT + Tab", step("apps", -1))

-- Releasing ⌥ / ⌘ switches. Two ways to notice it (the first one that fires wins):
--   1. release bindings on the modifier keys themselves
--   2. while the panel is open, a short timer asks Hyprland whether the key is still
--      held (hl.is_key_down) – only trusted once it has reported the key as held,
--      so a missing key name can never close the panel at once.
local seen_held = false
local poll = hl.timer(function()
    if not state then return end
    if held(state.mode) then
        seen_held = true
    elseif seen_held then
        finish(true)
    end
end, { timeout = 30, type = "repeat" })

function macos.switcher_release()
    finish(true)
    return hl.dsp.no_op()
end

hl.bind("SUPER + Super_L", function() if state and state.mode == "apps" then finish(true) end end,
    { release = true, non_consuming = true })
hl.bind("ALT + Alt_L", function() if state and state.mode == "windows" then finish(true) end end,
    { release = true, non_consuming = true })

-- Esc cancels (the key still reaches the app when no switcher is open)
hl.bind("ALT + Escape",   function() finish(false) end, { non_consuming = true })
hl.bind("SUPER + Escape", function() finish(false) end, { non_consuming = true })

-- A click on an icon in the panel (Switcher.qml) switches to that entry
function macos.switcher_pick(index)
    if state and state.entries[index] then
        state.index = index
        finish(true)
    end
    return hl.dsp.no_op()
end
