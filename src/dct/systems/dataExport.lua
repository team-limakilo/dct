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

local COALITIONS = {
    1, -- Red
    2, -- Blue
}

-- Reverse maps for asset and mission types
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
    if settings.exportperiod > 0 then
        Logger:debug("enabling data export every %d seconds",
            settings.exportperiod)
        theater:queueCommand(settings.exportperiod,
            Command("DataExport.update", self.update, theater))
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
local function location(point)
    local latitude, longitude, altitude = coord.LOtoLL(point)
    return {
        latitude = latitude,
        longitude = longitude,
        altitude = altitude,
    }
end

-- Expand assigned groups into a table containing the group and player name
local function withPlayerNames(assigned)
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
           dctenum.assetClass["STRATEGIC"][asset.type] then
            export[region][name] = {
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
        local tgtinfo = mission:getTargetInfo()
        id = tostring(id)
        missions[id] = {
            id = id,
            assigned = withPlayerNames(mission.assigned),
            coalition = tostring(mission.cmdr.owner),
            type = MISSION_TYPE[mission.type],
            target = {
                name = mission.target,
                intel = tgtinfo.intellvl,
                codename = tgtinfo.callsign,
                location = location(tgtinfo.location),
                status = tgtinfo.status,
                region = tgtinfo.region,
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
		return Logger:error("unable to open '%s'; msg: %s", path, tostring(msg))
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
    return settings.exportperiod
end

return DataExport
