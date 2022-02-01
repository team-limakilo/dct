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
local class    = require("libs.namedclass")
local msncodes = require("dct.ui.missioncodes")
local Vector   = require("dct.libs.vector")
local Logger   = dct.Logger.getByName("GroupMenu")

local function addMenu(asset, name, path, list)
	local menu = missionCommands.addSubMenuForGroup(asset.groupId, name, path)
	if list ~= nil then
		table.insert(list, menu)
	end
	return menu
end

local function addCmd(asset, name, path, handler, data, list)
	local cmd = missionCommands.addCommandForGroup(asset.groupId, name, path,
		handler, data)
	if list ~= nil then
		table.insert(list, cmd)
	end
	return cmd
end

local function addRqstCmd(asset, name, path, request, val, args, list)
	check.number(request)
	if args == nil then
		args = {}
	end
	args.name = asset.name
	args.type = request
	args.value = val
	return addCmd(asset, name, path, dct.Theater.playerRequest, args, list)
end

local function createMissionMenu(asset, mission, list)
	if mission ~= nil then
		-- asset has a mission
		local menu = addMenu(asset, string.format("Mission %d", mission.id))
		table.insert(list, menu)

		addRqstCmd(asset, "Briefing", menu, enum.uiRequestType.MISSIONBRIEF)
		addRqstCmd(asset, "Status", menu, enum.uiRequestType.MISSIONSTATUS)
		addRqstCmd(asset, "Abort", menu,
			enum.uiRequestType.MISSIONABORT, enum.missionAbortType.ABORT)
		addRqstCmd(asset, "Rolex +30", menu,
			enum.uiRequestType.MISSIONROLEX, 30 * 60)

		return {
			menu = menu,
		}
	else
		-- asset has no mission assigned
		local menu = addMenu(asset, "Mission")
		table.insert(list, menu)

		local typeMenu = addMenu(asset, "Request (Type)", menu)
		for typename, msntype in utils.sortedpairs(asset.ato) do
			addRqstCmd(asset, typename, typeMenu,
				enum.uiRequestType.MISSIONREQUEST, msntype)
		end

		local listMenu = addMenu(asset, "Request (List)", menu)

		addRqstCmd(asset, "Join (Scratchpad)", menu, enum.uiRequestType.MISSIONJOIN)

		local joinCodeMenu = addMenu(asset, "Join (Input Code)", menu)
		msncodes.addMissionCodes(asset, joinCodeMenu)

		return {
			menu = menu,
			listMenu = listMenu,
		}
	end
end

local GroupMenu = class("GroupMenu")
function GroupMenu:__init(asset)
	assert(asset:isa(require("dct.assets.Player")),
		"GroupMenu can only be initialized with a Player asset")
	self.asset       = asset
	self.menus       = {}
	self.msnList     = {}
	self.msnMenu     = nil
	self.msnListMenu = nil
	self.inMission   = false
	asset:addObserver(self.onDCTEvent, self, self.__clsname..".onDCTEvent")
end

local function emptyMenu(asset, menu)
	for _, item in ipairs(menu) do
		missionCommands.removeItemForGroup(asset.groupId, item)
	end
end

function GroupMenu:destroy()
	if next(self.menus) == nil then
		return
	end

	Logger:debug("destroy() - removing menu for group: %s", self.asset.name)
	emptyMenu(self.asset, self.menus)
	self.menus       = {}
	self.msnList     = {}
	self.msnMenu     = nil
	self.msnListMenu = nil
end

function GroupMenu:create(mission)
	if next(self.menus) ~= nil then
		Logger:debug("create() - group(%s) already had menu added",
			self.asset.name)
		return
	end

	Logger:debug("create() - adding menu for group: %s", self.asset.name)

	local padmenu = addMenu(self.asset, "Scratch Pad", nil, self.menus)
	addRqstCmd(self.asset, "DISPLAY", padmenu, enum.uiRequestType.SCRATCHPADGET)
	addRqstCmd(self.asset, "SET", padmenu, enum.uiRequestType.SCRATCHPADSET)

	addRqstCmd(self.asset, "Theater Update", nil,
		enum.uiRequestType.THEATERSTATUS, nil, nil, self.menus)

	table.insert(self.menus, loadout.addmenu(addCmd, self.asset, nil))

	local missionMenu = createMissionMenu(self.asset, mission, self.menus)
	self.msnListMenu = missionMenu.listMenu
	self.msnMenu = missionMenu.menu

	self:update()
end

function GroupMenu:update()
	if next(self.menus) == nil then
		return
	end

	if not self.inMission then
		if self.msnListMenu == nil then
			Logger:error("update() - group(%s) msnListMenu is nil", self.asset.name)
			return
		end

		Logger:debug("update() - updating mission list for group: %s",
			self.asset.name)

		emptyMenu(self.asset, self.msnList)
		self.msnList = {}

		local cmdr = dct.theater:getCommander(self.asset.owner)
		local targetList = cmdr:getTopTargets(self.asset.ato, 10)
		local playerLocation = self.asset:getLocation()

		for _, tgt in pairs(targetList) do
			local assetTypeName = utils.getkey(enum.assetType, tgt.type)
			local missionTypeId = dctutils.assettype2mission(tgt.type)
			local missionTypeName = utils.getkey(enum.missionType, missionTypeId)
			local distance = Vector.distance(playerLocation, tgt:getLocation())
			distance = dctutils.fmtdistance(distance, self.asset.units)

			local name = string.format("%s(%s): %s - %s",
				missionTypeName, assetTypeName, tgt.codename, distance)

			local msnRqstCmd = addRqstCmd(self.asset, name, self.msnListMenu,
				enum.uiRequestType.MISSIONREQUEST, missionTypeId, { target = tgt.name })

			table.insert(self.msnList, msnRqstCmd)
		end
	end
end

function GroupMenu:onJoinMission(mission)
	if next(self.menus) ~= nil then
		self:destroy()
		self.inMission = true
		self:create(mission)
	end
end

function GroupMenu:onLeaveMission()
	if next(self.menus) ~= nil then
		self:destroy()
		self.inMission = false
		self:create()
	end
end

function GroupMenu:onDCTEvent(event)
	if event.id == enum.event.DCT_EVENT_JOIN_MISSION then
		self:onJoinMission(event.mission)
	elseif event.id == enum.event.DCT_EVENT_LEAVE_MISSION then
		self:onLeaveMission()
	end
end

return GroupMenu
