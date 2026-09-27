-- Hyprland for riptide's login screen (greetd, user "greeter"): nothing but our login
-- window (Quickshell, layer surfaces). Started by /usr/local/lib/riptide/greeter/start.

hl.monitor({ output = "", mode = "preferred", position = "auto", scale = "auto" })

hl.config({
    input = {
        kb_layout = "de",
        numlock_by_default = true,
        -- no ⌃⌥F1 … F12: there are no text consoles to switch to
        kb_options = "srvrkeys:none",
    },
    general = { border_size = 0, gaps_in = 0, gaps_out = 0 },
    decoration = { rounding = 0, shadow = { enabled = false }, blur = { enabled = false } },
    misc = {
        background_color = "rgb(1b2a4a)",
        disable_hyprland_logo = true,
        disable_splash_rendering = true,
        disable_autoreload = true,
    },
    ecosystem = { no_update_news = true, no_donation_nag = true },
})

-- the login window fades in, nothing else moves
hl.curve("smooth", { type = "bezier", points = { {0.25, 0.1}, {0.25, 1} } })
hl.animation({ leaf = "global", enabled = false })
hl.animation({ leaf = "fadeLayersIn", enabled = true, speed = 4, bezier = "smooth" })

hl.on("hyprland.start", function()
    hl.exec_cmd("/usr/local/lib/riptide/greeter/run")
end)

-- Emergency: ⌃⌥F1 … F6 end the login window; the start script then offers the text login
-- (with a shell for repairs). There are no text consoles to switch to (srvrkeys:none).
for i = 1, 6 do
    hl.bind("CTRL + ALT + F" .. i, hl.dsp.exit())
end
