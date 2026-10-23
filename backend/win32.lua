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
    } COUCH_XINPUT_GAMEPAD;
    typedef struct {
        uint32_t dwPacketNumber;
        COUCH_XINPUT_GAMEPAD Gamepad;
    } COUCH_XINPUT_STATE;
    uint32_t XInputGetState(uint32_t dwUserIndex, COUCH_XINPUT_STATE* pState);

    // Configuration Manager: device list and device properties (battery level)
    typedef struct { uint32_t Data1; uint16_t Data2; uint16_t Data3; uint8_t Data4[8]; } COUCH_GUID;
    typedef struct { COUCH_GUID fmtid; uint32_t pid; } COUCH_DEVPROPKEY;
    uint32_t CM_Get_Device_ID_List_SizeW(uint32_t* pulLen, const uint16_t* pszFilter, uint32_t ulFlags);
    uint32_t CM_Get_Device_ID_ListW(const uint16_t* pszFilter, uint16_t* Buffer, uint32_t BufferLen, uint32_t ulFlags);
    uint32_t CM_Locate_DevNodeW(uint32_t* pdnDevInst, const uint16_t* pDeviceID, uint32_t ulFlags);
    uint32_t CM_Get_DevNode_PropertyW(uint32_t dnDevInst, const COUCH_DEVPROPKEY* PropertyKey,
        uint32_t* PropertyType, uint8_t* PropertyBuffer, uint32_t* PropertyBufferSize, uint32_t ulFlags);

    // Keyboard input for the overlay shortcut
    typedef struct {
        uint16_t  wVk;
        uint16_t  wScan;
        uint32_t  dwFlags;
        uint32_t  time;
        uintptr_t dwExtraInfo;
    } COUCH_KEYBDINPUT;
    typedef struct {
        int32_t   dx;
        int32_t   dy;
        uint32_t  mouseData;
        uint32_t  dwFlags;
        uint32_t  time;
        uintptr_t dwExtraInfo;
    } COUCH_MOUSEINPUT;
    typedef struct {
        uint32_t type;
        union { COUCH_MOUSEINPUT mi; COUCH_KEYBDINPUT ki; } u;
    } COUCH_INPUT;
    uint32_t SendInput(uint32_t cInputs, COUCH_INPUT* pInputs, int32_t cbSize);
    uint32_t MapVirtualKeyW(uint32_t uCode, uint32_t uMapType);

    // Which program is in front
    void*    GetForegroundWindow(void);
    uint32_t GetWindowThreadProcessId(void* hWnd, uint32_t* lpdwProcessId);
    void*    OpenProcess(uint32_t dwDesiredAccess, int32_t bInheritHandle, uint32_t dwProcessId);
    int32_t  QueryFullProcessImageNameW(void* hProcess, uint32_t dwFlags, uint16_t* lpExeName, uint32_t* lpdwSize);
    int32_t  CloseHandle(void* hObject);

    // Xbox mode controller access (see access.lua)
    int32_t  RegGetValueW(void* hkey, const uint16_t* lpSubKey, const uint16_t* lpValue, uint32_t dwFlags,
        uint32_t* pdwType, void* pvData, uint32_t* pcbData);
    uint32_t GetModuleFileNameW(void* hModule, uint16_t* lpFilename, uint32_t nSize);
    intptr_t ShellExecuteW(void* hwnd, const uint16_t* lpOperation, const uint16_t* lpFile,
        const uint16_t* lpParameters, const uint16_t* lpDirectory, int32_t nShowCmd);

    // Time and short waits
    uint64_t GetTickCount64(void);
    void     Sleep(uint32_t dwMilliseconds);

    // Process list, to find a game's child processes (see audio.lua)
    typedef struct {
        uint32_t  dwSize;
        uint32_t  cntUsage;
        uint32_t  th32ProcessID;
        uintptr_t th32DefaultHeapID;
        uint32_t  th32ModuleID;
        uint32_t  cntThreads;
        uint32_t  th32ParentProcessID;
        int32_t   pcPriClassBase;
        uint32_t  dwFlags;
        uint16_t  szExeFile[260];
    } COUCH_PROCESSENTRY32W;
    void*    CreateToolhelp32Snapshot(uint32_t dwFlags, uint32_t th32ProcessID);
    int32_t  Process32FirstW(void* hSnapshot, COUCH_PROCESSENTRY32W* lppe);
    int32_t  Process32NextW(void* hSnapshot, COUCH_PROCESSENTRY32W* lppe);

    // COM, for Windows' per-program volume (see audio.lua). Only the methods
    // that are called are typed; the others keep their place in the table.
    int32_t  CoInitializeEx(void* pvReserved, uint32_t dwCoInit);
    void     CoUninitialize(void);
    int32_t  CoCreateInstance(const COUCH_GUID* rclsid, void* pUnkOuter, uint32_t dwClsContext,
        const COUCH_GUID* riid, void** ppv);
    void     CoTaskMemFree(void* pv);

    typedef struct COUCH_IMMDeviceEnumerator COUCH_IMMDeviceEnumerator;
    typedef struct COUCH_IMMDeviceCollection COUCH_IMMDeviceCollection;
    typedef struct COUCH_IMMDevice COUCH_IMMDevice;
    typedef struct COUCH_IAudioSessionManager2 COUCH_IAudioSessionManager2;
    typedef struct COUCH_IAudioSessionEnumerator COUCH_IAudioSessionEnumerator;
    typedef struct COUCH_IAudioSessionControl2 COUCH_IAudioSessionControl2;
    typedef struct COUCH_ISimpleAudioVolume COUCH_ISimpleAudioVolume;

    typedef struct {
        void*    QueryInterface;
        void*    AddRef;
        uint32_t (*Release)(COUCH_IMMDeviceEnumerator*);
        int32_t  (*EnumAudioEndpoints)(COUCH_IMMDeviceEnumerator*, int32_t dataFlow, uint32_t dwStateMask,
            COUCH_IMMDeviceCollection** ppDevices);
    } COUCH_IMMDeviceEnumeratorVtbl;
    struct COUCH_IMMDeviceEnumerator { COUCH_IMMDeviceEnumeratorVtbl* lpVtbl; };

    typedef struct {
        void*    QueryInterface;
        void*    AddRef;
        uint32_t (*Release)(COUCH_IMMDeviceCollection*);
        int32_t  (*GetCount)(COUCH_IMMDeviceCollection*, uint32_t* pcDevices);
        int32_t  (*Item)(COUCH_IMMDeviceCollection*, uint32_t nDevice, COUCH_IMMDevice** ppDevice);
    } COUCH_IMMDeviceCollectionVtbl;
    struct COUCH_IMMDeviceCollection { COUCH_IMMDeviceCollectionVtbl* lpVtbl; };

    typedef struct {
        void*    QueryInterface;
        void*    AddRef;
        uint32_t (*Release)(COUCH_IMMDevice*);
        int32_t  (*Activate)(COUCH_IMMDevice*, const COUCH_GUID* iid, uint32_t dwClsCtx, void* pActivationParams,
            void** ppInterface);
    } COUCH_IMMDeviceVtbl;
    struct COUCH_IMMDevice { COUCH_IMMDeviceVtbl* lpVtbl; };

    typedef struct {
        void*    QueryInterface;
        void*    AddRef;
        uint32_t (*Release)(COUCH_IAudioSessionManager2*);
        void*    GetAudioSessionControl;
        void*    GetSimpleAudioVolume;
        int32_t  (*GetSessionEnumerator)(COUCH_IAudioSessionManager2*, COUCH_IAudioSessionEnumerator** ppEnum);
    } COUCH_IAudioSessionManager2Vtbl;
    struct COUCH_IAudioSessionManager2 { COUCH_IAudioSessionManager2Vtbl* lpVtbl; };

    typedef struct {
        void*    QueryInterface;
        void*    AddRef;
        uint32_t (*Release)(COUCH_IAudioSessionEnumerator*);
        int32_t  (*GetCount)(COUCH_IAudioSessionEnumerator*, int32_t* SessionCount);
        int32_t  (*GetSession)(COUCH_IAudioSessionEnumerator*, int32_t SessionCount, void** Session);
    } COUCH_IAudioSessionEnumeratorVtbl;
    struct COUCH_IAudioSessionEnumerator { COUCH_IAudioSessionEnumeratorVtbl* lpVtbl; };

    // IAudioSessionControl2 (it starts with all of IAudioSessionControl).
    typedef struct {
        int32_t  (*QueryInterface)(COUCH_IAudioSessionControl2*, const COUCH_GUID* riid, void** ppv);
        void*    AddRef;
        uint32_t (*Release)(COUCH_IAudioSessionControl2*);
        int32_t  (*GetState)(COUCH_IAudioSessionControl2*, int32_t* pRetVal);
        void*    GetDisplayName;
        void*    SetDisplayName;
        void*    GetIconPath;
        void*    SetIconPath;
        void*    GetGroupingParam;
        void*    SetGroupingParam;
        void*    RegisterAudioSessionNotification;
        void*    UnregisterAudioSessionNotification;
        void*    GetSessionIdentifier;
        int32_t  (*GetSessionInstanceIdentifier)(COUCH_IAudioSessionControl2*, uint16_t** pRetVal);
        int32_t  (*GetProcessId)(COUCH_IAudioSessionControl2*, uint32_t* pRetVal);
    } COUCH_IAudioSessionControl2Vtbl;
    struct COUCH_IAudioSessionControl2 { COUCH_IAudioSessionControl2Vtbl* lpVtbl; };

    typedef struct {
        void*    QueryInterface;
        void*    AddRef;
        uint32_t (*Release)(COUCH_ISimpleAudioVolume*);
        void*    SetMasterVolume;
        void*    GetMasterVolume;
        int32_t  (*SetMute)(COUCH_ISimpleAudioVolume*, int32_t bMute, const COUCH_GUID* EventContext);
        int32_t  (*GetMute)(COUCH_ISimpleAudioVolume*, int32_t* pbMute);
    } COUCH_ISimpleAudioVolumeVtbl;
    struct COUCH_ISimpleAudioVolume { COUCH_ISimpleAudioVolumeVtbl* lpVtbl; };
]]

local ok, err = pcall(function()
    M.xinput = ffi.load("xinput1_4")
    M.cfgmgr = ffi.load("cfgmgr32")
    M.user32 = ffi.load("user32")
    M.advapi32 = ffi.load("advapi32")
    M.shell32 = ffi.load("shell32")
    M.ole32 = ffi.load("ole32")
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

-- "BCDE0395-E52F-467C-8E3D-C4579291692E" to a GUID.
function M.guid(text)
    local hex = text:gsub("-", "")
    local g = ffi.new("COUCH_GUID")
    g.Data1 = tonumber(hex:sub(1, 8), 16)
    g.Data2 = tonumber(hex:sub(9, 12), 16)
    g.Data3 = tonumber(hex:sub(13, 16), 16)
    for i = 0, 7 do g.Data4[i] = tonumber(hex:sub(17 + i * 2, 18 + i * 2), 16) end
    return g
end

function M.now_ms()
    return tonumber(M.kernel32.GetTickCount64())
end

return M
