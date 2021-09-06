--[[
-- SPDX-License-Identifier: LGPL-3.0
--]]

require("math")
local class     = require("libs.class")
local utils     = require('dct.utils')
local Command   = require("dct.Command")
local vec       = require("dct.libs.vector")
local Logger    = require("dct.libs.Logger").getByName("RenderManager")
local StaticAsset = require("dct.assets.StaticAsset")

-- how long to wait between render checks
local CHECK_INTERVAL = 10

-- how long to keep an asset in the world after it's out of range
local DESPAWN_TIMEOUT = 180

local RangeType = {
    Player  = 1,
    Missile = 2,
}

-- maps specific unit attributes to maximum intended render ranges, in meters
local RENDER_RANGES = {
    [RangeType.Player] = {
        ["Ships"]       = 480000,
        ["EWR"]         = 320000,
        ["LR SAM"]      = 320000,
        ["MR SAM"]      = 160000,
        ["Default"]     =  40000,
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

-- exhaustively search every unit in every group in the template of the asset
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

local RenderManager = class()
function RenderManager:__init(theater)
    self.t         =  0 -- last update time
    self.object    = {} -- object of interest locations as Vector3D
    self.assets    = {} -- assets grouped by region
    self.assetPos  = {} -- asset locations as Vector3D
    self.lastSeen  = {} -- time each asset was last seen
    self.ranges    = {} -- asset render ranges
    self.missiles  = {} -- tracked missiles

    -- listen to weapon fired events to track stand-off weapons
    theater:addObserver(self.onDCSEvent, self, "RenderManager.onDCSEvent")

    -- defer init until after regions are set up
    theater:queueCommand(5, Command("RenderManager.delayedInit",
        self.delayedInit, self, theater))
end

local function isPlayer(object)
    return object:getPlayerName() ~= nil
end

local function weaponIsTracked(weapon)
    local desc = weapon:getDesc()
    return desc.category == Weapon.Category.MISSILE and
          (desc.missileCategory == Weapon.MissileCategory.ANTI_SHIP or
           desc.missileCategory == Weapon.MissileCategory.CRUISE or
           desc.missileCategory == Weapon.MissileCategory.OTHER)
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

function RenderManager:inRange(location, rangeType, asset)
    -- targeted assets should always be visible
    if asset:isTargeted(utils.getenemy(asset.owner)) then
        return true
    end
    -- compute and save asset render ranges for future lookups
    if self.ranges[asset.name] == nil then
        self.ranges[asset.name] = {}
        for _, type in pairs(RangeType) do
            self.ranges[asset.name][type] = calculateRange(asset, type)
        end
    end
    local dist = vec.distance(location, self.assetPos[asset.name])
    return dist <= self.ranges[asset.name][rangeType]
end

function RenderManager:update(assetmgr, time)
    if time - self.t > CHECK_INTERVAL / 2 then
        Logger:debug("_update()")
        self.t = time
        -- update player and missile locations
        self.objects = {}
        for co = 0, 2 do
            for _, player in pairs(coalition.getPlayers(co)) do
                table.insert(self.objects, {
                    location = vec.Vector3D(player:getPoint()),
                    rangeType = RangeType.Player,
                })
            end
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
        -- update asset locations
        self.assets = {}
        self.assetPos = {}
        for _, asset in assetmgr:iterate() do
            if asset:isa(StaticAsset) and asset:getLocation() ~= nil then
                self.lastSeen[asset.name] = self.lastSeen[asset.name] or -900
                self.assets[asset.rgnname] = self.assets[asset.rgnname] or {}
                self.assetPos[asset.name] = vec.Vector3D(asset:getLocation())
                table.insert(self.assets[asset.rgnname], asset)
            end
        end
    end
end

function RenderManager:delayedInit(theater, time)
    local assetmgr = theater:getAssetMgr()
    local regions = theater:getRegionMgr().regions
    for region, _ in pairs(regions) do
        local cmdname = string.format("RenderManager.checkRegion(%s)", region)
        theater:queueCommand(CHECK_INTERVAL,
            Command(cmdname, self.checkRegion, self, region, assetmgr))
    end
    self:update(assetmgr, time)
end

function RenderManager:checkRegion(region, assetmgr, time)
    self:update(assetmgr, time)
    local assets = self.assets[region]
    if assets ~= nil then
        -- O(n²) algorithm :(
        for _, asset in pairs(assets) do
            if asset:isSpawned() then
                local seen = false
                for _, obj in pairs(self.objects) do
                    if self:inRange(obj.location, obj.rangeType, asset) then
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
                for _, obj in pairs(self.objects) do
                    if self:inRange(obj.location, obj.rangeType, asset) then
                        self.lastSeen[asset.name] = time
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
