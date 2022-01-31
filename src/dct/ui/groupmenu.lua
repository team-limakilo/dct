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
local dctutils = require("dct.utils")
local Theater  = require("dct.Theater")
local loadout  = require("dct.systems.loadouts")
local utils    = require("libs.utils")
local msncodes = require("dct.ui.missioncodes")
local vec      = require("dct.libs.vector")
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
	for typename, msntype in utils.sortedpairs(asset.ato) do
		local title = string.format("Give me %s", typename)
		addcmd(asset, title, rqstmenu, Theater.playerRequest,
			{
				["name"]   = name,
				["type"]   = enum.uiRequestType.MISSIONREQUEST,
				["value"]  = msntype,
			})
	end

	local msnListMenu = addmenu(asset, "Let me choose", rqstmenu)
	local msnListItems = {}
	asset.uimenus.refresh = function()
		for _, msn in pairs(msnListItems) do
			missionCommands.removeItemForGroup(asset.groupId, msn)
		end
		msnListItems = {}
		local tgtlist = dct.theater:getCommander(asset.owner)
			:getTopTargets(asset.ato, 10)
		for _, tgt in pairs(tgtlist) do
			local typename = utils.getkey(enum.assetType, tgt.type)
			local missiontype = dctutils.assettype2mission(tgt.type)
			local missiontypename = utils.getkey(enum.missionType, missiontype)
			local distance = vec.distance(asset:getLocation(), tgt:getLocation())
			local nmi = distance * 0.00054 -- meters to nautical miles
			local msn = addcmd(asset, string.format("%s(%s): %s - %dnm", missiontypename,
				typename, tgt.codename, nmi), msnListMenu, Theater.playerRequest,
				{
					["name"]   = name,
					["type"]   = enum.uiRequestType.MISSIONREQUEST,
					["value"]  = missiontype,
					["target"] = tgt.name,
				})
			table.insert(msnListItems, msn)
		end
	end
	asset.uimenus.refresh()

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
	for _, menu in ipairs(asset.uimenus) do
		missionCommands.removeItemForGroup(asset.groupId, menu)
	end
	asset.uimenus = nil
end

return menus
