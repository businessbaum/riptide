-- Looks like macOS: no coloured borders, but large soft shadows,
-- "squircle" corners and blurred, translucent surfaces.
-- Colours come from the theme (modules/settings.lua), so light/dark mode changes them too.

local S = require("modules.settings")
local T = S.theme

hl.config({
    general = {
        gaps_in  = S.windows.gap,
        gaps_out = S.windows.gap, -- distance of maximized windows to the screen edge

        -- A hairline border, as macOS draws around windows
        border_size = 1,
        col = {
            active_border   = T.window_border_active or "rgba(ffffff26)",
            inactive_border = T.window_border_inactive or "rgba(ffffff14)",
        },

        -- Resize windows by dragging any edge. Hyprland measures the grab zone from the
        -- window content, and our title bar sits above it: a wide zone made the lower part
        -- of the bar resize instead of move. 4 px keeps the sides easy to grab.
        resize_on_border        = true,
        extend_border_grab_area = 4,

        allow_tearing = false,
        layout        = "dwindle",
    },

    decoration = {
        rounding       = S.windows.corner_radius,
        rounding_power = 3, -- 2 = circular arc; higher = Apple's softer "squircle" corners

        active_opacity   = 1.0,
        inactive_opacity = 1.0,

        -- macOS: large shadow offset downwards; weaker for inactive windows
        shadow = {
            enabled        = true,
            range          = 40,
            render_power   = 3,
            offset         = { 0, 12 },
            color          = T.shadow or "rgba(00000080)",
            color_inactive = T.shadow_inactive or "rgba(00000040)",
        },

        -- The "vibrancy" behind menu bar, dock, menus and panels.
        -- Off by default: with Hyprland 0.56 and the NVIDIA driver, blur leaves blocks of
        -- stale background pixels on screen (title bars). System Settings can turn it on
        -- again (appearance.blur) to try after updates.
        blur = {
            enabled   = S.appearance.blur == true,
            size      = 12,
            passes    = 3,
            noise     = 0.02,
            vibrancy  = 0.25,
            popups    = true,
        },
    },

    animations = {
        enabled = true,
    },

    misc = {
        force_default_wallpaper  = 0,    -- no Hyprland mascots; the wallpaper comes with Quickshell
        background_color         = T.desktop_background or "rgb(1c1c1e)",
        disable_hyprland_logo    = true,
        disable_splash_rendering = true,
        focus_on_activate        = true, -- apps may bring themselves to the front (opening links etc.)
    },
})


--------------------
---- ANIMATIONS ----
--------------------
-- One set of animations for every window, menu and panel – nothing animates itself.

-- macOS feels "springy": fast start, soft ending.
hl.curve("macos",        { type = "bezier", points = { {0.22, 1},    {0.36, 1} } })
hl.curve("easeOutQuint", { type = "bezier", points = { {0.23, 1},    {0.32, 1} } })
hl.curve("linear",       { type = "bezier", points = { {0, 0},       {1, 1}    } })
hl.curve("almostLinear", { type = "bezier", points = { {0.5, 0.5},   {0.75, 1} } })
hl.curve("quick",        { type = "bezier", points = { {0.15, 0},    {0.1, 1}  } })
hl.curve("spring",       { type = "spring", mass = 1, stiffness = 71.2633, dampening = 15.8273644 })

hl.animation({ leaf = "global",        enabled = true, speed = 10,   bezier = "default" })
hl.animation({ leaf = "border",        enabled = true, speed = 5.39, bezier = "easeOutQuint" })
hl.animation({ leaf = "windows",       enabled = true, speed = 4.79, spring = "spring" })
-- Windows "pop in" like on a Mac and shrink away when closing
hl.animation({ leaf = "windowsIn",     enabled = true, speed = 3.5,  spring = "spring", style = "popin 90%" })
hl.animation({ leaf = "windowsOut",    enabled = true, speed = 1.8,  bezier = "macos",  style = "popin 90%" })
hl.animation({ leaf = "fadeIn",        enabled = true, speed = 1.73, bezier = "almostLinear" })
hl.animation({ leaf = "fadeOut",       enabled = true, speed = 1.46, bezier = "almostLinear" })
hl.animation({ leaf = "fade",          enabled = true, speed = 3.03, bezier = "quick" })
hl.animation({ leaf = "layers",        enabled = true, speed = 3.81, bezier = "easeOutQuint" })
hl.animation({ leaf = "layersIn",      enabled = true, speed = 3,    bezier = "macos",  style = "popin 96%" })
hl.animation({ leaf = "layersOut",     enabled = true, speed = 1.5,  bezier = "linear", style = "fade" })
hl.animation({ leaf = "fadeLayersIn",  enabled = true, speed = 1.79, bezier = "almostLinear" })
hl.animation({ leaf = "fadeLayersOut", enabled = true, speed = 1.39, bezier = "almostLinear" })
-- Desktops ("Spaces") slide sideways like ⌃← / ⌃→ on a Mac
hl.animation({ leaf = "workspaces",    enabled = true, speed = 4,    bezier = "macos",  style = "slide" })
-- Minimized windows come from below, as if from the dock
hl.animation({ leaf = "specialWorkspace", enabled = true, speed = 3.5, bezier = "macos", style = "slidevert" })
hl.animation({ leaf = "zoomFactor",    enabled = true, speed = 7,    bezier = "quick" })
