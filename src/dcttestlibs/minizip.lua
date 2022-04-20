--[[
-- SPDX-License-Identifier: LGPL-3.0
--
-- Wrapper for lua-zip that implements a subset of ED's lua-minizip library
--]]
local zip = require("zip")

local minizip = {}

function minizip.unzOpen(path)
    local zipFile, err = zip.open(path)
    if err ~= nil then
        return nil, err
    end
    local curFile = nil
    local curPath = nil
    return {
        zipFile = zipFile,
        curFile = curFile,
        curPath = curPath,
        unzLocateFile = function(self, name)
            self.curFile, err = self.zipFile:open(name)
            if err ~= nil then
                return nil, err
            end
            self.curPath = name
            return self.curFile
        end,
        unzReadAllCurrentFile = function(self)
            assert(self.curFile, "no file in memory")
            assert(self.curFile:seek("set", 0))
            return self.curFile:read("*a")
        end,
        unzGetCurrentFileName = function(self)
            return self.curPath
        end,
        unzClose = function(self)
            return self.zipFile:close()
        end,
    }
end

return minizip
