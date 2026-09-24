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

-- Dock menu "Beenden"
function macos.quit_app(class)
    for _, w in ipairs(app_windows(class)) do
        hl.dispatch(hl.dsp.window.close({ window = w }))
    end
    return hl.dsp.no_op()
end

-- ⌘Space: Spotlight (pressed again it closes)
hl.bind("SUPER + space", hl.dsp.exec_cmd("qs ipc call spotlight toggle"))

-- Start the shell with the session. It reloads itself when its files change.
hl.on("hyprland.start", function()
    hl.exec_cmd("uwsm app -- qs")
end)
