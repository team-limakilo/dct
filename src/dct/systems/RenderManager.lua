--[[
-- SPDX-License-Identifier: LGPL-3.0
--
-- Automatically spawns and despawns assets based on their distances from
-- objects of interest (ie. aircraft and stand-off weapons) to reduce
-- active unit count.
--]]

-- luacheck: max_cyclomatic_complexity 100

local class     = require("libs.class")
local utils     = require("dct.utils")
local vec       = require("dct.libs.vector")
local Logger    = require("dct.libs.Logger").getByName("RenderManager")
local StaticAsset  = require("dct.assets.StaticAsset")
local CoroutineCmd = require("dct.CoroutineCommand")
local settings     = _G.dct.settings
local yield        = coroutine.yield

-- Ignore AI aircraft if true
local PLAYERS_ONLY = true

-- How many seconds to keep an asset in the world after it's out of range
local DESPAWN_TIMEOUT = 5 * 60
local ONDEMAND_TIMEOUT = 30 * 60

-- Default asset timestamp, ensuring everything is culled from the start
local AGE_OLD = -99999

local RangeType = {
	Aircraft   = 1, -- Flights
	CruiseMsl  = 2, -- INS, TV, and Radar-guided missiles
	AntiRadMsl = 3, -- Anti-radiation missiles
	GuidedBomb = 4, -- Laser and TV-guided bombs
}

local RadarDistanceFactor = {
	[RangeType.Aircraft]   = 2.5,
	[RangeType.CruiseMsl]  = nil,
	[RangeType.AntiRadMsl] = 0.5,
	[RangeType.GuidedBomb] = nil,
}

local cruiseGuidance = {
	[Weapon.GuidanceType.INS] = true,
	[Weapon.GuidanceType.TELE] = true,
	[Weapon.GuidanceType.RADAR_ACTIVE] = true,
}

-- Maps specific unit types and attributes to minimum render ranges, in meters
local UnitTypeRanges = {
	[RangeType.Aircraft] = {
		["SA-8 Osa LD 9T217"]   = 50000,
		["Tor 9A331"]           = 40000,
	},
	[RangeType.CruiseMsl]       = {},
	[RangeType.AntiRadMsl]      = {},
	[RangeType.GuidedBomb]      = {},
}
local AttributeRanges = {
	[RangeType.Aircraft] = {
		["Ships"]               = 100000,
	},
	[RangeType.CruiseMsl] = {
		["Ships"]               = 50000,
	},
	[RangeType.AntiRadMsl]      = {},
	[RangeType.GuidedBomb]      = {},
}
local DefaultRanges = {
	[RangeType.Aircraft]        = 30000,
	[RangeType.CruiseMsl]       = 10000,
	[RangeType.AntiRadMsl]      = 0,
	[RangeType.GuidedBomb]      = 0,
}

local assetRanges = {}

-- Gets the maximum radar detection range of an unit
local function getRadarRange(unit)
	local range = 0
	local sensors = unit:getSensors()
	if sensors ~= nil and sensors[Unit.SensorType.RADAR] ~= nil then
		for _, sensor in pairs(sensors[Unit.SensorType.RADAR]) do
			local detection = sensor.detectionDistanceAir
			if detection ~= nil then
				if detection.upperHemisphere.headOn > range then
					range = detection.upperHemisphere.headOn
				end
				if detection.lowerHemisphere.headOn > range then
					range = detection.lowerHemisphere.headOn
				end
			end
		end
	end
	return range
end

-- Exhaustively search every unit in every group of asset
-- to find its maximum render range based on various settings
local function calculateRangeFor(asset, rangeType)
	local assetRange = DefaultRanges[rangeType]
	local tpldata = asset:getTemplateData()
	-- Cannot calculate range, default to infinite range
	if tpldata == nil or not asset:isSpawned() then
		return nil
	end
	Logger:debug("asset '%s' calculating range for %s",
		asset.name, require("libs.utils").getkey(RangeType, rangeType))
	for _, tpl in pairs(tpldata) do
		local group = Group.getByName(tpl.data.name)
		if group ~= nil then
			for _, unit in pairs(group:getUnits()) do
				local unitDesc = unit:getDesc()
				local unitType = unit:getTypeName()
				-- Check unit type range
				local unitRange = UnitTypeRanges[rangeType][unitType]
				if unitRange ~= nil and unitRange > assetRange then
					Logger:debug("asset '%s' unit '%s' asset range = %d",
						asset.name, unitType, unitRange)
					assetRange = unitRange
				end
				-- Check attribute ranges
				for attr, attrRange in pairs(AttributeRanges[rangeType]) do
					if unitDesc.attributes[attr] ~= nil and attrRange > assetRange then
						assetRange = attrRange
						Logger:debug("asset '%s' unit '%s' attr '%s' set range = %d",
							asset.name, unitType, attr, attrRange)
					end
				end
				-- Check radar range
				if RadarDistanceFactor[rangeType] ~= nil then
					local radarRange = getRadarRange(unit) * RadarDistanceFactor[rangeType]
					if radarRange > assetRange then
						assetRange = radarRange
						Logger:debug("asset '%s' unit '%s' radar set range = %d",
							asset.name, unitType, radarRange)
					end
				end
			end
		end
	end
	Logger:debug("asset '%s' range for %s = %d",
		asset.name, require("libs.utils").getkey(RangeType, rangeType), assetRange)
	return assetRange
end

-- Compute and save asset render ranges for future lookups
local function computeRanges(asset)
	if assetRanges[asset.name] == nil then
		assetRanges[asset.name] = {}
		for _, type in pairs(RangeType) do
			assetRanges[asset.name][type] = calculateRangeFor(asset, type)
		end
	end
end

local function getAllAircraft()
	local units = {}
	for co = 1, 2 do
		if PLAYERS_ONLY then
			for _, player in pairs(coalition.getPlayers(co)) do
				table.insert(units, player)
			end
		else
			for _, group in pairs(coalition.getGroups(co, Group.Category.AIRPLANE)) do
				for _, unit in pairs(group:getUnits()) do
					if unit:isActive() then
						table.insert(units, unit)
					end
				end
			end
			for _, group in pairs(coalition.getGroups(co, Group.Category.HELICOPTER)) do
				for _, unit in pairs(group:getUnits()) do
					if unit:isActive() then
						table.insert(units, unit)
					end
				end
			end
		end
	end
	return units
end

local function weaponRangeType(weapon)
	if weapon == nil or
	   PLAYERS_ONLY and
	   weapon:getLauncher() ~= nil and
	   weapon:getLauncher():isExist() and
	   weapon:getLauncher():getPlayerName() == nil then
		return nil
	end
	local desc = weapon:getDesc()
	if desc.guidance == Weapon.GuidanceType.RADAR_PASSIVE then
		return RangeType.AntiRadMsl
	elseif desc.missileCategory ~= Weapon.MissileCategory.AAM and
	       cruiseGuidance[desc.guidance] ~= nil then
		return RangeType.CruiseMsl
	elseif desc.category == Weapon.Category.BOMB and
	       desc.guidance ~= nil then
		return RangeType.GuidedBomb
	end
end

local RenderManager = class()
function RenderManager:__init(theater)
	self.objects   = {} -- Object of interest locations as Vector3D
	self.assets    = {} -- Assets grouped by region
	self.assetPos  = {} -- Asset locations as Vector3D
	self.lastSeen  = {} -- Time each asset was last seen
	self.weapons   = {} -- Tracked weapons in flight

	-- Disable automatic execution in tests
	if _G.DCT_TEST then
		return
	end

	-- Listen to weapon fired events to track stand-off weapons
	theater:addObserver(self.onDCSEvent, self, "RenderManager.onDCSEvent")

	-- Run update function continuously
	theater:queueCommand(30, CoroutineCmd("RenderManager.update",
		self.update, self, theater))
end

function RenderManager:onDCSEvent(event)
	if event.id == world.event.S_EVENT_SHOT then
		local rangeType = weaponRangeType(event.weapon)
		if rangeType ~= nil then
			Logger:debug("start tracking wpn %d ('%s') released by '%s'",
				event.weapon.id_,
				event.weapon:getTypeName(),
				event.initiator:getPlayerName() or event.initiator:getName())
			table.insert(self.weapons, { event.weapon, rangeType })
		end
	end
end

-- Check if the asset should be visible regardless of range to other objects
function RenderManager:forcedVisibility(asset, time)
	if asset.nocull and asset:isSpawned() then
		return true
	elseif asset:isTargeted(utils.getenemy(asset.owner)) then
		return true
	elseif asset.ondemand then
		-- Force-hide ondemand assets after a while of not being targeted
		if time - self.lastSeen[asset.name] > ONDEMAND_TIMEOUT then
			return false
		end
	end
end

-- Check if the object is within the asset's render bubble
function RenderManager:inRange(object, asset)
	if assetRanges[asset.name][object.rangeType] == nil then
		return true
	end
	local dist = vec.distance(object.location, self.assetPos[asset.name])
	return dist <= assetRanges[asset.name][object.rangeType]
end

-- Check if the object is outside of the asset's render bubble + region size
-- at the longest possible visibility range (aircraft)
function RenderManager:tooFar(object, asset, region)
	if assetRanges[asset.name][RangeType.Aircraft] == nil then
		return false
	end
	local dist = vec.distance(object.location, self.assetPos[asset.name])
	return dist > assetRanges[asset.name][RangeType.Aircraft] + region.radius
end

function RenderManager:update(theater, time)
	local assetmgr = theater:getAssetMgr()
	local regions = theater:getRegionMgr().regions
	-- Update aircraft locations
	self.objects = {}
	local aircraft = getAllAircraft()
	for i = 1, #aircraft do
		table.insert(self.objects, {
			location = vec.Vector3D(aircraft[i]:getPoint()),
			rangeType = RangeType.Aircraft,
		})
	end
	yield()
	-- Update weapon locations
	for i = #self.weapons, 1, -1 do
		local wpn, rangeType = unpack(self.weapons[i])
		if wpn:isExist() then
			table.insert(self.objects, {
				location = vec.Vector3D(wpn:getPoint()),
				rangeType = rangeType,
			})
		else
			Logger:debug("end tracking wpn %d", wpn.id_)
			table.remove(self.weapons, i)
		end
	end
	yield()
	-- Update asset locations
	self.assets = {}
	self.assetPos = {}
	for _, asset in assetmgr:iterate() do
		if asset:isa(StaticAsset) then
			self.assets[asset.rgnname] = self.assets[asset.rgnname] or {}
			self.lastSeen[asset.name] = self.lastSeen[asset.name] or AGE_OLD
			self.assetPos[asset.name] = asset:getCurrentLocation()
			table.insert(self.assets[asset.rgnname], asset)
		end
	end
	yield()
	-- Check each region individually
	for name, region in pairs(regions) do
		if self.assets[name] ~= nil then
			self:checkRegion(region, time)
		end
	end
	return 2
end

--[[
-- Sorts the distances of each object to the region center and caches
-- the objects to their distances, so that we can exit from the inner
-- loop early when we find something that's too far away to continue
-- checking for other objects.
--
-- Note: we do this instead of sorting self.objects directly because
-- table.sort with default sorting is a *lot* faster than with a
-- custom sort function that calls back into lua every iteration.
--
-- Returns: sorted distances and distance -> object map
--]]
function RenderManager:getSortedDistances(region)
	local regionloc = vec.Vector3D(region.location)
	local distances = {}
	local objdist = {}
	for _, rangeType in pairs(RangeType) do
		distances[rangeType] = {}
		for _, obj in pairs(self.objects) do
			if obj.rangeType == rangeType then
				local dist = vec.distance(obj.location, regionloc)
				table.insert(distances[rangeType], dist)
				-- In the *extremely* unlikely case that we have more than one
				-- object at the same cached distance from the region center,
				-- prefer to store aircraft over any kind of weapon
				if objdist[dist] == nil or rangeType == RangeType.Aircraft then
					objdist[dist] = obj
				end
			end
		end
		table.sort(distances[rangeType])
	end
	return distances, objdist
end

function RenderManager:checkRegion(region, time)
	Logger:debug("checkRegion(%s)", region.name)
	local assets = self.assets[region.name]
	if assets ~= nil then
		local ops = 0
		local spawns = 0
		local start = os.clock()
		local distances, objdist = self:getSortedDistances(region)
		for i = 1, #assets do
			local asset = assets[i]
			local forcedVis = self:forcedVisibility(asset, time)
			if forcedVis == nil then
				computeRanges(asset)
				if asset:isSpawned() then
					local seen = false
					for rt = 1, #distances do
						for di = 1, #distances[rt] do
							local object = objdist[distances[rt][di]]
							ops = ops + 1
							if self:tooFar(object, asset, region) then
								break
							end
							ops = ops + 1
							if self:inRange(object, asset) then
								if not asset.ondemand then
									self.lastSeen[asset.name] = time
								end
								seen = true
								break
							end
						end
						if seen then
							break
						end
					end
					if not seen and time - self.lastSeen[asset.name] > DESPAWN_TIMEOUT then
						asset:despawn()
					end
				else
					for rt = 1, #distances do
						local seen = false
						for di = 1, #distances[rt] do
							local object = objdist[distances[rt][di]]
							ops = ops + 1
							if self:tooFar(object, asset, region) then
								break
							end
							ops = ops + 1
							if self:inRange(object, asset) then
								seen = true
								break
							end
						end
						if seen then
							self.lastSeen[asset.name] = time
							spawns = spawns + 1
							asset:spawn()
							yield()
							break
						end
					end
				end
			else
				if forcedVis == false and asset:isSpawned() then
					asset:despawn()
				elseif forcedVis == true then
					self.lastSeen[asset.name] = time
					if not asset:isSpawned() then
						spawns = spawns + 1
						asset:spawn()
						yield()
					end
				end
			end
		end
		if settings.server.profile == true then
			Logger:info("checkRegion(%s): aircraft = %d, weapons = %d, "..
				" assets = %d, ops = %d, spawns = %d, total time = %.2fms",
				region.name,
				#distances[RangeType.Aircraft],
				#distances[RangeType.AntiRadMsl] +
				#distances[RangeType.CruiseMsl]  +
				#distances[RangeType.GuidedBomb],
				#assets, ops, spawns, (os.clock() - start)*1000)
		end
		yield()
	end
end

return RenderManager
