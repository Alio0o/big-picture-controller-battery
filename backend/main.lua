local logger     = require("logger")
local millennium = require("millennium")
local win32      = require("win32")
local battery    = require("battery")
local settings   = require("settings")
local shortcut   = require("shortcut")

-- Small JSON encoder for the flat tables sent to the frontend.
local function quote(text)
    return '"' .. text:gsub('[%c"\\]', function(c)
        return string.format("\\u%04x", c:byte())
    end) .. '"'
end

local function encode(value)
    local kind = type(value)
    if kind == "table" then
        local parts = {}
        for k, v in pairs(value) do parts[#parts + 1] = quote(tostring(k)) .. ":" .. encode(v) end
        return "{" .. table.concat(parts, ",") .. "}"
    elseif kind == "string" then
        return quote(value)
    elseif kind == "number" or kind == "boolean" then
        return tostring(value)
    end
    return "null"
end

---@ffi
--- Battery level of the connected Bluetooth controller.
---@return string
function getBattery()
    local ok, result = pcall(battery.read)
    if not ok then
        logger:error("Battery read failed: " .. tostring(result))
        return encode({ status = "unavailable", message = tostring(result) })
    end
    return encode(result)
end

---@ffi
--- Called on a short timer while a game runs; see shortcut.lua.
---@return string
function pollShortcut()
    local ok, result = pcall(shortcut.poll)
    if not ok then
        logger:error("Shortcut poll failed: " .. tostring(result))
        return "error"
    end
    return result
end

---@ffi
---@return string
function getSettings()
    local values = {}
    for k, v in pairs(settings.get()) do values[k] = v end
    values.windows = win32.available
    values.unavailable_reason = win32.reason
    return encode(values)
end

---@ffi
--- Saves one setting. Returns "ok" or an error message for the settings page.
---@param key string
---@param value string
---@return string
function setSetting(key, value)
    local parsed = value
    if key == "overlay_shortcut" then parsed = value == "true"
    elseif key == "hold_ms" then parsed = tonumber(value) end
    local ok, message = settings.set(key, parsed)
    return ok and "ok" or message
end

local function on_load()
    if win32.available then
        logger:info("Loaded on Millennium " .. millennium.version())
    else
        logger:warn("Inactive: " .. tostring(win32.reason))
    end
    millennium.ready()
end

local function on_unload()
    logger:info("Unloaded")
end

return {
    on_load = on_load,
    on_unload = on_unload,
}
