--[[
-- SPDX-License-Identifier: LGPL-3.0
--
-- Represents an airspace.
-- Airspaces cannot die (i.e. be deleted), track zero-sum influence of
-- which side "controls" the space, and spawn nothing
--]]

local vector    = require("dct.libs.vector")
local utils     = require("dct.utils")
local enum      = require("dct.enum")
local Command   = require("dct.Command")
local AssetBase = require("dct.assets.AssetBase")

local Airspace = require("libs.namedclass")("Airspace", AssetBase)
function Airspace:__init(template)
	AssetBase.__init(self, template)
	self:_addMarshalNames({
		"_volume",
		"_maxStrategicAssets",
	})
end

function Airspace.assettypes()
	return {
		require("dct.enum").assetType.AIRSPACE,
	}
end

function Airspace:_completeinit(template)
	AssetBase._completeinit(self, template)
	assert(template.location ~= nil,
		"runtime error: Airspace requires template to define a location")
	self._location = vector.Vector3D(template.location):raw()
	assert(template.volume ~= nil,
		"runtime error: Airspace requires template to define a volume")
	self._volume = template.volume
	self:_trackStrategicAssets()
end

function Airspace:_unmarshalpost(data)
	AssetBase._unmarshalpost(self, data)
	self:_postinit()
end

function Airspace:_postinit()
	-- finish initialization after all assets have spawned
	local cmdname = "Airspace("..self.name.."):_trackStrategicAssets"
	dct.Theater.singleton():queueCommand(2,
		Command(cmdname, self._trackStrategicAssets, self))
end

function Airspace:_trackStrategicAssets()
	-- track strategic assets in the region
	self._strategicAssets = {}
	local theater = dct.Theater.singleton()
	theater:getAssetMgr():filterAssets(function(asset)
		if asset.rgnname == self.rgnname and
			enum.assetClass["STRATEGIC"][asset.type] then
			self._logger:debug("add asset: %s", asset.name)
			table.insert(self._strategicAssets, asset)
		end
	end)
	-- define owner based on highest strategic asset count
	local numAssets = {
		[coalition.side.NEUTRAL] = 0,
		[coalition.side.RED] = 0,
		[coalition.side.BLUE] = 0,
	}
	local owner = { count = 0, side = 0 }
	for _, asset in pairs(self._strategicAssets) do
		local count = numAssets[asset.owner] + 1
		if count > owner.count then
			owner.side = asset.owner
			owner.count = count
		end
		numAssets[asset.owner] = count
	end
	self.owner = owner.side
	-- remove assets that are not owned by the majority owner from the count
	for idx, asset in pairs(self._strategicAssets) do
		if asset.owner ~= self.owner then
			table.remove(self._strategicAssets, idx)
		end
	end
	self._maxStrategicAssets = self._maxStrategicAssets or #self._strategicAssets
	self._logger:debug("owner: %d", self.owner)
	self._logger:debug("tracking %d/%d alive strategic assets",
		#self._strategicAssets, self._maxStrategicAssets)
end

function Airspace:_countAliveStrategicAssets()
	if self._strategicAssets == nil then
		return 0
	end
	local count = 0
	for _, asset in pairs(self._strategicAssets) do
		if asset:isDead() == false then
			count = count + 1
		end
	end
	return count
end

-- TODO: need to figure out how to track influence within this space
-- this version of the function only calculates how many strategic objectives
-- have been completed in the region
function Airspace:getStatus()
	if self._maxStrategicAssets == 0 then
		return 0
	end
	local numAlive = self:_countAliveStrategicAssets()
	return math.ceil((1 - numAlive / self._maxStrategicAssets) * 100)
end

function Airspace:update()
	-- set as neutral and notify asset "death" to complete missions
	if self.owner ~= 0 and self:_countAliveStrategicAssets() == 0 then
		self.owner = 0
		self:notify(utils.buildevent.dead(self))
		self._logger:debug("neutralized")
	end
end

function Airspace:isDead()
	return false
end

return Airspace
