-- riptide's Hyprland config, styled and behaving like macOS.
-- This folder lives in ~/dotfiles/home/hypr and is linked to ~/.config/hypr (GNU stow).
-- Hyprland reloads it on every save. Errors appear as a notification (modules/notifications.lua).
--
-- Keys like on a Mac:  ⌘ = SUPER (Windows key)   ⌥ = ALT   ⌃ = CTRL   ⇧ = SHIFT
--
-- Hyprland is the one window manager for everything: every rule below applies to all
-- windows alike (animations, shadows, title bars, snapping). Apps never do this themselves.
--
-- Modules:
--   modules/notifications.lua  errors and notices as notifications (instead of Hyprland's error bar)
--   modules/settings.lua       reads settings.json + theme.json (the single source of truth)
--   modules/looks.lua          corners, shadows, blur, animations
--   modules/windows.lua        floating windows, rules for bars, menus and panels
--   modules/keys.lua           ⌘ shortcuts
--   modules/snapping.lua       snap windows to screen edges, zoom
--   modules/switcher.lua       ⌥Tab / ⌘Tab: switch between windows / apps
--   modules/window_memory.lua  apps reopen with the size and position they were closed with
--   modules/csd_apps.lua       apps that draw their own title bar (Finder & co.)
--   modules/shell.lua          bridge to Quickshell (menu bar, dock, Spotlight, notifications)
--   modules/autostart.lua      background services started with the session
--
-- Environment variables (NVIDIA, cursor) are in ~/.config/uwsm/env, so that
-- services started by uwsm/systemd see them too, not only Hyprland's children.


-- Errors and notices as notifications in the top right instead of Hyprland's error bar
require("modules.notifications")

-- Everything the user can change in System Settings, plus the active theme
local S = require("modules.settings")


------------------
---- MONITORS ----
------------------

-- Default for every screen …
hl.monitor({
    output   = "",
    mode     = "preferred",
    position = "auto",
    scale    = "auto",
})

-- … and what was chosen in System Settings → Displays
for name, m in pairs(S.monitors) do
    hl.monitor({
        output   = name,
        mode     = m.mode or "preferred",
        position = m.position or "auto",
        scale    = m.scale or "auto",
    })
end


---------------
---- INPUT ----
---------------

hl.config({
    input = {
        kb_layout    = S.keyboard.layout,
        repeat_delay = S.keyboard.repeat_delay,
        repeat_rate  = S.keyboard.repeat_rate,

        -- Like on a Mac: keyboard focus changes only on click,
        -- but scrolling always goes to the window under the mouse.
        follow_mouse = 2,

        -- false = classic, true = "natural" like on a Mac
        natural_scroll = S.mouse.natural_scroll,

        sensitivity = S.mouse.speed, -- -1.0 to 1.0, 0 = unchanged

        touchpad = {
            natural_scroll = S.mouse.natural_scroll,
        },
    },

    -- Never move the mouse pointer on its own (Hyprland otherwise jumps to the
    -- window centre on focus changes). On a Mac it stays where it is.
    cursor = {
        no_warps = true,
    },
})

-- Three-finger swipe switches desktops ("Spaces")
hl.gesture({
    fingers   = 3,
    direction = "horizontal",
    action    = "workspace",
})


-----------------
---- MODULES ----
-----------------

require("modules.looks")
require("modules.windows")
require("modules.keys")
require("modules.snapping")
require("modules.switcher")
require("modules.window_memory")
require("modules.shell")
require("modules.autostart")
