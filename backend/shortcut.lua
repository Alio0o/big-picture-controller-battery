-- Hold a controller button in a game to open the Steam overlay.
--
-- The frontend calls poll() on a short timer while a game is running. Each
-- call reads the controller through XInput; when the button has been held
-- long enough, the overlay key combination from Steam's settings is sent
-- with SendInput, the same way a keyboard press would arrive.
local win32 = require("win32")
local settings = require("settings")
local logger = require("logger")

local M = {}

local BUTTONS = { Menu = 0x0010, View = 0x0020 } -- XINPUT_GAMEPAD_START / _BACK
local ERROR_SUCCESS = 0
local RETRY_EMPTY_SLOT_MS = 2000 -- XInputGetState on an empty slot is slow
local INPUT_KEYBOARD = 1
local KEYEVENTF_KEYUP = 0x0002
local PROCESS_QUERY_LIMITED_INFORMATION = 0x1000

local state, retry_at = nil, { 0, 0, 0, 0 }
local hold = { down = false, done = false, since = 0 }

-- True exactly once per hold. A hold with any other button pressed
-- (for example Menu + View) never fires.
local function hold_step(now, pressed, other, hold_ms)
    if not pressed then
        hold.down, hold.done = false, false
        return false
    end
    if not hold.down then
        hold.down, hold.done, hold.since = true, false, now
    end
    if other then hold.done = true end
    if hold.done or now - hold.since < hold_ms then return false end
    hold.done = true
    return true
end
M.hold_step = hold_step

local function foreground_exe()
    local ffi = win32.ffi
    local window = win32.user32.GetForegroundWindow()
    if window == nil then return nil end
    local pid = ffi.new("uint32_t[1]")
    win32.user32.GetWindowThreadProcessId(window, pid)
    if pid[0] == 0 then return nil end
    local process = win32.kernel32.OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, 0, pid[0])
    if process == nil then return nil end
    local path = ffi.new("uint16_t[1024]")
    local size = ffi.new("uint32_t[1]", 1024)
    local ok = win32.kernel32.QueryFullProcessImageNameW(process, 0, path, size)
    win32.kernel32.CloseHandle(process)
    if ok == 0 then return nil end
    return (win32.narrow(path, size[0]):match("([^\\]+)$") or ""):lower()
end

-- In Big Picture itself (no game in front) the key combination would only
-- move the focus around, so it is not sent there.
local function steam_in_front()
    local exe = foreground_exe()
    return exe == "steam.exe" or exe == "steamwebhelper.exe"
end

local function key_event(input, vk, up)
    input.type = INPUT_KEYBOARD
    input.u.ki.wVk = vk
    input.u.ki.wScan = win32.user32.MapVirtualKeyW(vk, 0)
    input.u.ki.dwFlags = up and KEYEVENTF_KEYUP or 0
end

-- Press the keys in order, hold briefly so the overlay notices, then release
-- in reverse order. The release always runs, so a key can never stay down.
local function send_keys(keys)
    local ffi = win32.ffi
    local input = ffi.new("BPCB_INPUT[1]")
    local size = ffi.sizeof("BPCB_INPUT")
    local sent = 0
    local ok, err = pcall(function()
        for i = 1, #keys do
            key_event(input[0], keys[i], false)
            sent = sent + win32.user32.SendInput(1, input, size)
            win32.kernel32.Sleep(15)
        end
        win32.kernel32.Sleep(60)
    end)
    for i = #keys, 1, -1 do
        key_event(input[0], keys[i], true)
        sent = sent + win32.user32.SendInput(1, input, size)
    end
    if not ok then logger:error("Sending keys failed: " .. tostring(err)) end
    return sent
end

local function fire(config)
    if steam_in_front() then
        return "skipped: Steam itself is in front"
    end
    local keys = settings.parse_keys(config.keys)
    local sent = send_keys(keys)
    if sent == #keys * 2 then
        logger:info("Overlay shortcut sent: " .. config.keys)
        return "sent"
    end
    -- Windows drops simulated keys aimed at programs running as administrator.
    logger:warn("Overlay shortcut blocked by Windows (" .. sent .. " of " .. (#keys * 2) .. " key events)")
    return "blocked"
end

-- Returns "off", "idle" (no controller), "ok", or the result of a fired shortcut.
function M.poll()
    local config = settings.get()
    if not config.overlay_shortcut then return "off" end
    if not win32.available then return "off" end

    state = state or win32.ffi.new("BPCB_XINPUT_STATE")
    local now = win32.now_ms()
    local button = BUTTONS[config.button] or BUTTONS.Menu
    local connected, pressed, other = false, false, false

    -- Steam can add a virtual pad next to the real one, so all four slots
    -- count as one logical button.
    for slot = 0, 3 do
        if now >= retry_at[slot + 1] then
            if win32.xinput.XInputGetState(slot, state) == ERROR_SUCCESS then
                connected = true
                local buttons = state.Gamepad.wButtons
                if bit.band(buttons, button) ~= 0 then pressed = true end
                if bit.band(buttons, bit.bnot(button)) ~= 0 then other = true end
            else
                retry_at[slot + 1] = now + RETRY_EMPTY_SLOT_MS
            end
        end
    end

    if not connected then
        hold_step(now, false, false, config.hold_ms)
        return "idle"
    end
    if hold_step(now, pressed, other, config.hold_ms) then
        return fire(config)
    end
    return "ok"
end

return M
