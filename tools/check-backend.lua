-- Runs the backend outside Steam with stand-ins for Millennium's modules.
-- Usage (Windows, LuaJIT 2.1): luajit tools/check-backend.lua
-- Reads the real battery and controller. It polls the shortcut once, which
-- cannot complete a hold, so no keys are sent.
package.path = "backend/?.lua;" .. package.path

local config = {}
package.loaded.logger = {
    info = function(_, m) print("[info] " .. m) end,
    warn = function(_, m) print("[warn] " .. m) end,
    error = function(_, m) print("[error] " .. m) end,
}
package.loaded.millennium = {
    ready = function() end,
    version = function() return "test" end,
    config = {
        get = function(k) return config[k] end,
        set = function(k, v) config[k] = v; return true end,
    },
}

local failures = 0
local function check(name, ok)
    print((ok and "PASS " or "FAIL ") .. name)
    if not ok then failures = failures + 1 end
end

dofile("backend/main.lua")
local settings = require("settings")
local shortcut = require("shortcut")

-- Settings
check("defaults", settings.get().overlay_shortcut == true and settings.get().hold_ms == 600)
check("parse Shift+Tab", table.concat(settings.parse_keys("Shift+Tab"), ",") == "160,9")
check("parse F12", settings.parse_keys("f12")[1] == 0x7B)
check("reject bad key", settings.parse_keys("Shift+Banana") == nil)
check("set hold 300", setSetting("hold_ms", "300") == "ok" and settings.get().hold_ms == 300)
check("reject hold 50", setSetting("hold_ms", "50") ~= "ok")
check("reject bad button", setSetting("button", "A") ~= "ok")
check("set off", setSetting("overlay_shortcut", "false") == "ok" and pollShortcut() == "off")
check("set on", setSetting("overlay_shortcut", "true") == "ok")
check("settings json", getSettings():match('"hold_ms":300') ~= nil)

-- Hold logic (no Windows calls)
local h = shortcut.hold_step
h(0, false, false, 300)
check("short press does not fire", not h(0, true, false, 300) and not h(200, true, false, 300))
h(250, false, false, 300)
check("long press fires once", not h(1000, true, false, 300) and h(1300, true, false, 300) and not h(1600, true, false, 300))
h(1700, false, false, 300)
check("combo never fires", not h(2000, true, true, 300) and not h(2400, true, false, 300))
h(2500, false, false, 300)

-- Real hardware reads
print("battery: " .. getBattery())
-- One poll reads the controller; a single poll can never complete a hold.
setSetting("hold_ms", "5000")
print("shortcut poll: " .. pollShortcut())

print(failures == 0 and "All checks passed" or (failures .. " check(s) failed"))
os.exit(failures == 0 and 0 or 1)
