-- Recording the screen and loading plugins ask first, like "Bildschirm- &
-- Systemaudioaufnahme" on a Mac: Hyprland checks every program that uses screencopy or
-- loads a plugin; the question shows as our dialog (the hyprland-dialog stand-in in
-- ~/.local/bin → the shell's HyprDialogs.qml). "Erlauben" holds until the program ends.
-- Sandboxed apps never get screencopy (Wayland security context); they share through the
-- portal, which asks per app (riptide-session). Our own tools are allowed here.

local home = os.getenv("HOME")

-- a path as a regex that matches only itself
local function exactly(path)
    return "^" .. path:gsub("[%.%-%+%*%?%[%]%^%$%(%)]", "\\%0") .. "$"
end

hl.config({ ecosystem = { enforce_permissions = true } })

local allowed = {
    { "/usr/bin/quickshell", "screencopy" },                  -- the shell: previews, Launchpad's background
    { "/usr/bin/hyprlock", "screencopy" },                    -- lock screen: the blurred desktop
    { "/usr/bin/grim", "screencopy" },                        -- screenshots (⌘⇧3, ⌘⇧4)
    { "/usr/lib/xdg-desktop-portal-hyprland", "screencopy" }, -- sharing: asks per app itself
    { "/usr/bin/hyprpicker", "screencopy" },                  -- colour picker
    { "/usr/bin/gpu-screen-recorder", "screencopy" },         -- screen recording (⌘⇧5)
    { home .. "/.local/lib/hyprland-plugins/riptide-wm.so", "plugin" }, -- our plugin
}
local function rules()
    for _, a in ipairs(allowed) do
        hl.permission({ binary = exactly(a[1]), type = a[2], mode = "allow" })
    end
    -- Typing for others (input methods, on-screen keyboards) and the pointer position stay
    -- open as before; asking for them comes with the accessibility settings
    hl.permission({ binary = ".*", type = "keyboard", mode = "allow" })
    hl.permission({ binary = ".*", type = "cursorpos", mode = "allow" })
end

-- Hyprland drops rules given while enforce_permissions is still off – so at login (the
-- first reading of the config) they are given again at start, before autostart.lua loads
-- the plugin (handlers run in require order). On a reload it is already on.
rules()
hl.on("hyprland.start", rules)
