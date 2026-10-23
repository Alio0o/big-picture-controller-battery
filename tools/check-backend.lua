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

-- Settings from the old plugin id. Plain LuaJIT has no cjson, so this also
-- checks the small decoder used when Millennium has none.
local couch_json = require("couch_json")
local decoded = couch_json.decode([[ {"a":[1,2.5,-3e2,true,false,null],"b":{"c":"x\"A\n"},"d":{}} ]])
check("json decoder", decoded.a[2] == 2.5 and decoded.a[3] == -300 and decoded.a[4] == true and decoded.a[5] == false
    and decoded.b.c == 'x"A\n' and next(decoded.d) == nil)
check("json decoder unicode escape", couch_json.decode('"\\' .. 'u0041\\' .. 'u00e9"') == "A?")
check("json decoder rejects bad input", not pcall(couch_json.decode, '{"a":1,}') and not pcall(couch_json.decode, '{"a":1} x'))
local real = os.getenv("COUCH_CONFIG_JSON")
if real then
    local rf = assert(io.open(real, "rb"))
    local data = couch_json.decode(rf:read("*a"))
    rf:close()
    local old = data.plugins and data.plugins["big-picture-controller-battery"]
    print("real config.json old settings: hold_ms=" .. tostring(old and old.config and old.config.hold_ms))
    check("json decoder reads the real config.json", type(data.plugins) == "table")
end
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
    and settings.get().music_volume == 30 and settings.get().battery_badge == true)
check("set music volume", setSetting("music_volume", "55") == "ok" and setSetting("music_volume", "101") ~= "ok")
check("music in overlay off by default", settings.get().music_in_overlay == false and setSetting("music_in_overlay", "true") == "ok")
check("music not paused by default", settings.get().music_paused == false)
check("pause music", setSetting("music_paused", "true") == "ok" and settings.get().music_paused == true
    and getSettings():match('"music_paused":true') ~= nil)
check("resume music", setSetting("music_paused", "false") == "ok" and settings.get().music_paused == false)
check("set game mute off", setSetting("game_mute", "false") == "ok" and settings.get().game_mute == false)
fresh()

-- Music: one folder, one chosen file. The checks use a test folder with a
-- name outside English (UTF-8 here) instead of the real Music folder.
local music = require("music")
local win32 = require("win32")
local ffi = require("ffi")
ffi.cdef("int32_t RemoveDirectoryW(const uint16_t* lpPathName); int32_t DeleteFileW(const uint16_t* lpFileName);")
check("base64", music.base64("") == "" and music.base64("f") == "Zg==" and music.base64("fo") == "Zm8="
    and music.base64("foo") == "Zm9v" and music.base64("\255\0\128hello") == "/wCAaGVsbG8=")
check("music folder is per user", (music.folder() or ""):match("\\Couch Mode$") ~= nil)
print("music folder: " .. tostring(music.folder()))
check("music volume default 30", settings.get().music_volume == 30)
check("music file name only", setSetting("music_file", "C:\\x.mp3") ~= "ok" and setSetting("music_file", "a.mp3") == "ok")
setSetting("music_file", "")

local base = os.getenv("TEMP") .. "\\couch-mode-check"
local folder = base .. "\\M\195\188sik \226\156\147"
music.set_folder(folder)
check("utf8 round trip", win32.utf8(win32.utf16(folder)) == folder)
win32.create_folder(base)
check("music folder created", getMusic():match('"error":"Put music files in ') ~= nil and win32.path_kind(folder) == "folder")

-- Files go in through the dialog's adopt step, which copies them in.
local function write(path, data)
    local out = assert(io.open(path, "wb"))
    out:write(data)
    out:close()
end
write(base .. "\\b.MP3", string.rep("\1\2\3", 300000)) -- 900 000 bytes, two pieces
write(base .. "\\a.ogg", "abc")
write(base .. "\\notes.txt", "abc")
check("adopt copies a file in", music.adopt(base .. "\\b.MP3") == "b.MP3" and win32.path_kind(folder .. "\\b.MP3") == "file")
check("adopt keeps an existing name", music.adopt(base .. "\\b.MP3") == "b (2).MP3")
check("adopt takes a file already there", music.adopt(folder .. "\\b.MP3") == "b.MP3")
check("adopt refuses other files", music.adopt(base .. "\\notes.txt") == nil)
music.adopt(base .. "\\a.ogg")

local list = music.list()
check("first file plays when none is chosen", list.files == 3 and list.chosen == "a.ogg" and #list.tracks == 1)
setSetting("music_file", "B.mp3")
list = music.list()
check("chosen file plays", list.chosen == "b.MP3" and list.tracks[1].size == 900000 and list.tracks[1].type == "audio/mpeg")
local song = list.tracks[1].path
local first, second = readMusic(song, 0), readMusic(song, music.CHUNK)
check("music read in pieces", #first == math.ceil(music.CHUNK / 3) * 4 and #second > 0 and readMusic(song, 900000) == "")
check("music reads any music file in the folder", readMusic(folder .. "\\a.ogg", 0) == "YWJj")
check("music refuses files outside the folder", readMusic(base .. "\\a.ogg", 0) == "" and readMusic(folder .. "\\..\\a.ogg", 0) == "")
setSetting("music_file", "gone.mp3")
check("missing chosen file falls back to the first", music.list().chosen == "a.ogg")
check("music json", getMusic():match('"chosen":"a.ogg"') ~= nil and getMusic():match('"files":3') ~= nil)

fresh()

-- The Open dialog. Needs someone (or a script) to answer it, so it only runs
-- with COUCH_TEST_DIALOG set to a music file to choose; it ends up copied
-- into the test folder.
local dialog_file = os.getenv("COUCH_TEST_DIALOG")
if dialog_file then
    local chosen = browseMusic()
    print("dialog file: " .. chosen)
    check("dialog returns the chosen file's name", chosen == dialog_file:match("([^\\]+)$"))
    check("dialog file copied in", win32.path_kind(folder .. "\\" .. chosen) == "file")
    check("dialog cancelled", browseMusic() == "")
end
-- Clean up the test folders.
for _, name in ipairs(win32.list_files(folder)) do ffi.C.DeleteFileW(win32.utf16(folder .. "\\" .. name)) end
for _, name in ipairs({ "b.MP3", "a.ogg", "notes.txt" }) do os.remove(base .. "\\" .. name) end
ffi.C.RemoveDirectoryW(win32.utf16(folder))
ffi.C.RemoveDirectoryW(win32.utf16(base))
check("test folders removed", win32.path_kind(base) == nil)
music.set_folder(nil)
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
local front = steamInFront()
print("steam in front: " .. front)
check("steam in front answers", front == "yes" or front == "no")

-- Audio sessions. Lists them; changes nothing unless a test process is given.
local audio = require("audio")
local sessions = audio.sessions()
print("audio sessions: " .. #sessions)
check("unmute with nothing muted", unmuteGame() == 0)
check("process tree has its root", audio.process_tree(4242)[4242] == true)
local fake = {
    { 10, 1, "steam.exe" }, { 11, 10, "steamwebhelper.exe" }, { 12, 11, "steamwebhelper.exe" },
    { 20, 10, "upc.exe" }, { 21, 20, "game.exe" }, { 22, 21, "crashpad.exe" },
    { 30, 10, "brave.exe" }, { 31, 30, "brave.exe" }, { 40, 2, "other.exe" }, { 50, 10, "gameoverlayui64.exe" },
}
local games = audio.steam_games(fake)
check("games are what Steam started", games[20] and games[21] and games[22] and true or false)
check("Steam itself, browsers and others are not games", not (games[10] or games[11] or games[12] or games[30]
    or games[31] or games[40] or games[50]))

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
