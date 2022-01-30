--[[
-- SPDX-License-Identifier: LGPL-3.0
--
-- Provides functions for handling templates.
--]]

require("lfs")
local class = require("libs.class")
local utils = require("libs.utils")
local enum  = require("dct.enum")
local vector= require("dct.libs.vector")
local Goal  = require("dct.Goal")
local STM   = require("dct.templates.STM")

--[[
-- represents the amount of damage that can be taken before
-- that state is no longer considered valid.
-- example:
--   goal: damage unit to 85% of original health (aka incapacitate)
--
--   unit.health = .85
--   goal = 85
--   damage_taken = (1 - unit.health) * 100 = 15
--
--   if damage_taken > goal = goal met, in this case we have
--   not met our greater than 85% damage.
--]]
local damage = {
	["UNDAMAGED"]     = 10,
	["DAMAGED"]       = 45,
	["INCAPACITATED"] = 75,
	["DESTROYED"]     = 90,
}

--[[
-- generates a death goal from an object's name by
-- using keywords.
--]]
local function goalFromName(name, objtype)
	local goal = {}
	local goalvalid = false
	name = string.upper(name)

	for k, v in pairs(Goal.priority) do
		local index = string.find(name, k)
		if index ~= nil then
			goal.priority = v
			goalvalid = true
			break
		end
	end

	for k, v in pairs(damage) do
		local index = string.find(name, k)
		if index ~= nil then
			goal.value = v
			goalvalid = true
			break
		end
	end

	if not goalvalid then
		return nil
	end
	if goal.priority == nil then
		goal.priority = Goal.priority.PRIMARY
	end
	if goal.value == nil then
		goal.value = damage.INCAPACITATED
	end
	goal.objtype  = objtype
	goal.goaltype = Goal.goaltype.DAMAGE
	return goal
end

local function makeNamesUnique(data)
	for _, grp in ipairs(data) do
		grp.data.name = grp.data.name.." #"..
			dct.Theater.singleton():getcntr()
		for _, v in ipairs(grp.data.units or {}) do
			v.name = v.name.." #"..dct.Theater.singleton():getcntr()
		end
	end
end

local function sanitizeIds(data, tpl)
	env.info("SANITIZING")
	if data ~= nil and data.groupId ~= nil then
		tpl.groupNames[data.groupId] = data.name
		data.groupId = nil
	end
	if data ~= nil and data.unitId ~= nil then
		tpl.unitNames[data.unitId] = data.name
		data.unitId = nil
	end
end

local function overrideUnitOptions(unit, key, tpl, basename)
	if unit.playerCanDrive ~= nil then
		unit.playerCanDrive = false
	end
	unit.dct_deathgoal = goalFromName(unit.name, Goal.objtype.UNIT)
	if unit.dct_deathgoal ~= nil then
		tpl.hasDeathGoals = true
	end
	unit.name = basename.."-"..key
	sanitizeIds(unit, tpl)
end

local function overrideGroupOptions(grp, idx, tpl)
	if grp.category == enum.UNIT_CAT_SCENERY then
		return
	end

	local opts = {
		visible        = true,
		uncontrollable = true,
		lateActivation = false,
	}

	for k, v in pairs(opts) do
		if grp[k] ~= nil then grp[k] = v end
	end

	-- check if the group is intended to be replaced with a map marker
	local markLabel = string.match(grp.data.name, "^[Mm][Aa][Rr][Kk]=(.+)$")
	if markLabel ~= nil then
		grp.mark = {
			label = markLabel,
			x = grp.data.x,
			z = grp.data.y,
		}
		return
	end

	-- check if the group is intended to be replaced with marking smoke
	local smokeColor = string.match(grp.data.name, "^[Ss][Mm][Oo][Kk][Ee]=(.+)$")
	if smokeColor ~= nil then
		grp.smoke = {
			color = smokeColor,
			x = grp.data.x,
			y = land.getHeight(grp.data),
			z = grp.data.y,
		}
		return
	end

	-- otherwise process the group normally
	local goaltype = Goal.objtype.GROUP
	if grp.category == Unit.Category.STRUCTURE then
		goaltype = Goal.objtype.STATIC
	end

	grp.data.start_time = 0
	grp.data.dct_deathgoal = goalFromName(grp.data.name, goaltype)
	if grp.data.dct_deathgoal ~= nil then
		tpl.hasDeathGoals = true
	end

	local side = coalition.getCountryCoalition(grp.countryid)
	grp.data.name = string.format("%s_%s %d %s %d", tpl.regionname, tpl.name,
		side, utils.getkey(Unit.Category, grp.category), idx)

	sanitizeIds(grp.data, tpl)

	for i, unit in ipairs(grp.data.units or {}) do
		overrideUnitOptions(unit, i, tpl, grp.data.name)
	end
end

local function checktpldata(_, tpl)
	-- loop over all tpldata and process names and existence of deathgoals
	for idx, grp in ipairs(tpl.tpldata) do
		overrideGroupOptions(grp, idx, tpl)
	end
	return true
end

local function checkbldgdata(keydata, tpl)
	if next(tpl[keydata.name]) ~= nil and tpl.tpldata == nil then
		tpl.tpldata = {}
	end

	for _, bldg in ipairs(tpl[keydata.name]) do
		local bldgdata = {}
		bldgdata.category = enum.UNIT_CAT_SCENERY
		bldgdata.data = {
			["dct_deathgoal"] = goalFromName(bldg.goal,
				Goal.objtype.SCENERY),
			["name"] = tostring(bldg.id),
		}
		local sceneryobject = { id_ = tonumber(bldgdata.data.name), }
		utils.mergetables(bldgdata.data,
			vector.Vector2D(Object.getPoint(sceneryobject)):raw())
		table.insert(tpl.tpldata, bldgdata)
		if bldgdata.data.dct_deathgoal ~= nil then
			tpl.hasDeathGoals = true
		end
	end
	return true
end

local function checkobjtype(keydata, tbl)
	if type(tbl[keydata.name]) == "number" and
		utils.getkey(enum.assetType, tbl[keydata.name]) ~= nil then
		return true
	elseif type(tbl[keydata.name]) == "string" and
		enum.assetType[string.upper(tbl[keydata.name])] ~= nil then
		tbl[keydata.name] = enum.assetType[string.upper(tbl[keydata.name])]
		return true
	end
	return false
end

local function checkside(keydata, tbl)
	if type(tbl[keydata.name]) == "number" and
		utils.getkey(coalition.side, tbl[keydata.name]) ~= nil then
		return true
	elseif type(tbl[keydata.name]) == "string" and
		coalition.side[string.upper(tbl[keydata.name])] ~= nil then
		tbl[keydata.name] = coalition.side[string.upper(tbl[keydata.name])]
		return true
	elseif tbl[keydata.name] == nil then
		return true
	end
	return false
end

local function checkDesc(keydata, tbl)
	local val = tbl[keydata.name]
	return val == nil or type(val) == "string"
end

local function checktakeoff(keydata, tpl)
	local allowed = {
		["inair"]   = AI.Task.WaypointType.TURNING_POINT,
		["runway"]  = AI.Task.WaypointType.TAKEOFF,
		["parking"] = AI.Task.WaypointType.TAKEOFF_PARKING,
	}

	local val = allowed[tpl[keydata.name]]
	if val then
		tpl[keydata.name] = val
		return true
	end
	return false
end

local function checkrecovery(keydata, tpl)
	local allowed = {
		["terminal"] = true,
		["land"]     = true,
		["taxi"]     = true,
	}

	if allowed[tpl[keydata.name]] then
		return true
	end
	return false
end

local function checkmsntype(keydata, tbl)
	if tbl[keydata.name] == nil then
		return true
	end
	if type(tbl[keydata.name]) ~= "table" then
		return false, "value must be a table or nil"
	end
	local msnlist = {}
	for _, msntype in pairs(tbl[keydata.name]) do
		local msnstr = string.upper(msntype)
		if type(msntype) ~= "string" or
		   enum.missionType[msnstr] == nil then
			return false, "invalid mission type: "..tostring(msnstr)
		end
		msnlist[msnstr] = enum.missionType[msnstr]
	end
	tbl[keydata.name] = msnlist
	return true
end

local function check_payload_limits(keydata, tbl)
	local newlimits = {}
	for wpncat, val in pairs(tbl[keydata.name]) do
		local w = enum.weaponCategory[string.upper(wpncat)]
		if w == nil then
			return false
		end
		newlimits[w] = val
	end
	tbl[keydata.name] = newlimits
	return true
end

local function checkLocation(keydata, tbl)
	local val = tbl[keydata.name]
	if val == nil then
		return true
	end
	if type(val) ~= "table" then
		return false, "must be a table"
	end
	if type(val.y) == "number" and val.z == nil then
		val.z = val.y
		val.y = nil
	end
	if type(val.x) == "number" and type(val.z) == "number" then
		if type(val.y) ~= "number" then
			val.y = land.getHeight({ x = val.x, y = val.z })
		end
		return true
	end
	return false, "must contain 2 or 3 numeric coordinate values"
end

local function checkExtraMarks(keydata, tbl)
	for _, val in ipairs(tbl[keydata.name]) do
		if type(val.label) ~= "string" or
		   type(val.x) ~= "number" or
		   type(val.z) ~= "number" then
			return false
		end
	end
	return true
end

local function checkSmoke(keydata, tbl)
	for _, val in ipairs(tbl[keydata.name]) do
		if type(val.x) ~= "number" or
		   type(val.y) ~= "number" or
		   type(val.z) ~= "number" then
			return false, "Smoke coordinates must be specified"
		end
		if trigger.smokeColor[val.color] == nil then
			local colors = {}
			for name, _ in pairs(trigger.smokeColor) do
				table.insert(colors, string.format("'%s'", name))
			end
			return false, string.format(
				"Invalid smoke color: '%s', accepted values: %s",
				val.color, table.concat(colors, ", "))
		end
	end
	return true
end

local function checkTacan(keydata, tbl)
	local Tacan = require("dct.data.tacan")
	local channel = tbl[keydata.name]
	if channel ~= nil then
		tbl[keydata.name] = Tacan.decodeChannel(channel)
		if tbl[keydata.name] == nil then
			return false, string.format(
				"invalid channel: '%s'; "..
				"must start with a string containing a number [1-126], followed by X or Y",
				tostring(channel))
		end
	end
	return true
end

local function checkIcls(keydata, tbl)
	local channel = tbl[keydata.name]
	if channel == nil or
	   type(channel) == "number" and channel >= 1 and channel <= 20 then
		return true
	else
		return false, string.format("invalid channel: %s; "..
			"must be a number in the range [1-20]", tostring(channel))
	end
end

local function getkeys(objtype)
	local notpldata = {
		[enum.assetType.AIRSPACE]       = true,
		[enum.assetType.AIRBASE]        = true,
		[enum.assetType.SQUADRONPLAYER] = true,
	}
	local defaultintel = 0
	if objtype == enum.assetType.AIRBASE then
		defaultintel = 5
	end

	local keys = {
		{
			["name"]  = "name",
			["type"]  = "string",
		}, {
			["name"]  = "regionname",
			["type"]  = "string",
		}, {
			["name"]  = "coalition",
			["check"] = checkside,
		}, {
			["name"]    = "uniquenames",
			["type"]    = "boolean",
			["default"] = false,
		}, {
			["name"]    = "ignore",
			["type"]    = "boolean",
			["default"] = false,
		}, {
			["name"]    = "regenerate",
			["type"]    = "boolean",
			["default"] = false,
		}, {
			["name"]    = "priority",
			["type"]    = "number",
			["default"] = enum.assetTypePriority[objtype] or 1000,
		}, {
			["name"]    = "regionprio",
			["type"]    = "number",
		}, {
			["name"]    = "intel",
			["type"]    = "number",
			["default"] = defaultintel,
		}, {
			["name"]    = "spawnalways",
			["type"]    = "boolean",
			["default"] = false,
		}, {
			["name"]    = "cost",
			["type"]    = "number",
			["default"] = 0,
		}, {
			["name"]    = "desc",
			["check"]   = checkDesc,
		}, {
			["name"]    = "codename",
			["type"]    = "string",
			["default"] = "default codename",
		}, {
			["name"]    = "theater",
			["type"]    = "string",
			["default"] = env.mission.theatre,
		}, {
			["name"]    = "minagents",
			["type"]    = "number",
			["default"] = 1,
		}, {
			["name"]    = "backfill",
			["type"]    = "boolean",
			["default"] = false,
		}, {
			["name"]    = "location",
			["check"]   = checkLocation,
		}, {
			["name"]    = "extramarks",
			["default"] = {},
			["check"]   = checkExtraMarks,
		}, {
			["name"]    = "smoke",
			["default"] = {},
			["check"]   = checkSmoke,
		}, {
			["name"]    = "nocull",
			["type"]	= "boolean",
			["default"] = false,
		}, {
			["name"]    = "ondemand",
			["type"]	= "boolean",
			["default"] = false,
		},
	}

	if notpldata[objtype] == nil then
		table.insert(keys, {
			["name"]    = "buildings",
			["type"]    = "table",
			["default"] = {},
			["check"] = checkbldgdata,})
		table.insert(keys, {
			["name"]  = "tpldata",
			["type"]  = "table",
			["check"] = checktpldata,})
	end

	if objtype == enum.assetType.AIRSPACE then
		table.insert(keys, {
			["name"]  = "radius",
			["type"]  = "number",
			["default"] = 55560,})
	end

	if objtype == enum.assetType.AIRBASE then
		table.insert(keys, {
			["name"]  = "subordinates",
			["type"]  = "table", })
		table.insert(keys, {
			["name"]    = "takeofftype",
			["type"]    = "string",
			["default"] = "inair",
			["check"]   = checktakeoff,})
		table.insert(keys, {
			["name"]    = "recoverytype",
			["type"]    = "string",
			["default"] = "terminal",
			["check"]   = checkrecovery,})
		table.insert(keys, {
			["name"]    = "capturable",
			["type"]    = "boolean",
			["default"] = false,})
		table.insert(keys, {
			["name"]    = "tacan",
			["check"]   = checkTacan,})
		table.insert(keys, {
			["name"]    = "icls",
			["check"]   = checkIcls,})
	end

	if objtype == enum.assetType.SQUADRONPLAYER then
		table.insert(keys, {
			["name"]    = "ato",
			["check"]   = checkmsntype
		})

		table.insert(keys, {
			["name"]    = "payloadlimits",
			["type"]    = "table",
			["check"]   = check_payload_limits,
			["default"] = dct.settings.payloadlimits,
		})
	end

	if objtype == enum.assetType.SQUADRONPLAYER or
	   objtype == enum.assetType.AIRBASE then
		table.insert(keys, {
			["name"]  = "players",
			["type"]  = "table",
			["default"] = {},
		})
	end
	return keys
end

--[[
--  Template class
--    base class that reads in a template file and organizes
--    the data for spawning.
--
--    properties
--    ----------
--      * objtype   - represents an abstract type of asset
--      * name      - name of the template
--      * region    - the region name the template belongs too
--      * coalition - which coalition the template belongs too
--                    templates can only belong to one side and
--                    one side only
--      * desc      - description of the template, used to generate
--		              mission breifings from
--
--    Storage
--    -------
--    tpldata = {
--      # = {
--          category = Unit.Category
--          countryid = id,
--          data      = {
--            # group def members
--            dct_deathgoal = goalspec
--    }}}
--
--    DCT File
--    --------
--      Required Keys:
--        * objtype - the kind of "game object" the template represents
--
--      Optional Keys:
--        * uniquenames - when a Template's data is copied the group and
--              unit names a guaranteed to be unique if true
--
--]]
local Template = class()
function Template:__init(data)
	assert(data and type(data) == "table", "value error: data required")
	self.hasDeathGoals = false
	self.groupNames    = {}
	self.unitNames     = {}
	utils.mergetables(self, utils.deepcopy(data))
	self:validate()
	self.checklocation = nil
	self.fromFile = nil
end

Template.checkLocation = checkLocation

-- filter units tagged with special values into those values,
-- and remove the units from the template
function Template:_processTagUnits()
	local del = {}
	for idx, grp in ipairs(self.tpldata or {}) do
		if grp.mark ~= nil then
			table.insert(self.extramarks, grp.mark)
			table.insert(del, idx)
		end
		if grp.smoke ~= nil then
			table.insert(self.smoke, grp.smoke)
			table.insert(del, idx)
		end
	end
	-- very naive reverse deletion algorithm, could be improved
	for i = #del, 1, -1 do
		table.remove(self.tpldata, del[i])
	end
end

-- checks if either there is a manually defined coalition,
-- or if all units in the template are of the same coalition
function Template:_validateCoalition()
	if self.coalition == nil then
		for _, grp in ipairs(self.tpldata or {}) do
			if grp.countryid ~= nil then
				local groupCoalition = coalition.getCountryCoalition(grp.countryid)
				self.coalition = self.coalition or groupCoalition
				assert(self.coalition == groupCoalition, string.format(
					"template('%s') contains mixed unit coalitions; one group belongs to "..
					"country '%s', which is in the '%s' coalition, "..
					"but previous groups are in the '%s' coalition\n"..
					"note: coalition checks are made according to the .miz, not the .stm\n"..
					"note: if this is intentional, consider setting the template's "..
					"coalition manually",
					self.name,
					country.name[grp.countryid],
					utils.getkey(coalition.side, groupCoalition),
					utils.getkey(coalition.side, self.coalition)
				))
			end
		end
	end
	assert(self.coalition ~= nil, string.format(
		"cannot determine the coalition of template('%s') based on its units; "..
		"please set it manually in the .dct", self.name))
end

function Template:validate()
	utils.checkkeys({ [1] = {
		["name"]  = "objtype",
		["type"]  = "string",
		["check"] = checkobjtype,
	},}, self)

	utils.checkkeys(getkeys(self.objtype), self)
	self:_processTagUnits()
	self:_validateCoalition()

	-- Re-check smoke after processing tag units
	utils.checkkeys({{
		["name"]    = "smoke",
		["default"] = {},
		["check"]   = checkSmoke,
	}}, self)
end

-- PUBLIC INTERFACE
function Template:copyData()
	local copy = utils.deepcopy(self.tpldata)
	if self.uniquenames == true then
		makeNamesUnique(copy)
	end
	return copy
end

function Template.fromFile(region, dctfile, stmfile)
	assert(region ~= nil, "region is required")
	assert(dctfile ~= nil, "dctfile is required")

	local template = utils.readlua(dctfile)
	if template.metadata then
		template = template.metadata
	end
	template.regionname = region.name
	template.regionprio = region.priority
	template.path = dctfile
	if stmfile ~= nil then
		template = utils.mergetables(
			STM.transform(utils.readlua(stmfile, "staticTemplate")),
			template)
	end
	return Template(template)
end

return Template
