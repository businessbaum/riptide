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

-- Dock click on a running app
function macos.activate_app(class)
    local w = app_windows(class)[1]
    if w then bring_to_front(w) end
    return hl.dsp.no_op()
end

local function minimized(w)
    return w.workspace and w.workspace.name == "special:minimized"
end

-- Dock click on a running app, like on Windows: the app in front goes down into the
-- dock (its windows on this desktop are minimized); an app behind or minimized comes to
-- the front – from the minimized desktop with all its windows, the last used on top
function macos.toggle_app(class)
    local windows = app_windows(class)
    local active = hl.get_active_window()
    if active and active.class == class and not minimized(active) then
        for _, w in ipairs(windows) do
            if not minimized(w) and w.workspace and active.workspace and w.workspace.id == active.workspace.id then
                hl.dispatch(hl.dsp.window.move({ window = w, workspace = "special:minimized", follow = false }))
            end
        end
    elseif windows[1] and minimized(windows[1]) then
        for i = #windows, 1, -1 do
            if minimized(windows[i]) then bring_to_front(windows[i]) end
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
