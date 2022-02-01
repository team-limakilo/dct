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
local loadout  = require("dct.systems.loadouts")
local utils    = require("libs.utils")
local check    = require("libs.check")
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

local function addDCTcmd(asset, name, path, request, val, args)
	check.table(asset)
	check.string(name)
	check.number(request)
	if args == nil then
		args = {}
	end
	args.name = asset.name
	args.type = request
	args.value = val
	return addcmd(asset, name, path, dct.Theater.playerRequest, args)
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
	addDCTcmd(asset, "DISPLAY", padmenu, enum.uiRequestType.SCRATCHPADGET)
	addDCTcmd(asset, "SET", padmenu, enum.uiRequestType.SCRATCHPADSET)

	addDCTcmd(asset, "Theater Update", nil, enum.uiRequestType.THEATERSTATUS)

	local msnmenu = addmenu(asset, "Mission", nil)
	local rqstmenu = addmenu(asset, "Request", msnmenu)
	for typename, msntype in utils.sortedpairs(asset.ato) do
		addDCTcmd(asset, typename, rqstmenu,
			enum.uiRequestType.MISSIONREQUEST, msntype)
	end

	local msnListMenu = addmenu(asset, "List", rqstmenu)
	asset.uimenus.msnlist = {
		menu = msnListMenu,
		items = {},
	}

	local joinmenu = addmenu(asset, "Join", msnmenu)
	addDCTcmd(asset, "Use Scratch Pad Value", joinmenu,
		enum.uiRequestType.MISSIONJOIN)
	local codemenu = addmenu(asset, "Input Code (F1-F10)", joinmenu)
	msncodes.addMissionCodes(asset, name, codemenu)

	addDCTcmd(asset, "Briefing", msnmenu, enum.uiRequestType.MISSIONBRIEF)
	addDCTcmd(asset, "Status", msnmenu, enum.uiRequestType.MISSIONSTATUS)
	addDCTcmd(asset, "Abort", msnmenu, enum.uiRequestType.MISSIONABORT,
		enum.missionAbortType.ABORT)
	addDCTcmd(asset, "Rolex +30", msnmenu,
		enum.uiRequestType.MISSIONROLEX, 30 * 60)

	loadout.addmenu(addcmd, asset, nil)

	menus.update(asset)
end

function menus.removeMenu(asset)
	if asset.uimenus == nil then
		return
	end
	Logger:debug("removeMenu - removing menu for group: %s", asset.name)

	for _, menu in ipairs(asset.uimenus) do
		missionCommands.removeItemForGroup(asset.groupId, menu)
	end
	asset.uimenus = nil
end

function menus.update(asset)
	if asset.uimenus == nil then
		return
	end
	Logger:debug("update - updating menus for group: %s", asset.name)

	local msnlist = asset.uimenus.msnlist
	for _, msn in pairs(msnlist.items) do
		missionCommands.removeItemForGroup(asset.groupId, msn)
	end
	local cmdr = dct.theater:getCommander(asset.owner)
	local targetList = cmdr:getTopTargets(asset.ato, 10)
	local playerLocation = asset:getLocation()
	for _, tgt in pairs(targetList) do
		local assetTypeName = utils.getkey(enum.assetType, tgt.type)
		local missionTypeId = dctutils.assettype2mission(tgt.type)
		local missionTypeName = utils.getkey(enum.missionType, missionTypeId)
		local distance = vec.distance(playerLocation, tgt:getLocation())
		distance = dctutils.fmtdistance(distance, asset.units)

		local name = string.format("%s(%s): %s - %s",
			missionTypeName, assetTypeName, tgt.codename, distance)

		local msn = addDCTcmd(asset, name, msnlist.menu,
			enum.uiRequestType.MISSIONREQUEST, missionTypeId, { target = tgt.name })

		table.insert(msnlist.items, msn)
	end
end

return menus
