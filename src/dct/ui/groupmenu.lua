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

local enum     = require("dct.enum")
local Theater  = require("dct.Theater")
local loadout  = require("dct.systems.loadouts")
local utils    = require("libs.utils")
local msncodes = require("dct.ui.missioncodes")
local Logger   = dct.Logger.getByName("UI")

local function addmenu(asset, name, path)
	local menu = missionCommands.addSubMenuForGroup(asset.groupId, name, path)
	if path == nil then
		table.insert(asset.uimenus, menu)
	end
	return menu
end

local function addcmd(asset, name, path, handler, data)
	local cmd = missionCommands.addCommandForGroup(asset.groupId, name, path,
		handler, data)
	if path == nil then
		table.insert(asset.uimenus, cmd)
	end
	return cmd
end

local menus = {}
function menus.createMenu(asset)
	local name = asset.name

	if asset.uimenus ~= nil then
		Logger:debug("createMenu - group(%s) already had menu added", name)
		return
	end

	Logger:debug("createMenu - adding menu for group: %s", name)

	asset.uimenus = {}

	local padmenu = addmenu(asset, "Scratch Pad", nil)
	for k, v in pairs({
		["DISPLAY"] = enum.uiRequestType.SCRATCHPADGET,
		["SET"] = enum.uiRequestType.SCRATCHPADSET}) do
		addcmd(asset, k, padmenu, Theater.playerRequest,
			{
				["name"]   = name,
				["type"]   = v,
			})
	end

	addcmd(asset, "Theater Update", nil, Theater.playerRequest,
		{
			["name"]   = name,
			["type"]   = enum.uiRequestType.THEATERSTATUS,
		})

	local msnmenu = addmenu(asset, "Mission", nil)
	local rqstmenu = addmenu(asset, "Request", msnmenu)
	for k, v in utils.sortedpairs(asset.ato) do
		addcmd(asset, k, rqstmenu, Theater.playerRequest,
			{
				["name"]   = name,
				["type"]   = enum.uiRequestType.MISSIONREQUEST,
				["value"]  = v,
			})
	end

	local joinmenu = addmenu(asset, "Join", msnmenu)
	addcmd(asset, "Use Scratch Pad Value", joinmenu, Theater.playerRequest,
		{
			["name"]   = name,
			["type"]   = enum.uiRequestType.MISSIONJOIN,
			["value"]  = nil,
		})

	local codemenu = addmenu(asset, "Input Code (F1-F10)", joinmenu)
	msncodes.addMissionCodes(asset, name, codemenu)

	addcmd(asset, "Briefing", msnmenu, Theater.playerRequest,
		{
			["name"]   = name,
			["type"]   = enum.uiRequestType.MISSIONBRIEF,
		})
	addcmd(asset, "Status", msnmenu, Theater.playerRequest,
		{
			["name"]   = name,
			["type"]   = enum.uiRequestType.MISSIONSTATUS,
		})
	addcmd(asset, "Abort", msnmenu, Theater.playerRequest,
		{
			["name"]   = name,
			["type"]   = enum.uiRequestType.MISSIONABORT,
			["value"]  = enum.missionAbortType.ABORT,
		})
	addcmd(asset, "Rolex +30", msnmenu, Theater.playerRequest,
		{
			["name"]   = name,
			["type"]   = enum.uiRequestType.MISSIONROLEX,
			["value"]  = 30*60,  -- seconds
		})
	loadout.addmenu(addcmd, asset, nil, Theater.playerRequest)
end

function menus.removeMenu(asset)
	Logger:debug("removeMenu - removing menu for group: %s", asset.name)
	for _, menu in pairs(asset.uimenus) do
		missionCommands.removeItemForGroup(asset.groupId, menu)
	end
	asset.uimenus = nil
end

return menus
