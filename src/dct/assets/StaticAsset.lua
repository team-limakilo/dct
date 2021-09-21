--[[
-- SPDX-License-Identifier: LGPL-3.0
--
-- Static asset, represents assets that do not move.
--
-- StaticAsset<AssetBase>:
--   has associated DCS objects, has death goals related to the
--   state of the DCS objects, the asset does not move
--]]

require("math")
local utils    = require("libs.utils")
local enum     = require("dct.enum")
local dctutils = require("dct.utils")
local vector   = require("dct.libs.vector")
local Goal     = require("dct.Goal")
local AssetBase= require("dct.assets.AssetBase")

local function isUnitGroup(category)
	return category == Unit.Category.AIRPLANE
		or category == Unit.Category.HELICOPTER
		or category == Unit.Category.GROUND_UNIT
		or category == Unit.Category.SHIP
end

local StaticAsset = require("libs.namedclass")("StaticAsset", AssetBase)
function StaticAsset:__init(template)
	self._maxdeathgoals = 0
	self._curdeathgoals = 0
	self._status        = 0
	self._deathgoals    = {}
	self._assets        = {}
	self._eventhandlers = {
		[world.event.S_EVENT_DEAD] = self.handleDead,
	}
	AssetBase.__init(self, template)
	self:_addMarshalNames({
		"_hasDeathGoals",
		"_maxdeathgoals",
	})
end

function StaticAsset.assettypes()
	return {
		enum.assetType.OCA,
		enum.assetType.BASEDEFENSE,
		enum.assetType.SHORAD,
		enum.assetType.SPECIALFORCES,
		enum.assetType.AMMODUMP,
		enum.assetType.FUELDUMP,
		enum.assetType.C2,
		enum.assetType.MISSILE,
		enum.assetType.PORT,
		enum.assetType.SEA,
		enum.assetType.FACILITY,
		enum.assetType.BUNKER,
		enum.assetType.CHECKPOINT,
		enum.assetType.FACTORY,
		enum.assetType.FOB,
		enum.assetType.LOGISTICS,
		enum.assetType.FRONTLINE,
		enum.assetType.CONVOY,
	}
end

function StaticAsset:_completeinit(template)
	AssetBase._completeinit(self, template)
	self._hasDeathGoals = template.hasDeathGoals
	self._tpldata       = template:copyData()
end

--[[
-- Ensure only primary death goals are added
--]]
function StaticAsset:_addDeathGoal(name, goalspec)
	assert(name ~= nil and type(name) == "string",
		"value error: name must be provided")
	assert(goalspec ~= nil, "value error: goalspec must be provided")

	if goalspec.priority ~= Goal.priority.PRIMARY then
		return
	end

	self._deathgoals[name] = Goal.factory(name, goalspec)
	self._curdeathgoals = self._curdeathgoals + 1
	self._maxdeathgoals = math.max(self._curdeathgoals, self._maxdeathgoals)
end

--[[
-- Removes deathgoal entry, and upon no more deathgoals, set asset as dead
--]]
function StaticAsset:_removeDeathGoal(name, goal)
	assert(name ~= nil and type(name) == "string",
		"value error: name must be provided")
	assert(goal ~= nil, "value error: goal must be provided")

	self._logger:debug("_removeDeathGoal() - obj name: %s", name)
	if self:isDead() then
		self._logger:error("_removeDeathGoal() called '%s' marked as dead", self.name)
		return
	end

	self._deathgoals[name] = nil
	self._curdeathgoals = self._curdeathgoals - 1
	if next(self._deathgoals) == nil then
		self:setDead(true)
	end
end

--[[
-- Adds a death goal, which determines when the Asset is dead.
-- If no death goals have been defined, the default is to require 90%
-- damage for all objects of the same coalition as the Asset.
--]]
function StaticAsset:_setupDeathGoal(grpdata, category, country)
	if self._hasDeathGoals then
		if grpdata.dct_deathgoal ~= nil then
			self:_addDeathGoal(grpdata.name, grpdata.dct_deathgoal)
		end
		for _, unit in ipairs(grpdata.units or {}) do
			if unit.dct_deathgoal ~= nil then
				self:_addDeathGoal(unit.name, unit.dct_deathgoal)
			end
		end
	elseif country ~= nil and
	       coalition.getCountryCoalition(country) == self.owner then
		self:_addDeathGoal(grpdata.name,
			AssetBase.defaultgoal(
				category == Unit.Category.STRUCTURE or
				category == enum.UNIT_CAT_SCENERY))
	end
end

--[[
-- Checks if a goal is complete, and if so, removes it, and returns true
--]]
function StaticAsset:_checkDeathGoal(name)
	local goal = self._deathgoals[name]
	if goal and goal:checkComplete() then
		self:_removeDeathGoal(name, goal)
		return true
	end
end

--[[
-- Adds an object (group or static) to the monitored list for this
-- asset. This list will be needed later to save state.
--]]
function StaticAsset:_setup()
	for _, grp in ipairs(self._tpldata) do
		self:_setupDeathGoal(grp.data, grp.category, grp.countryid)
		self._assets[grp.data.name] = utils.deepcopy(grp)

		local route = grp.data.route
		if route ~= nil and route.points ~= nil and #route.points > 1 then
			self.isMobile = true
		end
	end

	if next(self._deathgoals) == nil then
		self._logger:error("runtime error: must have a deathgoal, deleting")
		self:setDead(true)
	end
end

function StaticAsset:getTemplateData()
	return self._tpldata
end

function StaticAsset:getLocation()
	if self._location == nil then
		local vec2, n
		for _, grp in pairs(self._assets) do
			vec2, n = dctutils.centroid2D(grp.data, vec2, n)
		end
		vec2.z = nil
		self._location = vector.Vector3D(vec2, land.getHeight(vec2)):raw()
	end
	return AssetBase.getLocation(self)
end

function StaticAsset:getCurrentLocation()
	if self:isSpawned() and self.isMobile then
		for name, group in pairs(self._assets) do
			if isUnitGroup(group.category) then
				return Group.getByName(name):getUnit(1):getPoint()
			end
		end
	end
	return self:getLocation()
end

function StaticAsset:getStatus()
	if not self:isSpawned() then
		return self._status
	end
	local total = 0
	local goals = self._maxdeathgoals
	for _, goal in pairs(self._deathgoals) do
		total = total + goal:getStatus()
		goals = goals - 1
	end
	total = total + goals * 100
	self._status = math.ceil(total / self._maxdeathgoals)
	return self._status
end

function StaticAsset:getObjectNames()
	local keyset = {}
	local n      = 0
	for k,_ in pairs(self._assets) do
		n = n+1
		keyset[n] = k
	end
	return keyset
end

function StaticAsset:update()
	if not self:isSpawned() then
		return
	end

	local cnt = 0
	for name, goal in pairs(self._deathgoals) do
		cnt = cnt + 1
		if goal:checkComplete() then
			self:_removeDeathGoal(name, goal)
		end
	end
	self._logger:debug("update() - max goals: %d; cur goals: %d; checked: %d",
		self._maxdeathgoals, self._curdeathgoals, cnt)
end

function StaticAsset:handleDead(event)
	local obj = event.initiator

	-- remove dead units and their respective goals
	local unitname = tostring(obj:getName())
	if obj:getCategory() == Object.Category.UNIT then
		local grpname = obj:getGroup():getName()
		local grp = self._assets[grpname]
		local units = grp.data.units
		for i = 1, #units do
			if units[i].name == unitname then
				self:_checkDeathGoal(unitname)
				table.remove(units, i)
				break
			end
		end
		self:_checkDeathGoal(grpname)
		if next(units) == nil then
			self._assets[grpname] = nil
		end
	else
		if self._assets[unitname].category == enum.UNIT_CAT_SCENERY then
			dct.Theater.singleton():getSystem(
				"dct.systems.bldgPersist"):addObject(unitname)
		end
		self._assets[unitname] = nil
	end
end

function StaticAsset:spawn(ignore)
	if not ignore and self:isSpawned() then
		self._logger:error("runtime bug - already spawned")
		return
	end

	for _, obj in pairs(self._assets) do
		if obj.category == Unit.Category.STRUCTURE then
			coalition.addStaticObject(obj.countryid, obj.data)
		elseif isUnitGroup(obj.category) then
			coalition.addGroup(obj.countryid, obj.category, obj.data)
		end
	end

	AssetBase.spawn(self)

	for _, goal in pairs(self._deathgoals) do
		goal:onSpawn()
	end

	self:getStatus()
end

function StaticAsset:despawn()
	for name, obj in pairs(self._assets) do
		if obj.category == Unit.Category.STRUCTURE then
			local structure = StaticObject.getByName(name)
			structure:destroy()
		elseif isUnitGroup(obj.category) then
			local group = Group.getByName(name)
			group:destroy()
		end
	end

	AssetBase.despawn(self)
end

-- copies live groups in the same order as the original template,
-- and removes group and unit ids inserted by DCS
local function filterTemplateData(template, aliveGroups)
	local out = {}
	for _, grp in ipairs(template) do
		table.insert(out, utils.deepcopy(aliveGroups[grp.data.name]))
	end
	for _, grp in ipairs(out) do
		grp.data.groupId = nil
		if grp.data.units ~= nil then
			for _, unit in ipairs(grp.data.units) do
				unit.unitId = nil
			end
		end
	end
	return out
end

function StaticAsset:marshal()
	local tbl = AssetBase.marshal(self)
	if tbl == nil then
		return nil
	end
	if self.regenerate then
		tbl._tpldata = self._tpldata
	else
		tbl._tpldata = filterTemplateData(self._tpldata, self._assets)
	end
	if next(tbl._tpldata) == nil then
		return nil
	end
	return tbl
end

return StaticAsset
