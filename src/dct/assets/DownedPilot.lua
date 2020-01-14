--[[
-- SPDX-License-Identifier: LGPL-3.0
--
-- Defines a DownedPilot asset to handle downed airmen.
--]]

local class    = require("libs.class")
local State    = require("dct.libs.State")
local StaticAsset = require("dct.assets.StaticAsset")
local Template = require("dct.templates.Template")
local Marshallable = require("dct.libs.Marshallable")
local Logger   = dct.Logger.getByName("Asset")
local settings = _G.dct.settings

local statetypes = {
	["DEAD"]        = 1,
	["PICKEDUP"]    = 2,
	["INCOUNTRY"]   = 3,
	["UNDERCANOPY"] = 4,
}

--[[
-- DeadState - terminal state
--  * enter: despawn dcs object
--  * enter: remove value of pilot from owner ticket pool
--  * enter: mark asset dead
--]]
local DeadState = class(State, Marshallable)
function DeadState:__init()
	Marshallable.__init(self)
	self.type = statetypes.DEAD
	self:_addMarshalNames({"type",})
end

function DeadState:enter(asset)
	asset:despawn()
	asset:setDead(true)
	-- hack: remove the cost of the downed pilot as we do not want to
	-- double charge the side for losing a downed pilot as we remove
	-- the ticket value when the pilot ejects.
	asset.cost = 0
end

--[[
-- PickedUp - terminal state
--   * enter: add pilot cost to mission reward pool
--   * enter: despawn dcs objects
--   * enter: mark asset dead
--]]
local PickedUp = class(State, Marshallable)
function PickedUp:__init(msnid)
	Marshallable.__init(self)
	self.type = statetypes.PICKEDUP
	self.id = msnid
	self:_addMarshalNames({
		"type",
		"id",
	})
end

function PickedUp:enter(asset)
	-- TODO: add pilot cost to mission pool
	asset:despawn()
	asset:setDead(true)
end

--[[
-- InCountry - pilot waiting to be picked up
--   * enter: start timeout timer
--   * enter: spawn asset
--   * transition: to PickedUp by mission event
--   * transition: to Dead by update expired timer, pause timer
--        if friendly in area
--   * transition: to Dead by dead event
--   * exit: none
--]]
local InCountry = class(State, Marshallable)
function InCountry:__init()
	Marshallable.__init(self)
	self.type = statetypes.INCOUNTRY
	self.timeout = 12*60*60 -- 12 hours
	self.ctime   = timer.getAbsTime()
	self._eventhandlers = {
		[world.event.S_EVENT_DEAD]  = self.handleDead,
		[dct.events.S_EVENT_PICKUP] = self.handlePickup,
	}
	self:_addMarshalNames({
		"type",
		"timeout",
	})
end

function InCountry:enter(asset)
	asset:spawn()
end

function InCountry:update(asset)
	local time = timer.getAbsTime()
	self.timeout = self.timeout - (time - self.ctime)
	self.ctime = time

	if (not asset:isTargeted(asset.owner)) and self.timeout <= 0 then
		return DeadState()
	end
	return nil
end

function InCountry:handlePickup(_ --[[asset]], event)
	return PickedUp(event.missionid)
end

function InCountry:handleDead(--[[asset, event]])
	return DeadState()
end

function InCountry:onDCTEvent(asset, event)
	local handler = self._eventhandlers[event.id]
	Logger:debug(string.format(
		"InCountry:onDCTEvent; event.id: %d, handler: %s",
		event.id, tostring(handler)))
	local state = nil
	if handler ~= nil then
		state = handler(self, asset, event)
	end
	return state
end

--[[
-- UnderCanopy - waiting for pilot to land
--   * enter: none
--   * transition: to InCountry on land event
--   * transition: to InCountry on timeout (30 min timeout, assumes
--      22fps fall rate and 40,000ft ejection)
--   * exit: none
--]]
local UnderCanopy = class(State, Marshallable)
function UnderCanopy:__init()
	Marshallable.__init(self)
	self.type = statetypes.UNDERCANOPY
	self.timeout = 30 * 60
	self.ctime   = timer.getAbsTime()
	self:_addMarshalNames({
		"type",
		"timeout",
	})
end

function UnderCanopy:update(--[[asset]])
	local time = timer.getAbsTime()
	self.timeout = self.timeout - (time - self.ctime)
	self.ctime = time

	if self.timeout <= 0 then
		return InCountry()
	end
	return nil
end

function UnderCanopy:onDCTEvent(_ --[[asset]], event)
	if event.id ~= world.event.S_EVENT_LANDING_AFTER_EJECTION then
		return nil
	end
	-- TODO: update position of template
	return InCountry()
end

local function statefactory(stype)
	local c = {
		[statetypes.DEAD] = DeadState,
		[statetypes.PICKEDUP] = PickedUp,
		[statetypes.INCOUNTRY] = InCountry,
		[statetypes.UNDERCANOPY] = UnderCanopy,
	}

	local state = c[stype]
	assert(state, "")
	return state()
end

local DownedPilot = class(StaticAsset)
function DownedPilot:__init(template, region)
	self.__clsname = "DownedPilot"
	StaticAsset.__init(self, template, region)
	self.create = nil
end

function DownedPilot:_completeinit(template, region)
	StaticAsset._completeinit(self, template, region)
	self.origname = template.origdcsname
	self.state = UnderCanopy()
	self.state:enter(self)
end

function DownedPilot:marshal()
	local t = StaticAsset.marshal(self)
	t.state = self.state:marshal()
	return t
end

function DownedPilot:unmarshal(data)
	StaticAsset.unmarshal(self, data)
	self.state = statefactory(data.state.type)
	self.state:unmarshal(data.state)
	self.state:enter(self)
end

function DownedPilot:getObjectNames()
	local names = StaticAsset.getObjectNames(self)
	table.insert(names, self.origname)
	return names
end

function DownedPilot:checkDead()
	StaticAsset.checkDead(self)
	local newstate = self.state:update(self)
	if newstate ~= nil then
		self.state:exit(self)
		self.state = newstate
		self.state:enter(self)
	end
end

function DownedPilot:onDCTEvent(event)
	StaticAsset.onDCTEvent(self, event)
	local newstate = self.state:onDCTEvent(self, event)
	if newstate ~= nil then
		self.state:exit(self)
		self.state = newstate
		self.state:enter(self)
	end
end

function DownedPilot.create(unit)
	local position = unit:getPoint()
	local owner    = unit:getCoalition()
	local cntry    = unit:getCountry()
	--local sprite   = settings.pilotdb[cntry] or "Soldier M4"
	local sprite   = "Soldier M4"
	local tpldata = {
		{
			["category"] = Unit.Category.GROUND_UNIT,
			["countryid"] = cntry,
			["data"] = {
				["visible"] = true,
				["lateActivation"] = false,
				["uncontrollable"] = true,
				["hidden"] = false,
				["units"] = {
					{
						["type"] = sprite,
						["skill"] = "Average",
						["y"] = position.x,
						["x"] = position.z,
						["name"] = "DESTROYED PRIMARY pilot",
						["heading"] = 0,
						["playerCanDrive"] = false,
					},
				},
				["y"] = position.x,
				["x"] = position.z,
				["name"] = "Downed Pilot Group",
				["start_time"] = 0,
			},
		},
	}
	local template = {}
	template.tpldata     = tpldata
	template.coalition   = owner
	template.cost        =
		dct.Theater.singleton():getTickets():getPlayerCost(owner)
	template.objtype     = "DOWNEDPILOT"
	template.uniquenames = true
	template.regionname  = "theater"
	template.name        = "Downed Pilot"
	template.desc        = "TODO: A downed airman is blah blah"
	template.origdcsname = unit:getName()
	return DownedPilot(Template(template),
		{["name"] = "theater", ["priority"] = 1})
end

return DownedPilot
