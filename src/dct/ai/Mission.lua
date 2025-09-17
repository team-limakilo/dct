--[[
-- SPDX-License-Identifier: LGPL-3.0
--
-- Represents a Mission within the game and this associates an
-- Objective to as assigned group of units responsible for
-- completing the Objective.
--]]

-- TODO:
--  * have a joinable flag in the mission class only let
--    assets join when the flag is true

require("os")
require("math")
local utils    = require("libs.utils")
local class    = require("libs.namedclass")
local enum     = require("dct.enum")
local dctutils = require("dct.utils")
local uicmds   = require("dct.ui.cmds")
local State    = require("dct.libs.State")
local Timer    = require("dct.libs.Timer")
local Logger   = require("dct.libs.Logger").getByName("Mission")

local MISSION_LIMIT = 60*60*3  -- 3 hours in seconds
local PREP_LIMIT    = 60*90    -- 90 minutes in seconds


---------------- STATES ----------------

local BaseMissionState = class("BaseMissionState", State)
function BaseMissionState:timeremain()
	return 0, 0
end

function BaseMissionState:timeextend(--[[addtime]])
end

local TimeoutState = class("Timeout", BaseMissionState)
function TimeoutState:enter(msn)
	Logger:debug("%s:enter()", self.__clsname)
	msn:queueabort(enum.missionAbortType.TIMEOUT)
end

local SuccessState = class("Success", BaseMissionState)
function SuccessState:enter(msn)
	Logger:debug("%s:enter()", self.__clsname)
	-- TODO: we could convert to emitting a DCT event to handle rewarding
	-- tickets, this would require a little more than just emitting an
	-- event here. Would require changing Tickets class a little too.
	dct.Theater.singleton():getTickets():reward(msn.cmdr.owner,
		msn.reward, true)
	msn:queueabort(enum.missionAbortType.COMPLETE)
end

--[[
-- ActiveState - mission is active and executing the plan
--  Critera:
--    * on plan completion, mission success
--    * on timer expired, mission timed out
--]]
local ActiveState  = class("Active",  BaseMissionState)
function ActiveState:__init()
	Logger:debug("%s:_init()", self.__clsname)
	self.timer = Timer(MISSION_LIMIT)
	self.action = nil
end

function ActiveState:enter(msn)
	Logger:debug("%s:enter()", self.__clsname)
	-- Special case: CAP missions end on next scheduled mission restart
	if msn.type == enum.missionType["CAP/SEAD"] and dct.settings.server.period > 0 then
		local timeLeft = dct.settings.server.period - timer.getTime()
		if timeLeft > 0 then
			self.timer = Timer(timeLeft)
		end
	end
	self.timer:reset()
	self.action = msn.plan:pophead()
end

function ActiveState:update(msn)
	Logger:debug("%s:update()", self.__clsname)
	self.timer:update()
	if self.timer:expired() then
		Logger:debug("%s:update() - transition timeout", self.__clsname)
		return TimeoutState()
	end

	if self.action == nil then
		Logger:debug("%s:update() - transition success", self.__clsname)
		return SuccessState()
	end
	if self.action:complete(msn) then
		Logger:debug("%s:update() - pop new action", self.__clsname)
		local newaction = msn.plan:pophead()
		self.action:exit(msn)
		self.action = newaction
		if self.action == nil then
			Logger:debug("%s:update() - transition success", self.__clsname)
			return SuccessState()
		end
		self.action:enter(msn)
	end
	return nil
end

function ActiveState:timeremain()
	Logger:debug("%s:timeremain()", self.__clsname)
	return self.timer:remain()
end

function ActiveState:timeextend(addtime)
	Logger:debug("%s:timeextend()", self.__clsname)
	self.timer:extend(addtime)
end

--[[
-- PrepState - mission is being planned
--  Maintains a timer and once the timer expires the mission expires.
--]]
-- TODO: find some way to remove players from mission if they de-slot
-- and mission in prep state
local PrepState = class("Preparing", State)
function PrepState:__init()
	self.timer = Timer(PREP_LIMIT)
end

function PrepState:enter()
	Logger:debug("%s:enter()", self.__clsname)
	self.timer:reset()
end

function PrepState:update(msn)
	Logger:debug("%s:update()", self.__clsname)
	self.timer:update()
	if self.timer:expired() then
		Logger:debug("%s:enter() - timeout", self.__clsname)
		return TimeoutState()
	end

	for _, v in pairs(msn:getAssigned()) do
		local asset =
			dct.Theater.singleton():getAssetMgr():getAsset(v)
		if asset.type == enum.assetType.PLAYERGROUP and
		   asset:inAir() then
			Logger:debug("%s:enter() - to active state", self.__clsname)
			return ActiveState()
		end
	end
	return nil
end

function PrepState:timeremain()
	Logger:debug("%s:timeremain()", self.__clsname)
	return self.timer:remain()
end

function PrepState:timeextend(addtime)
	Logger:debug("%s:timeextend()", self.__clsname)
	self.timer:extend(addtime)
end

local function composeBriefing(_, tgt, start_time)
	local briefing = tgt.briefing
	local interptbl = {
		["TOT"] = os.date("%F %Rz",
			dctutils.zulutime(start_time + MISSION_LIMIT * 0.6)),
	}
	return dctutils.interp(briefing, interptbl)
end

local function createPlanQ(plan)
	local Q = require("libs.containers.queue")()
	for _, v in ipairs(plan) do
		Q:pushtail(v)
	end
	return Q
end

local Mission = class("Mission")
function Mission:__init(cmdr, missiontype, tgt, plan)
	self.cmdr      = cmdr
	self.type      = missiontype
	self.target    = tgt.name
	self.reward    = tgt.cost
	self.plan      = createPlanQ(plan)
	self.iffcodes  = cmdr:genMissionCodes(missiontype)
	self.id        = self.iffcodes.id
	self.minagents = tgt.minagents or 1
	self.backfill  = tgt.backfill
	self.assigned  = {}
	self.isfull    = false
	self:_setComplete(false)
	self.state = ActiveState()
	self.state:enter(self)

	self._assignedIds = {}
	self._lastAssignedId = 0

	-- update the mission when individual stages are completed
	for _, action in pairs(plan) do
		action:addObserver(self.onDCTEvent, self, self.__clsname..".onDCSEvent")
	end

	-- compose the briefing at mission creation to represent
	-- known intel the pilots were given before departing
	self.briefing  = composeBriefing(self, tgt, timer.getAbsTime())
	tgt:setTargeted(self.cmdr.owner, true)

	self.tgtinfo = {}
	self.tgtinfo.location = tgt:getLocation()
	self.tgtinfo.callsign = tgt.codename
	self.tgtinfo.status   = tgt:getStatus()
	self.tgtinfo.intellvl = tgt:getIntel(self.cmdr.owner)
	self.tgtinfo.region   = tgt.rgnname
	self.tgtinfo.extramarks = tgt.extramarks
	self.tgtinfo.coalition  = tgt.owner
	self.tgtinfo.locations  = {}

	if tgt.getStaticTargetLocations then
		self.tgtinfo.locations = tgt:getStaticTargetLocations()
	end
end

function Mission:getStateName()
	return self.state.__clsname
end

function Mission:getID()
	return self.id
end

function Mission:isMember(name)
	local i = utils.getkey(self.assigned, name)
	if i then
		return true, i
	end
	return false
end

function Mission:getAssigned()
	return utils.shallowclone(self.assigned)
end

local function friendlyName(asset)
	local playerName = asset.getPlayerName and asset:getPlayerName()
	if playerName ~= nil then
		return string.format('Player "%s"', playerName)
	else
		return string.format('Unit "%s"', tostring(asset.name))
	end
end

function Mission:addAssigned(asset)
	if self:isMember(asset.name) then
		return
	end
	table.insert(self.assigned, asset.name)
	if self._assignedIds[asset.name] == nil then
		self._assignedIds[asset.name] = self._lastAssignedId
		self._lastAssignedId = self._lastAssignedId + 1
	end
	Logger:debug("Mission %d: addAssigned(%s)", self.id, asset.name)
	if #self.assigned >= self.minagents then
		self.isfull = true
	end
	asset.missionid = self:getID()
	asset:notify(dctutils.buildevent.joinMission(asset, self))

	local msg = string.format("%s has joined your mission", friendlyName(asset))
	for _, assigned in pairs(self.assigned) do
		if assigned ~= asset.name then
			local grp = Group.getByName(assigned)
			if grp ~= nil then
				trigger.action.outTextForGroup(grp:getID(), msg, 20, false)
			end
		end
	end
end

function Mission:removeAssigned(asset, reason)
	local member, i = self:isMember(asset.name)
	if not member then
		return
	end
	table.remove(self.assigned, i)
	if Logger:isDebugEnabled() then
		Logger:debug("Mission %d: removeAssigned(%s, %s)",
			self.id, asset.name, tostring(utils.getkey(enum.missionAbortType, reason)))
	end
	if self.backfill and #self.assigned < self.minagents then
		self.isfull = false
	end
	asset.missionid = enum.missionInvalidID
	asset:notify(dctutils.buildevent.leaveMission(asset, self, reason))

	local msg = string.format("%s has left your mission", friendlyName(asset))
	for _, assigned in pairs(self.assigned) do
		local grp = Group.getByName(assigned)
		if grp ~= nil then
			trigger.action.outTextForGroup(grp:getID(), msg, 20, false)
		end
	end
end

--[[
-- Abort - aborts a mission for etiher a single group or
--   completely terminating the mission for everyone assigned.
--
-- Things that need to be managed;
--  * remove requesting group from the assigned list
--  * if assigned list is empty or we need to force terminate the
--    mission
--    - remove the mission from the owning commander's mission list(s)
--    - release the targeted asset by resetting the asset's targeted
--      bit
--]]
function Mission:abort(asset, reason)
	Logger:debug("%s:abort()", self.__clsname)
	self:removeAssigned(asset, reason)
	if next(self.assigned) == nil then
		self.cmdr:removeMission(self.id)
		self.cmdr:notify(dctutils.buildevent.removeMission(self.cmdr, self, reason))
		local tgt = self.cmdr:getAsset(self.target)
		if tgt then
			tgt:setTargeted(self.cmdr.owner, false)
		end
	end
	return self.id
end

function Mission:queueabort(reason)
	Logger:debug("%s:queueabort()", self.__clsname)
	self:_setComplete(true)
	local theater = dct.Theater.singleton()
	for _, name in ipairs(self.assigned) do
		local request = {
			["type"]   = enum.uiRequestType.MISSIONABORT,
			["name"]   = name,
			["value"]  = reason,
		}
		-- We have to use theater:queueCommand() to bypass the
		-- limiting of players sending too many commands
		theater:queueCommand(10, uicmds[request.type](theater, request))
	end
end

function Mission:update()
	Logger:debug("update() called for state: "..self.state.__clsname)
	local newstate = self.state:update(self)
	if newstate ~= nil then
		Logger:debug("update() new state: "..newstate.__clsname)
		self.state:exit(self)
		self.state = newstate
		self.state:enter(self)
	end
end

function Mission:_setComplete(val)
	self._complete = val
end

function Mission:isComplete()
	return self._complete
end

--[[
-- getTargetInfo - provide target information
--
-- The target information supplied:
--   * location - centroid of the asset
--   * callsign - a short name the target area can be referenced by
--   * description - short two/three word description of the asset
--       like; factory, ammo bunker, etc.
--   * status - numercal value from 0 to 100 representing percentage
--       completion
--   * intellvl - numercal value representing the amount of 'intel'
--       gathered on the asset, dictates targeting coordinates
--       precision too
--]]
function Mission:getTargetInfo()
	local asset = dct.Theater.singleton():getAssetMgr():getAsset(self.target)
	if asset == nil then
		self.tgtinfo.status = 100
	else
		self.tgtinfo.status = asset:getStatus()
	end
	return utils.deepcopy(self.tgtinfo)
end

function Mission:getTimeout()
	local remain, ctime = self.state:timeremain()
	return ctime + remain
end

function Mission:addTime(time)
	self.state:timeextend(time)
	return time
end

function Mission:getIFFCodes(asset)
	local assignedId = 0
	if asset ~= nil then
		assignedId = (self._assignedIds[asset.name] or 0) % 8
	end
	local m1 = string.format("%o", self.iffcodes.m1)
	local m3 = string.format("%o", self.iffcodes.m3 + assignedId)
	return { ["m1"] = m1, ["m3"] = m3 }
end

local function getTargetDetails(tgt, cmdr, fmt)
	local intel = tgt:getIntel(cmdr.owner)
	if intel >= 4 and tgt.getStaticTargetLocations then
		local details = {}
		for _, location in pairs(tgt:getStaticTargetLocations()) do
			table.insert(details, string.format("  %s: %s", tostring(location.desc),
				dctutils.fmtposition(location, intel, fmt)))
		end
		if next(details) ~= nil then
			return table.concat(details, "\n")
		end
	end
	return "Precise locations are currently unavailable."
end

function Mission:getDescription(fmt)
	local tgt = self.cmdr:getAsset(self.target)
	if tgt == nil then
		return "Target destroyed abort mission"
	end
	local interptbl = {
		["LOCATION"] = dctutils.fmtposition(
			tgt:getLocation(),
			tgt:getIntel(self.cmdr.owner),
			fmt),
		["TARGETS"] = getTargetDetails(tgt, self.cmdr, fmt),
		["MINAGENTS"] = tostring(self.minagents),
	}
	return dctutils.interp(self.briefing, interptbl)
end

function Mission:onDCTEvent(event)
	if event.id == enum.event.DCT_EVENT_DEAD then
		self:update()
	end
	return nil
end

return Mission
