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
	[dctutils.COALITION_CONTESTED] = { 0.8, 0.2,  0.8, 0.1 },
	[coalition.side.NEUTRAL]       = { 0,   0,    0,   0.1 },
	[coalition.side.BLUE]          = { 0,   0.25, 1,   0.1 },
	[coalition.side.RED]           = { 1,   0.25, 0,   0.1 },
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
local mapLabels  = {}

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

local function drawPolygon(side, id, lineType, points, lineColor, fillColor)
	-- create vararg list expected by DCS
	local args = {}
	for _, point in ipairs(points) do
		table.insert(args, {
			x = point.x,
			y = land.getHeight(point),
			z = point.y
		})
	end
	table.insert(args, lineColor)
	table.insert(args, fillColor)
	table.insert(args, lineType)
	trigger.action.markupToAll(enum.markShape.Freeform, side, id, unpack(args))
end

function human.createBorders(regions, borders)
	for _, region in pairs(regions) do
		Logger:debug("creating borders for region %s", region.name)
		local lines, triangles, text = {}, {}, {}
		for _, border in pairs(borders[region.name]) do

			-- note: fill color doesn't work on polygons with too many vertices
			local polygonId = human.getMarkID(lines)
			drawPolygon(-1, polygonId, lineType[region.owner],
				border.polygon, lineColor[region.owner], transparent)

			-- so we draw a triangulated mesh to make the fill instead
			for _, triangle in ipairs(border.triangles) do
				local triangleId = human.getMarkID(triangles)
				drawPolygon(-1, triangleId, enum.lineType.NoLine,
					triangle, transparent, fillColor[region.owner])
			end

			local meanCenter = { x = border.center.x, y = 0, z = border.center.y }
			local textId = human.getMarkID(text)
			mapLabels[textId] = border.title
			trigger.action.textToAll(-1, textId, meanCenter,
				textColor[region.owner], transparent, 24, true, border.title)
		end
		mapBorders[region.name] = {
			owner = region.owner,
			lines = lines,
			triangles = triangles,
			text = text,
		}
	end
end

function human.updateBorders(region)
	local regionBorders = mapBorders[region.name]
	if regionBorders ~= nil and regionBorders.owner ~= region.owner then
		Logger:debug("updating borders for region %s from coalition %d to %d",
			region.name, regionBorders.owner, region.owner)
		for _, line in ipairs(regionBorders.lines) do
			trigger.action.setMarkupColor(line, lineColor[region.owner])
			trigger.action.setMarkupTypeLine(line, lineType[region.owner])
		end
		for _, tri in ipairs(regionBorders.triangles) do
			trigger.action.setMarkupColorFill(tri, fillColor[region.owner])
		end
		for _, text in ipairs(regionBorders.text) do
			-- text color update is buggy, requires a string change to apply
			trigger.action.setMarkupColor(text, textColor[region.owner])
			trigger.action.setMarkupText(text, mapLabels[text].." ")
			timer.scheduleFunction(
				function()
					trigger.action.setMarkupText(text, mapLabels[text])
				end,
				nil,
				timer.getTime() + 1
			)
		end
		regionBorders.owner = region.owner
	end
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
