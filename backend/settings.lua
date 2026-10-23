-- Plugin settings, stored by Millennium's own plugin config (removed together
-- with the plugin). Values are checked here so a bad value can never reach
-- the shortcut code.
local millennium = require("millennium")
local logger = require("logger")

local M = {}

M.defaults = {
    battery_badge = true,
    overlay_shortcut = true,
    hold_ms = 600,
    button = "Menu",
    keys = "Shift+Tab",
    game_mute = true,
    music = false,
    music_path = "",
    music_volume = 40,
    music_in_overlay = false,
}

local VIRTUAL_KEYS = { SHIFT = 0xA0, CTRL = 0xA2, CONTROL = 0xA2, ALT = 0xA4, TAB = 0x09 }

-- "Shift+Tab" -> { 0xA0, 0x09 }, or nil and an error message.
function M.parse_keys(text)
    local keys = {}
    for part in tostring(text or ""):gmatch("[^+]+") do
        local name = part:match("^%s*(.-)%s*$"):upper()
        local code = VIRTUAL_KEYS[name]
        if not code and name:match("^[A-Z0-9]$") then code = name:byte() end
        local f = name:match("^F(%d%d?)$")
        if not code and f and tonumber(f) >= 1 and tonumber(f) <= 12 then code = 0x70 + tonumber(f) - 1 end
        if not code then
            return nil, "Unknown key '" .. part .. "'. Use Shift, Ctrl, Alt, Tab, A-Z, 0-9 or F1-F12."
        end
        keys[#keys + 1] = code
    end
    if #keys == 0 then return nil, "Enter at least one key." end
    return keys
end

local checks = {
    overlay_shortcut = function(v) return type(v) == "boolean" end,
    hold_ms = function(v) return type(v) == "number" and v >= 200 and v <= 5000 and v % 1 == 0 end,
    button = function(v) return v == "Menu" or v == "View" end,
    keys = function(v) return type(v) == "string" and M.parse_keys(v) ~= nil end,
    battery_badge = function(v) return type(v) == "boolean" end,
    game_mute = function(v) return type(v) == "boolean" end,
    music = function(v) return type(v) == "boolean" end,
    music_in_overlay = function(v) return type(v) == "boolean" end,
    music_path = function(v) return type(v) == "string" and #v <= 1024 end,
    music_volume = function(v) return type(v) == "number" and v >= 0 and v <= 100 and v % 1 == 0 end,
}

M.booleans = { battery_badge = true, overlay_shortcut = true, game_mute = true, music = true, music_in_overlay = true }
M.numbers = { hold_ms = true, music_volume = true }

local current = nil
local listeners = {}

function M.on_change(callback)
    listeners[#listeners + 1] = callback
end

function M.get()
    if current then return current end
    current = {}
    for key, default in pairs(M.defaults) do
        local ok, value = pcall(millennium.config.get, key)
        -- config.get returns the value, or nil and an error.
        if ok and value ~= nil and checks[key](value) then
            current[key] = value
        else
            current[key] = default
        end
    end
    return current
end

-- Reads the stored values again on the next get().
function M.reload()
    current = nil
end

-- Before 3.0 this plugin was "big-picture-controller-battery". Millennium only
-- gives a plugin its own config, so the old settings are read once from
-- Millennium's config.json, where they sit under plugins.<old id>.config.
local OLD_ID = "big-picture-controller-battery"
local MIGRATED = "migrated_from_v2"

local function old_config_paths()
    local paths = {}
    local ok, steam = pcall(millennium.steam_path)
    if ok and type(steam) == "string" then paths[#paths + 1] = steam .. "/millennium/config/config.json" end
    local ok2, install = pcall(millennium.get_install_path)
    if ok2 and type(install) == "string" then
        paths[#paths + 1] = install .. "/config/config.json"
        paths[#paths + 1] = install .. "/millennium/config/config.json"
    end
    return paths
end

-- Returns the number of settings copied, or nil and the reason.
function M.migrate(paths)
    local ok, done = pcall(millennium.config.get, MIGRATED)
    if ok and done == true then return 0 end
    -- Millennium 3.6 has no cjson for plugins; the small decoder covers that.
    local okjson, json = pcall(require, "cjson")
    if not okjson or type(json) ~= "table" or type(json.decode) ~= "function" then json = require("couch_json") end

    local old
    for _, path in ipairs(paths or old_config_paths()) do
        local file = io.open(path, "rb")
        if file then
            local text = file:read("*a")
            file:close()
            local okdecode, data = pcall(json.decode, text)
            if okdecode and type(data) == "table" and type(data.plugins) == "table" then
                local entry = data.plugins[OLD_ID]
                old = type(entry) == "table" and type(entry.config) == "table" and entry.config or {}
                break
            end
        end
    end
    if not old then return nil, "config.json not found" end

    local copied = 0
    for key in pairs(M.defaults) do
        local value = old[key]
        local okget, mine = pcall(millennium.config.get, key)
        if value ~= nil and checks[key](value) and not (okget and mine ~= nil) then
            local okset, saved = pcall(millennium.config.set, key, value)
            if okset and saved ~= false then copied = copied + 1 end
        end
    end
    pcall(millennium.config.set, MIGRATED, true)
    current = nil
    if copied > 0 then logger:info("Copied " .. copied .. " setting(s) from " .. OLD_ID) end
    return copied
end

-- Returns true, or false and a message for the settings page.
function M.set(key, value)
    if not checks[key] then return false, "Unknown setting: " .. tostring(key) end
    if not checks[key](value) then
        local _, message = M.parse_keys(value)
        return false, key == "keys" and message or ("Invalid value for " .. key)
    end
    local ok, saved, err = pcall(millennium.config.set, key, value)
    if not ok or saved == false then return false, "Could not save: " .. tostring(err or saved) end
    M.get()[key] = value
    logger:info("Setting changed: " .. key .. " = " .. tostring(value))
    for _, callback in ipairs(listeners) do callback(M.get()) end
    return true
end

return M
