--[[
-- SPDX-License-Identifier: LGPL-3.0
--
-- Exports theater data like remaining tickets and active mission in a stable
-- JSON format
--]]

local dctenum  = require("dct.enum")
local json     = require("libs.json")
local class    = require("libs.class")
local Command  = require("dct.Command")
local Logger   = require("dct.libs.Logger").getByName("dataExport")
local settings = _G.dct.settings.server

local PERIOD = 30 -- Run every half a minute
local COALITIONS = {
    1, -- Red
    2, -- Blue
}

-- Reverse maps for asset and missiont types
local ASSET_TYPE = {}
local MISSION_TYPE = {}

for name, id in pairs(dctenum.assetType) do
    ASSET_TYPE[id] = name
end

for name, id in pairs(dctenum.missionType) do
    MISSION_TYPE[id] = name
end

local DataExport = class()
function DataExport:__init(theater)
    theater:queueCommand(PERIOD,
        Command("DataExport.update", self.update, theater))
end

-- Get the ticket counts for each coalition
local function getTickets(tickets, coalition)
    local current, start = tickets:get(coalition)
    return {
        current = current,
        start = start,
    }
end

-- Create a filter function to fetch all strategic assets of a coalition in a
-- given region
local function getFilter(region, coalition)
    return function(asset)
        return dctenum.assetClass["STRATEGIC"][asset.type]
           and asset.rgnname == region and asset.owner == coalition
    end
end

-- Convert DCS coordinates to a table with latitude, longitude, and altitude
local function location(point)
    local latitude, longitude, altitude = coord.LOtoLL(point)
    return {
        latitude = latitude,
        longitude = longitude,
        altitude = altitude,
    }
end

-- List strategic assets per coalition
local function getAssetsByRegion(theater, coalition)
    local assetmgr = theater:getAssetMgr()
    local regions = theater.regions
    local export = {}
    for region, _ in pairs(regions) do
        export[region] = {}
        local filter = getFilter(region, coalition)
        local assets = assetmgr:filterAssets(filter)
        for assetname, _ in pairs(assets) do
            local asset = assetmgr:getAsset(assetname)
            export[region][assetname] = {
                dead = asset._dead,
                codename = asset.codename,
                type = ASSET_TYPE[asset.type],
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
        missions[tostring(id)] = {
            id = tostring(mission.id),
            assigned = mission.assigned,
            coalition = tostring(mission.cmdr.owner),
            type = MISSION_TYPE[mission.type],
            target = {
                name = mission.target,
                codename = mission.tgtinfo.callsign,
                location = location(mission.tgtinfo.location),
                intel = mission.tgtinfo.intellvl,
                status = mission.tgtinfo.status,
            },
        }
    end
    return missions
end

-- Save the file to the disk
local function export(data)
    local path = settings.statepath..".export.json"
    local file, msg = io.open(path, "w+")

	if file == nil then
		return Logger:error(
            string.format("unable to open '%s'; msg: %s", path, tostring(msg)))
	end

    file:write(json:encode_pretty(data))
    file:close()
end

-- Run the data export
function DataExport.update(theater)
    local tickets = theater:getSystem("dct.systems.tickets")
    local data = {
        coalitions = {},
        version = dct._VERSION,
    }

    local coalitions = data.coalitions

    for _, coalition in pairs(COALITIONS) do
        local key = tostring(coalition)
        coalitions[key] = {}
        coalitions[key].tickets = getTickets(tickets, coalition)
        coalitions[key].missions = getMissions(theater:getCommander(coalition))
        coalitions[key].assets = getAssetsByRegion(theater, coalition)
    end

    export(data)
    return PERIOD
end

return DataExport
