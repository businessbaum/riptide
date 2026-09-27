-- The login screen (greetd; system/files/usr/local/share/riptide/greeter) may not read the
-- home folder. How mouse and keyboard should feel there – as here – is left for it on
-- every start and reload of this config, so after every change in System Settings:
--   /var/lib/riptide/greeter/users/<user>/input.conf   (the folder: system/setup-os.sh)
-- The login screen takes only checked numbers and a layout name from it.

local S = require("modules.settings")

local dir = "/var/lib/riptide/greeter/users/" .. (os.getenv("USER") or "")
local f = io.open(dir .. "/input.conf.tmp", "w")
if f then
    f:write(string.format(
        "sensitivity=%s\nnatural_scroll=%s\nscroll_factor=%s\nkb_layout=%s\nrepeat_rate=%s\nrepeat_delay=%s\ncursor_size=%s\n",
        tostring(tonumber(S.mouse.speed) or 0), tostring(S.mouse.natural_scroll == true),
        tostring(tonumber(S.mouse.scroll_factor) or 1), tostring(S.keyboard.layout or "de"),
        tostring(tonumber(S.keyboard.repeat_rate) or 25), tostring(tonumber(S.keyboard.repeat_delay) or 600),
        tostring(tonumber(S.mouse.cursor_size) or 22)))
    f:close()
    os.rename(dir .. "/input.conf.tmp", dir .. "/input.conf")
end
