-- Bedienungshilfen (System Settings → Bedienungshilfen; settings.json "accessibility"):
--   zoom_keys       zoom the screen like on a Mac: ⌥⌘8 on/off, ⌥⌘+ / ⌥⌘- closer/farther
--   reduce_motion   fades instead of sliding and popping (looks.lua reads it too)
--   contrast        stronger window borders (looks.lua)

local S = require("modules.settings")
local A = S.accessibility

macos = macos or {}

-- (macos.screen_zoom, not macos.zoom: that is the green button, snapping.lua)
local zoom, last = 1.0, 2.0
local function set_zoom(f)
    zoom = math.max(1.0, math.min(8.0, f))
    if zoom > 1.0 then last = zoom end
    hl.config({ cursor = { zoom_factor = zoom } })
end

function macos.screen_zoom(action)
    if action == "toggle" then set_zoom(zoom > 1.0 and 1.0 or last)
    elseif action == "in" then set_zoom(zoom + 0.5)
    elseif action == "out" then set_zoom(zoom - 0.5)
    end
    return hl.dsp.no_op()
end

if A.zoom_keys then
    hl.bind("SUPER + ALT + 8",     function() macos.screen_zoom("toggle") end) -- ⌥⌘8: zoom on/off
    hl.bind("SUPER + ALT + plus",  function() macos.screen_zoom("in") end,  { repeating = true }) -- ⌥⌘+
    hl.bind("SUPER + ALT + minus", function() macos.screen_zoom("out") end, { repeating = true }) -- ⌥⌘-
end
