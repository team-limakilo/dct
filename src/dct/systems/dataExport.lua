--[[
-- SPDX-License-Identifier: LGPL-3.0
--
-- Exports theater data like remaining tickets and active mission in a stable
-- JSON format
--]]

local json     = require("libs.json")
local class    = require("libs.class")
local utils    = require("libs.utils")
local dctenum  = require("dct.enum")
local Command  = require("dct.Command")
local Logger   = require("dct.libs.Logger").getByName("DataExport")
local settings = _G.dct.settings.server

-- Reverse maps for asset and mission type names
local ASSET_TYPE = {}
local MISSION_TYPE = {}

for name, id in pairs(dctenum.assetType) do
    ASSET_TYPE[id] = name
end

for name, id in pairs(dctenum.missionType) do
    MISSION_TYPE[id] = name
end

local function makeData()
    return {
        coalitions = {},
        version = dct._VERSION,
        theater = env.mission.theatre,
        date = os.date("!%F %TZ"),
    }
end

local DataExport = class()
function DataExport:__init(theater)
    self.theater = theater
    if settings.exportperiod > 0 then
        self.cachedData = makeData()
        Logger:debug("running data export every %d seconds",
            settings.exportperiod)
        theater:queueCommand(settings.exportperiod,
            Command("DataExport.update", self.update, self))
    else
        Logger:debug("data export disabled")
    end
end

-- Get the ticket counts for each coalition
local function getTickets(tickets, coalition)
    local current, start = tickets:get(coalition)
    return {
        current = current,
        start = start,
    }
end

-- Convert DCS coordinates to a table with latitude, longitude, and altitude
local function getLocation(point)
    local latitude, longitude = coord.LOtoLL(point)
    return {
        x = point.x,
        y = point.y,
        z = point.z,
        lat = latitude,
        lon = longitude,
    }
end

-- Expand assigned groups into a table containing the group and player name
local function getGroupAndPlayerName(assigned)
    local output = {}
    for id, groupname in pairs(assigned) do
        local group = Group.getByName(groupname)
        -- Protect against dead/removed units during data export
        if group ~= nil and group:getUnit(1) ~= nil then
            output[id] = {
                group = groupname,
                player = group:getUnit(1):getPlayerName(),
            }
        else
            output[id] = {
                group = groupname,
            }
        end
    end
    return output
end

-- List all tracked assets of a coalition in each region
local function getAssetsByRegion(theater, coalition)
    local assetmgr = theater:getAssetMgr()
    local export = {}
    for region, _ in pairs(theater:getRegionMgr().regions) do
        export[region] = {}
    end
    for name, asset in pairs(assetmgr._assetset) do
        local region = asset.rgnname
        if asset.owner == coalition and
           dctenum.assetClass["INITIALIZE"][asset.type] then
            export[region][name] = {
                dead = asset._dead,
                intel = asset.intel,
                codename = asset.codename,
                location = getLocation(asset:getLocation()),
                strategic = dctenum.assetClass["STRATEGIC"][asset.type] ~= nil,
                status = asset:getStatus(),
                type = ASSET_TYPE[asset.type],
                sitetype = asset.sitetype,
                cost = asset.cost,
            }
        end
    end
    return export
end

-- List active missions
local function getMissions(commander)
    local missions = {}
    for id, mission in pairs(commander.missions) do
        local tgtinfo = mission:getTargetInfo()
        id = tostring(id)
        missions[id] = {
            assigned = getGroupAndPlayerName(mission.assigned),
            type = MISSION_TYPE[mission.type],
            target = {
                name = mission.target,
                region = tgtinfo.region,
                coalition = tgtinfo.coalition,
            },
        }
    end
    return missions
end

-- Save the data to a file
local function export(data)
    local path = settings.statepath..".export.json"
    local file, msg = io.open(path, "w+")

	if file == nil then
		return Logger:error("unable to open '%s'; msg: %s", path, tostring(msg))
	end

    if settings.debug == true then
        file:write(json:encode_pretty(data))
    else
        file:write(json:encode(data))
    end

    file:close()
end

-- Run the data export
function DataExport:update()
    local theater = self.theater
    local tickets = theater:getSystem("dct.systems.tickets")
    local data = makeData()

    local coalitions = data.coalitions

    for _, coalition in pairs(coalition.side) do
        local key = tostring(coalition)
        coalitions[key] = {}
        coalitions[key].tickets = getTickets(tickets, coalition)
        coalitions[key].missions = getMissions(theater:getCommander(coalition))
        coalitions[key].assets = getAssetsByRegion(theater, coalition)
    end

    export(data)
    self.cachedData = data
    return settings.exportperiod
end

-- Get the latest exported data if enabled, else returns nil
function DataExport:get()
    return utils.deepcopy(self.cachedData)
end

return DataExport
