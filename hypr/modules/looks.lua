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
        border_size = S.accessibility.contrast and 2 or 1, -- Bedienungshilfen → Kontrast erhöhen
        col = {
            active_border   = T.window_border_active or "rgba(ffffff26)",
            inactive_border = T.window_border_inactive or "rgba(ffffff14)",
        },

        -- Resize windows by dragging any edge (8 px around the window). Clicks on the title
        -- bar – including the window's rounded top corners below it – belong to the bar
        -- (riptide-wm), so dragging there always moves the window.
        resize_on_border        = true,
        extend_border_grab_area = 8,

        allow_tearing = false,
        layout        = "dwindle",
    },

    decoration = {
        rounding       = S.windows.corner_radius,
        rounding_power = 3, -- 2 = circular arc; higher = Apple's softer "squircle" corners

        active_opacity   = 1.0,
        inactive_opacity = 1.0,

        -- macOS: large shadow offset downwards; weaker for inactive windows
        -- Off: with the NVIDIA driver the shadows flickered on every keystroke
        shadow = {
            enabled        = false,
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

-- Short and calm, like macOS: windows appear with a quick fade from slightly smaller
-- (about 0.2 s), without the overshoot of a spring. Speed is in tenths of a second.
hl.curve("macos",        { type = "bezier", points = { {0.22, 1},    {0.36, 1} } })
hl.curve("easeOutQuint", { type = "bezier", points = { {0.23, 1},    {0.32, 1} } })
hl.curve("linear",       { type = "bezier", points = { {0, 0},       {1, 1}    } })
hl.curve("almostLinear", { type = "bezier", points = { {0.5, 0.5},   {0.75, 1} } })
hl.curve("quick",        { type = "bezier", points = { {0.15, 0},    {0.1, 1}  } })

hl.animation({ leaf = "global",        enabled = true, speed = 10,   bezier = "default" })
hl.animation({ leaf = "border",        enabled = true, speed = 4,    bezier = "easeOutQuint" })
-- Moving/resizing (snapping, zoom): smooth, 0.25 s
hl.animation({ leaf = "windows",       enabled = true, speed = 2.5,  bezier = "easeOutQuint" })
-- Open: 0.2 s from 94 % size with fade-in; close: 0.15 s to 96 % with fade-out
hl.animation({ leaf = "windowsIn",     enabled = true, speed = 2,    bezier = "easeOutQuint", style = "popin 94%" })
hl.animation({ leaf = "windowsOut",    enabled = true, speed = 1.5,  bezier = "macos",        style = "popin 96%" })
hl.animation({ leaf = "fadeIn",        enabled = true, speed = 2,    bezier = "almostLinear" })
hl.animation({ leaf = "fadeOut",       enabled = true, speed = 1.5,  bezier = "almostLinear" })
hl.animation({ leaf = "fade",          enabled = true, speed = 2.5,  bezier = "quick" })
-- Menu bar, dock, menus, Spotlight: a quick fade (0.15 s)
hl.animation({ leaf = "layers",        enabled = true, speed = 2,    bezier = "easeOutQuint" })
hl.animation({ leaf = "layersIn",      enabled = true, speed = 1.5,  bezier = "macos",  style = "fade" })
hl.animation({ leaf = "layersOut",     enabled = true, speed = 1.2,  bezier = "linear", style = "fade" })
hl.animation({ leaf = "fadeLayersIn",  enabled = true, speed = 1.5,  bezier = "almostLinear" })
hl.animation({ leaf = "fadeLayersOut", enabled = true, speed = 1.2,  bezier = "almostLinear" })
-- Desktops ("Spaces") slide sideways like ⌃← / ⌃→ on a Mac
hl.animation({ leaf = "workspaces",    enabled = true, speed = 4,    bezier = "macos",  style = "slide" })
-- Minimized windows come from below, as if from the dock
hl.animation({ leaf = "specialWorkspace", enabled = true, speed = 3.5, bezier = "macos", style = "slidevert" })
hl.animation({ leaf = "zoomFactor",    enabled = true, speed = 7,    bezier = "quick" })

-- Bedienungshilfen → "Bewegung reduzieren": nothing slides or pops, things fade
if S.accessibility.reduce_motion then
    hl.animation({ leaf = "windowsIn",        enabled = true, speed = 2,   bezier = "almostLinear", style = "popin 100%" })
    hl.animation({ leaf = "windowsOut",       enabled = true, speed = 1.5, bezier = "almostLinear", style = "popin 100%" })
    hl.animation({ leaf = "windows",          enabled = true, speed = 1,   bezier = "quick" })
    hl.animation({ leaf = "workspaces",       enabled = true, speed = 2.5, bezier = "almostLinear", style = "fade" })
    hl.animation({ leaf = "specialWorkspace", enabled = true, speed = 2.5, bezier = "almostLinear", style = "fade" })
end
