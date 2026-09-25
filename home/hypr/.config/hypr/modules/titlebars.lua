-- Title bars with the three traffic-light buttons (close, minimize, zoom).
-- They come from our plugin riptide-wm (its title bar part is based on hyprbars and keeps
-- its names: plugin.hyprbars.*, hl.plugin.hyprbars), built by ~/dotfiles/plugins/build.sh
-- into ~/.local/lib/hyprland-plugins/.
--
-- It is NOT loaded here but once at startup (autostart.lua): loading a plugin
-- triggers a config reload. Loading it here would reload → load → reload … → crash.
-- After the plugin is loaded this file runs again, then hl.plugin.hyprbars exists.
--
-- Colours and sizes follow the theme (theme.json, incl. "traffic_lights"). GTK apps with
-- their own title bar get the very same buttons from desktop-theme (gtk.css).

if not hl.plugin.hyprbars then return end

local S = require("modules.settings")
local T = S.theme
local L = T.traffic_lights or {}
local dispatch = "hyprctl dispatch "

-- theme.json writes colours as "#rrggbb"; Hyprland wants "rgb(rrggbb)"
local function colour(hex, fallback)
    return hex and ("rgb(" .. hex:gsub("#", "") .. ")") or fallback
end
local SIZE = L.size or 13

-- Everything inside pcall: if something goes wrong we get a notification, not a crash.
local ok, err = pcall(function()
    hl.config({
        plugin = {
            hyprbars = {
                bar_height     = 30,
                bar_color      = T.titlebar or "rgb(2c2c2e)",
                col            = { text = T.titlebar_text or "rgba(ffffffb3)" },
                bar_text_font   = T.font and T.font.sans or "Noto Sans",
                bar_text_weight = "semibold",
                bar_text_size  = 11,
                bar_text_align = "center",

                bar_buttons_alignment = "left", -- buttons on the left, like on a Mac
                bar_padding           = 12,
                bar_button_padding    = L.spacing or 8,
                inactive_button_color = T.titlebar_button_inactive or "rgba(ffffff2a)", -- grey when inactive
                icon_on_hover         = true,  -- ×, −, + only while hovering

                bar_part_of_window         = true,
                bar_precedence_over_border = true,
                bar_blur                   = false,

                -- Double-click on the bar = "Zoom" like on a Mac (snapping.lua)
                on_double_click = dispatch .. [['macos.zoom()']],
            },
        },
    })

    -- Order = left to right
    hl.plugin.hyprbars.add_button({
        bg_color = colour(L.close, "rgb(ff5f57)"),
        fg_color = colour(L.close_glyph, "rgb(4d0000)"),
        size     = SIZE,
        icon     = "×",
        action   = dispatch .. [['hl.dsp.window.close()']],
    })

    hl.plugin.hyprbars.add_button({
        bg_color = colour(L.minimize, "rgb(febc2e)"),
        fg_color = colour(L.minimize_glyph, "rgb(5a3b00)"),
        size     = SIZE,
        icon     = "−",
        action   = dispatch .. [['hl.dsp.window.move({ workspace = "special:minimized", follow = false })']],
    })

    hl.plugin.hyprbars.add_button({
        bg_color = colour(L.zoom, "rgb(28c840)"),
        fg_color = colour(L.zoom_glyph, "rgb(0a4a00)"),
        size     = SIZE,
        icon     = "+",
        action   = dispatch .. [['macos.zoom()']],
    })

    -- Apps with their own title bar (GNOME apps like Finder) get no second one.
    -- Their bar has the traffic lights itself (desktop-theme); dragging, minimizing
    -- and zooming is done by riptide-wm (window_buttons.cpp). List: csd_apps.lua.
    hl.window_rule({
        name  = "own-titlebar",
        match = { class = require("modules.csd_apps").regex },

        ["hyprbars:no_bar"] = true,
    })
end)

if not ok then
    require("modules.notifications").show("Titelleisten konnten nicht eingerichtet werden", tostring(err), true)
end

-- After dragging by the title bar: snap to screen edges (snapping.lua).
-- The option on_drag_end is one of our changes (riptide-wm), so set it only if the loaded
-- plugin knows it.
local _, unknown = hl.get_config("plugin.hyprbars.on_drag_end")
if not unknown then
    hl.config({
        plugin = { hyprbars = { on_drag_end = dispatch .. [['macos.drag_ended()']] } },
    })
end
