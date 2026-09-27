-- Keyboard shortcuts like on a Mac.
-- ⌘ = SUPER (Windows key)   ⌥ = ALT   ⌃ = CTRL   ⇧ = SHIFT
--
-- Linux apps expect ⌃C, ⌃V and so on. So we translate ⌘ shortcuts into ⌃ shortcuts
-- and send them to the active window. That way copy, paste, save … work with the
-- same keys as on a Mac.

local S = require("modules.settings")

-- Apps are started through uwsm, so each one runs in its own systemd scope
-- (clean environment, survives a Hyprland reload, visible in the task manager).
local terminal  = "uwsm app -- kitty"
local finder    = "uwsm app -- nautilus --new-window"
local scripts   = "~/.config/hypr/scripts/"

-- Apps that understand ⌘ shortcuts themselves. They receive the ⌘ shortcut unchanged,
-- because in a terminal ⌃C would interrupt the running program.
local understands_cmd = {
    kitty = true,
}


-----------------
---- HELPERS ----
-----------------

local function active_window()
    return hl.get_active_window()
end

-- Layer namespaces of our menus (Quickshell, stage 3). While one is open it has
-- the keyboard, so ⌘ shortcuts must not go to the window below.
local MENU_NAMESPACES = { spotlight = true, launchpad = true, clipboard = true, ["apple-menu"] = true }

local function menu_open()
    for _, l in ipairs(hl.get_layers()) do
        if MENU_NAMESPACES[l.namespace] then return true end
    end
    return false
end

local function with_mods(prefix, mods)
    if mods == "" then return prefix end
    return prefix .. " " .. mods
end

-- ⌘ + mods + key  →  ⌃ + mods + key   (or unchanged for terminals)
local function as_ctrl(mods, key)
    return function()
        if menu_open() then return end
        local w = active_window()
        if w and understands_cmd[w.class] then
            hl.dispatch(hl.dsp.send_shortcut({ mods = with_mods("SUPER", mods), key = key }))
        else
            hl.dispatch(hl.dsp.send_shortcut({ mods = with_mods("CTRL", mods), key = key }))
        end
    end
end

-- Send any shortcut to the active window (for text navigation)
local function send(mods, key)
    return function()
        if menu_open() then return end
        hl.dispatch(hl.dsp.send_shortcut({ mods = mods, key = key }))
    end
end

-- Close all windows of an app (⌘Q = "Quit")
local function quit_app()
    local w = active_window()
    if not w then return end
    for _, other in ipairs(hl.get_windows()) do
        if other.class == w.class then
            hl.dispatch(hl.dsp.window.close({ window = other }))
        end
    end
end

-- Hide all windows of an app (⌘H = "Hide")
local function hide_app()
    local w = active_window()
    if not w then return end
    for _, other in ipairs(hl.get_windows()) do
        if other.class == w.class then
            hl.dispatch(hl.dsp.window.move({ window = other, workspace = "special:minimized", follow = false }))
        end
    end
end


---------------------------------
---- ⌘ SHORTCUTS FOR APPS ----
---------------------------------

-- Can be turned off in System Settings (Keyboard → "Mac-Kürzel mit ⌘")
if S.keyboard.cmd_shortcuts then
    -- ⌘C copy, ⌘X cut, ⌘A select all, ⌘Z undo, ⌘S save, ⌘F find,
    -- ⌘T new tab, ⌘N new window, ⌘W close tab/window, ⌘O open, ⌘P print, ⌘R reload,
    -- ⌘B/⌘I/⌘U bold/italic/underline, ⌘K link or clear terminal,
    -- ⌘G find next, ⌘, preferences, ⌘+/⌘-/⌘0 zoom
    -- Not here, they have their own meaning below: ⌘V clipboard history, ⌘L lock screen
    -- (paste and address bar: ⌃V and ⌃L)
    for _, key in ipairs({ "c", "x", "a", "z", "s", "f", "t", "n", "w", "o", "p",
                           "r", "b", "i", "u", "k", "g",
                           "comma", "plus", "minus", "0" }) do
        hl.bind("SUPER + " .. key, as_ctrl("", key))
    end

    -- ⌘⇧Z redo, ⌘⇧T reopen closed tab, ⌘⇧N private window / new folder,
    -- ⌘⇧G find previous   (⌘⇧S is the screenshot; save as: ⌃⇧S)
    for _, key in ipairs({ "z", "t", "n", "g" }) do
        hl.bind("SUPER + SHIFT + " .. key, as_ctrl("SHIFT", key))
    end
end


----------------------
---- TEXT EDITING ----
----------------------

-- ⌥←/⌥→ jump by word, ⌘←/⌘→ start/end of line, ⌘↑/⌘↓ start/end of document
hl.bind("ALT + left",    send("CTRL", "Left"),  { repeating = true })
hl.bind("ALT + right",   send("CTRL", "Right"), { repeating = true })
hl.bind("SUPER + left",  send("", "Home"))
hl.bind("SUPER + right", send("", "End"))
hl.bind("SUPER + up",    send("CTRL", "Home"))
hl.bind("SUPER + down",  send("CTRL", "End"))

-- The same with ⇧ selects the text
hl.bind("ALT + SHIFT + left",    send("CTRL SHIFT", "Left"),  { repeating = true })
hl.bind("ALT + SHIFT + right",   send("CTRL SHIFT", "Right"), { repeating = true })
hl.bind("SUPER + SHIFT + left",  send("SHIFT", "Home"))
hl.bind("SUPER + SHIFT + right", send("SHIFT", "End"))
hl.bind("SUPER + SHIFT + up",    send("CTRL SHIFT", "Home"))
hl.bind("SUPER + SHIFT + down",  send("CTRL SHIFT", "End"))

-- ⌥⌫ delete word, ⌘⌫ delete to start of line
hl.bind("ALT + BackSpace", send("CTRL", "BackSpace"), { repeating = true })
hl.bind("SUPER + BackSpace", function()
    if menu_open() then return end
    local w = active_window()
    if w and understands_cmd[w.class] then
        hl.dispatch(hl.dsp.send_shortcut({ mods = "CTRL", key = "u" })) -- shell: delete line up to cursor
    else
        hl.dispatch(hl.dsp.send_shortcut({ mods = "SHIFT", key = "Home" }))
        hl.dispatch(hl.dsp.send_shortcut({ mods = "", key = "BackSpace" }))
    end
end)


-------------------------
---- WINDOWS AND APPS ----
-------------------------

-- ⌘Space Spotlight and SUPER+V clipboard history: see shell.lua
hl.bind("SUPER + ALT + space",  hl.dsp.exec_cmd(finder))     -- ⌘⌥Space: Finder
hl.bind("SUPER + Return",       hl.dsp.exec_cmd(terminal))   -- (not a Mac shortcut, but handy)

hl.bind("SUPER + Q", quit_app)                               -- ⌘Q: quit app
hl.bind("SUPER + H", hide_app)                               -- ⌘H: hide app
hl.bind("SUPER + M", hl.dsp.window.move({ workspace = "special:minimized", follow = false })) -- ⌘M: minimize
hl.bind("SUPER + SHIFT + M", hl.dsp.workspace.toggle_special("minimized")) -- show all minimized windows

-- ⌘Tab / ⌥Tab: switch between apps / windows – see switcher.lua

hl.bind("SUPER + CTRL + F",     hl.dsp.window.fullscreen({ mode = "fullscreen" })) -- ⌃⌘F: full screen
hl.bind("SUPER + ALT + F",      hl.dsp.window.float({ action = "toggle" }))        -- tile/float window
hl.bind("SUPER + ALT + Escape", hl.dsp.exec_cmd("qs ipc call forcequit open"))     -- ⌥⌘⎋: "Sofort beenden" window
hl.bind("CTRL + SHIFT + Escape", hl.dsp.exec_cmd("uwsm app -- io.missioncenter.MissionCenter.desktop")) -- ⌃⇧⎋: task manager (like Windows)
hl.bind("SUPER + L",            hl.dsp.exec_cmd("pidof hyprlock || hyprlock"))     -- lock screen
hl.bind("SUPER + CTRL + Q",     hl.dsp.exec_cmd("pidof hyprlock || hyprlock"))     -- ⌃⌘Q: lock screen (Mac)
hl.bind("SUPER + SHIFT + Q",    hl.dsp.exec_cmd(scripts .. "logout.sh"))           -- ⇧⌘Q: log out …

-- Move windows with ⌘ + mouse (left) or resize them (right)
hl.bind("SUPER + mouse:272", hl.dsp.window.drag(),   { mouse = true })
hl.bind("SUPER + mouse:273", hl.dsp.window.resize(), { mouse = true })


----------------------------
---- DESKTOPS (SPACES) ----
----------------------------

-- ⌃←/⌃→ switch desktop, ⌃1…9 jump to it, ⌃⇧1…9 take the window along
hl.bind("CTRL + up",    hl.dsp.exec_cmd("qs ipc call mission all")) -- ⌃↑: Mission Control
hl.bind("CTRL + down",  hl.dsp.exec_cmd("qs ipc call mission app")) -- ⌃↓: App Exposé
hl.bind("CTRL + left",  hl.dsp.focus({ workspace = "r-1" }))
hl.bind("CTRL + right", hl.dsp.focus({ workspace = "r+1" }))
for i = 1, 9 do
    hl.bind("CTRL + " .. i,         hl.dsp.focus({ workspace = i }))
    hl.bind("CTRL + SHIFT + " .. i, hl.dsp.window.move({ workspace = i }))
end

hl.bind("SUPER + mouse_down", hl.dsp.focus({ workspace = "e+1" }))
hl.bind("SUPER + mouse_up",   hl.dsp.focus({ workspace = "e-1" }))


---------------------
---- SCREENSHOTS ----
---------------------

-- ⇧⌘3 whole screen, ⇧⌘4 select area → file in ~/Bilder/Bildschirmfotos
-- with ⌃ in addition the image goes to the clipboard instead
-- ⇧⌘S select area → saved and in the clipboard (like Windows' snipping tool)
hl.bind("SUPER + SHIFT + S",        hl.dsp.exec_cmd(scripts .. "screenshot.sh area both"))
hl.bind("SUPER + SHIFT + 3",        hl.dsp.exec_cmd(scripts .. "screenshot.sh screen"))
hl.bind("SUPER + SHIFT + 4",        hl.dsp.exec_cmd(scripts .. "screenshot.sh area"))
hl.bind("SUPER + CTRL + SHIFT + 3", hl.dsp.exec_cmd(scripts .. "screenshot.sh screen clipboard"))
hl.bind("SUPER + CTRL + SHIFT + 4", hl.dsp.exec_cmd(scripts .. "screenshot.sh area clipboard"))


--------------------
---- MEDIA KEYS ----
--------------------

-- Volume keys change the global volume (every output, also Bluetooth) and show the
-- volume display (Quickshell OSD, stage 3), like on a Mac
local function volume(command)
    -- (then the click of "Rückmeldung bei Änderung der Lautstärke", if on – SystemSounds.qml)
    return hl.dsp.exec_cmd(command .. " && qs ipc call sounds volume")
end
hl.bind("XF86AudioRaiseVolume", volume("wpctl set-volume -l 1 @DEFAULT_AUDIO_SINK@ 5%+"), { locked = true, repeating = true })
hl.bind("XF86AudioLowerVolume", volume("wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-"),      { locked = true, repeating = true })
hl.bind("XF86AudioMute",        volume("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"),     { locked = true })
hl.bind("XF86AudioMicMute",     hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle"),   { locked = true, repeating = true })
-- Brightness of all screens (DDC, the shell's Brightness.qml shows it); keys of Apple
-- keyboards and laptops
hl.bind("XF86MonBrightnessUp",   hl.dsp.exec_cmd("qs ipc call brightness up"),   { locked = true, repeating = true })
hl.bind("XF86MonBrightnessDown", hl.dsp.exec_cmd("qs ipc call brightness down"), { locked = true, repeating = true })
hl.bind("XF86AudioNext",  hl.dsp.exec_cmd("playerctl next"),       { locked = true })
hl.bind("XF86AudioPause", hl.dsp.exec_cmd("playerctl play-pause"), { locked = true })
hl.bind("XF86AudioPlay",  hl.dsp.exec_cmd("playerctl play-pause"), { locked = true })
hl.bind("XF86AudioPrev",  hl.dsp.exec_cmd("playerctl previous"),   { locked = true })
