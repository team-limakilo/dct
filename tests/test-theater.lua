#!/usr/bin/lua

require("os")
require("io")
local md5 = require("md5")
require("dcttestlibs")
require("dct")
local enum   = require("dct.enum")
local settings = _G.dct.settings.server
local DEBUG = false

local events = {
	{
		["id"] = world.event.S_EVENT_DEAD,
		["object"] = {
			["name"] = "Novorossiysk_NovoShipsinPort 1 SHIP 1-1",
			["objtype"] = Object.Category.UNIT,
		},
	},{
		["id"] = world.event.S_EVENT_DEAD,
		["object"] = {
			["name"] = "Novorossiysk_NovoShipsinPort 1 SHIP 1-2",
			["objtype"] = Object.Category.UNIT,
		},
	},{
		["id"] = world.event.S_EVENT_DEAD,
		["object"] = {
			["name"] = "Novorossiysk_NovoShipsinPort 1 SHIP 1-3",
			["objtype"] = Object.Category.UNIT,
		},
	},{
		["id"] = world.event.S_EVENT_DEAD,
		["object"] = {
			["name"] = "Novorossiysk_NovoShipsinPort 1 SHIP 1-4",
			["objtype"] = Object.Category.UNIT,
		},
	},{
		["id"] = world.event.S_EVENT_DEAD,
		["object"] = {
			["name"] = "Novorossiysk_NovoShipsinPort 1 SHIP 1-5",
			["objtype"] = Object.Category.UNIT,
		},
	},{
		["id"] = world.event.S_EVENT_DEAD,
		["object"] = {
			["name"] = "Novorossiysk_NovoShipsinPort 1 SHIP 1-6",
			["objtype"] = Object.Category.UNIT,
		},
	},{
		["id"] = world.event.S_EVENT_DEAD,
		["object"] = {
			["name"] = "Krasnodar_KrasnodarEWR 1 GROUND_UNIT 1-1",
			["objtype"] = Object.Category.UNIT,
		},
	},{
		["id"] = world.event.S_EVENT_DEAD,
		["object"] = {
			["name"] = "Krasnodar_KrasnodarEWR 1 GROUND_UNIT 1-2",
			["objtype"] = Object.Category.UNIT,
		},
	},{
		["id"] = world.event.S_EVENT_DEAD,
		["object"] = {
			["name"] = "Sukhumi_SukhumiAmmoDump 2 GROUND_UNIT 11-1",
			["objtype"] = Object.Category.UNIT,
		},
	},
}

local function copyfile(src, dest)
	local json = require("libs.json")
	local orig = io.open(src, "r")
	local save = io.open(dest, "w")
	save:write(json:encode_pretty(json:decode(orig:read("*a"))))
	orig:close()
	save:close()
end

local function createEvent(eventdata, player)
	local event = {}
	local objref

	if eventdata.object.objtype == Object.Category.UNIT then
		objref = Unit.getByName(eventdata.object.name)
	elseif eventdata.object.objtype == Object.Category.STATIC then
		objref = StaticObject.getByName(eventdata.object.name)
	elseif eventdata.object.objtype == Object.Category.GROUP then
		objref = Group.getByName(eventdata.object.name)
	else
		assert(false, "other object types not supported")
	end

	assert(objref, "objref is nil for '"..eventdata.object.name.."'")
	event.id = eventdata.id
	event.time = 2345
	if event.id == world.event.S_EVENT_DEAD then
		event.initiator = objref
		objref.clife = 0
		Object.destroy(objref)
	elseif event.id == world.event.S_EVENT_HIT then
		event.initiator = player
		event.weapon = nil
		event.target = objref
		objref.clife = objref.clife - eventdata.object.life
	else
		assert(false, "other event types not supported: "..tostring(event.id))
	end
	return event
end


local function main()
	local startdate = os.date("!*t")
	local playergrp = Group(4, {
		["id"] = 9,
		["name"] = "VMFA251 - Enfield 1-1",
		["coalition"] = coalition.side.BLUE,
		["exists"] = true,
	})
	local player1 = Unit({
		["name"]   = "player1",
		["exists"] = true,
		["desc"] = {
			["displayName"] = "F/A-18C Hornet",
			["typeName"] = "FA-18C_hornet",
			["attributes"] = {},
		},
	}, playergrp, "bobplayer")

	local theater = dct.Theater()
	_G.dct.theater = theater
	theater.startdate = startdate
	theater:exec(50)
	local expected = 32
	assert(dctcheck.spawngroups == expected,
		string.format("group spawn broken; expected(%d), got(%d)",
		expected, dctcheck.spawngroups))
	expected = 29
	assert(dctcheck.spawnstatics == expected,
		string.format("static spawn broken; expected(%d), got(%d)",
		expected, dctcheck.spawnstatics))

	--[[ TODO: test ATO once support is added for squadron
	local restriction =
		theater:getATORestrictions(coalition.side.BLUE, "A-10C")
	local validtbl = { ["BAI"] = 5, ["CAS"] = 1, ["STRIKE"] = 3,
		["ARMEDRECON"] = 7,}
	for k, v in pairs(restriction) do
		assert(validtbl[k] == v, "ATO Restriction error")
	end
	--]]

	-- kill off some units
	for _, eventdata in ipairs(events) do
		theater:onEvent(createEvent(eventdata, player1))
	end

	-- run all pending commands
	theater:exec(100)
	theater:exec(200)
	theater:export()
	local f = io.open(settings.statepath, "r")
	local sumorig = md5.sumhexa(f:read("*all"))
	f:close()
	if DEBUG == true then
		print("sumorig: "..tostring(sumorig))
		copyfile(settings.statepath, settings.statepath..".orig")
	end

	local newtheater = dct.Theater()
	_G.dct.theater = newtheater
	theater.startdate = startdate
	newtheater:exec(50)

	-- verify the units read in do not include the ones we killed off
	local deadasset = "Krasnodar_1_KrasnodarEWR"
	assert(newtheater:getAssetMgr():getAsset(deadasset) == nil,
		"state saving has an issue, dead asset is alive: "..deadasset)
	local deadunit = "Sukhumi_SukhumiAmmoDump 2 GROUND_UNIT 11-1"
	assert(Unit.getByName(deadunit) == nil,
		"state saving has an issue, dead unit is alive: "..deadunit)

	-- attempt to get theater status
	newtheater:onEvent({
		["id"]        = world.event.S_EVENT_BIRTH,
		["initiator"] = player1,
	})

	local status = {
		["data"] = {
			["name"]   = playergrp:getName(),
			["type"]   = enum.uiRequestType.THEATERSTATUS,
		},
		["assert"]     = true,
		["expected"]   = "== Theater Status ==\n"..
			"Friendly Force Str: Nominal\nEnemy Force Str: Nominal\n\n"..
			"Airbases:\n  Friendly: CVN-71 Theodore Roosevelt\n  "..
			"Friendly: Kutaisi\n  Friendly: Senaki-Kolkhi\n  Hostile: Krymsk\n\n"..
			"Current Active Air Missions:\n  None\n\n"..
			"Available missions:\n  CAP:  1\n  "..
			"SEAD:  1\n  STRIKE:  2\n\n"..
			"Recommended Mission Type: CAP",
	}
	local uicmds = require("dct.ui.cmds")
	trigger.action.setassert(status.assert)
	trigger.action.setmsgbuffer(status.expected)
	local cmd = uicmds[status.data.type](newtheater, status.data)
	cmd:execute(400)

	local playercnt = 0
	for _, asset in pairs(theater:getAssetMgr()._assetset) do
		if asset.type == enum.assetType.PLAYERGROUP then
			playercnt = playercnt + 1
		end
	end
	assert(playercnt == 20, "Player asset creation broken")

	os.remove(settings.statepath)
	newtheater:export()
	f = io.open(settings.statepath, "r")
	local sumsave = md5.sumhexa(f:read("*all"))
	f:close()
	if DEBUG == true then
		print("sumsave: "..tostring(sumsave))
		copyfile(settings.statepath, settings.statepath..".new")
	end
	os.remove(settings.statepath)

	if DEBUG == true then
		print("sumorig: "..tostring(sumorig))
		print("sumsave: "..tostring(sumsave))
		print(" sumorig == sumsave: "..tostring(sumorig == sumsave))
	end
	assert(newtheater.statef == true and sumorig == sumsave,
		"state saving didn't produce the same md5sum")
	return 0
end

os.exit(main())
