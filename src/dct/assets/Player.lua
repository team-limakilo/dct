--[[
-- SPDX-License-Identifier: LGPL-3.0
--
-- Represents a player asset.
--
-- Player<AssetBase>
-- A player asset doesn't die (the assetmanager prevents this), never
-- reduces status, and is always associated with a squadron.
-- Optionally the player can be associated with an airbase.
--
-- ## Ticket Consumption
-- Players only consume a ticket when a when they die or otherwise
-- leave the slot is an 'invalid' way. A valid way to leave a slot
-- is at an authorized airbase.
--
-- ## Slot Management
-- Spawned player objects are used as a signal for enabling/disabling
-- the slot. This is additionally combined with a transient state
-- potentially defined in the Player's State class (EmptyState or
-- OccupiedState) to ultimately determine if the slot is 'enabled'.
-- The hooks script used for slot management can utilize this by
-- directly asking the Player object if it is enabled via the
-- 'isEnabled()' API call.
-- This API call will combine the spawned(S) and kick pending(K)
-- states to prevent a race between posting a kick request
-- and affecting the kick in the hooks script. The boolean table
-- below shows the logic governing when a slot is considered
-- 'enabled';
--     EmptyState:     enabled = S & !K
--     OccupiedState:  enabled = S; we really don't care through
--                                  because the slot should be
--                                  occupied
--]]

-- luacheck: max cyclomatic complexity 12

require("math")
local class     = require("libs.namedclass")
local utils     = require("libs.utils")
local dctenum   = require("dct.enum")
local dctutils  = require("dct.utils")
local AssetBase = require("dct.assets.AssetBase")
local Squadron  = require("dct.assets.Squadron")
local GroupMenu = require("dct.ui.groupmenu")
local cmds      = require("dct.ui.cmds")
local loadout   = require("dct.systems.loadouts")
local State     = require("dct.libs.State")
local vec       = require("dct.libs.vector")
local settings = _G.dct.settings

local notifymsg =
	"Please read the loadout limits in the briefing and "..
	"use the F10 Menu to validate your loadout before departing."

local function build_kick_flagname(name)
	return name.."_kick"
end

local function on_birth(asset, event)
	local grp = event.initiator:getGroup()
	local id = grp and grp:getID()
	if asset.groupId ~= id then
		asset._logger:warn("asset.groupId(%d) != object:getID(%s)",
			asset.groupId, tostring(id))
	end
	asset.groupId = id
end

-- returns assigned mission, if any
local function reset_slot(asset)
	-- update location so it's not nil when the player is despawned
	asset:getLocation()

	local theater = dct.Theater.singleton()
	if asset.squadron then
		asset._logger:debug("squadron set: %s", asset.squadron)
		local sqdn = theater:getAssetMgr():getAsset(asset.squadron)
		if sqdn and sqdn:isa(Squadron) then
			asset._logger:debug("squadron overriding ato and payload")
			if sqdn:getATO() ~= nil then
				asset._logger:debug("squadron overriding ato")
				asset.ato = sqdn:getATO()
				asset._logger:debug("ato: %s",
					require("libs.json"):encode_pretty(asset.ato))
			end
			if sqdn:getPayloadLimits() ~= nil then
				asset._logger:debug("squadron overriding payload limits")
				asset.payloadlimits = sqdn:getPayloadLimits()
				asset._logger:debug("payloadlimits: %s",
					require("libs.json"):encode_pretty(asset.payloadlimits))
			end
		else
			asset._logger:warn("squadron does not exist, using default settings")
		end
	end

	local cmdr = theater:getCommander(asset.owner)
	local msn  = cmdr:getAssigned(asset)

	if msn then
		trigger.action.outTextForGroup(asset.groupId, string.format(
			"Welcome. Mission %d is already assigned to this slot, "..
			"use the F10 menu to get the briefing or find another.", msn:getID()),
			20, false)
	else
		local missions = cmdr:getAvailableMissions(asset.ato)
		local missionsfmt = {}
		for type, count in utils.sortedpairs(missions, dctutils.missionPairs) do
			table.insert(missionsfmt, string.format("%s:  %d", type, count))
		end
		if next(missionsfmt) == nil then
			table.insert(missionsfmt, "None")
		end
		local recommended = cmdr:recommendMissionType(asset.ato)
		trigger.action.outTextForGroup(asset.groupId,
			"Welcome. Use the F10 Menu to get a theater update and "..
			"request a mission.\n\nAvailable missions:\n  "..
			table.concat(missionsfmt, "\n  ")..
			"\n\nRecommended Mission Type: "..
			(utils.getkey(dctenum.missionType, recommended) or "None"), 20, false)
	end
	trigger.action.outTextForGroup(asset.groupId, notifymsg, 20, false)

	if not asset:isEnabled() then
		trigger.action.outTextForGroup(asset.groupId, "Warning: you have spawned "..
			"in a disabled slot, slot blocker potentially broken.", 20, false)
	end

	return msn
end

local OccupiedState = class("OccupiedState", State)
local EmptyState    = class("EmptyState", State)
function EmptyState:__init(kickcode)
	self.kickcode = kickcode or dctenum.kickCode.UNKNOWN
end

function EmptyState:enter(asset)
	asset:kick(self.kickcode)
	if asset.missionid ~= dctenum.missionInvalidID and
	   settings.server.emptyslottimeout > 0 then
		self.timer =
			require("dct.libs.Timer")(settings.server.emptyslottimeout,
				timer.getAbsTime)
	end
end

function EmptyState:update(asset)
	if self.timer == nil then
		return
	end

	self.timer:update()
	if self.timer:expired() then
		self.timer = nil
		local cmdr = dct.Theater.singleton():getCommander(asset.owner)
		local msn = cmdr:getMission(asset.missionid)
		if msn then
			msn:abort(asset, dctenum.missionAbortType.ABORT)
		end
	end
end

function EmptyState:onDCTEvent(asset, event)
	if world.event.S_EVENT_BIRTH ~= event.id then
		return nil
	end
	on_birth(asset, event)
	return OccupiedState(event.initiator:inAir())
end

function OccupiedState:__init(inair)
	self.inair = inair
	self.loseticket = inair
	self.bleedctr = 0
	self.bleedperiod = 5
	self.bleedwarn = false
	self._eventhandlers = {
		[world.event.S_EVENT_BIRTH]             = self.handleSwitchOccupied,
		[world.event.S_EVENT_TAKEOFF]           = self.handleTakeoff,
		[world.event.S_EVENT_EJECTION]          = self.handleEjection,
		[world.event.S_EVENT_DEAD]              = self.handleDead,
		[world.event.S_EVENT_PILOT_DEAD]        = self.handleDead,
		[world.event.S_EVENT_CRASH]             = self.handleDead,
		[world.event.S_EVENT_LAND]              = self.handleLand,
		[dctenum.event.DCT_EVENT_DEAD]          = self.handleTheaterChange,
		[dctenum.event.DCT_EVENT_ADD_ASSET]     = self.handleTheaterChange,
		[dctenum.event.DCT_EVENT_ADD_MISSION]   = self.handleTheaterChange,
		[dctenum.event.DCT_EVENT_REMOVE_MISSION]= self.handleTheaterChange,
	}
end

function OccupiedState:enter(asset)
	asset:setDead(false)
	local msn = reset_slot(asset)
	asset.menu:create(msn)
end

function OccupiedState:exit(asset)
	asset.menu:destroy()
	if self.loseticket then
		asset:setDead(true)
	end
end

function OccupiedState:_bleed(asset)
	local theater = dct.Theater.singleton()
	local tickets = theater:getTickets()
	if not (tickets:getConfig(asset.owner).bleed and
		self.inair == true) then
		return nil
	end

	local cmdr = theater:getCommander(asset.owner)
	local msn  = cmdr:getAssigned(asset)
	if msn then
		self.bleedctr = 0
		self.bleedwarn = false
	else
		self.bleedctr = self.bleedctr + 1
	end

	local state = nil
	if not self.bleedwarn and
	   self.bleedctr > math.floor(self.bleedperiod / 2) then
		self.bleedwarn = true
		trigger.action.outTextForGroup(asset.groupId,
			"WARNING! You do not have a mission assigned, land or obtain "..
			"a mission or you will be kicked.",
			20, true)
	end
	if self.bleedctr >= self.bleedperiod then
		self.loseticket = true
		self.bleedctr = 0
		trigger.action.outTextForGroup(asset.groupId,
			"You have been kicked for not having a mission assigned.",
			20, true)
		state = EmptyState(dctenum.kickCode.MISSION)
	end
	return state
end

function OccupiedState:_kickForNuke(asset)
	trigger.action.outTextForGroup(asset.groupId,
		"You have been kicked for carrying a nuclear weapon.", 20, true)
	return EmptyState(dctenum.kickCode.NUKE)
end

function OccupiedState:_checkPayload(asset, display)
	local ok, costs, nuke = loadout.check(asset)
	if nuke then
		return self:_kickForNuke(asset), ok
	end
	if display and not ok then
		-- Show the current loadout to the player
		local CheckPayloadCmd = cmds[dctenum.uiRequestType.CHECKPAYLOAD]
		local msg = CheckPayloadCmd:buildMessage(false, costs)
		trigger.action.outTextForGroup(asset.groupId, msg, 60, false)
	end
	return nil, ok
end

function OccupiedState:_checkLoadoutInAir(asset)
	local group = Group.getByName(asset.name)
	-- Possible race condition: if the player takes off with an invalid
	-- loadout, lands, and then takes off again in the span of one minute,
	-- the first timer will still be counting and they will be punished earlier.
	-- Very few aircraft (eg. the Harrier) can do that, and if they do, they
	-- deserve to be whacked.
	if self.inair and group ~= nil then
		local _, ok = self:_checkPayload(asset, false)
		if ok then
			trigger.action.outTextForGroup(asset.groupId, "You are "..
				"within payload limits and can safely land to re-arm.", 30, true)
		else
			-- ¯\_(ツ)_/¯
			self.loseticket = false
			local unit = group:getUnit(1):getName()
			trigger.action.setUnitInternalCargo(unit, 1000000)
			trigger.action.outTextForGroup(asset.groupId,
				"You have taken off with an invalid loadout and failed to comply "..
				"with orders in time. Your aircraft has been made unflyable.", 30, true)
		end
	end
end

function OccupiedState:update(asset)
	local grp = Group.getByName(asset.name)
	if grp == nil then
		return EmptyState(dctenum.kickCode.EMPTY)
	end
	if not self.inair then
		local newstate, _ = self:_checkPayload(asset, true)
		if newstate ~= nil then
			return newstate
		end
	end
	asset.menu:update()
	return self:_bleed(asset)
end

function OccupiedState:onDCTEvent(asset, event)
	local handler = self._eventhandlers[event.id]
	asset._logger:debug("OccupiedState:onDCTEvent; event.id: %d, handler: %s",
		event.id, tostring(handler))
	local state
	if handler ~= nil then
		state = handler(self, asset, event)
	end
	return state
end

function OccupiedState:handleTakeoff(asset, _ --[[event]])
	self.inair = true
	self.loseticket = true
	local ok, _, nuke = loadout.check(asset)
	if nuke then
		return self:_kickForNuke(asset)
	end
	if not ok then
		-- Give the player one minute to jettison
		-- weapons if they go over the loadout limit
		local loadouttimer = 60
		timer.scheduleFunction(function() self:_checkLoadoutInAir(asset) end,
			nil, timer.getTime() + loadouttimer)
		trigger.action.outTextForGroup(asset.groupId, string.format("You have "..
			"taken off with an illegal loadout!\nIf stores are not jettisoned within "..
			"[%d SECONDS] from takeoff, you will be punished!", loadouttimer), 30, true)
	end
	return nil
end

-- If returned to an authorized airbase clear loseticket flag.
-- An authorized airbase is any base defined as an asset for
-- the same side, or that the asset belongs to.
function OccupiedState:handleLand(asset, event)
	self.inair = false

	if event.place == nil then
		-- TODO: FARP handling
		return nil
	end

	local assetmgr = dct.Theater.singleton():getAssetMgr()
	local airbase = assetmgr:getAsset(event.place:getName())
	local homebase = event.place:getName() == asset.airbase

	if airbase and airbase.owner == dctutils.getenemy(asset.owner) then
		trigger.action.outTextForGroup(asset.groupId,
			"You have landed at an enemy airbase! Please leave immediately.", 20, true)
	elseif homebase or airbase and airbase.owner == asset.owner then
		self.loseticket = false
		trigger.action.outTextForGroup(asset.groupId,
			"Welcome home. You are able to safely disconnect"..
			" without costing your side tickets.", 20, true)
	else
		trigger.action.outTextForGroup(asset.groupId,
			"You have landed at an airbase not in use in this operation. "..
			"Please return to your home base, or a base listed as friendly in "..
			"F10 Other - Theather Update before logging off.",
			20, true)
	end
	return nil
end

function OccupiedState:handleDead(--[[asset, event]])
	return EmptyState(dctenum.kickCode.NOKICK)
end

function OccupiedState:handleEjection(asset, _)
	-- Prevent ejected players from blowing up by reslotting immediately
	if not asset:inAir() then
		return EmptyState(dctenum.kickCode.DEAD)
	else
		return self:handleDead()
	end
end

function OccupiedState:handleSwitchOccupied(asset, event)
	asset._logger:warn("player left slot, resetting state for birth event")
	on_birth(asset, event)
	return OccupiedState()
end

function OccupiedState:handleTheaterChange(asset)
	asset.menu:update()
end

--[[
-- Player - represents a player slot in DCS
--]]
local Player = class("Player", AssetBase)
function Player:__init(template)
	AssetBase.__init(self, template)
	self.inair = false
	self._operstate = false
	self.missionid = dctenum.missionInvalidID
	trigger.action.setUserFlag(self.name, false)
	trigger.action.setUserFlag(build_kick_flagname(self.name),
		dctenum.kickCode.NOKICK)
	self.marshal   = nil
	self.unmarshal = nil
end

function Player.assettypes()
	return {
		dctenum.assetType.PLAYERGROUP,
	}
end

local function airbaseId(grp)
	assert(grp, "value error: grp cannot be nil")
	local start = grp.data.route.points[1]
	-- helipadId can be either a ship (carrier, destroyer, etc) or a FARP
	if start["helipadId"] ~= nil then
		return start["helipadId"], false
	end
	-- airdromeId is an airfield
	if start["airdromeId"] ~= nil then
		return start["airdromeId"], true
	end
end

local function airbaseParkingId(grp)
	assert(grp, "value error: grp cannot be nil")
	local wp = grp.data.route.points[1]
	if wp.type == AI.Task.WaypointType.TAKEOFF_PARKING or
	   wp.type == AI.Task.WaypointType.TAKEOFF_PARKING_HOT then
		return grp.data.units[1].parking
	end
	return nil
end

local function isDCTAirbase(airbase, assetmgr)
	return assetmgr:getAsset(airbase:getName()) ~= nil
end

local function findAirbase(grp, assetmgr)
	-- try to find the airbase based on the template data
	local id, isAirdrome = airbaseId(grp)
	if id ~= nil then
		return dctutils.airbaseId2Name(id, isAirdrome)
	end

	-- if the slot is a ground spawn, search for the closest DCT airbase or FARP
	local point = { x = grp.data.x, y = land.getHeight(grp.data), z = grp.data.y }
	local nearest = dctutils.nearestAirbase(point, 7500, isDCTAirbase, assetmgr)
	if nearest ~= nil then
		return nearest:getName()
	end
end

function Player:_completeinit(template)
	AssetBase._completeinit(self, template)
	-- we assume all slots in a player group are the same
	self._tpldata   = template:copyData()
	self.unittype   = self._tpldata.data.units[1].type
	self.cmdpending = false
	self.firstspawn = true
	self.groupId    = self._tpldata.data.groupId
	self.squadron   = self.name:match("(%w+)(.+)")
	if settings.players.costs[self.unittype] ~= nil then
		self.cost = template.cost * settings.players.costs[self.unittype]
	end
	self.payloadlimits = settings.players.payloadlimits[self.unittype]
		or settings.payloadlimits
	self.ato = settings.players.ato[self.unittype]
		or dctenum.missionType
	self.gridfmt = settings.players.gridfmt[self.unittype]
		or dctutils.posfmt.DMS
	self.units = settings.players.units[self.unittype] or {}

	if self._logger:isDebugEnabled() then
		self._logger:debug("unittype: %s", tostring(self.unittype))
		self._logger:debug("ato: %s",
			require("libs.json"):encode_pretty(self.ato))
		self._logger:debug("cost: %g", self.cost, type(self.cost))
		self._logger:debug("gridfmt: %s",
			tostring(utils.getkey(dctutils.posfmt, self.gridfmt)))
		self._logger:debug("payloadlimits: %s",
			require("libs.json"):encode_pretty(self.payloadlimits))

		local units = {}
		for key, _ in pairs(self.units) do
			table.insert(units, tostring(utils.getkey(dctutils.units, key)))
		end
		self._logger:debug("units: [ %s ]", table.concat(units, ", "))
	end

	self.menu = GroupMenu(self)
end

function Player:registerObservable(observable)
	local name = string.format("%s.onDCTEvent('%s')", self.__clsname, self.name)
	observable:addObserver(self.onDCTEvent, self, name)
end

function Player:_setup()
	self.state = EmptyState(dctenum.kickCode.SETUP)
	self.state:enter(self)
end

-- Player assets cannot die, prevent them from ever being cleaned up
-- by the AssetManager
function Player:isDead()
	return false
end

function Player:inAir()
	self.inair = self.state.inair or false
	return self.inair
end

function Player:getObjectNames()
	return {self.name, }
end

function Player:getLocation()
	local p = Group.getByName(self.name)
	if p ~= nil then
		self._location = vec.Vector3D(p:getUnit(1):getPoint())
	end
	return AssetBase.getLocation(self)
end

function Player:isEnabled()
	return self:isSpawned() and self._operstate
end

function Player:doEnable()
	trigger.action.setUserFlag(self.name, self:isEnabled())
	self._logger:debug("setting enable flag: %s", tostring(self:isEnabled()))
end

function Player:update()
	self:doEnable()
	local newstate = self.state:update(self)
	if newstate ~= nil then
		self.state:exit(self)
		self.state = newstate
		self.state:enter(self)
	end
end

function Player:updateOperationalState()
	local assetmgr = dct.theater:getAssetMgr()
	local airbase = assetmgr:getAsset(self.airbase)
	if airbase then
		self._operstate = airbase:isOperational() and airbase.owner == self.owner
		self._logger:debug("setting operstate: %s", tostring(self._operstate))
	end
end

function Player:handleBaseState(event)
	if event.initiator.name == self.airbase then
		self:updateOperationalState()
		self:doEnable()
	else
		self._logger:warn("received unknown event %s(%d) from initiator(%s)",
			require("libs.utils").getkey(dctenum.event, event.id),
			event.id, event.initiator.name)
	end
end

function Player:onDCTEvent(event)
	if event.id == dctenum.event.DCT_EVENT_OPERATIONAL then
		self:handleBaseState(event)
	end
	local newstate = self.state:onDCTEvent(self, event)
	if newstate ~= nil then
		self.state:exit(self)
		self.state = newstate
		self.state:enter(self)
	end
end

function Player:spawn()
	AssetBase.spawn(self)
	if self.firstspawn then
		local assetmgr = dct.theater:getAssetMgr()
		self.airbase = findAirbase(self._tpldata, assetmgr)
		self.parking = airbaseParkingId(self._tpldata)
		self._logger:debug("airbase: %s", tostring(self.airbase))
		self._logger:debug("parking: %s", tostring(self.parking))
		self:registerObservable(dct.theater:getAssetMgr())
		self:registerObservable(dct.theater:getCommander(self.owner))
		local ab = assetmgr:getAsset(self.airbase)
		if ab ~= nil and ab.owner == self.owner then
			ab:addSubordinate(self)
		end
		self.firstspawn = false
	end
	self:updateOperationalState()
	self:doEnable()
end

function Player:despawn()
	AssetBase.despawn(self)
	self._logger:debug("setting operstate: false")
	self._operstate = false
	self:doEnable()
end

-- Calls a given function on the unit if it exists, otherwise
-- returns nil (ie. if there is no player in the slot)
local function callOnUnit(name, fn)
	local grp = Group.getByName(name)
	if grp ~= nil then
		local unit = grp:getUnit(1)
		if unit ~= nil then
			return fn(unit)
		end
	end
	return nil
end

function Player:getPlayerName()
	return callOnUnit(self.name, Unit.getPlayerName)
end

function Player:getAircraftName()
	local desc = callOnUnit(self.name, Unit.getDesc)
	if desc ~= nil then
		return desc["displayName"] or "Unknown Aircraft"
	end
	return nil
end

function Player:getTypeName()
	local desc = callOnUnit(self.name, Unit.getDesc)
	return desc and desc["typeName"]
end

--[[
-- kick - request player to be kicked from slot
--
-- Posts a request for the player to be kicked from the slot.
-- This depends on an outside DCS hooks script to be running
-- which will kick the player from the slot and reset the
-- kick flag.
-- This will then allow the player state the be reset allowing
-- another player to join the slot.
--]]
function Player:kick(kickcode)
	local flagname = build_kick_flagname(self.name)
	trigger.action.setUserFlag(flagname, kickcode)
	self._logger:debug("requesting kick: %s", flagname)
end

return Player
