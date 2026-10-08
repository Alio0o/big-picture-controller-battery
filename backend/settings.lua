-- Plugin settings, stored by Millennium's own plugin config (removed together
-- with the plugin). Values are checked here so a bad value can never reach
-- the shortcut code.
local millennium = require("millennium")
local logger = require("logger")

local M = {}

M.defaults = {
    overlay_shortcut = true,
    hold_ms = 600,
    button = "Menu",
    keys = "Shift+Tab",
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
}

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
