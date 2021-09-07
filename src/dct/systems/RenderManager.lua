--[[
-- SPDX-License-Identifier: LGPL-3.0
--
-- Automatically spawns and despawns assets based on their distances from
-- objects of interest (ie. players and stand-off weapons) to reduce
-- active unit count.
--]]

-- luacheck: max_cyclomatic_complexity 12

local class     = require("libs.class")
local utils     = require('dct.utils')
local Command   = require("dct.Command")
local vec       = require("dct.libs.vector")
local Logger    = require("dct.libs.Logger").getByName("RenderManager")
local StaticAsset = require("dct.assets.StaticAsset")

-- How long to wait between render checks
local CHECK_INTERVAL = 10

-- How long to keep an asset in the world after it's out of range
local DESPAWN_TIMEOUT = 180

-- Default asset age (ensures everything is culled from the start)
local AGE_OLD = -DESPAWN_TIMEOUT

local RangeType = {
	Player  = 1,
	Missile = 2,
}

-- Maps specific unit attributes to maximum intended render ranges, in meters
local RENDER_RANGES = {
	[RangeType.Player] = {
		["Ships"]       = 480000,
		["EWR"]         = 320000,
		["LR SAM"]      = 320000,
		["MR SAM"]      = 160000,
		["Default"]     =  20000,
	},
	[RangeType.Missile] = {
		["Ships"]       = 120000,
		["EWR"]         =  40000,
		["LR SAM"]      =  40000,
		["MR SAM"]      =  20000,
		["SR SAM"]      =  10000,
		["Default"]     =   5000,
	}
}

-- Exhaustively search every unit in every group in the template of the asset
-- to find its maximum render ranges based on unit attributes
local function calculateRange(asset, type)
	local template = asset:getTemplate()
	local assetRange = RENDER_RANGES[type]["Default"]
	if template == nil then
		return assetRange
	end
	for _, group in pairs(template) do
		Logger:debug("asset %s group %s", asset.name, group.data.name)
		if group.data ~= nil and group.data.units ~= nil then
			local groupRange = 0
			for _, unit in pairs(group.data.units) do
				local desc = Unit.getDescByName(unit.type)
				for attr, unitRange in pairs(RENDER_RANGES[type]) do
					if desc.attributes[attr] and unitRange > groupRange then
						Logger:debug(
							"asset %s unit %s attr %s overriding range = %d",
							asset.name, unit.type, attr, unitRange)
						groupRange = unitRange
					end
				end
			end
			if groupRange > assetRange then
				assetRange = groupRange
			end
		end
	end
	Logger:debug("asset %s range = %d", asset.name, assetRange)
	return assetRange
end

local function isPlayer(object)
	return object:getPlayerName() ~= nil
end

local function allPlayers()
	local players = {}
	for co = 0, 2 do
		for _, player in pairs(coalition.getPlayers(co)) do
			table.insert(players, player)
		end
	end
	return players
end

local function weaponIsTracked(weapon)
	local desc = weapon:getDesc()
	return desc.category == Weapon.Category.MISSILE and
		  (desc.missileCategory == Weapon.MissileCategory.ANTI_SHIP or
		   desc.missileCategory == Weapon.MissileCategory.CRUISE or
		   desc.missileCategory == Weapon.MissileCategory.OTHER)
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
	self.ranges    = {} -- Asset render ranges
	self.missiles  = {} -- Tracked missiles

	-- Listen to weapon fired events to track stand-off weapons
	theater:addObserver(self.onDCSEvent, self, "RenderManager.onDCSEvent")

	-- Run update function continuously
	theater:queueCommand(30, Command("RenderManager.update",
		self.update, self, theater))
end

function RenderManager:onDCSEvent(event)
	if event.id == world.event.S_EVENT_SHOT then
		if isPlayer(event.initiator) and weaponIsTracked(event.weapon) then
			Logger:debug("start tracking missile %d ('%s') released by '%s'",
				event.weapon:getID(),
				event.weapon:getTypeName(),
				event.initiator:getPlayerName())
			table.insert(self.missiles, event.weapon)
		end
	end
end

-- Compute and save asset render ranges for future lookups
function RenderManager:computeRanges(asset)
	if self.ranges[asset.name] == nil then
		self.ranges[asset.name] = {}
		for _, type in pairs(RangeType) do
			self.ranges[asset.name][type] = calculateRange(asset, type)
		end
	end
end

-- Check if the object is within the asset's render bubble
function RenderManager:inRange(object, asset)
	-- Flagged and targeted assets should always be visible
	if asset.nocull or asset:isTargeted(utils.getenemy(asset.owner)) then
		return true
	end

	self:computeRanges(asset)

	local dist = vec.distance(object.location, self.assetPos[asset.name])
	return dist <= self.ranges[asset.name][object.rangeType]
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

	self:computeRanges(asset)
	local range = math.max(
		self.ranges[asset.name][RangeType.Player],
		self.ranges[asset.name][RangeType.Missile])

	local dist = vec.distance(object.location, self.assetPos[asset.name])
	return dist > range + region.radius
end

function RenderManager:update(theater)
	local assetmgr = theater:getAssetMgr()
	local regions = theater:getRegionMgr().regions
	-- Update player and missile locations
	self.objects = {}
	local players = allPlayers()
	for i = 1, #players do
		table.insert(self.objects, {
			location = vec.Vector3D(players[i]:getPoint()),
			rangeType = RangeType.Player,
		})
	end
	for i = #self.missiles, 1, -1 do
		local msl = self.missiles[i]
		if msl:isExist() then
			table.insert(self.objects, {
				location = vec.Vector3D(msl:getPoint()),
				rangeType = RangeType.Missile,
			})
		else
			Logger:debug("end tracking missile %d", msl:getID())
			table.remove(self.missiles, i)
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
	for _, obj in pairs(self.objects) do
		local dist = vec.distance(obj.location, regionloc)
		table.insert(distances, dist)
		-- In the *extremely* unlikely case that we have more than one
		-- object at the same cached distance from the region center,
		-- prefer to store a player over a missile so that it can
		-- check the largest radius of the two
		if objdist[dist] == nil or
			objdist[dist].rangeType ~= RangeType.Player then
			objdist[dist] = obj
		end
	end
	table.sort(distances)
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
				for di = 1, #distances do
					ops = ops + 1
					local object = objdist[distances[di]]
					if self:tooFar(object, asset, region) then
						break
					end
					if self:inRange(object, asset) then
						self.lastSeen[asset.name] = time
						seen = true
						break
					end
				end
				if not seen then
					if time - self.lastSeen[asset.name] > DESPAWN_TIMEOUT then
						asset:despawn()
					end
				end
			else
				for di = 1, #distances do
					ops = ops + 1
					local object = objdist[distances[di]]
					if self:tooFar(object, asset, region) then
						break
					end
					if self:inRange(object, asset) then
						self.lastSeen[asset.name] = time
						asset:spawn()
						break
					end
				end
			end
		end
		Logger:info("checkRegion(%s) objects = %d, assets = %d, ops = %d",
			region.name, #distances, #assets, ops)
	end
end

return RenderManager
