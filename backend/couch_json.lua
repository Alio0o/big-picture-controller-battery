-- Small JSON decoder, for reading Millennium's config.json. Millennium's Lua
-- has no cjson on every version, so this is used when it is missing.
-- Strings keep \u escapes outside ASCII as "?"; only keys and simple values
-- are read here.
local M = {}

local function fail(pos, what)
    error("JSON: " .. what .. " at character " .. pos, 0)
end

local ESCAPES = { ['"'] = '"', ["\\"] = "\\", ["/"] = "/", b = "\b", f = "\f", n = "\n", r = "\r", t = "\t" }

local function skip(text, pos)
    return text:find("[^ \t\r\n]", pos) or #text + 1
end

local value

local function string_at(text, pos)
    local out, i = {}, pos + 1
    while true do
        local c = text:sub(i, i)
        if c == "" then fail(pos, "unterminated string") end
        if c == '"' then return table.concat(out), i + 1 end
        if c == "\\" then
            local e = text:sub(i + 1, i + 1)
            if e == "u" then
                local code = tonumber(text:sub(i + 2, i + 5), 16)
                if not code then fail(i, "bad escape") end
                out[#out + 1] = code < 128 and string.char(code) or "?"
                i = i + 6
            elseif ESCAPES[e] then
                out[#out + 1] = ESCAPES[e]
                i = i + 2
            else
                fail(i, "bad escape")
            end
        else
            local j = text:find('["\\]', i) or #text + 1
            out[#out + 1] = text:sub(i, j - 1)
            i = j
        end
    end
end

value = function(text, pos)
    pos = skip(text, pos)
    local c = text:sub(pos, pos)
    if c == "{" then
        local result = {}
        pos = skip(text, pos + 1)
        if text:sub(pos, pos) == "}" then return result, pos + 1 end
        while true do
            if text:sub(pos, pos) ~= '"' then fail(pos, "expected a key") end
            local key
            key, pos = string_at(text, pos)
            pos = skip(text, pos)
            if text:sub(pos, pos) ~= ":" then fail(pos, "expected ':'") end
            result[key], pos = value(text, pos + 1)
            pos = skip(text, pos)
            local sep = text:sub(pos, pos)
            if sep == "}" then return result, pos + 1 end
            if sep ~= "," then fail(pos, "expected ',' or '}'") end
            pos = skip(text, pos + 1)
        end
    elseif c == "[" then
        local result = {}
        pos = skip(text, pos + 1)
        if text:sub(pos, pos) == "]" then return result, pos + 1 end
        while true do
            result[#result + 1], pos = value(text, pos)
            pos = skip(text, pos)
            local sep = text:sub(pos, pos)
            if sep == "]" then return result, pos + 1 end
            if sep ~= "," then fail(pos, "expected ',' or ']'") end
            pos = pos + 1
        end
    elseif c == '"' then
        return string_at(text, pos)
    elseif text:sub(pos, pos + 3) == "true" then
        return true, pos + 4
    elseif text:sub(pos, pos + 4) == "false" then
        return false, pos + 5
    elseif text:sub(pos, pos + 3) == "null" then
        return nil, pos + 4
    end
    local number = text:match("^-?%d+%.?%d*[eE]?[-+]?%d*", pos)
    if number and tonumber(number) then return tonumber(number), pos + #number end
    fail(pos, "unexpected '" .. c .. "'")
end

function M.decode(text)
    local result, pos = value(text, 1)
    if skip(text, pos) <= #text then fail(pos, "extra text") end
    return result
end

return M
