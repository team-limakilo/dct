--[[
-- SPDX-License-Identifier: LGPL-3.0
--
-- Provides functions to define and manage goals.
--]]

local class    = require("libs.class")
local enums    = require("dct.goals.enum")
local BaseGoal = require("dct.goals.BaseGoal")
local Logger   = require("dct.libs.Logger").getByName("DamageGoal")

local scenery_mark_id = 56000
local marked_scenery = {}

local function postostring(pos)
	return string.format("{ x = %s, y = %s, z = %s }", tostring(pos.x), tostring(pos.y), tostring(pos.z))
end

local function get_scenery_id(tplname, desc)
	return function(id)
		if not marked_scenery[id] then
			local tbl = { id_ = tonumber(id), }
			local pos = SceneryObject.getPoint(tbl)
			local fmt = string.format("%s: %s", tostring(desc), tostring(id))
			Logger:info("SceneryObject - %s - %s", fmt, postostring(pos))
			trigger.action.markToAll(scenery_mark_id, fmt, pos)
			scenery_mark_id = scenery_mark_id + 1
		end
		marked_scenery[id] = true
		return { id_ = tonumber(id), }
	end
end

-- counts the number of alive units in the group manually, because
-- Group.getSize() can return an outdated value during death events
local function get_group_size(grp)
	local alive = 0
	for _, unit in pairs(grp:getUnits()) do
		-- Unit.getLife() uses a value of 1.00 to indicate dying units
		-- ie. sinking ships and burning ammo dumps
		if unit ~= nil and unit:getLife() > 1 then
			alive = alive + 1
		end
	end
	return alive
end

local function getobject(objtype, name, tplname, desc)
	local getobj = {
		[enums.objtype.UNIT]    = Unit.getByName,
		[enums.objtype.STATIC]  = StaticObject.getByName,
		[enums.objtype.GROUP]   = Group.getByName,
		[enums.objtype.SCENERY] = get_scenery_id(tplname, desc),
	}
	local getlifefncs = {
		[enums.objtype.UNIT]    = Unit.getLife,
		[enums.objtype.STATIC]  = StaticObject.getLife,
		[enums.objtype.GROUP]   = get_group_size,
		[enums.objtype.SCENERY] = SceneryObject.getLife,
	}

	local obj = getobj[objtype](name)
	return obj, getlifefncs[objtype]
end

local DamageGoal = class(BaseGoal)
function DamageGoal:__init(data)
	assert(type(data.value) == 'number',
		"value error: data.value must be a number")
	assert(data.value >= 0 and data.value <= 100,
		"value error: data.value must be between 0 and 100")
	BaseGoal.__init(self, data)
	self._tgtdamage = data.value
	self.tplname = data.tplname
	self.desc = data.desc
end

function DamageGoal:_afterspawn()
	if self._maxlife ~= nil then return end

	local obj, getlife = getobject(self.objtype, self.name, self.tplname, self.desc)
	if obj == nil or not Object.isExist(obj) and not Group.isExist(obj) then
		Logger:error("_afterspawn() - object '%s' doesn't exist, presumed dead",
			self.name)
		self:_setComplete()
		return
	end

	local life = getlife(obj)
	if life == nil or life < 1 then
		Logger:warn("_afterspawn() - object '%s' initial life value is nil or "..
			"below 1: %s", tostring(self.name), tostring(life))
		self._maxlife = 1
	else
		self._maxlife = life
	end

	Logger:debug("_afterspawn() - goal: %s",
		require("libs.json"):encode_pretty(self))
end

-- Note: game objects can be removed out from under us, so
-- verify the lookup by name yields an object before using it
function DamageGoal:checkComplete()
	if self:isComplete() then return true end
	local status = self:getStatus()

	Logger:debug("checkComplete() - status: %.2f%%", status)

	if status >= self._tgtdamage then
		return self:_setComplete()
	end
end

-- returns the completion percentage of the damage goal
function DamageGoal:getStatus()
	if self:isComplete() then return 100 end

	-- assume assets that were never spawned are intact
	if self._maxlife == nil then return 0 end

	local health = 0
	local obj, getlife = getobject(self.objtype, self.name)
	if obj ~= nil then
		health = getlife(obj)
		if health == nil then
			Logger:warn("getStatus() - object '%s' health value is nil", self.name)
			health = 0
		end
	end

	-- some scenery objects can return bugged life values before they're damaged,
	-- so we're fixing them now...
	if health > self._maxlife then
		Logger:warn("getStatus() - object '%s' health is greater than maxlife; fixed",
			self.name)
		self._maxlife = health
	end

	Logger:debug("getStatus() - name: '%s'; health: %.2f; maxlife: %.2f",
		self.name, health, self._maxlife)

	return (1 - (health/self._maxlife)) * 100
end

return DamageGoal
