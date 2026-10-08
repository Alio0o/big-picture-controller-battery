-- Windows API bindings through LuaJIT FFI. Everything the plugin needs from
-- Windows is declared here, so it is easy to review in one place.
local ffi = require("ffi")

local M = { available = false, reason = nil }

if jit.os ~= "Windows" then
    M.reason = "This plugin only works on Windows."
    return M
end

ffi.cdef [[
    // XInput: controller buttons
    typedef struct {
        uint16_t wButtons;
        uint8_t  bLeftTrigger;
        uint8_t  bRightTrigger;
        int16_t  sThumbLX, sThumbLY, sThumbRX, sThumbRY;
    } BPCB_XINPUT_GAMEPAD;
    typedef struct {
        uint32_t dwPacketNumber;
        BPCB_XINPUT_GAMEPAD Gamepad;
    } BPCB_XINPUT_STATE;
    uint32_t XInputGetState(uint32_t dwUserIndex, BPCB_XINPUT_STATE* pState);

    // Configuration Manager: device list and device properties (battery level)
    typedef struct { uint32_t Data1; uint16_t Data2; uint16_t Data3; uint8_t Data4[8]; } BPCB_GUID;
    typedef struct { BPCB_GUID fmtid; uint32_t pid; } BPCB_DEVPROPKEY;
    uint32_t CM_Get_Device_ID_List_SizeW(uint32_t* pulLen, const uint16_t* pszFilter, uint32_t ulFlags);
    uint32_t CM_Get_Device_ID_ListW(const uint16_t* pszFilter, uint16_t* Buffer, uint32_t BufferLen, uint32_t ulFlags);
    uint32_t CM_Locate_DevNodeW(uint32_t* pdnDevInst, const uint16_t* pDeviceID, uint32_t ulFlags);
    uint32_t CM_Get_DevNode_PropertyW(uint32_t dnDevInst, const BPCB_DEVPROPKEY* PropertyKey,
        uint32_t* PropertyType, uint8_t* PropertyBuffer, uint32_t* PropertyBufferSize, uint32_t ulFlags);

    // Keyboard input for the overlay shortcut
    typedef struct {
        uint16_t  wVk;
        uint16_t  wScan;
        uint32_t  dwFlags;
        uint32_t  time;
        uintptr_t dwExtraInfo;
    } BPCB_KEYBDINPUT;
    typedef struct {
        int32_t   dx;
        int32_t   dy;
        uint32_t  mouseData;
        uint32_t  dwFlags;
        uint32_t  time;
        uintptr_t dwExtraInfo;
    } BPCB_MOUSEINPUT;
    typedef struct {
        uint32_t type;
        union { BPCB_MOUSEINPUT mi; BPCB_KEYBDINPUT ki; } u;
    } BPCB_INPUT;
    uint32_t SendInput(uint32_t cInputs, BPCB_INPUT* pInputs, int32_t cbSize);
    uint32_t MapVirtualKeyW(uint32_t uCode, uint32_t uMapType);

    // Which program is in front
    void*    GetForegroundWindow(void);
    uint32_t GetWindowThreadProcessId(void* hWnd, uint32_t* lpdwProcessId);
    void*    OpenProcess(uint32_t dwDesiredAccess, int32_t bInheritHandle, uint32_t dwProcessId);
    int32_t  QueryFullProcessImageNameW(void* hProcess, uint32_t dwFlags, uint16_t* lpExeName, uint32_t* lpdwSize);
    int32_t  CloseHandle(void* hObject);

    // Time and short waits
    uint64_t GetTickCount64(void);
    void     Sleep(uint32_t dwMilliseconds);
]]

local ok, err = pcall(function()
    M.xinput = ffi.load("xinput1_4")
    M.cfgmgr = ffi.load("cfgmgr32")
    M.user32 = ffi.load("user32")
    M.kernel32 = ffi.C
end)

if not ok then
    M.reason = "Could not load a Windows library: " .. tostring(err)
    return M
end

M.available = true
M.ffi = ffi

-- ASCII string to a NUL-terminated UTF-16 buffer. Device IDs are ASCII.
function M.wide(text)
    local buf = ffi.new("uint16_t[?]", #text + 1)
    for i = 1, #text do buf[i - 1] = text:byte(i) end
    return buf
end

-- UTF-16 buffer to a Lua string. Characters outside ASCII become "?";
-- this is only used for names that are compared and shown.
function M.narrow(buf, count)
    local out = {}
    for i = 0, count - 1 do
        local c = buf[i]
        if c == 0 then break end
        out[#out + 1] = c < 128 and string.char(c) or "?"
    end
    return table.concat(out)
end

function M.now_ms()
    return tonumber(M.kernel32.GetTickCount64())
end

return M
