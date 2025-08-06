--[[
-- SPDX-License-Identifier: LGPL-3.0
--
-- Define some basic global enumerations for DCT.
--]]

local enum = {}

enum.assetType = {
	-- control zones
	["KEEPOUT"]     = 1,

	-- strategic types
	["AMMODUMP"]    = 2,
	["FUELDUMP"]    = 3,
	["C2"]          = 4,
	["EWR"]         = 5,
	["MISSILE"]     = 6,
	["OCA"]         = 7,
	["PORT"]        = 8,
	["SAM"]         = 9,
	["FACILITY"]    = 10,

	-- bases
	["BASEDEFENSE"] = 11,

	-- tactical
	["JTAC"]        = 12,
	["LOGISTICS"]   = 13,
	["SEA"]         = 14,
	["FRONTLINE"]   = 25,
	["CONVOY"]      = 26,
	["ARTILLERY"]   = 1027,
	["DAS"]         = 1037,

	-- extended type set
	["BUNKER"]      = 15,
	["CHECKPOINT"]  = 16,
	["FACTORY"]     = 17,
	["AIRSPACE"]    = 18,
	["SHORAD"]      = 19,
	["AIRBASE"]     = 20,
	["PLAYERGROUP"] = 21,
	["SPECIALFORCES"] = 22,
	["FOB"]           = 23,
	["SQUADRONPLAYER"]= 24,
}

--[[
-- We use a min-heap so priority is in reverse numerical order,
-- a higher number is lower priority
--]]
enum.assetTypePriority = {
	[enum.assetType.AIRSPACE]    = 10,
	[enum.assetType.JTAC]        = 10,
	[enum.assetType.EWR]         = 20,
	[enum.assetType.SAM]         = 20,
	[enum.assetType.C2]          = 30,
	[enum.assetType.AMMODUMP]    = 40,
	[enum.assetType.FUELDUMP]    = 40,
	[enum.assetType.ARTILLERY]   = 40,
	[enum.assetType.CONVOY]      = 50,
	[enum.assetType.MISSILE]     = 50,
	[enum.assetType.SEA]         = 50,
	[enum.assetType.FRONTLINE]   = 60,
	[enum.assetType.BASEDEFENSE] = 60,
	[enum.assetType.OCA]         = 70,
	[enum.assetType.PORT]        = 70,
	[enum.assetType.LOGISTICS]   = 70,
	[enum.assetType.AIRBASE]     = 70,
	[enum.assetType.DAS]         = 80,
	[enum.assetType.SHORAD]      = 100,
	[enum.assetType.FACILITY]    = 100,
	[enum.assetType.BUNKER]      = 100,
	[enum.assetType.CHECKPOINT]  = 100,
	[enum.assetType.SPECIALFORCES] = 100,
	[enum.assetType.FOB]         = 100,
	[enum.assetType.FACTORY]     = 100,
	[enum.assetType.KEEPOUT]     = 10000,
}

enum.missionInvalidID = nil

enum.missionType = {
	["CAS"]        = 1,
	["CAP"]        = 2,
	["STRIKE"]     = 3,
	["SEAD"]       = 4,
	["BAI"]        = 5,
	["OCA"]        = 6,
	["ARMEDRECON"] = 7,
	["ANTISHIP"]   = 8,
	["DAS"]        = 9,
}

enum.squawkMissionType = {
	[enum.missionType.CAP]        = 2,
	[enum.missionType.SEAD]       = 3,
	[enum.missionType.ANTISHIP]   = 4,
	[enum.missionType.CAS]        = 5,
	[enum.missionType.STRIKE]     = 5,
	[enum.missionType.BAI]        = 5,
	[enum.missionType.DAS]        = 5,
	[enum.missionType.OCA]        = 5,
	[enum.missionType.ARMEDRECON] = 5,
}

enum.squawkMissionSubType = {
	[enum.missionType.STRIKE]     = 0,
	[enum.missionType.OCA]        = 0,
	[enum.missionType.BAI]        = 1,
	[enum.missionType.DAS]        = 1,
	[enum.missionType.ARMEDRECON] = 2,
	[enum.missionType.CAS]        = 3,
}

enum.assetClass = {
	["INITIALIZE"] = {
		[enum.assetType.AMMODUMP]    = true,
		[enum.assetType.FUELDUMP]    = true,
		[enum.assetType.C2]          = true,
		[enum.assetType.EWR]         = true,
		[enum.assetType.MISSILE]     = true,
		[enum.assetType.OCA]         = true,
		[enum.assetType.SEA]         = true,
		[enum.assetType.PORT]        = true,
		[enum.assetType.SAM]         = true,
		[enum.assetType.FACILITY]    = true,
		[enum.assetType.BUNKER]      = true,
		[enum.assetType.CHECKPOINT]  = true,
		[enum.assetType.FACTORY]     = true,
		[enum.assetType.SHORAD]      = true,
		[enum.assetType.AIRBASE]     = true,
		[enum.assetType.SPECIALFORCES] = true,
		[enum.assetType.FOB]         = true,
		[enum.assetType.AIRSPACE]    = true,
		[enum.assetType.LOGISTICS]   = true,
		[enum.assetType.FRONTLINE]   = true,
		[enum.assetType.CONVOY]      = true,
		[enum.assetType.ARTILLERY]   = true,
		[enum.assetType.DAS]         = true,
	},
	-- strategic list is used in calculating ownership of a region
	-- among other things
	["STRATEGIC"] = {
		[enum.assetType.AMMODUMP]    = true,
		[enum.assetType.FUELDUMP]    = true,
		[enum.assetType.C2]          = true,
		[enum.assetType.EWR]         = true,
		[enum.assetType.MISSILE]     = true,
		[enum.assetType.PORT]        = true,
		[enum.assetType.SAM]         = true,
		[enum.assetType.SEA]         = true,
		[enum.assetType.FACILITY]    = true,
		[enum.assetType.BUNKER]      = true,
		[enum.assetType.CHECKPOINT]  = true,
		[enum.assetType.FACTORY]     = true,
		[enum.assetType.AIRBASE]     = true,
		[enum.assetType.FOB]         = true,
	},
	-- agents never get serialized to the state file
	["AGENTS"] = {
		[enum.assetType.PLAYERGROUP] = true,
	},
}

enum.missionTypeMap = {
	[enum.missionType.STRIKE] = {
		[enum.assetType.AMMODUMP]   = true,
		[enum.assetType.FUELDUMP]   = true,
		[enum.assetType.C2]         = true,
		[enum.assetType.MISSILE]    = true,
		[enum.assetType.PORT]       = true,
		[enum.assetType.FACILITY]   = true,
		[enum.assetType.BUNKER]     = true,
		[enum.assetType.CHECKPOINT] = true,
		[enum.assetType.FACTORY]    = true,
		[enum.assetType.SHORAD]     = true,
	},
	[enum.missionType.SEAD] = {
		[enum.assetType.EWR]        = true,
		[enum.assetType.SAM]        = true,
	},
	[enum.missionType.OCA] = {
		[enum.assetType.OCA]        = true,
		[enum.assetType.AIRBASE]    = true,
	},
	[enum.missionType.BAI] = {
		[enum.assetType.LOGISTICS]  = true,
		[enum.assetType.ARTILLERY]  = true,
		[enum.assetType.CONVOY]     = true,
	},
	[enum.missionType.CAS] = {
		[enum.assetType.JTAC]       = true,
		[enum.assetType.FRONTLINE]  = true,
	},
	[enum.missionType.CAP] = {
		[enum.assetType.AIRSPACE]   = true,
	},
	[enum.missionType.ARMEDRECON] = {
		[enum.assetType.SPECIALFORCES] = true,
		[enum.assetType.FOB]           = true,
	},
	[enum.missionType.ANTISHIP] = {
		[enum.assetType.SEA]        = true,
	},
	[enum.missionType.DAS] = {
		[enum.assetType.DAS]        = true,
	},
}

enum.missionAbortType = {
	["ABORT"]    = 0,
	["COMPLETE"] = 1,
	["TIMEOUT"]  = 2,
}

enum.uiRequestType = {
	["THEATERSTATUS"]   = 1,
	["MISSIONREQUEST"]  = 2,
	["MISSIONBRIEF"]    = 3,
	["MISSIONSTATUS"]   = 4,
	["MISSIONABORT"]    = 5,
	["MISSIONROLEX"]    = 6,
	["MISSIONCHECKIN"]  = 7,
	["MISSIONCHECKOUT"] = 8,
	["SCRATCHPADGET"]   = 9,
	["SCRATCHPADSET"]   = 10,
	["CHECKPAYLOAD"]    = 11,
	["MISSIONJOIN"]     = 12,
}

enum.weaponCategory = {
	["AA"] = 1,
	["AG"] = 2,
}

enum.WPNINFCOST = 5000
enum.UNIT_CAT_SCENERY = Unit.Category.STRUCTURE + 1

enum.eventbase = 2000
enum.event = {
	["DCT_EVENT_DEAD"] = enum.eventbase + 1,
		--[[
		-- DEAD definition:
		--   id = id of this event
		--   initiator = asset sending the death notification
		--]]
	["DCT_EVENT_HIT"] = enum.eventbase + 2,
		--[[
		-- HIT definition:
		--   id = id of this event
		--   initiator = DCT asset that was hit
		--   weapon = DCTWeapon object
		--]]
	["DCT_EVENT_OPERATIONAL"] = enum.eventbase + 3,
		--[[
		-- OPERATIONAL definition:
		--   id = id of this event
		--   initiator = base sending the operational notification
		--   state = of the base, true == operational
		--]]
	["DCT_EVENT_CAPTURED"] = enum.eventbase + 4,
		--[[
		-- CAPTURED definition:
		--   id = id of this event
		--   initiator = object that initiated the capture
		--   target = the base that has been captured
		--   owner = previous coalition of the base
		--]]
	["DCT_EVENT_IMPACT"] = enum.eventbase + 5,
		--[[
		-- IMPACT definition:
		--   id = id of the event
		--   initiator = DCTWeapon class causing the impact
		--   point = impact point
		--]]
	["DCT_EVENT_ADD_ASSET"] = enum.eventbase + 6,
		--[[
		-- ADD_ASSET definition:
		--  A new asset was added to the asset manager.
		--   id = id of this event
		--   initiator = asset being added
		--]]
	["DCT_EVENT_ADD_MISSION"] = enum.eventbase + 7,
		--[[
		-- CREATE_MISSION definition:
		--  A mission was added to the active list of an AI commander.
		--   id = id of this event
		--   initiator = commander that owns the mission
		--   mission = new mission object
		--   target = mission target asset
		--]]
	["DCT_EVENT_REMOVE_MISSION"] = enum.eventbase + 8,
		--[[
		-- REMOVE_MISSION definition:
		--  A mission was removed from the active list of an AI commander.
		--   id = id of this event
		--   initiator = commander that owned the mission
		--   mission = mission object to be destroyed
		--   reason = reason for mission removal
		--]]
	["DCT_EVENT_JOIN_MISSION"] = enum.eventbase + 9,
		--[[
		-- JOIN_MISSION definition:
		--  An asset has joined a mission.
		--   id = id of this event
		--   initiator = asset
		--   mission = mission object
		--]]
	["DCT_EVENT_LEAVE_MISSION"] = enum.eventbase + 10,
		--[[
		-- LEAVE_MISSION definition:
		--  An asset has left a mission.
		--   id = id of this event
		--   initiator = asset
		--   mission = mission object
		--   reason = reason for leaving
		--]]
	["DCT_EVENT_MAX"] = enum.eventbase + 11,
}

enum.kickCode = require("dct.libs.kickinfo").kickCode

enum.markShape = {
	["Line"]     = 1,
	["Circle"]   = 2,
	["Rect"]     = 3,
	["Arrow"]    = 4,
	["Text"]     = 5,
	["Quad"]     = 6,
	["Freeform"] = 7,
}

enum.lineType = {
	["NoLine"]   = 0,
	["Solid"]    = 1,
	["Dashed"]   = 2,
	["Dotted"]   = 3,
	["DotDash"]  = 4,
	["LongDash"] = 5,
	["TwoDash"]  = 6,
}

for _, msntype in pairs(enum.missionType) do
	assert(enum.squawkMissionType[msntype],
		"not all mission types are mapped to squawk codes")
end

return enum
