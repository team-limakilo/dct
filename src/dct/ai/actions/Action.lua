--[[
-- SPDX-License-Identifier: LGPL-3.0
--
-- A simple Action interface.
-- Represents an activity in a mission plan
-- to be completed for mission progression.
--]]

local Observable = require("dct.libs.Observable")
local State = require("dct.libs.State")
local Class = require("libs.namedclass")

local Action = Class("Action", State, Observable)
function Action:__init(--[[tgtasset]])
	self._logger = require("dct.libs.Logger").getByName("Action")
	Observable.__init(self, self._logger)
end

Action.update = nil

-- Perform check for action completion here
-- Examples: target death criteria, F10 command execution, etc
function Action:complete()
	return false
end

--[[
-- The human readable description of the task.
-- This will be presented to the user in the mission briefing.
function Action:getHumanDesc()
end
--]]

return Action
