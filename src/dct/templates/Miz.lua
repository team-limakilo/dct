--[[
-- SPDX-License-Identifier: LGPL-3.0
--
-- Handles reading groups and other information from a packed
-- Miz file into a Template-compatible structure.
--]]

local minizip = require("minizip")

local Miz = {}

local function readFileFromZip(zip, path)
    assert(zip:unzLocateFile(path))
    return assert(zip:unzReadAllCurrentFile())
end

local function readLuaFromZip(zip, path, root)
    local lua = readFileFromZip(zip, path)
    local chunk = assert(loadstring(lua))
    local env = {}
    setfenv(chunk, env)
    chunk()
    return env[root]
end

function Miz.read(path)
    local zip = assert(minizip.unzOpen(path))
    return {
        mission    = readLuaFromZip(zip, "mission", "mission"),
        options    = readLuaFromZip(zip, "options", "options"),
        theatre    = readFileFromZip(zip, "theatre"),
        warehouses = readLuaFromZip(zip, "warehouses", "warehouses"),
        l18n = {
            DEFAULT = {
                dictionary  = readLuaFromZip(zip,
                    "l10n/DEFAULT/dictionary", "dictionary"),
                mapResource = readLuaFromZip(zip,
                    "l10n/DEFAULT/mapResource", "mapResource"),
            }
        }
    }
end

return Miz
