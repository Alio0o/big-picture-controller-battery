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

-- Settings from the old plugin id. Plain LuaJIT has no cjson, so a stand-in
-- turns this simple JSON into a Lua table.
package.loaded.cjson = package.loaded.cjson or {
    decode = function(text)
        local lua = text:gsub('"([%w_%-]+)"%s*:', '["%1"]=')
        return assert(loadstring("return " .. lua))()
    end,
}
local function fresh() config = {}; settings.reload() end
local tmp = os.tmpname()
local f = assert(io.open(tmp, "wb"))
f:write('{"plugins":{"big-picture-controller-battery":{"config":{"hold_ms":250,"button":"View","keys":"Banana"}}}}')
f:close()
fresh()
check("migrate copies valid old settings", settings.migrate({ tmp }) == 2 and settings.get().hold_ms == 250
    and settings.get().button == "View" and settings.get().keys == "Shift+Tab")
check("migrate runs once", settings.migrate({ tmp }) == 0)
fresh()
check("migrate keeps own settings", setSetting("hold_ms", "900") == "ok" and settings.migrate({ tmp }) == 1
    and settings.get().hold_ms == 900)
fresh()
check("migrate without file", settings.migrate({ tmp .. ".missing" }) == nil)
os.remove(tmp)
fresh()
check("new defaults", settings.get().game_mute == true and settings.get().music == false
    and settings.get().music_volume == 40 and settings.get().battery_badge == true)
check("set music volume", setSetting("music_volume", "55") == "ok" and setSetting("music_volume", "101") ~= "ok")
check("set game mute off", setSetting("game_mute", "false") == "ok" and settings.get().game_mute == false)
fresh()

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

-- Audio sessions. Lists them; changes nothing unless a test process is given.
local audio = require("audio")
local sessions = audio.sessions()
print("audio sessions: " .. #sessions)
check("unmute with nothing muted", unmuteGame() == 0)
check("process tree has its root", audio.process_tree(4242)[4242] == true)

-- With COUCH_TEST_PID set to a process that plays sound (or that started one
-- that does), mutes and unmutes it once. Use something silent.
local test_pid = tonumber(os.getenv("COUCH_TEST_PID") or "")
if test_pid then
    local function is_muted()
        local tree, any, all = audio.process_tree(test_pid), false, true
        for _, s in ipairs(audio.sessions()) do
            if tree[s.pid] then any = true; all = all and s.muted end
        end
        return any and all, any
    end
    local _, has_session = is_muted()
    check("test process has an audio session", has_session)
    setSetting("game_mute", "true")
    print("mute: " .. muteGame(test_pid))
    check("test process muted", is_muted())
    check("mute twice changes nothing", muteGame(test_pid):match("^muted 0 ") ~= nil)
    check("unmute", unmuteGame() >= 1 and not is_muted())
    setSetting("game_mute", "false")
    check("mute off in settings", muteGame(test_pid) == "off")
end

print(failures == 0 and "All checks passed" or (failures .. " check(s) failed"))
os.exit(failures == 0 and 0 or 1)
