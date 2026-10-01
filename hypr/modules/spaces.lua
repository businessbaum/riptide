-- Full screen like on a Mac: a window that goes to full screen gets a desktop (Space) of
-- its own, right after the one it came from, with nothing else on it. The other windows
-- stay where they were – none lies in front of the full-screen window (menu bar and dock
-- come over it at the screen's edges, FullscreenReveal.qml), and on the desktop menu bar
-- and dock behave as always. ⌃←/⌃→ and Mission Control reach it like any desktop (Mission
-- Control names it after the app). Back from full screen – or closed – the window returns
-- to its desktop, and the extra one goes (Hyprland drops empty desktops).
-- A window of another app that opens while such a desktop is in front goes to the desktop
-- it came from, and that one comes to the front, like on a Mac; the app's own windows,
-- file dialogs and system dialogs stay over it.
--
-- Which window has which desktop: $XDG_RUNTIME_DIR/riptide/fullscreen-spaces.tsv (window,
-- its desktop, the desktop it came from) – `hyprctl reload` clears this module's state.

local DIR  = (os.getenv("XDG_RUNTIME_DIR") or "/tmp") .. "/riptide"
local FILE = DIR .. "/fullscreen-spaces.tsv"

local spaces = {} -- window address → { space = desktop id, origin = desktop id }
-- while this module moves a window: Hyprland takes full screen away for the move and
-- gives it back – those steps are not the user's, the handlers leave them alone
local moving = 0

local function save()
    local f = io.open(FILE, "w")
    if not f then
        os.execute("mkdir -p '" .. DIR .. "'")
        f = io.open(FILE, "w")
        if not f then return end
    end
    for address, s in pairs(spaces) do
        f:write(string.format("%s\t%d\t%d\n", address, s.space, s.origin))
    end
    f:close()
end

local function load()
    local f = io.open(FILE, "r")
    if not f then return end
    for line in f:lines() do
        local address, space, origin = line:match("^(%S+)\t(%-?%d+)\t(%-?%d+)$")
        if address then spaces[address] = { space = tonumber(space), origin = tonumber(origin) } end
    end
    f:close()
end

-- (internal mode: 1 maximized, 2 full screen, 3 both)
local function is_fullscreen(w)
    local mode = tonumber(w and w.fullscreen) or 0
    return mode == 2 or mode == 3
end

-- the first desktop number after `after` that is not taken (on any screen)
local function free_id(after)
    local used = {}
    for _, ws in ipairs(hl.get_workspaces()) do used[ws.id] = true end
    local id = after + 1
    while used[id] do id = id + 1 end
    return id
end

local function shown(id, m)
    return m ~= nil and m.active_workspace ~= nil and m.active_workspace.id == id
end

-- Windows that stay over a full-screen window: file dialogs, system dialogs, our shell's
-- small windows, password prompts
local function stays(w)
    local class = w.class or ""
    return w.pinned or class:match("^xdg%-desktop%-portal") or class:match("^hyprland%-")
        or class == "org.quickshell" or class == "gcr-prompter"
end

-- Move `w` to desktop `id` on its screen `m`; `follow`: that desktop comes to the front.
-- A desktop that does not exist yet is made on the focused screen (Hyprland) – moved over
-- to `m` if that is another one. Full screen stays.
local function move_to(w, id, m, follow)
    moving = moving + 1
    local ok, err = pcall(function()
        local focused = hl.get_active_monitor()
        if follow and focused and m and focused.name == m.name then
            hl.dispatch(hl.dsp.window.move({ window = w, workspace = id })) -- switches and focuses
            return
        end
        local full = is_fullscreen(w)
        hl.dispatch(hl.dsp.window.move({ window = w, workspace = id, follow = false }))
        local ws = hl.get_workspace(tostring(id))
        if m and ws and ws.monitor and ws.monitor.name ~= m.name then
            hl.dispatch(hl.dsp.workspace.move({ workspace = id, monitor = m.name }))
        end
        w = hl.get_window("address:" .. w.address) or w
        if full and not is_fullscreen(w) then
            hl.dispatch(hl.dsp.window.fullscreen_state({ window = w, internal = 2, client = 2 }))
        end
        if follow then
            hl.dispatch(hl.dsp.focus({ workspace = id }))
        end
    end)
    moving = moving - 1
    if not ok then error(err) end
end

-- the other windows on a full-screen desktop, to `origin` (they stayed over it)
local function move_others(address, space, origin)
    moving = moving + 1
    pcall(function()
        for _, o in ipairs(hl.get_windows()) do
            if o.address ~= address and o.mapped and o.workspace and o.workspace.id == space then
                hl.dispatch(hl.dsp.window.move({ window = o, workspace = origin, follow = false }))
            end
        end
    end)
    moving = moving - 1
end

-- into full screen: onto a desktop of its own
local function enter(w)
    if not w or not w.mapped or not is_fullscreen(w) or spaces[w.address] then return end
    local ws, m = w.workspace, w.monitor
    if not ws or ws.id <= 0 or not m then return end -- (hidden desktops: special ones)
    local id = free_id(ws.id)
    local active = hl.get_active_window()
    local follow = shown(ws.id, m) and active ~= nil and active.address == w.address
    spaces[w.address] = { space = id, origin = ws.id }
    save()
    move_to(w, id, m, follow)
end

-- Into full screen the right way round – F11 and videos (snapping's fullscreen_request),
-- ⌃⌘F, window memory: first onto a desktop of its own, then full screen, so the app never
-- sees full screen taken away and given back. Moving a window that is in full screen
-- already does that (Hyprland drops it for the move): Firefox/Zen take the moment for
-- "full screen is over" and leave it – F11 did nothing (2026-10-01). Full screen that
-- comes another way is still caught by the handler below (moved afterwards).
function macos.fullscreen_on(w)
    if not w then return end
    if not is_fullscreen(w) and not spaces[w.address] then
        local ws, m = w.workspace, w.monitor
        if ws and ws.id > 0 and m then
            local id = free_id(ws.id)
            local active = hl.get_active_window()
            local follow = shown(ws.id, m) and active ~= nil and active.address == w.address
            spaces[w.address] = { space = id, origin = ws.id }
            save()
            move_to(w, id, m, follow) -- (not in full screen yet: nothing to drop)
            w = hl.get_window("address:" .. w.address) or w
        end
    end
    moving = moving + 1
    pcall(function() hl.dispatch(hl.dsp.window.fullscreen_state({ window = w, internal = 2, client = 2 })) end)
    moving = moving - 1
end

-- out of full screen: back to its desktop, and the windows that stayed with it too
local function leave(w)
    local s = spaces[w.address]
    if not s or is_fullscreen(w) then return end
    spaces[w.address] = nil
    save()
    if not (w.workspace and w.workspace.id == s.space) then return end
    local m = w.monitor
    local follow = shown(s.space, m)
    move_others(w.address, s.space, s.origin)
    move_to(w, s.origin, m, follow)
end

hl.on("window.fullscreen", function(w)
    if not w or moving > 0 then return end
    if is_fullscreen(w) then enter(w) else leave(w) end
end)

-- Moved elsewhere (⌃⇧1…9, minimized, Mission Control): it has no desktop of its own any
-- more – still in full screen on another desktop, it gets a new one there
hl.on("window.move_to_workspace", function(w, ws)
    if not w or not ws or moving > 0 then return end
    local s = spaces[w.address]
    if s and ws.id ~= s.space then
        spaces[w.address] = nil
        save()
    end
    if not spaces[w.address] and ws.id > 0 and is_fullscreen(w) then enter(w) end
end)

-- Closed in full screen: back to the desktop it came from (if its desktop was in front),
-- with the windows that were over it
hl.on("window.close", function(w)
    local s = w and spaces[w.address]
    if not s then return end
    spaces[w.address] = nil
    save()
    move_others(w.address, s.space, s.origin)
    if shown(s.space, w.monitor) then hl.dispatch(hl.dsp.focus({ workspace = s.origin })) end
end)

-- A window of another app opens on a full-screen desktop (Spotlight, a link, window memory
-- putting it on that screen): to the desktop it came from
hl.on("window.open", function(w)
    if not w or not w.workspace or moving > 0 or stays(w) then return end
    for address, s in pairs(spaces) do
        if address ~= w.address and w.workspace.id == s.space then
            local full = hl.get_window("address:" .. address)
            if full and full.class ~= w.class then
                move_to(w, s.origin, w.monitor, shown(s.space, w.monitor))
            end
            return
        end
    end
end)

-- After a reload (or start): what is known still holds; a full-screen window that shares
-- its desktop (from before, or back while this state was gone) gets one of its own
load()
hl.timer(function()
    local changed = false
    for address, s in pairs(spaces) do
        local w = hl.get_window("address:" .. address)
        if not w or not w.workspace or w.workspace.id ~= s.space then
            spaces[address] = nil
            changed = true
        elseif not is_fullscreen(w) then
            leave(w)
        end
    end
    if changed then save() end
    for _, w in ipairs(hl.get_windows()) do
        if w.mapped and is_fullscreen(w) and not spaces[w.address] then enter(w) end
    end
end, { timeout = 200, type = "oneshot" })
