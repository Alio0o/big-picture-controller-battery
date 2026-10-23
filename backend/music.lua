-- Music files for the background music.
--
-- The music lives in one folder: "Couch Mode" in the user's Music folder
-- (wherever Windows keeps it), created when the plugin starts. The music
-- setting is the name of one file in it; without one, the first file in the
-- folder plays. Steam's UI cannot open local files itself, so the frontend
-- reads the file from here in pieces. Only music files in the folder can be read.
-- Files go through the Windows API, so names in any language work.
local win32 = require("win32")
local settings = require("settings")

local M = {}

local CHUNK = 512 * 1024
local MAX_SIZE = 64 * 1024 * 1024
local TYPES = {
    mp3 = "audio/mpeg", ogg = "audio/ogg", oga = "audio/ogg", opus = "audio/ogg",
    m4a = "audio/mp4", aac = "audio/aac", wav = "audio/wav", flac = "audio/flac", webm = "audio/webm",
}

local folder_override = nil -- for tools/check-backend.lua

function M.folder()
    if folder_override then return folder_override end
    local music = win32.available and win32.music_folder()
    if not music then
        local home = os.getenv("USERPROFILE")
        music = home and (home .. "\\Music")
    end
    return music and (music .. "\\Couch Mode") or nil
end

function M.set_folder(path) folder_override = path end

-- Creates the music folder if it is missing. Returns the folder or nil.
function M.ensure_folder()
    local folder = M.folder()
    if not folder or not win32.available then return nil end
    if win32.path_kind(folder) ~= "folder" then win32.create_folder(folder) end
    return win32.path_kind(folder) == "folder" and folder or nil
end

local function kind(path)
    local ext = path:match("%.([%w]+)$")
    return ext and TYPES[ext:lower()]
end
M.kind = kind

-- Playable files in the folder, in name order: { { name, size, type } }.
local function playable(folder)
    local files, too_big = {}, 0
    local names = win32.list_files(folder)
    table.sort(names, function(a, b) return a:lower() < b:lower() end)
    for _, name in ipairs(names) do
        local type_ = kind(name)
        local size = type_ and win32.file_size(folder .. "\\" .. name)
        if size and size > MAX_SIZE then too_big = too_big + 1 end
        if size and size > 0 and size <= MAX_SIZE then
            files[#files + 1] = { name = name, size = size, type = type_ }
        end
    end
    return files, too_big
end

-- Returns { folder, files, chosen, tracks = { { path, name, size, type } }, error }.
-- tracks holds the one file that plays.
function M.list()
    local result = { folder = M.folder() or "", tracks = {}, files = 0, chosen = "" }
    if not win32.available then
        result.error = win32.reason
        return result
    end
    local folder = M.ensure_folder()
    if not folder then
        result.error = "Could not create " .. result.folder
        return result
    end
    local files, too_big = playable(folder)
    result.files = #files
    local wanted = settings.get().music_file
    local pick = files[1]
    for _, file in ipairs(files) do
        if wanted ~= "" and file.name:lower() == wanted:lower() then pick = file end
    end
    if not pick then
        result.error = too_big > 0 and "The music is bigger than 64 MB per file" or ("Put music files in " .. folder)
        return result
    end
    local path = folder .. "\\" .. pick.name
    result.chosen = pick.name
    result.tracks[1] = { path = path, name = pick.name, size = pick.size, type = pick.type }
    return result
end

-- Takes a file chosen in the Open dialog. A file from elsewhere is copied
-- into the folder. Returns its name in the folder, or nil and a message.
function M.adopt(path)
    local folder = M.ensure_folder()
    if not folder then return nil, "The music folder is missing" end
    local name = path:match("([^\\/]+)$")
    if not name or not kind(name) then return nil, "Not a music file (mp3, ogg, opus, m4a, aac, wav, flac or webm)" end
    local parent = path:sub(1, #path - #name - 1)
    if parent:lower() == folder:lower() then return name end
    local size = win32.file_size(path)
    if not size or size > MAX_SIZE then return nil, "The music is bigger than 64 MB" end
    -- Keep a file of the same name that is already there.
    local stem, ext = name:match("^(.*)(%.[^.]+)$")
    local target, n = name, 1
    while win32.path_kind(folder .. "\\" .. target) do
        n = n + 1
        target = stem .. " (" .. n .. ")" .. ext
    end
    if not win32.copy_file(path, folder .. "\\" .. target) then return nil, "Could not copy the file into " .. folder end
    return target
end

local ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local SYMBOL = {}
for i = 1, 64 do SYMBOL[i - 1] = ALPHABET:sub(i, i) end

local function base64(data)
    local out, n = {}, 0
    for i = 1, #data, 3 do
        local a, b, c = data:byte(i, i + 2)
        local v = a * 65536 + (b or 0) * 256 + (c or 0)
        n = n + 1
        out[n] = SYMBOL[bit.rshift(v, 18)] .. SYMBOL[bit.band(bit.rshift(v, 12), 63)]
            .. (b and SYMBOL[bit.band(bit.rshift(v, 6), 63)] or "=")
            .. (c and SYMBOL[bit.band(v, 63)] or "=")
    end
    return table.concat(out)
end
M.base64 = base64

-- Part of a music file as base64, starting at offset. Empty at the end.
-- Any music file directly in the music folder can be read, nothing else. This
-- does not depend on the last list(), so the settings page listing the
-- folder never breaks a read that is under way.
function M.chunk(path, offset)
    local folder = M.folder()
    local name = path:match("([^\\/]+)$")
    if not folder or not name or path:sub(1, #path - #name - 1):lower() ~= folder:lower() or not kind(name) then
        error("not a music file in " .. tostring(folder), 0)
    end
    local size = win32.file_size(path)
    if not size or size > MAX_SIZE then error("cannot read the music file", 0) end
    offset = tonumber(offset) or 0
    if offset < 0 or offset >= size then return "" end
    local data = win32.read_file(path, offset, math.min(CHUNK, size - offset))
    if not data then error("cannot read the music file", 0) end
    return base64(data)
end
M.CHUNK = CHUNK

return M
