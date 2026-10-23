-- Mutes a game while the Steam overlay is open.
--
-- Windows keeps a volume and mute switch per program (the Volume mixer).
-- mute(pid) turns on the mute switch of the game's audio sessions, on every
-- playback device, for the game and the processes it started. Steam's own
-- sounds come from steamwebhelper.exe and keep playing.
--
-- Only sessions this module muted are unmuted again. A game the user muted
-- in the Volume mixer stays muted.
local win32 = require("win32")
local logger = require("logger")

local M = {}

local CLSCTX_ALL = 23
local COINIT_MULTITHREADED = 0
local E_RENDER = 0
local DEVICE_STATE_ACTIVE = 1
local TH32CS_SNAPPROCESS = 2
local INVALID_HANDLE = -1

local ids

local function init_ids()
    if ids then return end
    ids = {
        enumerator_class = win32.guid("BCDE0395-E52F-467C-8E3D-C4579291692E"),
        enumerator = win32.guid("A95664D2-9614-4F35-A746-DE8DB63617E6"),
        manager2 = win32.guid("77AA99A0-1BD6-484F-8BC7-2C654C9A9B6F"),
        control2 = win32.guid("BFB7FF88-7239-4FC9-8FA2-07C950BE9C6D"),
        volume = win32.guid("87CE5498-68D6-44E5-9215-6DA47EF883D8"),
    }
end

-- Instance id of each session muted here.
local muted = {}

local function failed(hr) return hr < 0 end

-- Runs fn with COM set up on this thread, and always tidies up.
local function with_com(fn)
    local hr = win32.ole32.CoInitializeEx(nil, COINIT_MULTITHREADED)
    -- A negative result (another threading model) still leaves COM usable.
    local ok, result = pcall(fn)
    if hr >= 0 then win32.ole32.CoUninitialize() end
    if not ok then error(result, 0) end
    return result
end

-- Calls visit(pid, instance_id, volume) for every audio session on every
-- active playback device. The COM objects are released afterwards.
local function each_session(visit)
    local ffi = win32.ffi
    init_ids()
    local out = ffi.new("void*[1]")
    if failed(win32.ole32.CoCreateInstance(ids.enumerator_class, nil, CLSCTX_ALL, ids.enumerator, out)) then
        error("audio devices unavailable", 0)
    end
    local enumerator = ffi.cast("COUCH_IMMDeviceEnumerator*", out[0])
    local collection_out = ffi.new("COUCH_IMMDeviceCollection*[1]")
    local hr = enumerator.lpVtbl.EnumAudioEndpoints(enumerator, E_RENDER, DEVICE_STATE_ACTIVE, collection_out)
    enumerator.lpVtbl.Release(enumerator)
    if failed(hr) then error("audio devices unavailable", 0) end
    local collection = collection_out[0]

    local count = ffi.new("uint32_t[1]")
    collection.lpVtbl.GetCount(collection, count)
    for d = 0, count[0] - 1 do
        local device_out = ffi.new("COUCH_IMMDevice*[1]")
        if not failed(collection.lpVtbl.Item(collection, d, device_out)) then
            local device = device_out[0]
            if not failed(device.lpVtbl.Activate(device, ids.manager2, CLSCTX_ALL, nil, out)) then
                local manager = ffi.cast("COUCH_IAudioSessionManager2*", out[0])
                local list_out = ffi.new("COUCH_IAudioSessionEnumerator*[1]")
                if not failed(manager.lpVtbl.GetSessionEnumerator(manager, list_out)) then
                    local list = list_out[0]
                    local sessions = ffi.new("int32_t[1]")
                    list.lpVtbl.GetCount(list, sessions)
                    for s = 0, sessions[0] - 1 do
                        if not failed(list.lpVtbl.GetSession(list, s, out)) then
                            local session = ffi.cast("COUCH_IAudioSessionControl2*", out[0])
                            local control_out = ffi.new("void*[1]")
                            local volume_out = ffi.new("void*[1]")
                            if not failed(session.lpVtbl.QueryInterface(session, ids.control2, control_out)) then
                                local control = ffi.cast("COUCH_IAudioSessionControl2*", control_out[0])
                                local pid = ffi.new("uint32_t[1]")
                                local text = ffi.new("uint16_t*[1]")
                                control.lpVtbl.GetProcessId(control, pid)
                                local instance = ""
                                if not failed(control.lpVtbl.GetSessionInstanceIdentifier(control, text)) and text[0] ~= nil then
                                    instance = win32.narrow(text[0], 4096)
                                    win32.ole32.CoTaskMemFree(text[0])
                                end
                                if not failed(session.lpVtbl.QueryInterface(session, ids.volume, volume_out)) then
                                    local volume = ffi.cast("COUCH_ISimpleAudioVolume*", volume_out[0])
                                    local ok, err = pcall(visit, pid[0], instance, volume)
                                    volume.lpVtbl.Release(volume)
                                    if not ok then logger:error("Audio session: " .. tostring(err)) end
                                end
                                control.lpVtbl.Release(control)
                            end
                            session.lpVtbl.Release(session)
                        end
                    end
                    list.lpVtbl.Release(list)
                end
                manager.lpVtbl.Release(manager)
            end
            device.lpVtbl.Release(device)
        end
    end
    collection.lpVtbl.Release(collection)
end

-- pid and every process it started, directly or further down.
local function process_tree(root)
    local ffi = win32.ffi
    local tree = { [root] = true }
    local snapshot = win32.kernel32.CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0)
    if snapshot == nil or ffi.cast("intptr_t", snapshot) == INVALID_HANDLE then return tree end
    local entry = ffi.new("COUCH_PROCESSENTRY32W")
    entry.dwSize = ffi.sizeof(entry)
    local parents = {}
    if win32.kernel32.Process32FirstW(snapshot, entry) ~= 0 then
        repeat
            parents[#parents + 1] = { entry.th32ProcessID, entry.th32ParentProcessID }
        until win32.kernel32.Process32NextW(snapshot, entry) == 0
    end
    win32.kernel32.CloseHandle(snapshot)
    -- Keep adding children until nothing new turns up.
    local grew = true
    while grew do
        grew = false
        for _, p in ipairs(parents) do
            if tree[p[2]] and not tree[p[1]] and p[1] ~= p[2] and p[1] ~= 0 then
                tree[p[1]] = true
                grew = true
            end
        end
    end
    return tree
end
M.process_tree = process_tree

-- Mutes the audio of pid and its child processes. Returns a short summary,
-- for example "muted 1 of 1 session(s)".
function M.mute(pid)
    if not win32.available then return "unavailable" end
    pid = tonumber(pid)
    if not pid or pid <= 0 then return "no game" end
    local tree = process_tree(pid)
    local found, newly = 0, 0
    with_com(function()
        each_session(function(session_pid, instance, volume)
            if not tree[session_pid] then return end
            found = found + 1
            if muted[instance] then return end
            local state = win32.ffi.new("int32_t[1]")
            if failed(volume.lpVtbl.GetMute(volume, state)) or state[0] ~= 0 then return end
            if not failed(volume.lpVtbl.SetMute(volume, 1, nil)) then
                muted[instance] = true
                newly = newly + 1
            end
        end)
    end)
    if newly > 0 then logger:info("Muted " .. newly .. " audio session(s) of process " .. pid) end
    return "muted " .. newly .. " of " .. found .. " session(s)"
end

-- Unmutes every session muted by mute(). Returns how many.
function M.unmute()
    if next(muted) == nil then return 0 end
    local count = 0
    if win32.available then
        with_com(function()
            each_session(function(_, instance, volume)
                if muted[instance] then
                    if not failed(volume.lpVtbl.SetMute(volume, 0, nil)) then count = count + 1 end
                end
            end)
        end)
    end
    -- A session that ended while muted is gone; nothing is left to undo.
    muted = {}
    if count > 0 then logger:info("Unmuted " .. count .. " audio session(s)") end
    return count
end

-- Every audio session, for diagnostics: { { pid, muted }, ... }.
function M.sessions()
    local list = {}
    if not win32.available then return list end
    with_com(function()
        each_session(function(pid, _, volume)
            local state = win32.ffi.new("int32_t[1]")
            volume.lpVtbl.GetMute(volume, state)
            list[#list + 1] = { pid = pid, muted = state[0] ~= 0 }
        end)
    end)
    return list
end

return M
