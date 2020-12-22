#!/usr/bin/lua

require("os")
require("dcttestlibs")
require("dct")
local json  = require("libs.json")
local vector = require("dct.libs.vector")
local dcsenum  = require("dct.dcs.enum")
local dcstasks = require("dct.dcs.aitasks")

local function main()
	local task = dcstasks.command.createTACAN("TST", 74,
		dcsenum.BEACON.TACANMODE.X, "test", false, false, true)
	print("TACAN: "..json:encode_pretty(task))

	task = dcstasks.option.create(AI.Option.Air.id.REACTION_ON_THREAT,
		AI.Option.Air.val.REACTION_ON_THREAT.PASSIVE_DEFENCE)
	print("Option: "..json:encode_pretty(task))

	local mission = dcstasks.Mission(true)
	local waypoint = dcstasks.Waypoint(AI.Task.WaypointType.TAKEOFF,
		vector.Vector3D.create(5, 10, 2000), 200, "Takeoff")
	waypoint:addTask(
		dcstasks.option.create(AI.Option.Air.id.REACTION_ON_THREAT,
			AI.Option.Air.val.REACTION_ON_THREAT.PASSIVE_DEFENCE))
	waypoint:addTask(dcstasks.command.eplrs(true))
	mission:addWaypoint(waypoint)
	waypoint = dcstasks.Waypoint(AI.Task.WaypointType.TURNING_POINT,
		vector.Vector3D.create(100, -430, 1000), 200, "Ingress")
	waypoint:addTask(dcstasks.task.orbit(AI.Task.OrbitPattern.RACE_TRACK,
		vector.Vector2D.create(100, -450),
		vector.Vector2D.create(400, -600),
		190, 6500))
	waypoint:addTask(dcstasks.task.tanker())
	mission:addWaypoint(waypoint)
	print("Mission: "..json:encode_pretty(mission:raw()))
	return 0
end

os.exit(main())
