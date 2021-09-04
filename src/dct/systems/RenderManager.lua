--[[
-- SPDX-License-Identifier: LGPL-3.0
--]]

require("math")
local class     = require("libs.class")
local Command   = require("dct.Command")
local vec       = require("dct.libs.vector")
local Logger    = require("dct.libs.Logger").getByName("RenderManager")
local StaticAsset = require("dct.assets.StaticAsset")

-- how long to wait between render checks
local CHECK_INTERVAL = 10

-- how long to keep an asset in the world after it's out of range
-- from any player
local DESPAWN_TIMEOUT = 60

-- maps specific unit attributes to maximum intended render ranges, in meters
local ATTRIBUTE_RENDER_RANGES = {
    ["Ships"]       = 480000,
    ["EWR"]         = 320000,
    ["LR SAM"]      = 320000,
    ["MR SAM"]      = 160000,
}

-- default range of 40km (max useful TGP distance)
local DEFAULT_RANGE = 40000

-- exhaustively search every unit in every group in the template of the asset
-- to find its maximum render range based on unit attributes
local function calculateRange(asset)
    local template = asset:getTemplate()
    local assetRange = DEFAULT_RANGE
    if template == nil then
        return assetRange
    end
    for _, group in pairs(template) do
        Logger:debug("asset %s group %s", asset.name, group.data.name)
        if group.data ~= nil and group.data.units ~= nil then
            local groupRange = 0
            for _, unit in pairs(group.data.units) do
                local desc = Unit.getDescByName(unit.type)
                for attr, unitRange in pairs(ATTRIBUTE_RENDER_RANGES) do
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

local RenderManager = class()
function RenderManager:__init(theater)
    self._t         =  0 -- last update time
    self._players   = {} -- player positions as Vector3D
    self._assets    = {} -- assets grouped by region
    self._assetPos  = {} -- asset positions as Vector3D
    self._lastSeen  = {} -- time each asset was last seen
    self._ranges    = {} -- asset render ranges
    -- defer init to after regions are set up
    theater:queueCommand(5, Command("RenderManager._delayedInit",
        self._delayedInit, self, theater))
end

function RenderManager:_inRange(playerPos, asset)
    if self._ranges[asset.name] == nil then
        self._ranges[asset.name] = calculateRange(asset)
    end
    local dist = vec.distance(playerPos, self._assetPos[asset.name])
    return dist <= self._ranges[asset.name]
end

function RenderManager:_update(assetmgr, time)
    if time - self._t > CHECK_INTERVAL / 2 then
        Logger:debug("_update()")
        self._t = time
        -- update player positions
        self._players = {}
        for co = 0, 2 do
            for _, player in pairs(coalition.getPlayers(co)) do
                local pos = vec.Vector3D(player:getPoint())
                table.insert(self._players, pos)
            end
        end
        -- update asset lists
        self._assets = {}
        self._assetPos = {}
        for _, asset in assetmgr:iterate() do
            if asset:isa(StaticAsset) and asset:getLocation() ~= nil then
                self._lastSeen[asset.name] = self._lastSeen[asset.name] or 0
                self._assets[asset.rgnname] = self._assets[asset.rgnname] or {}
                self._assetPos[asset.name] = vec.Vector3D(asset:getLocation())
                table.insert(self._assets[asset.rgnname], asset)
            end
        end
    end
end

function RenderManager:_delayedInit(theater, time)
    local assetmgr = theater:getAssetMgr()
    local regions = theater:getRegionMgr().regions
    for region, _ in pairs(regions) do
        local cmdname = string.format("RenderManager._checkRegion(%s)", region)
        theater:queueCommand(CHECK_INTERVAL,
            Command(cmdname, self._checkRegion, self, region, assetmgr))
    end
    self:_update(assetmgr, time)
end

function RenderManager:_checkRegion(region, assetmgr, time)
    self:_update(assetmgr, time)
    local players = self._players
    local assets = self._assets[region]
    if assets ~= nil then
        -- O(n²) algorithm :(
        for _, asset in pairs(assets) do
            if asset:isSpawned() then
                local keep = false
                for _, player in pairs(players) do
                    if self:_inRange(player, asset) then
                        self._lastSeen[asset.name] = time
                        keep = true
                        break
                    end
                end
                if not keep then
                    Logger:debug("%s time - lastSeen: %d",
                        asset.name, time - self._lastSeen[asset.name])
                    if time - self._lastSeen[asset.name] > DESPAWN_TIMEOUT then
                        asset:despawn()
                    end
                end
            else
                for _, player in pairs(players) do
                    if self:_inRange(player, asset) then
                        self._lastSeen[asset.name] = time
                        asset:spawn()
                        break
                    end
                end
            end
        end
    end
    return CHECK_INTERVAL
end

return RenderManager
