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

-- Reverse maps for int -> string lookups
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

local function getPlayers()
    local players = {}
    for _, id in pairs(net.get_player_list()) do
        table.insert(players, {
            id = net.get_player_info(id, 'id'),
            name = net.get_player_info(id, 'name'),
            slot = net.get_player_info(id, 'slot'),
            side = net.get_player_info(id, 'side'),
        })
    end
    return players
end

local function formatDcsMissionDate(date)
    return string.format("%d-%d-%d", date.Year, date.Month, date.Day)
end

local function formatLuaDate(date)
    return string.format("%d-%02d-%02d %02d:%02d:%02dZ",
        date.year, date.month, date.day,
        date.hour, date.min, date.sec)
end

local function createExportData(dataExport)
    local players = getPlayers()
    local data = {
        coalitions  = {},
        version     = dct._VERSION,
        theater     = env.mission.theatre,
        sortie      = env.getValueDictByKey(env.mission.sortie),
        period      = dct.settings.server.period,
        date        = os.date("!%F %TZ"),
        runtimeinit = dataExport.runtimeinit,
        startdate   = formatLuaDate(dataExport.theater.startdate),
        modeldate   = formatDcsMissionDate(env.mission.date),
        modeltime   = timer.getTime(),
        abstime     = timer.getAbsTime(),
        dcs_version = _G._APP_VERSION,
        ended       = dataExport.ended,
        players     = {
            current = #players,
            max = dataExport.dcsServerSettings.maxPlayers,
            list = players,
        },
    }
    if data.ended then
        data.players.current = 0
    end
    return data
end

local DataExport = class()
function DataExport:__init(theater)
    self.runtimeinit = os.date("!%F %TZ")
    self.theater = theater
    self.saveToDisk = true
    self.ended = false
    self.suffix = ""
    if settings.exportperiod > 0 then
        self.dcsServerSettings =
            utils.readlua(lfs.writedir().."/Config/serverSettings.lua", "cfg")
        self.cachedData = createExportData(self)
        Logger:debug("running data export every %d seconds",
            settings.exportperiod)
        theater:queueCommand(settings.exportperiod,
            Command("DataExport.update", self.update, self), true)
        world.addEventHandler(self)
    else
        Logger:debug("data export disabled")
    end
end

local function getTickets(tickets, coalition)
    local current, start = tickets:get(coalition)
    local percentage = math.floor((current / start) * 100)
    return {
        text = human.strength(percentage),
        current = current,
        start = start,
    }
end

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

local function getAssignedUnits(mission, assetmgr)
    local output = {}
    local groups = mission.assigned
    for idx, groupname in pairs(groups) do
        local asset = assetmgr:getAsset(groupname)
        if asset ~= nil and type(asset.getPlayerName) == "function" then
            output[idx] = {
                group = groupname,
                type = asset:getTypeName(),
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

local function getStrategicAssets(regionmgr, assetmgr, commander)
    local export = {}
    for region, _ in pairs(regionmgr.regions) do
        export[region] = {}
    end
    for name, asset in assetmgr:iterate() do
        local region = asset.rgnname
        if asset.owner == commander.owner and
           dctenum.assetClass["INITIALIZE"][asset.type] then
            -- Because `regionmgr.regions` is based on the filesystem structure,
            -- and assets are loaded from the state file, there is a chance that
            -- a region was deleted from the theater while there are still
            -- valid assets in said region, so we need to handle that edge case
            if export[region] == nil then
                export[region] = {}
            end
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

local function getActiveMissions(commander, assetmgr)
    local missions = {}
    for id, mission in pairs(commander.missions) do
        local tgt = mission:getTargetInfo()
        local pos = dctutils.degrade_position(tgt.location, tgt.intellvl)
        id = tostring(id)
        missions[id] = {
            assigned = getAssignedUnits(mission, assetmgr),
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

local function getCommanderInfo(commander)
    return {
        availablemissions = commander:getAvailableMissions(dctenum.missionType),
    }
end

-- Save the data to a file
local function saveToDisk(data, suffix)
    local path = settings.statepath..suffix..".export.json"
    local file, msg = io.open(path, "w+")

	if file == nil then
		Logger:error("unable to open '%s'; msg: %s", path, tostring(msg))
        return
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
    local data = createExportData(self)
    local coalitions = data.coalitions

    for _, coalition in pairs(coalition.side) do
        local cmdr = theater:getCommander(coalition)
        local key = tostring(coalition)
        coalitions[key] = {
            assets    = {},
            commander = {},
            tickets   = {},
            missions  = {},
        }
        coalitions[key].assets = getStrategicAssets(regionmgr, assetmgr, cmdr)
        coalitions[key].commander = getCommanderInfo(cmdr)
        coalitions[key].tickets = getTickets(tickets, coalition)
        if not self.ended then
            coalitions[key].missions = getActiveMissions(cmdr, assetmgr)
        end
    end

    if self.saveToDisk then
        saveToDisk(data, self.suffix)
    end
    self.cachedData = data
    return settings.exportperiod
end

-- Track events so we can tell when the mission is over
function DataExport:onEvent(event)
    if event.id == world.event.S_EVENT_MISSION_END then
        self.ended = true
        -- This check prevents an extra error if the theater fails to initialize
        if self.theater:getRegionMgr() ~= nil then
            self:update()
        end
    end
end

-- If enabled, gets the latest export data
function DataExport:get()
    return utils.deepcopy(self.cachedData)
end

return DataExport
