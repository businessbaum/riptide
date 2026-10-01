-- Reading our JSON files (the user's settings in ~/.config/macos/, the software's data in data/)
-- in the Lua config. Minimal, but enough for our files.
--   json.read("settings.json")  → table, or nil and the reason
--   json.read_data("theme.json") → the same, from the software's data/
--   json.parse(text)            → value (errors on bad input)

local function parse_json(text)
    local pos = 1
    local value

    local function skip() pos = text:find("[^ \t\r\n]", pos) or #text + 1 end
    local function fail(what) error(what .. " at character " .. pos) end

    local function str()
        local parts = {}
        pos = pos + 1
        while true do
            local c = text:sub(pos, pos)
            if c == "" then fail("unterminated string") end
            if c == '"' then pos = pos + 1; return table.concat(parts) end
            if c == "\\" then
                local n = text:sub(pos + 1, pos + 1)
                local repl = ({ ['"'] = '"', ["\\"] = "\\", ["/"] = "/", n = "\n", t = "\t", r = "\r", b = "\b", f = "\f" })[n]
                if n == "u" then
                    repl = utf8.char(tonumber(text:sub(pos + 2, pos + 5), 16)); pos = pos + 4
                end
                if not repl then fail("unknown escape \\" .. n) end
                parts[#parts + 1] = repl; pos = pos + 2
            else
                parts[#parts + 1] = c; pos = pos + 1
            end
        end
    end

    function value()
        skip()
        local c = text:sub(pos, pos)
        if c == "{" then
            local t = {}; pos = pos + 1; skip()
            if text:sub(pos, pos) == "}" then pos = pos + 1; return t end
            while true do
                skip(); if text:sub(pos, pos) ~= '"' then fail("key expected") end
                local k = str(); skip()
                if text:sub(pos, pos) ~= ":" then fail("':' expected") end
                pos = pos + 1; t[k] = value(); skip()
                local s = text:sub(pos, pos); pos = pos + 1
                if s == "}" then return t end
                if s ~= "," then fail("',' or '}' expected") end
            end
        elseif c == "[" then
            local t = {}; pos = pos + 1; skip()
            if text:sub(pos, pos) == "]" then pos = pos + 1; return t end
            while true do
                t[#t + 1] = value(); skip()
                local s = text:sub(pos, pos); pos = pos + 1
                if s == "]" then return t end
                if s ~= "," then fail("',' or ']' expected") end
            end
        elseif c == '"' then return str()
        elseif text:sub(pos, pos + 3) == "true" then pos = pos + 4; return true
        elseif text:sub(pos, pos + 4) == "false" then pos = pos + 5; return false
        elseif text:sub(pos, pos + 3) == "null" then pos = pos + 4; return nil
        else
            local num = text:match("^-?%d+%.?%d*[eE]?[-+]?%d*", pos)
            if not num or num == "" then fail("unexpected character") end
            pos = pos + #num
            return tonumber(num)
        end
    end

    return value()
end

local DIR = os.getenv("HOME") .. "/.config/macos/"
-- the software's own data (knowledge about apps, design tokens): data/ next to this config
-- folder in riptide's tree (hypr/data links to ../data) – wherever the tree is
local CONFIG = debug.getinfo(1, "S").source:match("^@(.*)/modules/[^/]+$") or (os.getenv("HOME") .. "/.config/hypr")
local DATA = CONFIG .. "/data/"

local function read_file(path, name)
    local f = io.open(path, "r")
    if not f then return nil, name .. " not found" end
    local text = f:read("a"); f:close()
    local ok, data = pcall(parse_json, text)
    if not ok or type(data) ~= "table" then return nil, name .. ": " .. tostring(data) end
    return data
end

-- The user's settings: a name in ~/.config/macos/, or an absolute path (state files in
-- ~/.local/state/macos/)
local function read(name)
    return read_file((name:sub(1, 1) == "/" and "" or DIR) .. name, name)
end

-- the software's data: a name in data/ (titlebars.json, theme.json …)
local function read_data(name)
    return read_file(DATA .. name, name)
end

return { parse = parse_json, read = read, read_data = read_data, config_dir = CONFIG }
