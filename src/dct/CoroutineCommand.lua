--[[
-- SPDX-License-Identifier: LGPL-3.0
--
-- Enhances Command with the ability to run coroutines for pausable execution.
--
-- CoroutineCommand:execute() returns nil until the coroutine is finished
--]]

local class   = require("libs.namedclass")
local utils   = require("libs.utils")
local Command = require("dct.Command")
local Logger  = dct.Logger.getByName("CoroutineCommand")

local CoroutineCommand = class("CoroutineCommand", Command)
function CoroutineCommand:__init(name, func, ...)
    Command.__init(self, name, func, ...)
    self.originalArgs = self.args
end

function CoroutineCommand:execute(time)
	if self.done or self.coroutine == nil then
        Logger:debug("executing: %s", self.name)
        self.coroutine = coroutine.create(self.func)
        self.args = self.originalArgs
    else
        Logger:debug("resuming: %s", self.name)
    end

    local args = utils.shallowclone(self.args)
	table.insert(args, time)

    local rc = { coroutine.resume(self.coroutine, unpack(args)) }
    self.done = coroutine.status(self.coroutine) == "dead"

    -- bubble up coroutine errors
    if rc[1] == false then
        self.done = true
        error(select(2, unpack(rc)))
    end

    -- clear args so next run only gets sent current time
    self.args = {}

    if self.done then
        return select(2, unpack(rc))
	end
end


if dct.settings and dct.settings.server and
   dct.settings.server.profile == true then
	require("os")
	local TimedCommand = class("TimedCoroutineCommand", CoroutineCommand)
	function TimedCommand:execute(time)
		local tstart = os.clock()
		local rc = { CoroutineCommand.execute(self, time) }
		Logger:info("'%s' exec time: %5.2fms", self.name, (os.clock()-tstart)*1000)
		return unpack(rc)
	end

    return TimedCommand
end

return CoroutineCommand
