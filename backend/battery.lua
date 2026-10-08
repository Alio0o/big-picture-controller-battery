-- Reads the controller battery level that Windows already keeps for paired
-- Bluetooth LE devices (the same number Windows Settings shows). Nothing is
-- sent to the controller; this only reads a device property.
local win32 = require("win32")

local M = {}

local CR_SUCCESS = 0
local CM_GETIDLIST_FILTER_ENUMERATOR = 0x00000001
local CM_GETIDLIST_FILTER_PRESENT = 0x00000100

local keys

local function make_key(d1, d2, d3, bytes, pid)
    local key = win32.ffi.new("BPCB_DEVPROPKEY")
    key.fmtid.Data1, key.fmtid.Data2, key.fmtid.Data3 = d1, d2, d3
    for i = 1, 8 do key.fmtid.Data4[i - 1] = bytes[i] end
    key.pid = pid
    return key
end

local function init_keys()
    if keys then return end
    keys = {
        -- DEVPKEY_NAME
        name = make_key(0xB725F130, 0x47EF, 0x101A, { 0xA5, 0xF1, 0x02, 0x60, 0x8C, 0x9E, 0xEB, 0xAC }, 10),
        -- Bluetooth battery level, 0-100 (DEVPKEY_Bluetooth_Battery)
        battery = make_key(0x104EA319, 0x6EE2, 0x4701, { 0xBD, 0x47, 0x8D, 0xDB, 0xF4, 0x25, 0xBB, 0xE5 }, 2),
        -- Whether the device is connected right now (DEVPKEY_Device_IsConnected)
        connected = make_key(0x83DA6326, 0x97A6, 0x4088, { 0x94, 0x53, 0xA1, 0x92, 0x3F, 0x57, 0x3B, 0x29 }, 15),
    }
end

local buffer = nil
local function read_property(devinst, key)
    local ffi = win32.ffi
    buffer = buffer or ffi.new("uint8_t[512]")
    local prop_type = ffi.new("uint32_t[1]")
    local size = ffi.new("uint32_t[1]", 512)
    if win32.cfgmgr.CM_Get_DevNode_PropertyW(devinst, key, prop_type, buffer, size, 0) ~= CR_SUCCESS then
        return nil
    end
    return buffer, size[0]
end

local function device_ids()
    local ffi, cfgmgr = win32.ffi, win32.cfgmgr
    local filter = win32.wide("BTHLE")
    local flags = CM_GETIDLIST_FILTER_ENUMERATOR + CM_GETIDLIST_FILTER_PRESENT
    local length = ffi.new("uint32_t[1]")
    if cfgmgr.CM_Get_Device_ID_List_SizeW(length, filter, flags) ~= CR_SUCCESS then return {} end
    local list = ffi.new("uint16_t[?]", length[0] + 1)
    if cfgmgr.CM_Get_Device_ID_ListW(filter, list, length[0], flags) ~= CR_SUCCESS then return {} end

    -- The list is NUL-separated and ends with an empty string.
    local ids, i = {}, 0
    while i < length[0] and list[i] ~= 0 do
        local start = i
        while list[i] ~= 0 do i = i + 1 end
        ids[#ids + 1] = win32.narrow(list + start, i - start)
        i = i + 1
    end
    return ids
end

local function is_controller(name)
    local lower = name:lower()
    return lower:find("controller", 1, true) ~= nil or lower:find("gamepad", 1, true) ~= nil
end

-- Returns { status = "connected" | "disconnected" | "unavailable", percent, name, message }
function M.read()
    if not win32.available then
        return { status = "unavailable", message = win32.reason }
    end
    init_keys()

    local ffi = win32.ffi
    local found_paired = nil
    for _, id in ipairs(device_ids()) do
        local devinst = ffi.new("uint32_t[1]")
        if win32.cfgmgr.CM_Locate_DevNodeW(devinst, win32.wide(id), 0) == CR_SUCCESS then
            local name_buf, name_size = read_property(devinst[0], keys.name)
            local name = name_buf and win32.narrow(ffi.cast("uint16_t*", name_buf), name_size / 2) or ""
            if is_controller(name) then
                local battery = read_property(devinst[0], keys.battery)
                local percent = battery and battery[0] or nil
                local connected_buf = read_property(devinst[0], keys.connected)
                -- If Windows does not report the connection state, assume connected.
                local connected = connected_buf == nil or connected_buf[0] ~= 0
                if connected and percent and percent <= 100 then
                    return { status = "connected", percent = percent, name = name }
                end
                found_paired = found_paired or name
            end
        end
    end

    if found_paired then
        return { status = "disconnected", name = found_paired }
    end
    return { status = "disconnected", message = "No paired Bluetooth controller with a battery level" }
end

return M
