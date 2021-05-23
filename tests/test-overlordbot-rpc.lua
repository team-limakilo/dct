#!/usr/bin/lua

require("math")
math.randomseed(50)
require("dcttestlibs")
require("dct")

local Mission = require("dct.ai.Mission")
local enum    = require("dct.enum")

-- create a player group
local grp = Group(4, {
	["id"] = 12,
	["name"] = "99thFS Uzi 11",
	["coalition"] = coalition.side.BLUE,
	["exists"] = true,
})

local unit1 = Unit({
	["name"] = "pilot1",
	["exists"] = true,
	["desc"] = {
		["typeName"] = "FA-18C_hornet",
		["attributes"] = {},
	},
}, grp, "bobplayer");

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

    local _, err, msg

    -- Start mission
    _, err, msg = GRPC.methods.requestMissionAssignment({
        unitName = "pilot1",
        missionType = "Strike",
    })
    checkError(err, msg)
    theater:exec(60)
    assert(player.missionid ~= nil, "player mission request did not complete")

    -- Leave mission
    dct.Theater.playerRequest({
        name = grp:getName(),
        type = enum.uiRequestType.MISSIONABORT,
    })
    theater:exec(70)
    assert(player.missionid == nil, "player did not leave the mission")

    -- Join another mission
    local tgt = theater:getAssetMgr():getAsset("Test region_1_bldgTest")
    local cmdr = theater:getCommander(coalition.side.BLUE)
    local mission = Mission(cmdr, enum.missionType.SEAD, tgt, {})
    cmdr:addMission(mission)

    _, err, msg = GRPC.methods.joinMission({
        unitName = unit1:getName(),
        missionCode = tostring(mission.id),
    })
    checkError(err, msg)
    theater:exec(80)
    assert(player.missionid == mission.id, string.format(
        "player did not join mission '%s' (current mission: '%s')",
        tostring(mission.id), tostring(player.missionid)))

	return 0
end

os.exit(main())
