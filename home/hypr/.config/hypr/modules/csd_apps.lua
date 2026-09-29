-- Apps that draw their own title bar ("client-side decorations") get no second bar with
-- traffic lights from riptide-wm. Which ones – data, not code:
--   ~/.config/macos/titlebars.json   what we know: GNOME apps like Finder, browsers,
--                                    Electron apps with their own frame (Discord, Obsidian)
--   settings.json → titlebars        the user's choice per app, wins (System Settings →
--                                    Erscheinungsbild → Titelleisten): class → "app" (its
--                                    own bar) or "ours" (our bar with the traffic lights)
-- Their traffic lights come from our theme (GTK: gtk.css from desktop-theme); Electron apps
-- draw their own buttons. Dragging/minimizing/zooming: riptide-wm (window_buttons.cpp).
-- Used by titlebars.lua (window rules) and snapping.lua (is there a bar of ours above?).

local json = require("modules.json")
local S = require("modules.settings")

local data = json.read("titlebars.json") or {}
local choice = type(S.titlebars) == "table" and S.titlebars or {}

-- "org.gnome.*" → a regular expression (window rules) and a Lua pattern (matches)
local function to_regex(glob)
    local escaped = glob:gsub("[%.%+%?%^%$%(%)%[%]%{%}|\\]", "\\%0")
    return (escaped:gsub("%*", ".*"))
end
local function to_lua(glob)
    local escaped = glob:gsub("[%.%+%-%?%^%$%(%)%[%]%%]", "%%%0")
    return "^" .. escaped:gsub("%*", ".*") .. "$"
end

local own, ours = {}, {}
for _, glob in ipairs(type(data.own) == "table" and data.own or {}) do
    if type(glob) == "string" then own[#own + 1] = glob end
end
for class, how in pairs(choice) do
    if type(class) == "string" and class:match("^[%w%.%-_]+$") then
        if how == "app" then own[#own + 1] = class elseif how == "ours" then ours[#ours + 1] = class end
    end
end

local function alternatives(globs)
    local parts = {}
    for _, g in ipairs(globs) do parts[#parts + 1] = to_regex(g) end
    return "^(" .. table.concat(parts, "|") .. ")$"
end

local M = {}

-- For Hyprland's window rules: no bar for these, and ours again for those the user chose
M.regex = #own > 0 and alternatives(own) or nil
M.ours_regex = #ours > 0 and alternatives(ours) or nil

-- Apps where only the main window draws its own bar (Thunderbird: its compose window,
-- message windows and dialogs have none). The main window is told apart by its title.
M.main_only = {}
for _, app in ipairs(type(data.main_only) == "table" and data.main_only or {}) do
    if type(app.classes) == "table" and type(app.initial_title) == "string" then
        M.main_only[#M.main_only + 1] = {
            class = alternatives(app.classes), initial_title = "^" .. to_regex(app.initial_title) .. "$",
            classes = app.classes, title = app.initial_title,
        }
    end
end

function M.matches(w)
    if not w or not w.class then return false end
    if choice[w.class] == "ours" then return false end
    if choice[w.class] == "app" then return true end
    for _, glob in ipairs(own) do
        if w.class:match(to_lua(glob)) then return true end
    end
    for _, app in ipairs(M.main_only) do
        for _, c in ipairs(app.classes) do
            if w.class == c and (w.initial_title or "") == app.title then return true end
        end
    end
    return false
end

return M
