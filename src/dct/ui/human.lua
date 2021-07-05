--[[
-- SPDX-License-Identifier: LGPL-3.0
--
-- common functions to convert data to human readable formats
--]]

require("math")
local utils    = require("libs.utils")
local enum     = require("dct.enum")
local dctutils = require("dct.utils")

local human = {}

local markindex = 10
function human.getMarkID()
	markindex = markindex + 1
	return markindex
end

-- mapping of inserted marks for later removal
local marks = {}

-- enemy air superiroty as defined by the US-DOD is
--  'incapability', 'denial', 'parity', 'superiority',
--  'supremacy' - this is simply represented by a number
--  which can then be mapped to a given word
function human.airthreat(value)
	assert(value >= 0 and value <= 100, "value error: value out of range")
	if value >= 0 and value < 20 then
		return "incapability"
	elseif value >= 20 and value < 40 then
		return "denial"
	elseif value >= 40 and value < 60 then
		return "parity"
	elseif value >= 60 and value < 80 then
		return "superiority"
	end
	return "supremacy"
end

-- The value is a rough representation of threat level between 0
-- and 100. This is translated in to 'low', 'med', & 'high'.
function human.threat(value)
	assert(value >= 0 and value <= 100, "value error: value out of range")
	if value >= 0 and value < 30 then
		return "low"
	elseif value >= 30 and value < 70 then
		return "medium"
	end
	return "high"
end

function human.strength(value)
	if value == nil then
		return "Unknown"
	end

	if value < 25 then
		return "Critical"
	elseif value >= 25 and value < 75 then
		return "Marginal"
	elseif value >= 75 and value < 125 then
		return "Nominal"
	end
	return "Excellent"
end

function human.missiontype(mtype)
	return assert(utils.getkey(enum.missionType, mtype),
		"no name found for mission type ("..mtype..")")
end

function human.locationhdr(msntype)
	local hdr = "Target AO"
	if msntype == enum.missionType.CAS or
		msntype == enum.missionType.CAP then
		hdr = "Station AO"
	end
	return hdr
end

local function markToGroup(label, pos, missionId, groupId, readonly)
	local markId = human.getMarkID()
	trigger.action.markToGroup(markId, label, pos, groupId, readonly)
	if marks[groupId] == nil then
		marks[groupId] = {}
	end
	if marks[groupId][missionId] == nil then
		marks[groupId][missionId] = {}
	end
	table.insert(marks[groupId][missionId], markId)
end

function human.drawTargetIntel(mission, groupId, readonly)
	local tgtInfo = mission:getTargetInfo()
	local degpos = dctutils.degrade_position(tgtInfo.location, tgtInfo.intellvl)
	markToGroup("TGT: "..tgtInfo.callsign, degpos, mission.id, groupId, readonly)
	for _, mark in pairs(tgtInfo.extramarks) do
		mark.y = mark.y or 0
		mark.label = dctutils.interp(mark.label, { ["TARGET"] = tgtInfo.callsign })
		markToGroup(mark.label, mark, mission.id, groupId, readonly)
	end
end

function human.removeIntel(missionId, groupId)
	if marks[groupId] ~= nil and marks[groupId][missionId.id] ~= nil then
		local marksToRemove = marks[groupId][missionId.id]
		for i = 1, #marksToRemove do
			trigger.action.removeMark(marksToRemove[i])
			marksToRemove[i] = nil
		end
	end
end

return human
