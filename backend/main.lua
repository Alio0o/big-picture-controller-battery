local logger     = require("logger")
local millennium = require("millennium")
local win32      = require("win32")
local battery    = require("battery")
local settings   = require("settings")
local shortcut   = require("shortcut")
local access     = require("access")
local audio      = require("audio")
local music      = require("music")
local dialog     = require("dialog")

-- Small JSON encoder for the tables sent to the frontend. A table with keys
-- 1..n is a list; an empty table is an object.
local function quote(text)
    return '"' .. text:gsub('[%c"\\]', function(c)
        return string.format("\\u%04x", c:byte())
    end) .. '"'
end

local function encode(value)
    local kind = type(value)
    if kind == "table" then
        local parts, count = {}, 0
        for _ in pairs(value) do count = count + 1 end
        if count > 0 and count == #value then
            for i = 1, #value do parts[i] = encode(value[i]) end
            return "[" .. table.concat(parts, ",") .. "]"
        end
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
    if settings.booleans[key] then parsed = value == "true"
    elseif settings.numbers[key] then parsed = tonumber(value) end
    local ok, message = settings.set(key, parsed)
    return ok and "ok" or message
end

---@ffi
--- Whether this plugin may read the controller in Xbox mode: "on" or "off".
---@return string
function getXboxModeAccess()
    local ok, result = pcall(access.status)
    return ok and result or "off"
end

---@ffi
--- Turns Xbox mode controller access on or off. Windows asks for administrator
--- rights. Returns "started", "cancelled" or "error".
---@param state string "on" or "off"
---@return string
function setXboxModeAccess(state)
    local ok, result = pcall(state == "on" and access.enable or access.disable)
    if not ok then
        logger:error("Changing Xbox mode access failed: " .. tostring(result))
        return "error"
    end
    return result
end

---@ffi
--- Whether a Steam window (Big Picture, its menus or popups) is the window
--- in front: "yes", "no" or "unknown".
---@return string
function steamInFront()
    if not win32.available then return "unknown" end
    local ok, result = pcall(shortcut.steam_in_front)
    if not ok then return "unknown" end
    return result and "yes" or "no"
end

---@ffi
--- Mutes the game with this process id (and the processes it started) while
--- the Steam overlay is open. Returns a short summary for the log.
---@param pid number
---@return string
function muteGame(pid)
    if not settings.get().game_mute then return "off" end
    local ok, result = pcall(audio.mute, pid)
    if not ok then
        logger:error("Muting the game failed: " .. tostring(result))
        return "error"
    end
    return result
end

---@ffi
--- Unmutes what muteGame muted. Returns how many audio sessions.
---@return number
function unmuteGame()
    local ok, result = pcall(audio.unmute)
    if not ok then
        logger:error("Unmuting the game failed: " .. tostring(result))
        return 0
    end
    return result
end

---@ffi
--- The music files to play on Home and Library, from the music setting.
---@return string
function getMusic()
    local ok, result = pcall(music.list)
    if not ok then
        logger:error("Listing music failed: " .. tostring(result))
        return encode({ folder = "", tracks = {}, error = tostring(result) })
    end
    return encode(result)
end

---@ffi
--- Part of a music file from getMusic, as base64. Empty at the end.
---@param path string
---@param offset number
---@return string
function readMusic(path, offset)
    local ok, result = pcall(music.chunk, path, offset)
    if not ok then
        logger:error("Reading music failed: " .. tostring(result))
        return ""
    end
    return result
end

---@ffi
--- Opens Windows' Open dialog to choose the music. Returns the chosen path,
--- "" when cancelled, or "error: ..." when the dialog cannot open.
---@param kind string "file" or "folder"
---@return string
function browseMusic(kind)
    local ok, path, err = pcall(dialog.choose, kind == "folder" and "folder" or "file", music.start_folder())
    if not ok or path == nil then
        local message = tostring(ok and err or path)
        logger:error("Music dialog failed: " .. message)
        return "error: " .. message
    end
    return path
end

local function on_load()
    if win32.available then
        logger:info("Loaded on Millennium " .. millennium.version())
    else
        logger:warn("Inactive: " .. tostring(win32.reason))
    end
    local ok, copied, reason = pcall(settings.migrate)
    if not ok or copied == nil then
        logger:warn("Settings from Big Picture Controller Battery not copied: " .. tostring(ok and reason or copied))
    end
    millennium.ready()
end

local function on_unload()
    pcall(audio.unmute)
    logger:info("Unloaded")
end

return {
    on_load = on_load,
    on_unload = on_unload,
}
