--[[
-- SPDX-License-Identifier: LGPL-3.0
--
-- Defines the Region class.
--]]

require("lfs")
require("math")
local class      = require("libs.class")
local utils      = require("libs.utils")
local dctenums   = require("dct.enum")
local dctutils   = require("dct.utils")
local vector     = require("dct.libs.vector")
local Template   = require("dct.templates.Template")
local Logger     = dct.Logger.getByName("Region")

local tplkind = {
	["TEMPLATE"]  = 1,
	["EXCLUSION"] = 2,
}

local DOMAIN = {
	["AIR"]  = 1,
	["LAND"] = 2,
	["SEA"]  = 3,
}

local function processlimits(_, tbl)
	-- process limits; convert the human readable asset type names into
	-- their numerical equivalents.
	local limits = {}
	for key, data in pairs(tbl.limits) do
		local typenum = dctenums.assetType[string.upper(key)]
		if typenum == nil then
			Logger:warn("invalid asset type '"..key..
				"' found in limits definition in file: "..
				tbl.defpath or "nil")
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
	Logger:debug("=> regiondefpath: "..regiondefpath)
	local keys = {
		{
			["name"] = "name",
			["type"] = "string",
		}, {
			["name"] = "priority",
			["type"] = "number",
		}, {
			["name"] = "limits",
			["type"] = "table",
			["default"] = {},
			["check"] = processlimits,
		}, {
			["name"] = "altitude_floor",
			["type"] = "number",
			["default"] = 914.4, -- meters; 3000ft msl
		}, {
			["name"] = "links",
			["type"] = "table",
			["check"] = processlinks,
		}
	}

	local region = utils.readlua(regiondefpath)
	if region.region then
		region = region.region
	end
	region.defpath = regiondefpath
	utils.checkkeys(keys, region)
	utils.mergetables(self, region)
end

local function getTemplates(self, basepath)
	local ignorepaths = {
		["."] = true,
		[".."] = true,
		["region.def"] = true,
	}

	Logger:debug("=> basepath: "..basepath)
	for filename in lfs.dir(basepath) do
		if ignorepaths[filename] == nil then
			local fpath = basepath..utils.sep..filename
			local fattr = lfs.attributes(fpath)
			if fattr.mode == "directory" then
				getTemplates(self, basepath..utils.sep..filename)
			elseif string.find(fpath, ".dct", -4, true) ~= nil then
				Logger:debug("=> process template: "..fpath)
				local stmpath = string.gsub(fpath, "[.]dct", ".stm")
				if lfs.attributes(stmpath) == nil then
					stmpath = nil
				end
				self:addTemplate(
					Template.fromFile(self.name, fpath, stmpath))
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

local function addAndSpawnAsset(self, name, assetmgr)
	if name == nil then
		return nil
	end

	local tpl = self:getTemplateByName(name)
	if tpl == nil then
		return nil
	end

	local mgr = dct.Theater.singleton():getAssetMgr()
	local asset = mgr:factory(tpl.objtype)(tpl, self)
	assetmgr:add(asset)
	asset:generate(assetmgr, self)
	local location = asset:getLocation()
	if location then
		self.centroid.point, self.centroid.n = dctutils.centroid(location,
			self.centroid.point, self.centroid.n)
	end
	return asset
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
local Region = class()
function Region:__init(regionpath)
	self.path          = regionpath
	self._templates    = {}
	self._tpltypes     = {}
	self._exclusions   = {}
	self.centroid      = {
		["point"] =  nil, -- 2D point where the center of the region is
		["n"] = 0,
	}
	Logger:debug("=> regionpath: "..regionpath)
	loadMetadata(self, regionpath..utils.sep.."region.def")
	getTemplates(self, self.path)
	Logger:debug("'"..self.name.."' Loaded")
	self.DOMAIN = nil
end

Region.DOMAIN = DOMAIN

function Region:addTemplate(tpl)
	assert(self._templates[tpl.name] == nil,
		"duplicate template '"..tpl.name.."' defined; "..tostring(tpl.path))
	Logger:debug("  + add template: "..tpl.name)
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

function Region:_generate(assetmgr, objtype, names)
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
			addAndSpawnAsset(self, tpl.name, assetmgr)
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
		addAndSpawnAsset(self, name, assetmgr)
		table.remove(names, idx)
		limits.current = 1 + limits.current
	end
end

-- generates all "strategic" assets for a region from
-- a spawn format (limits). We then immediatly register
-- that asset with the asset manager (provided) and spawn
-- the asset into the game world. Region generation should
-- be limited to mission startup.
function Region:generate(assetmgr)
	local tpltypes = utils.deepcopy(self._tpltypes)

	for objtype, _ in pairs(dctenums.assetClass["STRATEGIC"]) do
		local names = tpltypes[objtype]
		if names ~= nil then
			self:_generate(assetmgr, objtype, names)
		end
	end
end

-- TODO: getting the center-point of a region might be a problem
-- because the only time this is valid is after the generate function
-- has run. How do we preserve the center of a region?
function Region:getPoint()
	return self.centroid.point
end

local function calcCost(thisrgn, otherrgn)
	if thisrgn == nil or otherrgn == nil then
		return nil
	end
	return vector.distance(vector.Vector2D(thisrgn:getPoint()),
		vector.Vector2D(otherrgn:getPoint()))
end

function Region:validateEdges(regions)
	local links = {}
	for domain, lnks in pairs(self.links) do
		links[domain] = {}
		for _, rgnname in pairs(lnks) do
			links[domain][rgnname] = calcCost(self, regions[rgnname])
		end
	end
	self.links = links
end

function Region:getEdges(domain)
	assert(utils.getkey(Region.DOMAIN, domain),
		"value error: invalid domain")
	return utils.deepcopy(self.links[domain])
end

return Region
