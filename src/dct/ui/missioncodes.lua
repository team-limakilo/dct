--[[
-- SPDX-License-Identifier: LGPL-3.0
--
-- Creates all menu entries necessary to input a mission code
-- from the radio menu UI
--]]

local enum    = require("dct.enum")
local addmenu = missionCommands.addSubMenuForGroup
local addcmd  = missionCommands.addCommandForGroup

local function empty() end

local function addEmptyCommand(gid, path)
	addcmd(gid, "", path, empty)
end

local validFirstDigit = {}
for _, m1 in pairs(enum.squawkMissionType) do
	validFirstDigit[m1] = true
end

-- digits __3_ and ___4 (mission codes always end in zero)
local function createJoinCmds(gid, name, parentMenu, halfCode)
	for digit3 = 1, 10 do
		if digit3 % 10 < 8 then
			local missionCode = string.format("%s%d0", halfCode, digit3 % 10)
			addcmd(gid, string.format("Mission %s", missionCode), parentMenu,
				dct.Theater.playerRequest, {
					["name"]  = name,
					["type"]  = enum.uiRequestType.MISSIONJOIN,
					["value"] = missionCode,
				}
			)
		else
			addEmptyCommand(gid, parentMenu)
		end
	end
end

-- digit _2__
local function createDigit2Menu(gid, name, parentMenu, quarterCode)
	for digit2 = 1, 10 do
		if digit2 % 10 < 8 then
			local halfCode = string.format("%s%d", quarterCode, digit2 % 10)
			local menu = addmenu(gid,
				string.format("Mission %s__", halfCode), parentMenu)
			createJoinCmds(gid, name, menu, halfCode)
		else
			addEmptyCommand(gid, parentMenu)
		end
	end
end

-- digit 1___
local function createDigit1Menu(gid, name, parentMenu)
	for digit1 = 1, 10 do
		if validFirstDigit[digit1] then
			local quarterCode = tostring(digit1 % 10)
			local menu = addmenu(gid,
				string.format("Mission %s___", quarterCode), parentMenu)
			createDigit2Menu(gid, name, menu, quarterCode)
		else
			addEmptyCommand(gid, parentMenu)
		end
	end
end

local missioncodes = {}
function missioncodes.addMissionCodes(asset, parentMenu)
	createDigit1Menu(asset.groupId, asset.name, parentMenu)
end

return missioncodes
