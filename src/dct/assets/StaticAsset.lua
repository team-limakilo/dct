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
local check    = require("libs.check")
local enum     = require("dct.enum")
local dctutils = require("dct.utils")
local vector   = require("dct.libs.vector")
local Goal     = require("dct.Goal")
local AssetBase= require("dct.assets.AssetBase")

local SMOKE_INTERVAL = 5 * 60

local function isUnitGroup(category)
	return category == Unit.Category.AIRPLANE
		or category == Unit.Category.HELICOPTER
		or category == Unit.Category.GROUND_UNIT
		or category == Unit.Category.SHIP
end

local function isAirborne(category)
	return category == Unit.Category.AIRPLANE
		or category == Unit.Category.HELICOPTER
end

local function isStatic(category)
	return category == Unit.Category.STRUCTURE or
	       category == enum.UNIT_CAT_SCENERY
end

local StaticAsset = require("libs.namedclass")("StaticAsset", AssetBase)
function StaticAsset:__init(template)
	self._maxdeathgoals = 0
	self._curdeathgoals = 0
	self._status        = 0
	self._deathgoals    = {}
	self._assets        = {}
	self._groups        = {}
	self._units         = {}
	self._tplGroupNames = {}
	self._tplUnitNames  = {}
	self._initialized   = {}
	self._eventhandlers = {
		[world.event.S_EVENT_DEAD] = self.handleDead,
	}
	AssetBase.__init(self, template)
	self:_addMarshalNames({
		"_hasDeathGoals",
		"_maxdeathgoals",
		"_tplGroupNames",
		"_tplUnitNames",
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
		enum.assetType.ARTILLERY,
	}
end

function StaticAsset:_completeinit(template)
	AssetBase._completeinit(self, template)
	self._hasDeathGoals = template.hasDeathGoals
	self._tplGroupNames = template.groupNames
	self._tplUnitNames  = template.unitNames
	self._tpldata       = template:copyData()

	if next(template.smoke) ~= nil then
		self._smoke = template.smoke
		self:_addMarshalNames({ "_smoke" })
	end
end

--[[
-- Adds a death goal to the asset if it's a primary goal
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
function StaticAsset:_removeDeathGoal(name)
	assert(name ~= nil and type(name) == "string",
		"value error: name must be provided")

	if self._deathgoals[name] == nil then
		return
	end

	self._logger:debug("_removeDeathGoal() - obj name: %s", name)

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
			AssetBase.defaultgoal(isStatic(category)))
	end
end

--[[
-- Removes unit goals if all units have a goal, as well as the group,
-- leaving only the group's goal. This avoids automatic mission editor
-- unit naming from creating unecessary goals, which affects how the mission
-- status is displayed.
--]]
function StaticAsset:_removeDuplicateGoals(grpdata)
	if grpdata.units == nil or next(grpdata.units) == nil or
	   self._deathgoals[grpdata.name] == nil then
		-- No point in removing unit goals
		return
	end
	for _, unit in ipairs(grpdata.units) do
		if self._deathgoals[unit.name] == nil then
			-- Abort if at least one unit has no goals, meaning the mission
			-- creator has only set specific units as "VIPs" alongside a
			-- group destruction goal.
			return
		end
	end
	-- At this point we know both that there is a group goal, and that all units
	-- also have goals, so we prune unit goals.
	self._logger:warn("group '%s' and all of its units have goals; "..
		"removing unit goals and keeping group goal", grpdata.name)
	for _, unit in ipairs(grpdata.units) do
		self:_removeDeathGoal(unit.name)
	end
end

--[[
-- Adds an object (group or static) to the monitored list for this
-- asset. This list will be needed later to save state.
--]]
function StaticAsset:_setup()
	for _, grp in ipairs(self._tpldata) do
		self:_setupDeathGoal(grp.data, grp.category, grp.countryid)
		self:_removeDuplicateGoals(grp.data)
		self._assets[grp.data.name] = utils.deepcopy(grp)

		local route = grp.data.route
		if route ~= nil and route.points ~= nil and #route.points > 1 then
			self.isMobile = true
		end
	end

	local goals = 0
	for _ in pairs(self._deathgoals) do
		goals = goals + 1
	end
	self._logger:debug("total death goals: %d", goals)

	if next(self._deathgoals) == nil then
		self._logger:error("runtime error: must have a deathgoal, deleting")
		self:setDead(true)
	end
end

function StaticAsset:getTemplateData()
	return self._tpldata
end

function StaticAsset:_refreshSmoke(time)
	if self:isDead() then
		return
	end
	for id, smoke in pairs(self._smoke) do
		self._logger:debug("refreshing smoke; id: %d, color: %s", id, smoke.color)
		trigger.action.smoke(smoke, trigger.smokeColor[smoke.color])
	end
	return time + SMOKE_INTERVAL
end

function StaticAsset:setTargeted(side, val)
	AssetBase.setTargeted(self, side, val)

	if self._smoke ~= nil and dctutils.getenemy(self.owner) == side then
		local targeted = self:isTargeted(side)
		if targeted and self._smokeFunc == nil then
			self._smokeFunc = timer.scheduleFunction(
				self._refreshSmoke, self, timer.getTime() + 30)
		elseif not targeted and self._smokeFunc ~= nil then
			timer.removeFunction(self._smokeFunc)
			self._smokeFunc = nil
		end
	end
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
		for name, _ in pairs(self._assets) do
			local grp = Group.getByName(name)
			if grp ~= nil then
				local unit = grp:getUnit(1)
				if unit ~= nil then
					return vector.Vector3D(unit:getPoint())
				end
			end
		end
	end
	return self:getLocation()
end

function StaticAsset:getStaticTargetLocations()
	local locations = {}
	for name, grp in pairs(self._assets) do
		if isStatic(grp.category) then
			local goal = self._deathgoals[name]
			if goal ~= nil and goal.priority == Goal.priority.PRIMARY then
				table.insert(locations, {
					desc = grp.data.desc,
					x = grp.data.x,
					y = land.getHeight(grp.data),
					z = grp.data.y,
				})
			end
		end
	end
	return locations
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

-- Clean up units which didn't have death events (2.7.12 bug)
function StaticAsset:cleanup()
	if not self:isSpawned() then return end

	for grpname, group in pairs(self._assets) do
		local units = group.data.units or {}
		for i = #units, 1, -1 do
			local name = units[i].name
			local unit = Unit.getByName(name)
			-- Life of 1 or less is considered "dead" by DCS
			if unit ~= nil and unit:getLife() <= 1 then
				self._logger:debug(
					"cleanup() - unit '%s' is dead; calling handleDead()", name)
				self:handleDead({
					id = world.event.S_EVENT_DEAD,
					time = timer.getTime(),
					initiator = unit,
				})
			elseif unit == nil then
				self._logger:debug(
					"cleanup() - unit '%s' does not exist; removing", name)
				self:_removeDeathGoal(name)
				table.remove(units, i)
				if next(units) == nil then
					self:_removeDeathGoal(grpname)
					self._assets[grpname] = nil
					break
				end
			end
		end
	end
end

function StaticAsset:update()
	if not self:isSpawned() then return end

	local cnt = 0
	for name, goal in pairs(self._deathgoals) do
		cnt = cnt + 1
		if goal:checkComplete() then
			self:_removeDeathGoal(name)
		end
	end
	self:cleanup()
	self._logger:debug("update() - max goals: %d; cur goals: %d; checked: %d",
		self._maxdeathgoals, self._curdeathgoals, cnt)
end

function StaticAsset:handleDead(event)
	local obj = event.initiator

	-- remove dead units and their respective goals
	local unitname = tostring(obj:getName())
	if obj:getCategory() == Object.Category.UNIT then
		local grp = obj:getGroup()
		local grpname = grp and grp:getName()
		local asset = self._assets[grpname]
		local units = asset.data.units
		for i = #units, 1, -1 do
			if units[i].name == unitname then
				self:_removeDeathGoal(unitname)
				table.remove(units, i)
				break
			end
		end
		if next(units) == nil then
			self:_removeDeathGoal(grpname)
			self._assets[grpname] = nil
		end
	else
		self:_removeDeathGoal(unitname)
		self._assets[unitname] = nil
	end
end

local function remapID(idmap, objmap, tbl, tblkey)
	check.table(idmap)
	check.table(tbl)
	check.string(tblkey)
	local oldid = tbl[tblkey]
	local name = idmap[oldid]
	local obj = objmap[name]
	local newid
	if obj ~= nil then
		newid = obj:getID()
		tbl[tblkey] = newid
	end
	return oldid, newid
end

function StaticAsset:_transformTask(task)
	if task.id == "ComboTask" then
		for _, subtask in pairs(task.params.tasks) do
			self:_transformTask(subtask)
		end
	end

	-- remap target IDs in the template to the spawned IDs
	if task.params.groupId ~= nil then
		local old, new =
			remapID(self._tplGroupNames, self._groups, task.params, "groupId")
		self._logger:debug("remapped task groupId: %d -> %s", old, tostring(new))
	end

	if task.params.unitId ~= nil then
		local old, new =
			remapID(self._tplUnitNames, self._units, task.params, "unitId")
		self._logger:debug("remapped task unitId: %d -> %s", old, tostring(new))
	end

	-- the "action" sub-key has the same structure as "task"
	if task.params.action ~= nil then
		self:_transformTask(task.params.action)
	end
end

function StaticAsset:_transformPoints(points)
	for _, point in pairs(points) do
		if point.task ~= nil then
			self:_transformTask(point.task)
		end
	end
end

function StaticAsset:_afterspawn(group, obj)
	local points = obj.data.route and obj.data.route.points
	if points ~= nil then
		if not self._initialized[obj.data.name] then
			self:_transformPoints(points)
		end
		-- reapply transformed waypoints
		group:getController():setTask({
			id = "Mission",
			route = {
				airborne = isAirborne(obj.category),
				points = points,
			}
		})
	end
	self._initialized[obj.data.name] = true
end

function StaticAsset:spawn(ignore)
	if not ignore and self:isSpawned() then
		self._logger:error("runtime bug - already spawned")
		return
	end

	local spawnedObjects = {}

	for _, obj in pairs(self._assets) do
		if obj.category == Unit.Category.STRUCTURE then
			local static = coalition.addStaticObject(obj.countryid, obj.data)
			table.insert(spawnedObjects, { static, obj })
		elseif isUnitGroup(obj.category) then
			local group = coalition.addGroup(obj.countryid, obj.category, obj.data)
			table.insert(spawnedObjects, { group, obj })

			-- record spawned groups and units for later lookups
			self._groups[group:getName()] = group
			for _, unit in pairs(group:getUnits()) do
				self._units[unit:getName()] = unit
			end
		end
	end

	for _, spawned in pairs(spawnedObjects) do
		self:_afterspawn(unpack(spawned))
	end

	AssetBase.spawn(self)

	for name, goal in pairs(self._deathgoals) do
		goal:onSpawn()
		if goal:isComplete() then
			self:_removeDeathGoal(name)
		end
	end

	self:getStatus()
end

function StaticAsset:despawn()
	self:update()

	for name, obj in pairs(self._assets) do
		if obj.category == Unit.Category.STRUCTURE then
			local structure = StaticObject.getByName(name)
			if structure ~= nil then
				structure:destroy()
			end
		elseif isUnitGroup(obj.category) then
			local group = Group.getByName(name)
			if group ~= nil then
				group:destroy()
			end
		end
	end

	self._groups = {}
	self._units  = {}
	AssetBase.despawn(self)
end

-- copies live groups in the same order as the original template,
-- and removes group and unit ids inserted by DCS
local function filterTemplateData(template, aliveGroups)
	local out = {}
	for _, grp in ipairs(template) do
		local alivegrp = utils.deepcopy(aliveGroups[grp.data.name])
		if alivegrp ~= nil then
			alivegrp.data.route = grp.data.route
			table.insert(out, alivegrp)
		end
	end
	for _, grp in ipairs(out) do
		grp.data.unitId = nil
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
