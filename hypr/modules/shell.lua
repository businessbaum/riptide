-- Bridge to our shell (Quickshell: menu bar, dock, Spotlight, notifications).
-- The shell asks, Hyprland acts: window logic stays here, the shell only displays.
-- Called from Quickshell as e.g.  Hyprland.dispatch("macos.activate_app('kitty')"),
-- so every function returns a dispatcher (no_op).

macos = macos or {}

-- Mapped windows of an app, most recently used first
local function app_windows(class)
    local list = {}
    for _, w in ipairs(hl.get_windows()) do
        if w.mapped and w.class == class then list[#list + 1] = w end
    end
    table.sort(list, function(a, b) return a.focus_history_id < b.focus_history_id end)
    return list
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

-- Mission Control: a click on one window brings exactly that one to the front
function macos.focus_window(address)
    -- (the shell may give it with or without 0x)
    if not address:match("^0x") then address = "0x" .. address end
    local w = hl.get_window("address:" .. address)
    if w and w.mapped then bring_to_front(w) end
    return hl.dsp.no_op()
end

-- "Schreibtisch" (hot corner): every window of the visible desktops steps aside;
-- the second time they come back where they were
local set_aside = {}
function macos.show_desktop()
    if #set_aside > 0 then
        for _, e in ipairs(set_aside) do
            local w = hl.get_window("address:" .. e.address)
            if w and w.mapped then
                hl.dispatch(hl.dsp.window.move({ window = w, workspace = e.workspace, follow = false }))
            end
        end
        set_aside = {}
        return hl.dsp.no_op()
    end
    local visible = {}
    for _, m in ipairs(hl.get_monitors()) do
        if m.active_workspace then visible[m.active_workspace.id] = true end
    end
    for _, w in ipairs(hl.get_windows()) do
        if w.mapped and w.workspace and visible[w.workspace.id] then
            set_aside[#set_aside + 1] = { address = w.address, workspace = w.workspace.id }
            hl.dispatch(hl.dsp.window.move({ window = w, workspace = "special:desktop", follow = false }))
        end
    end
    return hl.dsp.no_op()
end

-- Dock click on a running app
function macos.activate_app(class)
    local w = app_windows(class)[1]
    if w then bring_to_front(w) end
    return hl.dsp.no_op()
end

local function minimized(w)
    return w.workspace and w.workspace.name == "special:minimized"
end

-- Hidden apps (⌘H, app menu "ausblenden", "Andere ausblenden") step aside onto their own
-- hidden desktop "hidden" – not "minimized": "Alle einblenden" brings back hidden apps
-- only, minimized windows stay in the dock, like on a Mac. A dock click, ⌘Tab or
-- Mission Control brings a hidden app back as well.
local function hidden(w)
    return w.workspace and w.workspace.name == "special:hidden"
end
local function stowed(w)
    return minimized(w) or hidden(w)
end
local hidden_from = {} -- window address → desktop it was hidden from

local function hide(w)
    if not w.mapped or not w.workspace or w.workspace.name:match("^special:") then return end
    hidden_from[w.address] = w.workspace.id
    hl.dispatch(hl.dsp.window.move({ window = w, workspace = "special:hidden", follow = false }))
end

function macos.hide_app(class)
    for _, w in ipairs(app_windows(class)) do hide(w) end
    return hl.dsp.no_op()
end

function macos.hide_others(class)
    for _, w in ipairs(hl.get_windows()) do
        if w.class ~= class then hide(w) end
    end
    return hl.dsp.no_op()
end

function macos.show_all()
    local active = hl.get_active_workspace()
    for _, w in ipairs(hl.get_windows()) do
        if w.mapped and hidden(w) then
            local ws = hidden_from[w.address] or (active and active.id) or 1
            hl.dispatch(hl.dsp.window.move({ window = w, workspace = ws, follow = false }))
            hidden_from[w.address] = nil
        end
    end
    return hl.dsp.no_op()
end

-- In the background (dock menu "In die Menüleiste ausblenden"): an app without windows
-- that keeps running – for its messages – with its icon in the menu bar instead of the
-- dock (Background.qml). Its windows live on their own hidden desktop "background", new
-- ones go there at once (also when it is reopened after the next login), until it is
-- opened again from its icon. Which apps: ~/.local/state/macos/background.json, written
-- by the shell ({ app: window class }).
local json = require("modules.json")
local BACKGROUND = "special:background"
local function in_background(class)
    for _, c in pairs(json.read(os.getenv("HOME") .. "/.local/state/macos/background.json") or {}) do
        if c == class then return true end
    end
    return false
end

function macos.to_background(class)
    for _, w in ipairs(app_windows(class)) do
        if not (w.workspace and w.workspace.name == BACKGROUND) then
            hl.dispatch(hl.dsp.window.move({ window = w, workspace = BACKGROUND, follow = false }))
        end
    end
    return hl.dsp.no_op()
end

function macos.from_background(class)
    local windows = app_windows(class)
    for i = #windows, 1, -1 do bring_to_front(windows[i]) end -- the last used on top
    return hl.dsp.no_op()
end

hl.on("window.open", function(w)
    if w and w.class and in_background(w.class) then
        hl.dispatch(hl.dsp.window.move({ window = w, workspace = BACKGROUND, follow = false }))
    end
end)

-- Hyprland shows the hidden desktop when a window on it asks for attention and gets it
-- (a click on one of its notifications): the window comes to the desktop instead, and the
-- app leaves the background (the shell hears it)
hl.on("window.active", function(w)
    if not w or not w.workspace or w.workspace.name ~= BACKGROUND then return end
    local open = hl.get_active_special_workspace()
    if open and open.name == BACKGROUND then
        hl.dispatch(hl.dsp.window.move({ window = w, workspace = hl.get_active_workspace() }))
        hl.dispatch(hl.dsp.event("background-left>>" .. w.class))
    end
end)

-- Dock click on a running app, like on Windows: the app in front goes down into the
-- dock (its windows on this desktop are minimized); an app behind or minimized comes to
-- the front – from the minimized desktop with all its windows, the last used on top
function macos.toggle_app(class)
    local windows = app_windows(class)
    local active = hl.get_active_window()
    if active and active.class == class and not stowed(active) then
        for _, w in ipairs(windows) do
            if not stowed(w) and w.workspace and active.workspace and w.workspace.id == active.workspace.id then
                hl.dispatch(hl.dsp.window.move({ window = w, workspace = "special:minimized", follow = false }))
            end
        end
    elseif windows[1] and stowed(windows[1]) then
        for i = #windows, 1, -1 do
            if stowed(windows[i]) then bring_to_front(windows[i]) end
        end
    elseif windows[1] then
        bring_to_front(windows[1])
    end
    return hl.dsp.no_op()
end

-- Dock menu "Beenden"
function macos.quit_app(class)
    for _, w in ipairs(app_windows(class)) do
        hl.dispatch(hl.dsp.window.close({ window = w }))
    end
    return hl.dsp.no_op()
end

-- Log out / restart / shut down (Session.qml): ask every window to close, like
-- clicking its close button – apps with unsaved changes can ask to save
function macos.close_all_windows()
    for _, w in ipairs(hl.get_windows()) do
        if w.mapped then hl.dispatch(hl.dsp.window.close({ window = w })) end
    end
    return hl.dsp.no_op()
end

-- ⌘Space: Spotlight (pressed again it closes), SUPER+V: clipboard history, ⌃⌘Space: emoji
hl.bind("SUPER + space", hl.dsp.exec_cmd("qs ipc call spotlight toggle"))
hl.bind("SUPER + V",     hl.dsp.exec_cmd("qs ipc call clipboard toggle"))
hl.bind("CTRL + SUPER + space", hl.dsp.exec_cmd("qs ipc call emoji toggle")) -- ⌃⌘Space: Emoji & Symbole

-- Start the shell with the session (riptide-shell.service: systemd starts it again should
-- it crash; the session target starts it too – this is for when it is not enabled).
-- It reloads itself when its files change.
hl.on("hyprland.start", function()
    hl.exec_cmd("systemctl --user start riptide-shell.service")
end)
