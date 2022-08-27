--[[
-- SPDX-License-Identifier: LGPL-3.0
--
-- common functions to convert data to human readable formats
--]]

require("math")
local utils    = require("libs.utils")
local enum     = require("dct.enum")
local dctutils = require("dct.utils")
local Logger   = dct.Logger.getByName("UI")

local lineType = {
	[dctutils.COALITION_CONTESTED] = enum.lineType.LongDash,
	[coalition.side.NEUTRAL]       = enum.lineType.Solid,
	[coalition.side.BLUE]          = enum.lineType.Solid,
	[coalition.side.RED]           = enum.lineType.Solid,
}

local lineColor = {
	[dctutils.COALITION_CONTESTED] = { 0.5, 0,   0.5, 1 },
	[coalition.side.NEUTRAL]       = { 0.5, 0.5, 0.5, 1 },
	[coalition.side.BLUE]          = { 0,   0,   1,   1 },
	[coalition.side.RED]           = { 1,   0,   0,   1 },
}

local fillColor = {
	[dctutils.COALITION_CONTESTED] = { 0.8, 0.4,  0.8, 0.075 },
	[coalition.side.NEUTRAL]       = { 0,   0,    0,   0.075 },
	[coalition.side.BLUE]          = { 0,   0.25, 1,   0.075 },
	[coalition.side.RED]           = { 1,   0.25, 0,   0.075 },
}

local textColor = {
	[dctutils.COALITION_CONTESTED] = { 0.4,  0,    0.4,  1 },
	[coalition.side.NEUTRAL]       = { 1,    1,    1,    1 },
	[coalition.side.BLUE]          = { 0,    0,    0.75, 1 },
	[coalition.side.RED]           = { 0.75, 0,    0,    1 },
}

local transparent = { 0, 0, 0, 0 }

local human = {}

local mapBorders = {}

local markindex = 10
function human.getMarkID(list)
	markindex = markindex + 1
	if list ~= nil then
		table.insert(list, markindex)
	end
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

function human.formatAltitude(location, unitSystems)
	local _, pressure = atmosphere.getTemperatureAndPressure(location)

	local alt
	if unitSystems ~= nil and unitSystems[dctutils.units.METRIC] then
		alt = string.format("%.0f m", location.y)
	else -- Imperial
		alt = string.format("%.0f ft", location.y * 3.28084)
	end

	if unitSystems ~= nil and unitSystems[dctutils.units.MMHG] then
		return string.format("%s (%.01f mmHg)", alt, pressure * 0.007501)
	elseif unitSystems ~= nil and unitSystems[dctutils.units.HPA] then
		return string.format("%s (%.01f hPa)", alt, pressure * 0.01)
	elseif unitSystems ~= nil and unitSystems[dctutils.units.MBAR] then
		return string.format("%s (%.01f mbar)", alt, pressure * 0.01)
	else -- inHg
		return string.format("%s (%.02f inHg)", alt, pressure * 0.000295)
	end
end

function human.formatDistance(meters, unitSystems)
	if unitSystems ~= nil and unitSystems[dctutils.units.METRIC] or
	   unitSystems ~= nil and unitSystems[dctutils.units.US_ARMY] then
		return string.format("%.0f km", meters * 0.00100)
	else
		return string.format("%.0f nm", meters * 0.00054)
	end
end

local function point3D(point)
	return {
		x = point.x,
		y = land.getHeight(point),
		z = point.y
	}
end

function human.updateBorders(region, borders)
	local oldBorders = mapBorders[region.name]
	if oldBorders ~= nil and oldBorders.owner == region.owner then
		return
	end

	if oldBorders == nil then
		oldBorders = { marks = {} }
	end

	Logger:debug("updating borders for region %s from coalition %s to %d",
		region.name, tostring(oldBorders.owner), region.owner)

	for _, oldMark in pairs(oldBorders.marks) do
		trigger.action.removeMark(oldMark)
	end

	local borderMarks = {}
	for _, border in pairs(borders) do
		-- note: fill color doesn't work on polygons with too many vertices
		local points = border.polygon
		for i = 1, #points do
			local prev
			if i == 1 then
				prev = points[#points]
			else
				prev = points[i - 1]
			end
			local curr = points[i]
			local lineId = human.getMarkID(borderMarks)
			trigger.action.lineToAll(-1, lineId, point3D(prev), point3D(curr),
				lineColor[region.owner], lineType[region.owner])
		end

		-- so we draw a triangulated mesh to make the fill instead
		for _, triangle in ipairs(border.triangles) do
			local triangleId = human.getMarkID(borderMarks)
			trigger.action.markupToAll(enum.markShape.Freeform, -1, triangleId,
				point3D(triangle[1]), point3D(triangle[2]), point3D(triangle[3]),
				transparent, fillColor[region.owner], enum.lineType.NoLine)
		end

		local textId = human.getMarkID(borderMarks)
		trigger.action.textToAll(-1, textId, point3D(border.center),
			textColor[region.owner], transparent, 24, true, border.title)
	end

	mapBorders[region.name] = {
		owner = region.owner,
		marks = borderMarks,
	}
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

function human.drawTargetIntel(mission, groupId, fmt)
	assert(fmt == nil or type(fmt) == "number", "fmt must be a number")
	local tgtInfo = mission:getTargetInfo()
	local intel = tgtInfo.intellvl
	if intel >= 4 and #tgtInfo.locations > 1 then
		-- Mission has multiple static locations
		for _, location in pairs(tgtInfo.locations) do
			local degpos = dctutils.degrade_position(location, intel, fmt)
			markToGroup(string.format(
				"TGT: %s (%s)", tgtInfo.callsign, tostring(location.desc)),
				degpos, mission.id, groupId, false)
		end
	else
		-- Mission only has a single location
		local degpos = dctutils.degrade_position(tgtInfo.location, intel, fmt)
		markToGroup("TGT: "..tgtInfo.callsign, degpos, mission.id, groupId, false)
	end
	-- Designer-authored marks
	for _, mark in pairs(tgtInfo.extramarks) do
		mark.y = mark.y or 0
		mark.label = dctutils.interp(mark.label, { ["TARGET"] = tgtInfo.callsign })
		markToGroup(mark.label, mark, mission.id, groupId, false)
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

function human.relationship(side1, side2)
	if side1 == side2 then
		return "Friendly"
	elseif dctutils.getenemy(side1) == side2 then
		return "Hostile"
	else
		return "Neutral"
	end
end

return human
