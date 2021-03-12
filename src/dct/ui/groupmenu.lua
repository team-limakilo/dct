--[[
-- SPDX-License-Identifier: LGPL-3.0
--
-- Handles applying a F10 menu UI to player groups
--]]

--[[
-- Assumptions:
-- It is assumed each player group consists of a single player
-- aircraft due to issues with the game.
--
-- Notes:
--   Once a menu is added to a group it does not need to be added
--   again, which is why we need to track which group ids have had
--   a menu added. The reason why this cannot be done up front on
--   mission start is because the the group does not exist until at
--   least one player occupies a slot. We must add the menu upon
--   object creation.
--]]

local enum    = require("dct.enum")
local Logger  = dct.Logger.getByName("UI")
local loadout = require("dct.systems.loadouts")
local addmenu = missionCommands.addSubMenuForGroup
local addcmd  = missionCommands.addCommandForGroup

local function emptycmd() end

local function addemptycmd(gid, path)
	addcmd(gid, "", path, emptycmd)
end

local menus = {}
function menus.createMenu(asset)
	local theater = require("dct.Theater").singleton()
	local gid  = asset.groupId
	local name = asset.name

	if asset.uimenus ~= nil then
		Logger:debug("createMenu - group("..name..") already had menu added")
		return
	end

	Logger:debug("createMenu - adding menu for group: "..tostring(name))

	asset.uimenus = {}

	local padmenu = addmenu(gid, "Scratch Pad", nil)
	for k, v in pairs({
		["DISPLAY"] = enum.uiRequestType.SCRATCHPADGET,
		["SET"] = enum.uiRequestType.SCRATCHPADSET}) do
		addcmd(gid, k, padmenu, theater.playerRequest, theater,
			{
				["name"]   = name,
				["type"]   = v,
			})
	end

	addcmd(gid, "Theater Update", nil, theater.playerRequest, theater,
		{
			["name"]   = name,
			["type"]   = enum.uiRequestType.THEATERSTATUS,
		})

	local msnmenu = addmenu(gid, "Mission", nil)
	local rqstmenu = addmenu(gid, "Request", msnmenu)
	for k, v in pairs(asset.ato) do
		addcmd(gid, k, rqstmenu, theater.playerRequest, theater,
			{
				["name"]   = name,
				["type"]   = enum.uiRequestType.MISSIONREQUEST,
				["value"]  = v,
			})
	end

	-- addcmd(gid, "Join", msnmenu, theater.playerRequest, theater,
	-- 	{
	-- 		["name"]   = name,
	-- 		["type"]   = enum.uiRequestType.MISSIONJOIN,
	-- 	})

	-- Take a seat, this is going to be a long ride
	local msnjoin = addmenu(gid, "Join", msnmenu);
	local totalmissions = 0
	local emptyentries = 0
	for d1 = 1, 10 do
		-- Mission types only go up to 5
		if d1 % 10 <= 5 then
			local missioncode = tostring(d1 % 10)
			local msndigit1 = addmenu(gid, "Mission "..missioncode.."__0", msnjoin)
			for d2 = 1, 10 do
				-- Specific mission code only goes up to 63
				if d2 % 10 <= 6 then
					local missioncode = missioncode..(d2 % 10)
					local msndigit2 = addmenu(gid, "Mission "..missioncode.."_0", msndigit1)
					for d3 = 1, 10 do
						-- Don't include missions 64+
						if d2 % 10 < 6 or d2 == 6 and d3 % 10 <= 3 then
							local missioncode = missioncode..(d3 % 10).."0"
							-- Last mission code digit is always zero
							addcmd(gid, "Mission "..missioncode, msndigit2, theater.playerRequest, theater, {
								["name"]  = name,
								["type"]  = enum.uiRequestType.MISSIONJOIN,
								["value"] = missioncode
							})
							totalmissions = totalmissions + 1
						else
							addemptycmd(gid, msndigit2)
							emptyentries = emptyentries + 1
						end
					end
				else
					addemptycmd(gid, msndigit1)
					emptyentries = emptyentries + 1
				end
			end
		elseif d1 == 9 then
			-- Allow joining through scratchpad
			addcmd(gid, "Use Scratchpad Code", msnjoin, theater.playerRequest, theater, {
				["name"]  = name,
				["type"]  = enum.uiRequestType.MISSIONJOIN
			})
		else
			addemptycmd(gid, msnjoin)
			emptyentries = emptyentries + 1
		end
	end

	Logger:debug("createMenu - total missions: "..tostring(totalmissions))
	Logger:debug("createMenu - empty entries: "..tostring(emptyentries))

	addcmd(gid, "Briefing", msnmenu, theater.playerRequest, theater,
		{
			["name"]   = name,
			["type"]   = enum.uiRequestType.MISSIONBRIEF,
		})
	addcmd(gid, "Status", msnmenu, theater.playerRequest, theater,
		{
			["name"]   = name,
			["type"]   = enum.uiRequestType.MISSIONSTATUS,
		})
	addcmd(gid, "Abort", msnmenu, theater.playerRequest, theater,
		{
			["name"]   = name,
			["type"]   = enum.uiRequestType.MISSIONABORT,
			["value"]  = enum.missionAbortType.ABORT,
		})
	addcmd(gid, "Rolex +30", msnmenu, theater.playerRequest, theater,
		{
			["name"]   = name,
			["type"]   = enum.uiRequestType.MISSIONROLEX,
			["value"]  = 30*60,  -- seconds
		})
	addcmd(gid, "Check-In", msnmenu, theater.playerRequest, theater,
		{
			["name"]   = name,
			["type"]   = enum.uiRequestType.MISSIONCHECKIN,
		})
	addcmd(gid, "Check-Out", msnmenu, theater.playerRequest, theater,
		{
			["name"]   = name,
			["type"]   = enum.uiRequestType.MISSIONCHECKOUT,
		})
	loadout.addmenu(asset, nil, theater.playerRequest, theater)
end

return menus
