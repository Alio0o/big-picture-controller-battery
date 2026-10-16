-- Xbox mode controller access.
--
-- In Windows' Xbox mode (full screen experience), programs in the background
-- get a blank controller unless GameInput lists them as allowed to read input
-- in the background. Steam is listed; Millennium's plugin host is not, so the
-- overlay shortcut sees no button presses there.
--
-- The per-program setting lives in
--   HKLM\SOFTWARE\Microsoft\GameInputRedist\Exe\<program>  BackgroundInput = 1
-- Reading it needs no rights. Changing it needs administrator rights once, so
-- enable() and disable() start reg.exe through Windows' own elevation prompt.
local win32 = require("win32")

local M = {}

local REDIST_KEY = "SOFTWARE\\Microsoft\\GameInputRedist"
local VALUE = "BackgroundInput"
local RRF_RT_DWORD = 0x00000018
local RRF_SUBKEY_WOW6464KEY = 0x00010000
local ERROR_SUCCESS = 0
local SW_HIDE = 0

local function hklm()
    -- HKEY_LOCAL_MACHINE is (HKEY)(LONG)0x80000002, sign-extended on 64-bit.
    return win32.ffi.cast("void*", win32.ffi.cast("intptr_t", -2147483646))
end

-- File name of the program this backend runs in, e.g. "millennium.luavm64.exe".
local function host_exe()
    local buf = win32.ffi.new("uint16_t[1024]")
    local n = win32.kernel32.GetModuleFileNameW(nil, buf, 1024)
    if n == 0 then return nil end
    return win32.narrow(buf, n):match("([^\\]+)$")
end
M.host_exe = host_exe

-- "on" or "off".
function M.status()
    if not win32.available then return "off" end
    local exe = host_exe()
    if not exe then return "off" end
    local data = win32.ffi.new("uint32_t[1]", 0)
    local size = win32.ffi.new("uint32_t[1]", 4)
    local r = win32.advapi32.RegGetValueW(hklm(), win32.wide(REDIST_KEY .. "\\Exe\\" .. exe), win32.wide(VALUE),
        bit.bor(RRF_RT_DWORD, RRF_SUBKEY_WOW6464KEY), nil, data, size)
    return (r == ERROR_SUCCESS and data[0] == 1) and "on" or "off"
end

-- Starts reg.exe with an elevation prompt. Returns "started", or "cancelled"
-- when the prompt was declined. reg.exe runs on its own; call status() again
-- a moment later to see the result.
local function run_reg(args)
    local r = win32.shell32.ShellExecuteW(nil, win32.wide("runas"), win32.wide("reg.exe"),
        win32.wide(args), nil, SW_HIDE)
    return tonumber(r) > 32 and "started" or "cancelled"
end

function M.enable()
    local exe = host_exe()
    if not exe then return "error" end
    return run_reg(string.format('add "HKLM\\%s\\Exe\\%s" /v %s /t REG_DWORD /d 1 /f', REDIST_KEY, exe, VALUE))
end

function M.disable()
    local exe = host_exe()
    if not exe then return "error" end
    return run_reg(string.format('delete "HKLM\\%s\\Exe\\%s" /f', REDIST_KEY, exe))
end

return M
