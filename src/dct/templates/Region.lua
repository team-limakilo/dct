--[[
-- SPDX-License-Identifier: LGPL-3.0
--
-- Defines the Region class.
--]]

local lfs        = require("lfs")
local math       = require("math")
local class      = require("libs.namedclass")
local utils      = require("libs.utils")
local dctenums   = require("dct.enum")
local dctutils   = require("dct.utils")
local vector     = require("dct.libs.vector")
local Marshallable = require("dct.libs.Marshallable")
local Template   = require("dct.templates.Template")
local Logger     = dct.Logger.getByName("Region")

local tplkind = {
	["TEMPLATE"]  = 1,
	["EXCLUSION"] = 2,
}

local DOMAIN = {
	["AIR"]  = "air",
	["LAND"] = "land",
	["SEA"]  = "sea",
}

local function processlimits(_, tbl)
	-- process limits; convert the human readable asset type names into
	-- their numerical equivalents.
	local limits = {}
	for key, data in pairs(tbl.limits) do
		local typenum = dctenums.assetType[string.upper(key)]
		if typenum == nil then
			Logger:warn("invalid asset type '%s' "..
				"found in limits definition in file: %s",
				key, tbl.defpath or "nil")
		else
			limits[typenum] = data
		end
	end
	tbl.limits = limits
	return true
end

local function processlinks(keydata, tbl)
	local links = {}
	for k, v in pairs(tbl[keydata.name]) do
		local d = string.upper(k)
		if DOMAIN[d] ~= nil then
			links[DOMAIN[d]] = v
		end
	end
	tbl[keydata.name] = links
	return true
end

local function loadMetadata(self, regiondefpath)
	Logger:debug("=> regiondefpath: %s", regiondefpath)
	local keys = {
		{
			["name"] = "name",
			["type"] = "string",
		}, {
			["name"] = "priority",
			["type"] = "number",
		}, {
			["name"] = "location",
			["check"] = Template.checkLocation
		}, {
			["name"] = "limits",
			["type"] = "table",
			["default"] = {},
			["check"] = processlimits,
		}, {
			["name"] = "airspace",
			["type"] = "boolean",
			["default"] = true,
		}, {
			["name"] = "altitude_floor",
			["type"] = "number",
			["default"] = 914.4, -- meters; 3000ft msl
		}, {
			["name"] = "links",
			["type"] = "table",
			["check"] = processlinks,
			["default"] = {},
		}
	}

	local region = utils.readlua(regiondefpath)
	if region.region then
		region = region.region
	end
	region.defpath = regiondefpath
	region.path = regiondefpath
	utils.checkkeys(keys, region)
	region.path = nil
	utils.mergetables(self, region)
end

local function getTemplates(self, basepath)
	local ignorepaths = {
		["."] = true,
		[".."] = true,
		["region.def"] = true,
	}

	Logger:debug("=> basepath: %s", basepath)
	for filename in lfs.dir(basepath) do
		if ignorepaths[filename] == nil then
			local fpath = basepath..utils.sep..filename
			local fattr = lfs.attributes(fpath)
			if fattr.mode == "directory" then
				getTemplates(self, basepath..utils.sep..filename)
			elseif string.find(fpath, ".dct", -4, true) ~= nil then
				Logger:debug("=> process template: %s", fpath)
				local stmpath = string.gsub(fpath, "[.]dct", ".stm")
				if lfs.attributes(stmpath) == nil then
					stmpath = nil
				end
				self:addTemplate(
					Template.fromFile(self, fpath, stmpath))
			end
		end
	end
end

local function createExclusion(self, tpl)
	self._exclusions[tpl.exclusion] = {
		["ttype"] = tpl.objtype,
		["names"] = {},
	}
end

local function registerExclusion(self, tpl)
	assert(tpl.objtype == self._exclusions[tpl.exclusion].ttype,
	       "exclusions across objective types not allowed, '"..
	       tpl.name.."'")
	table.insert(self._exclusions[tpl.exclusion].names,
	             tpl.name)
end

local function registerType(self, kind, ttype, name)
	local entry = {
		["kind"] = kind,
		["name"] = name,
	}

	if self._tpltypes[ttype] == nil then
		self._tpltypes[ttype] = {}
	end
	table.insert(self._tpltypes[ttype], entry)
end

local function addAndSpawnAsset(region, name, assetmgr)
	if name == nil then
		return nil
	end

	local tpl = region:getTemplateByName(name)
	if tpl == nil then
		return nil
	end

	local mgr = dct.Theater.singleton():getAssetMgr()
	local asset = mgr:factory(tpl.objtype)(tpl, region)
	assetmgr:add(asset)
	asset:generate(assetmgr, region)
	return asset
end

local function calculateCentroidAndRadius(region, assets)
	-- default centroid (in case of empty region)
	local centroid = {
		point = vector.Vector2D.create(0, 0)
	}

	-- default minimum radius
	local radius = 25

	-- centroid
	for _, asset in pairs(assets) do
		local location = asset:getLocation()
		if location then
			centroid.point, centroid.n = dctutils.centroid2D(
				location, centroid.point, centroid.n)
		end
	end

	-- radius
	for _, asset in pairs(assets) do
		local distance = vector.distance(
			vector.Vector2D(region:getPoint() or centroid.point),
			vector.Vector2D(asset:getLocation()))
		radius = math.max(radius, distance)
	end

	return centroid, radius
end


--[[
--  Region class
--    base class that reads in a region definition.
--
--    properties
--    ----------
--      * name
--      * priority
--
--    Storage
--    -------
--		_templates   = {
--			["<tpl-name>"] = Template(),
--		},
--		_tpltypes    = {
--			<ttype> = {
--				[#] = {
--					kind = tpl | exclusion,
--					name = "<tpl-name>" | "<ex-name>",
--				},
--			},
--		},
--		_exclusions  = {
--			["<ex-name>"] = {
--				ttype = <ttype>,
--				names = {
--					[#] = ["<tpl-name>"],
--				},
--			},
--		}
--
--    region.def File
--    ---------------
--      Required Keys:
--        * priority - how high in the targets from this region will be
--				ordered
--        * name - the name of the region, mainly used for debugging
--
--      Optional Keys:
--        * limits - a table defining the minimum and maximum number of
--              assets to spawn from a given asset type
--              [<objtype>] = { ["min"] = <num>, ["max"] = <num>, }
--]]
local Region = class("Region", Marshallable)
function Region:__init(regionpath)
	Marshallable.__init(self)
	self:_addMarshalNames({
		"location",
		"links",
		"radius",
	})

	self.path          = regionpath
	self._templates    = {}
	self._tpltypes     = {}
	self._exclusions   = {}
	self.weight        = {}
	for _, side in pairs(coalition.side) do
		self.weight[side] = 0
	end
	self.owner  = coalition.side.NEUTRAL
	self.DOMAIN = nil

	Logger:debug("=> regionpath: %s", regionpath)
	loadMetadata(self, regionpath..utils.sep.."region.def")
	getTemplates(self, self.path)
	Logger:debug("'%s' Loaded", self.name)
end

Region.DOMAIN = DOMAIN

function Region:addTemplate(tpl)
	assert(self._templates[tpl.name] == nil,
		"duplicate template '"..tpl.name.."' defined; "..tostring(tpl.path))
	if tpl.theater ~= env.mission.theatre then
		Logger:warn("Region(%s):Template(%s) not for map(%s):template(%s) - ignoring",
			self.name, tpl.name, env.mission.theatre, tpl.theater)
		return
	end

	Logger:debug("  + add template: %s", tpl.name)
	self._templates[tpl.name] = tpl
	if tpl.exclusion ~= nil then
		if self._exclusions[tpl.exclusion] == nil then
			createExclusion(self, tpl)
			registerType(self, tplkind.EXCLUSION,
				tpl.objtype, tpl.exclusion)
		end
		registerExclusion(self, tpl)
	else
		registerType(self, tplkind.TEMPLATE, tpl.objtype, tpl.name)
	end
end

function Region:getTemplateByName(name)
	return self._templates[name]
end

function Region:_generate(assetmgr, objtype, names, outAssets)
	local limits = {
		["min"]     = #names,
		["max"]     = #names,
		["limit"]   = #names,
		["current"] = 0,
	}

	if self.limits and self.limits[objtype] then
		limits.min   = self.limits[objtype].min
		limits.max   = self.limits[objtype].max
		limits.limit = math.random(limits.min, limits.max)
	end

	for i, tpl in ipairs(names) do
		if tpl.kind ~= tplkind.EXCLUSION and
			self._templates[tpl.name].spawnalways == true then
			local asset = addAndSpawnAsset(self, tpl.name, assetmgr)
			table.insert(outAssets, asset)
			table.remove(names, i)
			limits.current = 1 + limits.current
		end
	end

	while #names >= 1 and limits.current < limits.limit do
		local idx  = math.random(1, #names)
		local name = names[idx].name
		if names[idx].kind == tplkind.EXCLUSION then
			local i = math.random(1, #self._exclusions[name].names)
			name = self._exclusions[name]["names"][i]
		end
		local asset = addAndSpawnAsset(self, name, assetmgr)
		table.insert(outAssets, asset)
		table.remove(names, idx)
		limits.current = 1 + limits.current
	end
end

-- generates all "strategic" assets for a region from
-- a spawn format (limits). We then immediatly register
-- that asset with the asset manager (provided) and spawn
-- the asset into the game world. Region generation should
-- be limited to mission startup.
function Region:generate()
	local assetmgr = dct.Theater.singleton():getAssetMgr()
	local tpltypes = utils.deepcopy(self._tpltypes)
	local assets = {}

	for objtype, _ in pairs(dctenums.assetClass.INITIALIZE) do
		local names = tpltypes[objtype]
		if names ~= nil then
			self:_generate(assetmgr, objtype, names, assets)
		end
	end

	local centroid, radius = calculateCentroidAndRadius(self, assets)
	self.radius = radius

	-- set default location to the calculated centroid
	if self.location == nil then
		self.location = vector.Vector3D(
			centroid.point, land.getHeight(centroid.point:raw())):raw()
	end

	Logger:debug("Region(%s) location - %d, %d, %d",
		self.name, self.location.x, self.location.y, self.location.z)

	-- do not create an airspace object if not wanted
	if self.airspace ~= true then
		return
	end

	-- create airspace asset
	local airspacetpl = Template({
		["objtype"]    = "airspace",
		["name"]       = "airspace",
		["regionname"] = self.name,
		["regionprio"] = self.priority,
		["intel"]      = 1,
		["cost"]       = 0,
		["coalition"]  = coalition.side.NEUTRAL,
		["location"]   = self.location,
		["backfill"]   = true,
	})
	self:addTemplate(airspacetpl)
	addAndSpawnAsset(self, airspacetpl.name, assetmgr)
end

function Region:getWeight(side)
	return self.weight[side]
end

function Region:getPoint()
	return self.location
end

function Region:getEdges(domain)
	assert(utils.getkey(Region.DOMAIN, domain),
		"value error: invalid domain")
	return utils.deepcopy(self.links[domain])
end

local function isStrategic(asset)
	return dctenums.assetClass.STRATEGIC[asset.type]
end

local function get_asset_weight(asset)
	local weight = asset.cost
	if weight == 0 then
		weight = 1
	end
	if not isStrategic(asset) then
		weight = weight * 0.2
	end
	Logger:debug("asset weight(%s): %s", asset.name, tostring(weight))
	return weight
end

function Region:updateOwner()
	local side = coalition.side

	if self.weight[side.RED] == 0 or self.weight[side.BLUE] == 0 then
		if self.weight[side.RED] - self.weight[side.BLUE] == 0 then
			self.owner = side.NEUTRAL
		else
			if self.weight[side.RED] > self.weight[side.BLUE] then
				self.owner = side.RED
			else
				self.owner = side.BLUE
			end
		end
		return
	end

	local c = 4
	local ratioB = self.weight[side.BLUE] / self.weight[side.RED]

	if ratioB > c then
		self.owner = side.BLUE
	elseif ratioB < 1/c then
		self.owner = side.RED
	else
		self.owner = dctutils.COALITION_CONTESTED
	end
end

local function handleDead(region, event)
	local asset = event.initiator
	region.weight[asset.owner] =
		region.weight[asset.owner] - get_asset_weight(asset)
	if region.weight[asset.owner] < 0 then
		region.weight[asset.owner] = 0
	end
	Logger:debug("Region(%s).handleDead %d - new weight: %s",
		region.name, asset.owner, tostring(region.weight[asset.owner]))
end

local function handleAddAsset(region, event)
	local asset = event.initiator
	region.weight[asset.owner] = region.weight[asset.owner] +
		get_asset_weight(asset)
	Logger:debug("Region(%s).handleAddAsset %d - new weight: %s",
		region.name, asset.owner, tostring(region.weight[asset.owner]))
end

local handlers = {
	[dctenums.event.DCT_EVENT_DEAD]      = handleDead,
	[dctenums.event.DCT_EVENT_ADD_ASSET] = handleAddAsset,
}

function Region:onDCTEvent(event)
	local handler = handlers[event.id]
	if handler ~= nil then
		handler(self, event)
		self:updateOwner()
	end
end

return Region
