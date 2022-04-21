--[[
-- SPDX-License-Identifier: LGPL-3.0
--
-- Exports theater data like remaining tickets and active mission in a stable
-- JSON format
--]]

local lfs      = require("lfs")
local json     = require("libs.json")
local class    = require("libs.class")
local utils    = require("libs.utils")
local dctenum  = require("dct.enum")
local dctutils = require("dct.utils")
local human    = require("dct.ui.human")
local Command  = require("dct.Command")
local Logger   = require("dct.libs.Logger").getByName("DataExport")
local settings = _G.dct.settings.server

-- Reverse maps for asset and mission type names
local ASSET_TYPE = {}
local MISSION_TYPE = {}
local ASSET_MISSION_TYPE = {}

for name, id in pairs(dctenum.assetType) do
    ASSET_TYPE[id] = name
end

for name, id in pairs(dctenum.missionType) do
    MISSION_TYPE[id] = name
end

for msnTypeId, assetTypes in pairs(dctenum.missionTypeMap) do
    for assetTypeId, _ in pairs(assetTypes) do
        ASSET_MISSION_TYPE[assetTypeId] = MISSION_TYPE[msnTypeId]
    end
end

local function countPlayers()
    local num = 0
    for _ in pairs(net.get_player_list()) do
        num = num + 1
    end
    return num
end

local function isoDate(dcsDate)
    return string.format("%d-%d-%d", dcsDate.Year, dcsDate.Month, dcsDate.Day)
end

local function makeData(export)
    return {
        coalitions = {},
        version = dct._VERSION,
        theater = env.mission.theatre,
        sortie  = env.getValueDictByKey(env.mission.sortie),
        period  = dct.settings.server.period,
        startdate = os.date("%F %TZ", os.time(export.theater.startdate)),
        date      = os.date("!%F %TZ"),
        modeldate = isoDate(env.mission.date),
        modeltime = timer.getTime(),
        abstime   = timer.getAbsTime(),
        dcs_version = _G._APP_VERSION,
        players = {
            current = countPlayers(),
            max = export.maxPlayers,
        },
    }
end

local DataExport = class()
function DataExport:__init(theater)
    self.theater = theater
    self.saveToDisk = true
    if settings.exportperiod > 0 then
        local dcsServerSettings =
            utils.readlua(lfs.writedir().."/Config/serverSettings.lua", "cfg")
        self.maxPlayers = dcsServerSettings.maxPlayers
        self.cachedData = makeData(self)
        Logger:debug("running data export every %d seconds",
            settings.exportperiod)
        theater:queueCommand(settings.exportperiod,
            Command("DataExport.update", self.update, self), true)
    else
        Logger:debug("data export disabled")
    end
end

-- Get the ticket counts for each coalition
local function getTickets(tickets, coalition)
    local current, start = tickets:get(coalition)
    local percentage = math.floor((current / start) * 100)
    return {
        text = human.strength(percentage),
        current = current,
        start = start,
    }
end

-- Convert DCS coordinates to a table with latitude, longitude,
-- and the original DCS coordinates
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

-- Expand assigned groups into a table containing the player name
-- and aircraft type
local function getAssignedUnitInfo(mission, assetmgr)
    local output = {}
    local groups = mission.assigned
    for idx, groupname in pairs(groups) do
        local asset = assetmgr:getAsset(groupname)
        if asset ~= nil and type(asset.getPlayerName) == "function" then
            output[idx] = {
                group = groupname,
                player = asset:getPlayerName(),
                aircraft = asset:getAircraftName(),
                iffmode3 = mission:getIFFCodes(asset).m3,
            }
        else
            output[idx] = {
                group = groupname,
            }
        end
    end
    return output
end

-- List all tracked assets of a coalition in each region
local function getAssets(regionmgr, assetmgr, coalition)
    local export = {}
    for region, _ in pairs(regionmgr.regions) do
        export[region] = {}
    end
    for name, asset in assetmgr:iterate() do
        local region = asset.rgnname
        if asset.owner == coalition and
           dctenum.assetClass["INITIALIZE"][asset.type] then
            export[region][name] = {
                dead = asset:isDead(),
                intel = asset.intel,
                ignore = asset.ignore,
                codename = asset.codename,
                spawned = asset:isSpawned(),
                location = getLocation(asset:getLocation()),
                strategic = dctenum.assetClass["STRATEGIC"][asset.type] ~= nil,
                missiontype = ASSET_MISSION_TYPE[asset.type],
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
local function getMissions(commander, assetmgr)
    local missions = {}
    for id, mission in pairs(commander.missions) do
        local tgt = mission:getTargetInfo()
        local pos = dctutils.degrade_position(tgt.location, tgt.intellvl)
        id = tostring(id)
        missions[id] = {
            assigned = getAssignedUnitInfo(mission, assetmgr),
            iffmode1 = mission:getIFFCodes().m1,
            type = MISSION_TYPE[mission.type],
            state = mission:getStateName(),
            timeout = mission:getTimeout(),
            target = {
                name = mission.target,
                region = tgt.region,
                coalition = tostring(tgt.coalition),
                location_degraded = getLocation(pos),
                intel = tgt.intellvl,
                status = tgt.status,
            },
        }
    end
    return missions
end

-- List assorted information from the commander
local function getCommanderInfo(commander)
    return {
        availablemissions = commander:getAvailableMissions(dctenum.missionType),
    }
end

-- Save the data to a file
local function saveToDisk(data)
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
    local assetmgr = theater:getAssetMgr()
    local regionmgr = theater:getRegionMgr()
    local tickets = theater:getSystem("dct.systems.tickets")
    local data = makeData(self)
    local coalitions = data.coalitions

    for _, coalition in pairs(coalition.side) do
        local cmdr = theater:getCommander(coalition)
        local key = tostring(coalition)
        coalitions[key] = {}
        coalitions[key].tickets = getTickets(tickets, coalition)
        coalitions[key].missions = getMissions(cmdr, assetmgr)
        coalitions[key].assets = getAssets(regionmgr, assetmgr, coalition)
        coalitions[key].commander = getCommanderInfo(cmdr)
    end

    if self.saveToDisk then
        saveToDisk(data)
    end
    self.cachedData = data
    return settings.exportperiod
end

-- Get the latest exported data if enabled, else returns nil
function DataExport:get()
    return utils.deepcopy(self.cachedData)
end

return DataExport
