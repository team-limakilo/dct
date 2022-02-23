--[[
-- SPDX-License-Identifier: LGPL-3.0
--
-- Overview:
-- ```
-- conditions = {
--   -- action
--   create = {
--     when = {
--       -- rule group (OR relation between groups)
--       {
--         -- rules (AND relation between rules)
--         ["Asset1"] = "dead",
--         ["Asset2"] = "alive",
--         ["Asset3"] = "route_finished",
--       }
--     },
--     -- options
--     delay = 120,
--     after = 60 * 10,
--   }
-- }
-- ```
--]]

local enum         = require("dct.enum")
local utils        = require("libs.utils")
local check        = require("libs.check")
local class        = require("libs.namedclass")
local Command      = require("dct.Command")
local Marshallable = require("dct.libs.Marshallable")
local Logger       = dct.Logger.getByName("AssetConditions")

local actionTypes = {
	["create"] = function(_, assetmgr, asset)
		assetmgr:remove(asset)
		assetmgr:add(asset)
		asset:spawn()
	end,
	["destroy"] = function(opts, _, asset)
		if opts.despawn then
			asset:despawn()
		end
		if not opts.losetickets then
			asset.cost = 0
		end
		asset:setDead(true)
	end,
}

local ruleTypes = {
	["dead"] = function(asset)
		return asset == nil or asset:isDead()
	end,
	["alive"] = function(asset)
		return asset ~= nil and not asset:isDead()
	end,
	["route_finished"] = function(asset)
		error("TODO")
	end,
}

local options = {
	{
		["name"]    = "after",
		["type"]    = "number",
		["default"] = 0,
	}, {
		["name"]    = "delay",
		["type"]    = "number",
		["default"] = 0,
	}, {
		["name"]    = "despawn",
		["type"]    = "boolean",
		["default"] = false,
	}, {
		["name"]    = "losetickets",
		["type"]    = "boolean",
		["default"] = false,
	},
}

local function checkConditions(action)
	local function checkOptions(conditions)
		for _, opt in pairs(options) do
			if conditions[opt.name] == nil then
				conditions[opt.name] = opt.default
			end
			if type(conditions[opt.name]) ~= opt.type then
				return false, string.format("'%s' must be a %s", opt.name, opt.type)
			end
		end
	end
	local function checkRuleGroups(conditions)
		if conditions.when == nil then
			return true
		end
		for _, group in pairs(conditions.when) do
			if type(group) ~= "table" then
				return false,
					string.format("unexpected '%s' in rules", tostring(group))
			end
			if next(group) == nil then
				return false, "empty rule groups are not allowed"
			end
			for asset, rule in pairs(group) do
				if ruleTypes[rule] == nil then
					return false, string.format(
						"unknown asset rule '%s' for '%s'", rule, asset)
				end
			end
		end
	end
	return function(keydata, tbl)
		local conditions = tbl[keydata.name]
		if conditions == nil then
			return true
		elseif type(conditions) ~= "table" then
			return false, string.format("%s must be a table or nil", keydata.name)
		end
		local result, msg
		result, msg = checkOptions(conditions)
		if result == false then
			return result, msg
		end
		result, msg = checkRuleGroups(conditions)
		if result == false then
			return result, msg
		end
		return true
	end
end

local actionKeys = {}
for action, _ in pairs(actionTypes) do
	table.insert(actionKeys, {
		["name"]  = action,
		["check"] = checkConditions(action),
	})
end

local AssetConditions = class("AssetConditions", Marshallable)
function AssetConditions:__init(template, assetname)
	Marshallable.__init(self)
	if template ~= nil then
		check.table(template)
		check.string(assetname)
		utils.checkkeys(actionKeys, template.conditions)
		self.path = template.path
		self.actions = utils.deepcopy(template.conditions)
		self.tplname = template.name
		self.assetname = assetname
	end
	self:_addMarshalNames({
		"actions",
		"tplname",
		"assetname",
	})
	self.watchedtpls = {}
end

-- Creates, validates, and returns a condition list if it's not empty
function AssetConditions.from(template, assetName)
	if not AssetConditions.isEmpty(template.conditions) then
		local conditions = AssetConditions(template, assetName)
		for action, _ in pairs(actionTypes) do
			Logger:debug("'%s' %s conditions: %s", conditions.tplname, action,
				require("libs.json"):encode_pretty(conditions.actions[action]))
		end
		return conditions
	end
end

-- Checks if the template conditions contain at least one asset rule group
-- or a time rule
function AssetConditions.isEmpty(conditions)
	for action, _ in pairs(actionTypes) do
		local condition = conditions[action] or {}
		if condition.when ~= nil and condition.when[1] ~= nil or condition.after then
			return false
		end
	end
	return true
end

function AssetConditions:setup(assetmgr)
	self:_validateTemplateNames()
	self.assetmgr = assetmgr
	self.assetmgr:addObserver(self.handleAssetEvent, self,
		self.__clsname..".handleAssetEvent")
	self.theater = dct.Theater.singleton()
	self._setup = true
	self:checkExec(nil, true)
end

-- Checks rules for a given action and returns a boolean indicating if
-- it should be executed, and a copy of the matching rules.
-- If no decision is to be taken, returns nil.
function AssetConditions:check(action)
	assert(self._setup, "setup() must be called by the asset manager before "..
		"conditions are used")

	Logger:debug("check called for action '%s': %s", tostring(action),
		require("libs.json"):encode_pretty(self.actions))

	local condition = self.actions[action]
	if condition == nil then
		return nil, nil
	end

	local after = condition.after or 0
	check.number(after)
	if timer.getTime() < after then
		return false, utils.shallowclone(condition)
	end

	-- Each group must have all assets match the rule,
	-- but any matching group activates the event
	-- Effectively, assets in a group are an AND condition,
	-- while groups in a rule are an OR condition
	local actionResult = true
	if condition.when ~= nil then
		actionResult = false
		for _, ruleGroup in pairs(condition.when) do
			local groupResult = true
			for tplname, ruleName in pairs(ruleGroup) do
				local asset = self:_findAsset(tplname)
				if ruleTypes[ruleName](asset) ~= true then
					groupResult = false
					break
				end
			end
			if groupResult == true then
				actionResult = true
				break
			end
		end
	end
	return actionResult, utils.shallowclone(condition)
end

-- Checks rules and immediately runs actions if they match.
function AssetConditions:checkExec(action, nodelay)
	if action == nil then
		for act, _ in pairs(actionTypes) do
			self:checkExec(act, nodelay)
		end
		return
	end
	Logger:debug("%s", debug.traceback("checkExec", 2))
	local result, opts = self:check(action)
	if result ~= nil then
		-- Create/destroy the asset
		opts.nodelay = nodelay
		local asset = self.assetmgr._conditional[self.assetname]
		self:_runAction(action, opts, asset)
	end
end

-- Returns whether the asset creation is conditional, so it should
-- not be created with the rest of the theater.
function AssetConditions:delayCreation()
	return self.actions.create ~= nil
end

local function reschedule(self, delay, action, opts, asset)
	local cmdname = string.format("%s.%s('%s')",
		self.__clsname, tostring(action), asset.name)
	local cmd = Command(cmdname, self._runAction, self, action, opts, asset)
	dct.Theater.singleton():queueCommand(delay, cmd)
end

function AssetConditions:_runAction(action, opts, asset)
	if opts.delay > 0 and opts.nodelay ~= true then
		Logger:debug("%s._runAction('%s', '%s') delayed for %ds",
			self.__clsname, tostring(action), asset.name, opts.delay)
		-- Disable the delay so this doesn't loop infinitely
		opts.nodelay = true
		reschedule(self, opts.delay, action, opts, asset)
		return
	end
	if opts.after > 0 and opts.after > timer.getTime() then
		Logger:debug("%s._runAction('%s', '%s') too early; re-running after %ds",
			self.__clsname, tostring(action), asset.name, opts.after)
		-- Reschedule with an extra second to account for possible rounding issues
		local delay = (opts.after - timer.getTime()) + 1
		reschedule(self, delay, action, opts, asset)
		return
	end
	-- Re-check to make sure the conditions are still valid after any delays
	if self:check(action) then
		Logger:debug("%s._runAction('%s', '%s') condition met",
			self.__clsname, tostring(action), asset.name)
		self.actions[action] = nil
		actionTypes[action](opts, self.assetmgr, asset)
	end
end

local assetEvents = {
	[enum.event.DCT_EVENT_DEAD]      = true,
	[enum.event.DCT_EVENT_ADD_ASSET] = true,
}

function AssetConditions:handleAssetEvent(event)
	if assetEvents[event.id] ~= nil and event.initiator ~= nil then
		Logger:debug("'%s' detected event '%s' from '%s', is initiator watched? %s",
			tostring(self.tplname), utils.getkey(enum.event, event.id), tostring(event.initiator.tplname),
				tostring(self.watchedtpls[event.initiator.tplname:lower()] ~= nil))
		if self.watchedtpls[event.initiator.tplname:lower()] then
			Logger:debug("handleAssetEvent('%s') triggered", self.tplname)
			self:checkExec()
		end
	end
end

-- Verify that all template names are valid in the theater
function AssetConditions:_validateTemplateNames()
	local regionmgr = dct.Theater.singleton():getRegionMgr()
	for action, _ in pairs(actionTypes) do
		local rules = self.actions[action] and self.actions[action].when or {}
		for _, rule in pairs(rules) do
			for tplname, _ in pairs(rule) do
				local found = false
				for _, region in pairs(regionmgr.regions) do
					if region:getTemplateByName(tplname:lower()) ~= nil then
						Logger:debug("'%s' watching template '%s'", self.tplname, tplname)
						self.watchedtpls[tplname:lower()] = true
						found = true
						break
					end
				end
				if not found then
					error(string.format("'%s' conditions depend on template "..
						"'%s', which does not exist", self.tplname, tplname))
				end
			end
		end
	end
end

-- Finds an asset based on its template name
function AssetConditions:_findAsset(tplname)
	local assets = self.assetmgr:filterAssets(function(asset)
		return asset.tplname:lower() == tplname:lower()
	end)
	local _, first = next(assets)
	return first
end

return AssetConditions
