#!/usr/bin/lua

require("math")
math.randomseed(50)
require("dcttestlibs")
require("dct")

local Mission = require("dct.ai.Mission")
local enum    = require("dct.enum")

local function main()
	local theater = dct.Theater()
	_G.dct.theater = theater
	theater:exec(50)

    local tgt = theater:getAssetMgr():getAsset("Krasnodar_1_KrasnodarFuelDump")
    local cmdr = theater:getCommander(coalition.side.BLUE)
    local mission = Mission(cmdr, enum.missionType.STRIKE, tgt, {})
    mission.id = 5000
    cmdr:addMission(mission)

    local export = theater:getSystem("dct.systems.dataExport")
    export:update()

    export.suffix = ".ended"
    export:onEvent({ id = world.event.S_EVENT_MISSION_END })
    export:update()

	return 0
end

os.exit(main())
