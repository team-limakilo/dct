--[[
-- SPDX-License-Identifier: LGPL-3.0
--
-- Overview:
-- ```
-- conditions = {
--   -- action
--   spawn = {
--     rules = {
--       -- rule group
--       {
--         -- one rule
--         ["Asset"] = "dead"
--       }
--     },
--     -- option
--     delay = 120
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

local function json(obj)
	return require("libs.json"):encode_pretty(obj)
end

local AssetConditions = class("AssetConditions", Marshallable)
AssetConditions.actionType = {
	["SPAWN"]   = "spawn",
	["DESTROY"] = "destroy",
}

local actionFns = {
	[AssetConditions.actionType.SPAWN] = function(_, assetmgr, asset)
		Logger:debug("'spawn' called on '%s'", asset.name)
		asset.conditions.spawn = nil
		assetmgr:remove(asset)
		assetmgr:add(asset)
		asset:spawn()
	end,
	[AssetConditions.actionType.DESTROY] = function(opts, _, asset)
		Logger:debug("'destroy' called on '%s'", asset.name)
		asset.conditions.destroy = nil
		if opts.despawn then
			asset:despawn()
		end
		if not opts.losetickets then
			asset.cost = 0
		end
		asset:setDead(true)
	end,
}

local assetRules = {
	["dead"] = function(asset)
		return asset == nil or asset:isDead()
	end,
	["alive"] = function(asset)
		return asset ~= nil and not asset:isDead()
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
		["only"]    = AssetConditions.actionType.DESTROY,
	}, {
		["name"]    = "losetickets",
		["type"]    = "boolean",
		["default"] = false,
		["only"]    = AssetConditions.actionType.DESTROY,
	},
}

local function checkConditions(action)
	local function checkOptions(conditions)
		for _, opt in pairs(options) do
			if opt.only == nil or opt.only == action then
				if conditions[opt.name] == nil then
					conditions[opt.name] = opt.default
				end
				if type(conditions[opt.name]) ~= opt.type then
					return false, string.format("'%s' must be a %s", opt.name, opt.type)
				end
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
				if assetRules[rule] == nil then
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
for _, action in pairs(AssetConditions.actionType) do
	table.insert(actionKeys, {
		["name"]  = action,
		["check"] = checkConditions(action),
	})
end

function AssetConditions:__init(template, assetName)
	Marshallable.__init(self)
	if template ~= nil then
		self.path = template.path
		utils.mergetables(self, utils.deepcopy(template.conditions))
		utils.checkkeys(actionKeys, self)
		self.tplname = template.name
		self.assetName = assetName
	end
	self:_addMarshalNames({
		"tplname",
		"assetname",
	})
	for _, action in pairs(actionKeys) do
		self:_addMarshalNames({ action.name })
	end
	self.watchedTpls = {}
end

-- Creates, validates, and returns a condition list if it's not empty
function AssetConditions.from(template, assetName)
	if not AssetConditions.isEmpty(template.conditions) then
		local cond = AssetConditions(template, assetName)
		Logger:debug("'%s' spawn conditions: %s", cond.tplname,
			json(cond[AssetConditions.actionType.SPAWN]))
		Logger:debug("'%s' destroy conditions: %s", cond.tplname,
			json(cond[AssetConditions.actionType.DESTROY]))
		return cond
	end
end

-- Checks if the template conditions contain at least one asset rule group
-- or a time rule
function AssetConditions.isEmpty(conditions)
	for _, action in pairs(actionKeys) do
		local condition = conditions[action.name]
		if condition ~= nil then
			if condition.when ~= nil and condition.when[1] ~= nil or
			   condition.after then
				return false
			end
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
	self.setup = true
	self:checkExec(nil, true)
end

-- Checks all the conditional rules and returns either true or false
-- If no decision is to be taken, returns nil
function AssetConditions:check(action)
	assert(self.setup, "setup() was not called by the asset manager")

	local condition = self[action]
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
				self.watchedTpls[tplname:lower()] = true
				local asset = self:_findAsset(tplname)
				if assetRules[ruleName](asset) ~= true then
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

function AssetConditions:checkExec(action, nodelay)
	if action == nil then
		for _, act in pairs(actionKeys) do
			self:checkExec(act, nodelay)
		end
		return
	end
	local result, opts = self:check(action.name)
	if result ~= nil then
		-- Spawn/despawn the asset
		opts.nodelay = nodelay
		local asset = self.assetmgr._conditional[self.assetName]
		self:_runAction(action, opts, asset)
	end
end

local function reschedule(self, delay, action, opts, asset)
	local cmdname = string.format("%s.%s('%s')",
		self.__clsname, action.name, asset.name)
	local cmd = Command(cmdname, self._runAction, self, action, opts, asset)
	dct.Theater.singleton():queueCommand(delay, cmd)
end

function AssetConditions:_runAction(action, opts, asset)
	if opts.delay > 0 and opts.nodelay ~= true then
		Logger:debug("%s._runAction('%s', '%s') delayed for %ds",
			self.__clsname, action.name, asset.name, opts.delay)
		-- Disable the delay so this doesn't loop infinitely
		opts.nodelay = true
		reschedule(self, opts.delay, action, opts, asset)
		return
	end
	if opts.after > 0 and opts.after > timer.getTime() then
		Logger:debug("%s._runAction('%s', '%s') too early; re-running after %ds",
			self.__clsname, action.name, asset.name, opts.after)
		-- Reschedule with an extra second in case the floating point math
		-- gets weird
		local delay = (opts.after - timer.getTime()) + 1
		reschedule(self, delay, action, opts, asset)
		return
	end
	-- Re-check to make sure the conditions are still valid
	if self:check(action.name) then
		Logger:debug("%s._runAction('%s', '%s') conditions met",
			self.__clsname, action.name, asset.name)
		actionFns[action.name](opts, self.assetmgr, asset)
	end
end

local assetEvents = {
	[enum.event.DCT_EVENT_DEAD]      = true,
	[enum.event.DCT_EVENT_ADD_ASSET] = true,
}

function AssetConditions:handleAssetEvent(event)
	if assetEvents[event.id] ~= nil and event.initiator ~= nil then
		Logger:debug("Asset event %s for %s, watched? %s",
			tostring(utils.getkey(enum.event, event.id)), self.tplname,
				tostring(self.watchedTpls[event.initiator.tplname:lower()] ~= nil))
		if self.watchedTpls[event.initiator.tplname:lower()] then
			Logger:debug("handleAssetEvent('%s') triggered", self.tplname)
			self:checkExec()
		end
	end
end

-- Verify that all template names are valid within the theater
function AssetConditions:_validateTemplateNames()
	local regionmgr = dct.Theater.singleton():getRegionMgr()
	for _, action in pairs(self.actionType) do
		local condition = self[action] and self[action].when or {}
		for _, rule in pairs(condition) do
			for tplname, _ in pairs(rule) do
				local found = false
				for _, region in pairs(regionmgr.regions) do
					if region:getTemplateByName(tplname:lower()) ~= nil then
						found = true
						break
					end
				end
				if not found then
					error(string.format("'%s' has a condition on template '%s', "..
						"which does not exist", self.tplname, tplname))
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
