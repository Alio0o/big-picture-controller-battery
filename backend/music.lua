-- Music files for the Home and Library background music.
--
-- The music setting is a file or a folder. Empty means the default folder,
-- Music\Couch Mode in the user's profile. Steam's UI cannot open local
-- files itself, so the frontend reads the chosen file from here in pieces.
-- Only files from the current list can be read.
local settings = require("settings")

local M = {}

local CHUNK = 512 * 1024
local MAX_SIZE = 64 * 1024 * 1024
local TYPES = {
    mp3 = "audio/mpeg", ogg = "audio/ogg", oga = "audio/ogg", opus = "audio/ogg",
    m4a = "audio/mp4", aac = "audio/aac", wav = "audio/wav", flac = "audio/flac", webm = "audio/webm",
}

local okfs, fs = pcall(require, "fs")
if not okfs or type(fs) ~= "table" then fs = nil end
M.set_fs = function(value) fs = value end

local tracks = {}

function M.default_folder()
    local home = os.getenv("USERPROFILE")
    return home and (home .. "\\Music\\Couch Mode") or nil
end

local function kind(path)
    local ext = path:match("%.([%w]+)$")
    return ext and TYPES[ext:lower()]
end

local function size_of(path)
    local file = io.open(path, "rb")
    if not file then return nil end
    local size = file:seek("end")
    file:close()
    return size
end

local function is_directory(path)
    if fs then
        local ok, dir = pcall(fs.is_directory, path)
        return ok and dir
    end
    return false
end

-- Returns { folder, tracks = { { path, name, size, type } }, error }.
function M.list()
    local setting = settings.get().music_path
    local path = (setting ~= "" and setting or M.default_folder() or ""):gsub('^"(.*)"$', "%1")
    local result = { folder = path, tracks = {} }
    tracks = {}
    local candidates = {}
    if path == "" then
        result.error = "No music file or folder set"
    elseif is_directory(path) then
        local ok, entries = pcall(fs.list, path)
        if ok and type(entries) == "table" then
            for _, entry in ipairs(entries) do
                if entry.is_file then candidates[#candidates + 1] = entry.path end
            end
            table.sort(candidates, function(a, b) return a:lower() < b:lower() end)
        end
    else
        candidates[1] = path
    end

    for _, file in ipairs(candidates) do
        local type_ = kind(file)
        local size = type_ and size_of(file)
        if size and size > 0 and size <= MAX_SIZE then
            tracks[file] = size
            result.tracks[#result.tracks + 1] = {
                path = file, name = file:match("([^\\/]+)$") or file, size = size, type = type_,
            }
        end
    end
    if not result.error and #result.tracks == 0 then
        result.error = #candidates == 0 and ("Nothing found at " .. path)
            or "No playable music there (mp3, ogg, m4a, aac, wav, flac or webm, up to 64 MB)"
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
    local file = io.open(path, "rb")
    if not file then error("cannot open the music file", 0) end
    file:seek("set", offset)
    local data = file:read(CHUNK) or ""
    file:close()
    return base64(data)
end

M.CHUNK = CHUNK

return M
