--[[
-- SPDX-License-Identifier: LGPL-3.0
--
-- Represents an airspace.
-- Airspaces cannot die (i.e. be deleted), track zero-sum influence of
-- which side "controls" the space, and spawn nothing
--]]

local utils     = require("libs.utils")
local dctenum   = require("dct.enum")
local dctutils  = require("dct.utils")
local AssetBase = require("dct.assets.AssetBase")

local Airspace = require("libs.namedclass")("Airspace", AssetBase)
function Airspace:__init(template)
	AssetBase.__init(self, template)
	self:_addMarshalNames({
		"_maxStrategicAssets",
		"_radius",
	})
end

function Airspace.assettypes()
	return {
		require("dct.enum").assetType.AIRSPACE,
	}
end

function Airspace:_completeinit(template)
	AssetBase._completeinit(self, template)
	assert(type(template.radius) == "number",
		"runtime error: Airspace requires template to define a numeric radius")
	self._radius   = template.radius
end

function Airspace:spawn(ignore)
	AssetBase.spawn(self, ignore)
	self:_trackStrategicAssets()
end

local function isStrategic(asset, inRegion)
	return dctenum.assetClass["STRATEGIC"][asset.type]
		and asset.rgnname == inRegion
		-- Airbases can't be captured normally, so they will not be tracked
		and asset.type ~= dctenum.assetType.AIRBASE
end

function Airspace:_recalculateCapacity()
	local numAssets = #self._strategicAssets
	local capacity = math.max(2, math.ceil(numAssets / 4))
	self._logger:debug("setting minagents = %d", capacity)
	self.minagents = capacity
end

function Airspace:_trackStrategicAssets()
	self._strategicAssets = {}
	local theater = dct.Theater.singleton()
	theater:getAssetMgr():filterAssets(function(asset)
		if isStrategic(asset, self.rgnname) then
			self._logger:debug("add asset: %s", asset.name)
			table.insert(self._strategicAssets, asset)
		end
	end)
	-- Define owner based on highest strategic asset count
	-- TODO: migrate to region ownership system
	local numAssets = {
		[coalition.side.NEUTRAL] = 0,
		[coalition.side.RED] = 0,
		[coalition.side.BLUE] = 0,
	}
	local owner = { count = 0, side = coalition.side.NEUTRAL }
	for _, asset in pairs(self._strategicAssets) do
		local count = numAssets[asset.owner] + 1
		if count > owner.count then
			owner.side = asset.owner
			owner.count = count
		end
		numAssets[asset.owner] = count
	end
	self.owner = owner.side
	self._logger:debug("set owner = %s", utils.getkey(coalition.side, self.owner))
	-- Ignore assets that are not owned by the region owner
	for idx, asset in pairs(self._strategicAssets) do
		if asset.owner ~= self.owner then
			self._logger:debug("%s owned by different coalition, removing", asset.name)
			table.remove(self._strategicAssets, idx)
		end
	end
	self._maxStrategicAssets = self._maxStrategicAssets or #self._strategicAssets
	self._logger:debug("tracking %d/%d alive strategic assets",
		#self._strategicAssets, self._maxStrategicAssets)

	self:_recalculateCapacity()
end

function Airspace:_updateAliveAssets()
	if self._strategicAssets == nil then
		return 0
	end
	local aliveAssets = {}
	for _, asset in pairs(self._strategicAssets) do
		if not asset:isDead() then
			table.insert(aliveAssets, asset)
		end
	end
	self._logger:debug("alive assets = %d", #aliveAssets)
	self._strategicAssets = aliveAssets
	return #aliveAssets
end

-- Right now, we only calculats how many strategic assets
-- have been destroyed in the region
function Airspace:getStatus()
	if self._maxStrategicAssets == 0 then
		return 0
	end
	local numAlive = self:_updateAliveAssets()
	return math.ceil((1 - numAlive / self._maxStrategicAssets) * 100)
end

function Airspace:update()
	self:_updateAliveAssets()
	self:_recalculateCapacity()

	-- When empty, set to neutral and notify asset death to trigger mission update
	if self.owner ~= coalition.side.NEUTRAL and #self._strategicAssets == 0 then
		self.owner = coalition.side.NEUTRAL
		self:notify(dctutils.buildevent.dead(self))
		self._logger:debug("neutralized")
	end
end

-- Keep this asset alive after completion
function Airspace:isDead()
	return false
end

return Airspace
