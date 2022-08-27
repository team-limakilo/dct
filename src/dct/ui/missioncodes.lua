--[[
-- SPDX-License-Identifier: LGPL-3.0
--
-- Creates all menu entries necessary to input a mission code
-- from the radio menu UI
--]]

local enum    = require("dct.enum")
local check   = require("libs.check")

local function doNothing() end

local function addEmptyCommand(path, addCmd)
	addCmd("", path, doNothing)
end

local missionTypeDigits = {}
for _, m1 in pairs(enum.squawkMissionType) do
	missionTypeDigits[m1] = true
end

-- digits __3_ and ___4 (mission codes always end in zero)
local function createJoinCmds(asset, parentMenu, firstTwoDigits, cmds)
	check.table(parentMenu)
	for digit3 = 1, 10 do
		if digit3 % 10 < 8 then
			local missionCode = string.format("%s%d0", firstTwoDigits, digit3 % 10)
			cmds.addCmd(string.format("Mission %s", missionCode), parentMenu,
				dct.Theater.playerRequest, {
					["name"]  = asset.name,
					["type"]  = enum.uiRequestType.MISSIONJOIN,
					["value"] = missionCode,
				}
			)
		else
			addEmptyCommand(parentMenu, cmds.addCmd)
		end
	end
end

-- digit _2__
local function createDigit2Menu(asset, parentMenu, firstDigit, cmds)
	check.table(parentMenu)
	for digit2 = 1, 10 do
		if digit2 % 10 < 8 then
			local firstTwoDigits = string.format("%s%d", firstDigit, digit2 % 10)
			local menu = cmds.addMenu(string.format(
				"Mission %s__", firstTwoDigits), parentMenu)
			createJoinCmds(asset, menu, firstTwoDigits, cmds)
		else
			addEmptyCommand(parentMenu, cmds.addCmd)
		end
	end
end

-- digit 1___
local function createDigit1Menu(asset, parentMenu, cmds)
	check.table(parentMenu)
	for digit1 = 1, 10 do
		if missionTypeDigits[digit1] then
			local firstDigit = tostring(digit1 % 10)
			local menu = cmds.addMenu(string.format(
				"Mission %s___", firstDigit), parentMenu)
			createDigit2Menu(asset, menu, firstDigit, cmds)
		else
			addEmptyCommand(parentMenu, cmds.addCmd)
		end
	end
end

local missioncodes = {}
function missioncodes.addMissionCodes(asset, parentMenu, cmds)
	check.table(asset)
	check.table(parentMenu)
	check.table(cmds)
	check.func(cmds.addCmd)
	check.func(cmds.addMenu)
	createDigit1Menu(asset, parentMenu, cmds)
end

return missioncodes
