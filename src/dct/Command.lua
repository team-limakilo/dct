--[[
-- SPDX-License-Identifier: LGPL-3.0
--
-- Provides a basic Command class to call an arbitrary function
-- at a later time via the Command's execute function.
--]]

local class = require("libs.namedclass")
local utils = require("libs.utils")
local check = require("libs.check")
local Logger= dct.Logger.getByName("Command")

-- lower value is higher priority; total of 127 priority values
local cmdpriority = {
	["UI"]     = 10,
	["NORMAL"] = 64,
}

local Command = class("Command")
function Command:__init(name, func, ...)
	self.name = check.string(name)
	self.func = check.func(func)
	self.prio = cmdpriority.NORMAL
	self.args = {select(1, ...)}
	self.done = false
	self.PRIORITY = nil
end

function Command:execute(time)
	Logger:debug("executing: %s", self.name)
	local args = utils.shallowclone(self.args)
	table.insert(args, time)
	self.done = true
	return self.func(unpack(args))
end

function Command:isDone()
	return self.done
end

Command.PRIORITY = cmdpriority


if dct.settings and dct.settings.server and
   dct.settings.server.profile == true then
	require("os")
	local TimedCommand = class("TimedCommand", Command)
	function TimedCommand:execute(time)
		local tstart = os.clock()
		local rc = { Command.execute(self, time) }
		Logger:info("'%s' exec time: %5.2fms", self.name, (os.clock()-tstart)*1000)
		return unpack(rc)
	end
	TimedCommand.PRIORITY = cmdpriority

	return TimedCommand
end

return Command
