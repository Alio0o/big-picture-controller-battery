-- Windows' own Open dialog, to choose the music file or folder.
--
-- The dialog belongs to the window in front (desktop Steam with the settings
-- page), so it opens on top of it. While it is open, the plugin's backend
-- waits for it; the overlay shortcut pauses until it closes.
local win32 = require("win32")

local M = {}

local CLSCTX_INPROC_SERVER = 1
local COINIT_APARTMENTTHREADED = 2
local FOS_PICKFOLDERS = 0x20
local FOS_FORCEFILESYSTEM = 0x40
local FOS_PATHMUSTEXIST = 0x800
local FOS_FILEMUSTEXIST = 0x1000
local SIGDN_FILESYSPATH = 0x80058000
local ERROR_CANCELLED = -2147023673 -- HRESULT_FROM_WIN32(ERROR_CANCELLED)

M.AUDIO_PATTERN = "*.mp3;*.ogg;*.oga;*.opus;*.m4a;*.aac;*.wav;*.flac;*.webm"

local function shell_item(path)
    if not path or path == "" then return nil end
    local out = win32.ffi.new("void*[1]")
    local hr = win32.shell32.SHCreateItemFromParsingName(win32.utf16(path), nil,
        win32.guid("43826D1E-E718-42EE-BC55-A1E261C37BFE"), out)
    if hr < 0 then return nil end
    return win32.ffi.cast("COUCH_IShellItem*", out[0])
end

-- kind is "file" or "folder"; start is a folder to open in.
-- Returns the chosen path, "" when cancelled, or nil and an error.
function M.choose(kind, start)
    if not win32.available then return nil, win32.reason end
    local ffi = win32.ffi
    local init = win32.ole32.CoInitializeEx(nil, COINIT_APARTMENTTHREADED)
    local ok, result, err = pcall(function()
        local out = ffi.new("void*[1]")
        local hr = win32.ole32.CoCreateInstance(win32.guid("DC1C5A9C-E88A-4DDE-A5A1-60F82A20AEF7"), nil,
            CLSCTX_INPROC_SERVER, win32.guid("D57C7288-D4AD-4768-BE02-9D969532D960"), out)
        if hr < 0 then return nil, string.format("dialog unavailable (0x%08X)", bit.tobit(hr) % 2 ^ 32) end
        local dialog = ffi.cast("COUCH_IFileOpenDialog*", out[0])
        local done, path, problem = pcall(function()
            local options = ffi.new("uint32_t[1]")
            dialog.lpVtbl.GetOptions(dialog, options)
            local wanted = FOS_FORCEFILESYSTEM + FOS_PATHMUSTEXIST
                + (kind == "folder" and FOS_PICKFOLDERS or FOS_FILEMUSTEXIST)
            dialog.lpVtbl.SetOptions(dialog, bit.bor(options[0], wanted))
            local title = win32.utf16(kind == "folder" and "Couch Mode: choose a music folder" or "Couch Mode: choose a music file")
            dialog.lpVtbl.SetTitle(dialog, title)
            local name, spec, filters
            if kind ~= "folder" then
                name, spec = win32.utf16("Music"), win32.utf16(M.AUDIO_PATTERN)
                filters = ffi.new("COUCH_FILTERSPEC[1]")
                filters[0].pszName, filters[0].pszSpec = name, spec
                dialog.lpVtbl.SetFileTypes(dialog, 1, filters)
            end
            local folder = shell_item(start)
            if folder then
                dialog.lpVtbl.SetFolder(dialog, folder)
                folder.lpVtbl.Release(folder)
            end

            local shown = dialog.lpVtbl.Show(dialog, win32.user32.GetForegroundWindow())
            if shown == ERROR_CANCELLED then return "" end
            if shown < 0 then return nil, string.format("dialog failed (0x%08X)", shown % 2 ^ 32) end
            local item_out = ffi.new("COUCH_IShellItem*[1]")
            if dialog.lpVtbl.GetResult(dialog, item_out) < 0 then return nil, "no result" end
            local item = item_out[0]
            local text = ffi.new("uint16_t*[1]")
            local hr2 = item.lpVtbl.GetDisplayName(item, SIGDN_FILESYSPATH, text)
            item.lpVtbl.Release(item)
            if hr2 < 0 then return nil, "not a folder on this PC" end
            local chosen = win32.utf8(text[0])
            win32.ole32.CoTaskMemFree(text[0])
            return chosen
        end)
        dialog.lpVtbl.Release(dialog)
        if not done then error(path, 0) end
        return path, problem
    end)
    if init >= 0 then win32.ole32.CoUninitialize() end
    if not ok then return nil, tostring(result) end
    return result, err
end

return M
