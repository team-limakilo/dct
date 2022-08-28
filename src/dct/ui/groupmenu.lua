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
local human    = require("dct.ui.human")
local Logger   = dct.Logger.getByName("GroupMenu")

local function addMenu(groupMenu, name, path)
	local groupId = groupMenu.asset.groupId
	local menu = missionCommands.addSubMenuForGroup(groupId, name, path)
	table.insert(groupMenu.menus, menu)
	return menu
end

local function addCmd(groupMenu, name, path, handler, data)
	local groupId = groupMenu.asset.groupId
	local cmd = missionCommands.addCommandForGroup(groupId, name, path,
		handler, data)
	table.insert(groupMenu.menus, cmd)
	return cmd
end

local function addRqstCmd(groupMenu, name, path, request, val, args)
	check.number(request)
	if args == nil then
		args = {}
	end
	args.name = groupMenu.asset.name
	args.type = request
	args.value = val
	return addCmd(groupMenu, name, path, dct.Theater.playerRequest, args)
end

local function createMissionMenu(groupMenu, mission)
	if mission ~= nil then
		-- asset already has a mission
		local menu = addMenu(groupMenu, string.format("Mission %d", mission.id))

		addRqstCmd(groupMenu, "Briefing", menu, enum.uiRequestType.MISSIONBRIEF)
		addRqstCmd(groupMenu, "Status", menu, enum.uiRequestType.MISSIONSTATUS)
		addRqstCmd(groupMenu, "Abort", menu,
			enum.uiRequestType.MISSIONABORT, enum.missionAbortType.ABORT)
		addRqstCmd(groupMenu, "Rolex +30", menu,
			enum.uiRequestType.MISSIONROLEX, 30 * 60)

		return {
			menu = menu,
		}
	else
		-- asset has no mission assigned
		local menu = addMenu(groupMenu, "Mission")

		local requestTypeMenu = addMenu(groupMenu, "Request (Type)", menu)
		for typename, msntype in utils.sortedpairs(groupMenu.asset.ato, dctutils.missionPairs) do
			addRqstCmd(groupMenu, typename, requestTypeMenu,
				enum.uiRequestType.MISSIONREQUEST, msntype)
		end

		local requestListMenu = addMenu(groupMenu, "Request (List)", menu)

		addRqstCmd(groupMenu, "Join (Scratchpad)", menu,
			enum.uiRequestType.MISSIONJOIN)

		local joinCodeMenu = addMenu(groupMenu, "Join (Input Code)", menu)
		msncodes.addMissionCodes(groupMenu.asset, joinCodeMenu, {
			addCmd = function(...) return addCmd(groupMenu, ...) end,
			addMenu = function(...) return addMenu(groupMenu, ...) end,
		})

		return {
			menu = menu,
			requestListMenu = requestListMenu,
		}
	end
end

local GroupMenu = class("GroupMenu")
function GroupMenu:__init(asset)
	assert(asset:isa(require("dct.assets.Player")),
		"GroupMenu can only be initialized with a Player asset")
	self.asset         = asset
	self.menus         = {}
	self.msnList       = {}
	self.msnListFilter = {}
	self.msnMenu       = nil
	self.msnListMenu   = nil
	self.inMission     = false
	asset:addObserver(self.onDCTEvent, self, self.__clsname..".onDCTEvent")
end

local function clearMenu(asset, menu)
	-- make sure we always remove child items first
	for i = #menu, 1, -1 do
		missionCommands.removeItemForGroup(asset.groupId, menu[i])
		table.remove(menu, i)
	end
end

function GroupMenu:destroy()
	if next(self.menus) == nil then
		return
	end

	Logger:debug("destroy() - removing menu for group: %s", self.asset.name)
	clearMenu(self.asset, self.menus)
	self.menus         = {}
	self.msnList       = {}
	self.msnListFilter = {}
	self.msnMenu       = nil
	self.msnListMenu   = nil
end

function GroupMenu:create(mission)
	if next(self.menus) ~= nil then
		Logger:debug("create() - group(%s) already had menu added",
			self.asset.name)
		return
	end

	Logger:debug("create() - adding menu for group: %s", self.asset.name)

	local padmenu = addMenu(self, "Scratch Pad", nil)
	addRqstCmd(self, "DISPLAY", padmenu, enum.uiRequestType.SCRATCHPADGET)
	addRqstCmd(self, "SET", padmenu, enum.uiRequestType.SCRATCHPADSET)

	addRqstCmd(self, "Theater Update", nil, enum.uiRequestType.THEATERSTATUS)

	loadout.addMenu(function(...) return addCmd(self, ...) end, self.asset, nil)

	local missionMenu = createMissionMenu(self, mission)
	self.msnListMenu = missionMenu.requestListMenu
	self.msnMenu = missionMenu.menu

	self:update()
end

function GroupMenu:update()
	-- do not update if no root menus exist yet
	if next(self.menus) == nil then
		return
	end

	if self.asset.missionid == enum.missionInvalidID then
		if self.msnListMenu == nil then
			Logger:error("update() - group(%s) msnListMenu is nil", self.asset.name)
			return
		end

		Logger:debug("update() - updating active mission list for group: %s",
			self.asset.name)

		clearMenu(self.asset, self.msnList)
		self.msnList = {}

		-- remove already deleted entries from the main menu list
		for i = #self.menus, 1, -1 do
			if self.msnListFilter[self.menus[i]] ~= nil then
				table.remove(self.menus, i)
			end
		end
		self.msnListFilter = {}

		local cmdr = dct.theater:getCommander(self.asset.owner)
		local targetList = cmdr:getTopTargets(self.asset.ato, 10)
		local playerLocation = self.asset:getLocation()

		for _, tgt in pairs(targetList) do
			local assetTypeName = utils.getkey(enum.assetType, tgt.type)
			if tgt.sitetype ~= nil and tgt.sitetype ~= assetTypeName then
				assetTypeName = assetTypeName.."/"..tgt.sitetype
			end
			local missionTypeId = dctutils.assettype2mission(tgt.type)
			local missionTypeName = utils.getkey(enum.missionType, missionTypeId)
			local distance = Vector.distance(playerLocation, tgt:getLocation())
			distance = human.formatDistance(distance, self.asset.units)

			local name = string.format("%s (%s): %s - %s",
				missionTypeName, assetTypeName, tgt.codename, distance)

			local msnRqstCmd = addRqstCmd(self, name, self.msnListMenu,
				enum.uiRequestType.MISSIONREQUEST, missionTypeId, { target = tgt.name })

			self.msnListFilter[msnRqstCmd] = true
			table.insert(self.msnList, msnRqstCmd)
		end
	end
end

function GroupMenu:onJoinMission(mission)
	if next(self.menus) ~= nil then
		self:destroy()
		self:create(mission)
	end
end

function GroupMenu:onLeaveMission()
	if next(self.menus) ~= nil then
		self:destroy()
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
