-- Music files for the Home and Library background music.
--
-- The music setting is a file or a folder. Empty means the default folder,
-- "Couch Mode" in the user's Music folder, which is created when the music is
-- turned on. Steam's UI cannot open local files itself, so the frontend reads
-- the chosen file from here in pieces. Only files from the current list can
-- be read. Files and folders go through the Windows API, so names in any
-- language work.
local win32 = require("win32")
local settings = require("settings")

local M = {}

local CHUNK = 512 * 1024
local MAX_SIZE = 64 * 1024 * 1024
local TYPES = {
    mp3 = "audio/mpeg", ogg = "audio/ogg", oga = "audio/ogg", opus = "audio/ogg",
    m4a = "audio/mp4", aac = "audio/aac", wav = "audio/wav", flac = "audio/flac", webm = "audio/webm",
}

local tracks = {}

function M.default_folder()
    local music = win32.available and win32.music_folder()
    if not music then
        local home = os.getenv("USERPROFILE")
        music = home and (home .. "\\Music")
    end
    return music and (music .. "\\Couch Mode") or nil
end

-- Where the Open dialog starts: the folder of the current music, the default
-- folder, or the Music folder, whichever exists first.
function M.start_folder()
    local setting = settings.get().music_path:gsub('^%s*"?(.-)"?%s*$', "%1")
    local candidates = {}
    if setting ~= "" then
        candidates[#candidates + 1] = setting
        candidates[#candidates + 1] = setting:match("^(.*)[\\/][^\\/]*$")
    end
    candidates[#candidates + 1] = M.default_folder()
    candidates[#candidates + 1] = win32.available and win32.music_folder() or nil
    for _, path in ipairs(candidates) do
        if path and win32.available and win32.path_kind(path) == "folder" then return path end
    end
    return nil
end

local function kind(path)
    local ext = path:match("%.([%w]+)$")
    return ext and TYPES[ext:lower()]
end

-- Returns { folder, tracks = { { path, name, size, type } }, error }.
function M.list()
    local config = settings.get()
    local setting = config.music_path:gsub('^%s*"?(.-)"?%s*$', "%1"):gsub("[\\/]+$", "")
    local path = setting ~= "" and setting or M.default_folder() or ""
    local result = { folder = path, tracks = {} }
    tracks = {}
    if path == "" then
        result.error = "No music file or folder set"
        return result
    end
    if not win32.available then
        result.error = win32.reason
        return result
    end

    local what = win32.path_kind(path)
    if not what and setting == "" and config.music then
        win32.create_folder(path)
        what = win32.path_kind(path)
    end
    if not what then
        result.error = (setting == "" and "Put music files in " or "Not found: ") .. path
        return result
    end

    local candidates = {}
    if what == "folder" then
        for _, name in ipairs(win32.list_files(path)) do candidates[#candidates + 1] = path .. "\\" .. name end
        table.sort(candidates, function(a, b) return a:lower() < b:lower() end)
    else
        candidates[1] = path
    end

    local too_big = 0
    for _, file in ipairs(candidates) do
        local type_ = kind(file)
        local size = type_ and win32.file_size(file)
        if size and size > MAX_SIZE then too_big = too_big + 1 end
        if size and size > 0 and size <= MAX_SIZE then
            tracks[file] = size
            result.tracks[#result.tracks + 1] = {
                path = file, name = file:match("([^\\/]+)$") or file, size = size, type = type_,
            }
        end
    end
    if #result.tracks == 0 then
        if #candidates == 0 then
            result.error = "Put music files in " .. path
        elseif too_big > 0 then
            result.error = "The music is bigger than 64 MB per file"
        else
            result.error = "No playable music in " .. path .. " (mp3, ogg, opus, m4a, aac, wav, flac or webm)"
        end
    end
    return result
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

-- Part of a listed file as base64, starting at offset. Empty at the end.
function M.chunk(path, offset)
    local size = tracks[path]
    if not size then error("not a listed music file", 0) end
    offset = tonumber(offset) or 0
    if offset < 0 or offset >= size then return "" end
    local data = win32.read_file(path, offset, math.min(CHUNK, size - offset))
    if not data then error("cannot read the music file", 0) end
    return base64(data)
end

M.CHUNK = CHUNK

return M
