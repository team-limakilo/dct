--[[
-- SPDX-License-Identifier: LGPL-3.0
--
-- A list that shuffles an input list and optionally provides
-- facilities for reading elements in order, and reshuffling after
-- reaching the end.
--
-- Note: the length of the list is cached, so changing any values
-- pertaining to the class is undefined behavior.
--]]

require("math")
local class = require("libs.class")
local utils = require("libs.utils")

local ShuffledList = class()
function ShuffledList:__init(input)
    self.list = utils.shallowclone(input)
    self.length = #self.list
    self:shuffle()
end

function ShuffledList:shuffle()
    for i, _ in ipairs(self.list) do
        local j = math.random(i, self.length - i)
        self.list[i], self.list[j] = self.list[j], self.list[i]
    end
    self.index = 1
end

function ShuffledList:next()
    if self.index <= self.length then
        local value = self.list[self.index]
        self.index = self.index + 1
        return value
    else
        self:shuffle()
        return self.list[self.index]
    end
end

return ShuffledList
