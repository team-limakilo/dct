#!/usr/bin/lua

require("math")
math.randomseed(50)
require("dcttestlibs")
require("dct")

local Mission = require("dct.ai.Mission")
local enum    = require("dct.enum")

-- create a player group
local grp = Group(4, {
	["id"] = 9,
	["name"] = "VMFA251 - Enfield 1-1",
	["coalition"] = coalition.side.BLUE,
	["exists"] = true,
})

local unit1 = Unit({
	["name"] = "pilot1",
	["exists"] = true,
	["desc"] = {
        ["displayName"] = "F/A-18C Hornet",
		["typeName"] = "FA-18C_hornet",
		["attributes"] = {},
	},
}, grp, "bobplayer")

_G.GRPC = {
    methods = {},
    success = function(arg)
        return arg
    end,
    errorNotFound = function(msg)
        return nil, "ErrorNotFound", msg
    end,
}

local function checkError(err, msg)
    assert(err == nil, string.format("Caught %s with msg: '%s'",
        tostring(err), tostring(msg)))
end

local function main()
    _G.dct.settings.server.exportperiod = 60
	local theater = dct.Theater()
	_G.dct.theater = theater
	theater:exec(50)
	theater:onEvent({
		["id"]        = world.event.S_EVENT_BIRTH,
		["initiator"] = unit1,
	})

    local player = theater:getAssetMgr():getAsset(grp:getName())

    local rpcSystem = theater:getSystem("dct.systems.overlordBotRPC")
    assert(rpcSystem ~= nil,
        "OverlordBot RPC system was not loaded by the theater")

    local _, err, msg, exportData

    -- Start mission
    _, err, msg = GRPC.methods.requestMissionAssignment({
        groupName = grp:getName(),
        missionType = "Strike",
    })
    checkError(err, msg)
    theater:exec(60)
    assert(player.missionid ~= enum.missionInvalidID,
        "player mission request did not complete")

    -- Leave mission
    _, err, msg = GRPC.methods.abortMission({
        groupName = grp:getName(),
    })
    checkError(err, msg)
    theater:exec(70)
    assert(player.missionid == enum.missionInvalidID,
        "player did not leave the mission")

    -- Join another mission
    local tgt = theater:getAssetMgr():getAsset("Krasnodar_1_KrasnodarFactory")
    local cmdr = theater:getCommander(coalition.side.BLUE)
    local mission = Mission(cmdr, enum.missionType.SEAD, tgt, {})
    cmdr:addMission(mission)

    _, err, msg = GRPC.methods.joinMission({
        groupName = grp:getName(),
        missionCode = tostring(mission.id),
    })
    checkError(err, msg)
    theater:exec(80)
    assert(player.missionid == mission.id, string.format(
        "player did not join mission '%s' (current mission: '%s')",
        tostring(mission.id), tostring(player.missionid)))

    -- Request mission status
    _, err, msg = GRPC.methods.getMissionStatus({
        groupName = grp:getName(),
    })
    checkError(err, msg)
    trigger.action.setassert(true)
    trigger.action.setmsgbuffer(
        "Mission State: Active\n"..
        "Package: 3730\n"..
        "Timeout: 2016-06-21 14:00z (in 180 mins)\n"..
        "BDA: 0% complete\n"..
        "\n"..
        "Assigned Pilots:\n"..
        "bobplayer (F/A-18C Hornet)")
    theater:exec(90)
    trigger.action.setassert(false)

    -- Test export system endpoint
    exportData, err, msg = GRPC.methods.getExportData()
    checkError(err, msg)
    assert(type(exportData) == "table",
        "expected export data to be a table")
    assert(exportData.version == _G.dct._VERSION,
        "expected export data to contain DCT version")

	return 0
end

os.exit(main())
