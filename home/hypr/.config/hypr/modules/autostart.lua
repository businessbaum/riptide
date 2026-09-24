-- At Hyprland startup: background helpers of the session.
--
-- Everything is started through uwsm ("uwsm app --"), so each helper runs in its
-- own systemd scope with the session environment (~/.config/uwsm/env).
-- Stage 3 adds Quickshell (menu bar, dock, notifications, …) here.

local S = require("modules.settings")

hl.on("hyprland.start", function()
    -- Clipboard history for SUPER+V: remember text and images
    hl.exec_cmd("uwsm app -- wl-paste --type text --watch cliphist store")
    hl.exec_cmd("uwsm app -- wl-paste --type image --watch cliphist store")

    hl.exec_cmd("hyprctl setcursor Adwaita " .. S.mouse.cursor_size)
end)
