-- Windows behave like on a Mac: they float freely, open centred
-- and may overlap instead of tiling the screen.
-- Tiling is still available: ⌘⌥F toggles a window.

hl.window_rule({
    name  = "everything-floats",
    match = { class = ".*" },

    float  = true,
    center = true,
})

-- Picture-in-picture videos stay visible on every desktop
hl.window_rule({
    name  = "picture-in-picture",
    match = { title = "^(Bild-im-Bild|Picture-in-Picture)$" },

    float = true,
    pin   = true,
})

-- Dialogs of hyprland-guiutils (log out, run): centred and on top, the rest dimmed – like a Mac sheet
hl.window_rule({
    name  = "system-dialogs",
    match = { class = "^hyprland-(dialog|run)$" },

    float      = true,
    center     = true,
    pin        = true,
    dim_around = true,
})

hl.window_rule({
    -- Fix some dragging issues with XWayland
    name  = "fix-xwayland-drags",
    match = {
        class      = "^$",
        title      = "^$",
        xwayland   = true,
        float      = true,
        fullscreen = false,
        pin        = false,
    },

    no_focus = true,
})


------------------------------------------------
---- MENU BAR, DOCK, MENUS AND PANELS ----
------------------------------------------------

-- Blur behind the translucent surfaces.
-- ignore_alpha: fully transparent pixels (e.g. next to the dock) stay sharp.
hl.layer_rule({
    name  = "blur-bars",
    match = { namespace = "^(menubar|dock)$" },

    blur         = true,
    blur_popups  = true, -- the Apple menu and the dock menus
    ignore_alpha = 0.1,
})

-- Menus and panels: blur only the panel itself, and no fade-out animation.
-- Otherwise a shadow of the panel lingers over maximized windows after closing.
hl.layer_rule({
    name  = "blur-menus",
    match = { namespace = "^(spotlight|launchpad|clipboard|apple-menu|control-center|notification-center|switcher)$" },

    blur         = true,
    ignore_alpha = 0.3,
    no_anim      = true,
})

-- Dialogs of the shell (password, confirmation): blurred, the rest of the screen dimmed
hl.layer_rule({
    name  = "shell-dialogs",
    match = { namespace = "^(polkit|confirm)$" },

    blur         = true,
    ignore_alpha = 0.3,
    dim_around   = true,
})

-- Notifications: blur only the cards, not the transparent area around them
hl.layer_rule({
    name  = "blur-notifications",
    match = { namespace = "^notifications$" },

    blur         = true,
    ignore_alpha = 0.5,
})


-----------------------------
---- FULL SCREEN IN FRONT ----
-----------------------------

-- A window in full screen that gets the focus (a click on it, ⌘Tab) is in front of
-- everything on its desktop, like on a Mac: the other windows go behind it. Hyprland lets
-- floating windows – here every window – lie above a full-screen one and, when that one is
-- focused again, left them drawn on top while it took their clicks: seen, but dead.
-- Lowering them takes the "above full screen" back (they fade out); picked again (⌘Tab,
-- dock) one comes back over the full screen by itself. The app's own windows and file
-- dialogs stay (its "Speichern unter" must not vanish behind it); pinned ones stay anyway.
hl.on("window.active", function(w)
    if not w or (tonumber(w.fullscreen) or 0) ~= 2 or not w.workspace then
        return
    end
    for _, o in ipairs(hl.get_windows()) do
        if o.address ~= w.address and o.mapped and o.allowed_over_fullscreen and not o.pinned
            and o.workspace and o.workspace.id == w.workspace.id
            and o.class ~= w.class and not (o.class or ""):match("^xdg%-desktop%-portal") then
            hl.dispatch(hl.dsp.window.alter_zorder({ mode = "bottom", window = o }))
        end
    end
end)


------------------
---- MINIMIZE ----
------------------

-- Minimized windows (⌘M or yellow button) move to the hidden desktop "minimized".
-- Clicking them in the dock makes Hyprland show that desktop – then we bring the
-- window straight back, like on a Mac.
hl.on("window.active", function(w)
    if not w or not w.workspace or w.workspace.name ~= "special:minimized" then
        return
    end
    local open = hl.get_active_special_workspace()
    if open and open.name == "special:minimized" then
        hl.dispatch(hl.dsp.window.move({ window = w, workspace = hl.get_active_workspace() }))
    end
end)
