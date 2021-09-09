--[[
-- SPDX-License-Identifier: LGPL-3.0
--
-- Automatically spawns and despawns assets based on their distances from
-- objects of interest (ie. players and stand-off weapons) to reduce
-- active unit count.
--
-- Terminology:
--  * Asset: a static DCT asset
--  * Object (of interest): objects that are analyzed for proxmity to assets
--    (players and player-launched missiles)
--]]

-- luacheck: max_cyclomatic_complexity 16

local class     = require("libs.class")
local utils     = require("dct.utils")
local Command   = require("dct.Command")
local vec       = require("dct.libs.vector")
local Logger    = require("dct.libs.Logger").getByName("RenderManager")
local StaticAsset = require("dct.assets.StaticAsset")

-- How many seconds to wait between render checks
local CHECK_INTERVAL = 10

-- How many seconds to keep an asset in the world after it's out of range
local DESPAWN_TIMEOUT = 180

-- Default asset age (ensures everything is culled from the start)
local AGE_OLD = -DESPAWN_TIMEOUT

local RangeType = {
	Player     = 1, -- Player flights
	Missile    = 2, -- Guided missiles and some guided bombs
	GuidedBomb = 3, -- Most other guided bombs
}

local RadarDistanceFactor = {
	[RangeType.Player]     = 2.5,
	[RangeType.Missile]    = 1.0,
	[RangeType.GuidedBomb] = nil,
}

local AGM = {
	[Weapon.MissileCategory.BM] = true,
	[Weapon.MissileCategory.ANTI_SHIP] = true,
	[Weapon.MissileCategory.CRUISE] = true,
	[Weapon.MissileCategory.OTHER] = true,
}

-- Maps specific unit types and attributes to minimum render ranges, in meters
local UnitRanges = {
	[RangeType.Player]          = {},
	[RangeType.Missile]         = {},
	[RangeType.GuidedBomb]      = {},
}
local AttributeRanges = {
	[RangeType.Player] = {
		["Ships"]               = 500000,
		["EWR"]                 = 300000,
	},
	[RangeType.Missile] = {
		["Ships"]               = 300000,
	},
	[RangeType.GuidedBomb]      = {},
}
local DefaultRanges = {
	[RangeType.Player]          = 30000,
	[RangeType.Missile]         = 5000,
	[RangeType.GuidedBomb]      = 5000,
}

local radarRanges = {}
local assetRanges = {}

-- Spawns an unit and checks its radar range if needed
local function getRadarRange(unitType)
	if radarRanges[unitType] ~= nil then
		return radarRanges[unitType]
	end
	local range = 0
	local prefix = string.format("DCT_RenderManager_RadarRange")
	local category = Unit.getDescByName(unitType).category
	local group = coalition.addGroup(0, category, {
		name = string.format("%s Group", prefix),
		task = "Ground Nothing",
		start_time = 0,
		hidden = true,
		units = {{
			playerCanDrive = false,
			name = string.format("%s Unit", prefix),
			type = unitType,
			heading = 0,
			x = 0,
			y = 0,
		}},
		x = 0,
		y = 0,
	})
	local sensors = group:getUnit(1):getSensors()
	Logger:debug("unit %s sensors = %s",
		unitType, require("libs.json"):encode_pretty(sensors))
	if sensors ~= nil and sensors[Unit.SensorType.RADAR] ~= nil then
		for _, sensor in pairs(sensors[Unit.SensorType.RADAR]) do
			local detection = sensor.detectionDistanceAir
			if sensor.type == 1 and detection ~= nil then
				if detection.upperHemisphere.headOn > range then
					range = detection.upperHemisphere.headOn
				end
				if detection.lowerHemisphere.headOn > range then
					range = detection.lowerHemisphere.headOn
				end
			end
		end
	end
	radarRanges[unitType] = range
	group:destroy()
	return range
end

-- Exhaustively search every unit in every group in the template of the asset
-- to find its maximum render ranges based on various settings
local function calculateRangeFor(asset, rangeType)
	local assetRange = DefaultRanges[rangeType]
	local template = asset:getTemplate()
	if template == nil then
		return assetRange
	end
	Logger:debug("asset '%s' calculating range for '%s'",
		asset.name, require("libs.utils").getkey(RangeType, rangeType))
	for _, group in pairs(template) do
		if group.data ~= nil and group.data.units ~= nil then
			for _, unit in pairs(group.data.units) do
				local desc = Unit.getDescByName(unit.type)
				local unitRange = UnitRanges[rangeType][unit.type]
				for attr, attrRange in pairs(AttributeRanges[rangeType]) do
					if desc.attributes[attr] ~= nil and attrRange > assetRange then
						unitRange = attrRange
						Logger:debug("asset '%s' unit '%s' attr '%s' set range = %d",
							asset.name, unit.type, attr, attrRange)
					end
				end
				if RadarDistanceFactor[rangeType] ~= nil then
					local range = getRadarRange(unit.type) * RadarDistanceFactor[rangeType]
					if range > assetRange then
						unitRange = range
						Logger:debug("asset '%s' unit '%s' radar set range = %d",
							asset.name, unit.type, range)
					end
				end
				if unitRange ~= nil and unitRange > assetRange then
					assetRange = unitRange
					Logger:debug("asset '%s' unit '%s' asset range = %d",
						asset.name, unit.type, unitRange)
				end
			end
		end
	end
	Logger:debug("asset '%s' range for '%s' = %d",
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

local function isPlayer(object)
	return object:getPlayerName() ~= nil
end

local function getAllPlayers()
	local players = {}
	for co = 0, 2 do
		for _, player in pairs(coalition.getPlayers(co)) do
			table.insert(players, player)
		end
	end
	return players
end

local function weaponRangeType(weapon)
	local desc = weapon:getDesc()
	if desc.category == Weapon.Category.MISSILE and AGM[desc.missileCategory] then
		return RangeType.Missile
	end
	if desc.category == Weapon.Category.BOMB and desc.guidance ~= nil then
		return RangeType.GuidedBomb
	end
end

local RenderManager = class()
function RenderManager:__init(theater)
	-- Disable this system in tests
	if _G.DCT_TEST then
		return
	end

	self.object    = {} -- Object of interest locations as Vector3D
	self.assets    = {} -- Assets grouped by region
	self.assetPos  = {} -- Asset locations as Vector3D
	self.lastSeen  = {} -- Time each asset was last seen
	self.weapons   = {} -- Tracked weapons in flight

	-- Listen to weapon fired events to track stand-off weapons
	theater:addObserver(self.onDCSEvent, self, "RenderManager.onDCSEvent")

	-- Run update function continuously
	theater:queueCommand(30, Command("RenderManager.update",
		self.update, self, theater))
end

function RenderManager:onDCSEvent(event)
	if event.id == world.event.S_EVENT_SHOT then
		if isPlayer(event.initiator) and weaponRangeType(event.weapon) ~= nil then
			Logger:debug("start tracking wpn %d ('%s') released by '%s'",
				event.weapon.id_,
				event.weapon:getTypeName(),
				event.initiator:getPlayerName())
			table.insert(self.weapons, event.weapon)
		end
	end
end

-- Check if the object is within the asset's render bubble
function RenderManager:inRange(object, asset)
	-- Flagged and targeted assets should always be visible
	if asset.nocull or asset:isTargeted(utils.getenemy(asset.owner)) then
		return true
	end

	computeRanges(asset)
	local dist = vec.distance(object.location, self.assetPos[asset.name])
	return dist <= assetRanges[asset.name][object.rangeType]
end

--[[
-- Check if the object is outside of the asset's render bubble + region size
--
-- Since we're using this to early-exit the loop, we'll use the longest of the
-- two ranges between player and missile render range
--]]
function RenderManager:tooFar(object, asset, region)
	-- Flagged and targeted assets should always be visible
	if asset.nocull or asset:isTargeted(utils.getenemy(asset.owner)) then
		return false
	end

	computeRanges(asset)
	local dist = vec.distance(object.location, self.assetPos[asset.name])
	return dist > assetRanges[asset.name][object.rangeType] + region.radius
end

function RenderManager:update(theater)
	local assetmgr = theater:getAssetMgr()
	local regions = theater:getRegionMgr().regions
	-- Update player and weapon locations
	self.objects = {}
	local players = getAllPlayers()
	for i = 1, #players do
		table.insert(self.objects, {
			location = vec.Vector3D(players[i]:getPoint()),
			rangeType = RangeType.Player,
		})
	end
	for i = #self.weapons, 1, -1 do
		local wpn = self.weapons[i]
		if wpn:isExist() then
			table.insert(self.objects, {
				location = vec.Vector3D(wpn:getPoint()),
				rangeType = weaponRangeType(wpn),
			})
		else
			Logger:debug("end tracking wpn %d", wpn.id_)
			table.remove(self.weapons, i)
		end
	end
	-- Update asset locations
	self.assets = {}
	self.assetPos = {}
	for _, asset in assetmgr:iterate() do
		if asset:isa(StaticAsset) and asset:getLocation() ~= nil then
			self.assets[asset.rgnname] = self.assets[asset.rgnname] or {}
			self.lastSeen[asset.name] = self.lastSeen[asset.name] or AGE_OLD
			self.assetPos[asset.name] = vec.Vector3D(asset:getLocation())
			table.insert(self.assets[asset.rgnname], asset)
		end
	end
	-- Queue region checks
	for name, region in pairs(regions) do
		local cmdname = string.format("RenderManager.checkRegion(%s)", name)
		if self.assets[name] ~= nil then
			theater:queueCommand(theater.cmdmindelay,
				Command(cmdname, self.checkRegion, self, region))
		end
	end
	return CHECK_INTERVAL
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
				-- prefer to store a player over any kind of weapon
				if objdist[dist] == nil or rangeType == RangeType.Player then
					objdist[dist] = obj
				end
			end
		end
		table.sort(distances[rangeType])
	end
	return distances, objdist
end

function RenderManager:checkRegion(region, time)
	local assets = self.assets[region.name]
	if assets ~= nil then
		local ops = 0
		local distances, objdist = self:getSortedDistances(region)
		for i = 1, #assets do
			local asset = assets[i]
			if asset:isSpawned() then
				local seen = false
				for rt = 1, #distances do
					for di = 1, #distances[rt] do
						ops = ops + 1
						local object = objdist[distances[rt][di]]
						if self:tooFar(object, asset, region) then
							break
						end
						if self:inRange(object, asset) then
							self.lastSeen[asset.name] = time
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
						ops = ops + 1
						local object = objdist[distances[rt][di]]
						if self:tooFar(object, asset, region) then
							break
						end
						if self:inRange(object, asset) then
							self.lastSeen[asset.name] = time
							seen = true
							break
						end
					end
					if seen then
						asset:spawn()
						break
					end
				end
			end
		end
		Logger:info("checkRegion(%s) objects = %d, assets = %d, ops = %d",
			region.name, #distances[1]+#distances[2]+#distances[3], #assets, ops)
	end
end

return RenderManager
