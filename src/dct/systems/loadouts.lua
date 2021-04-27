--[[
-- SPDX-License-Identifier: LGPL-3.0
--
-- Implements a loadout point buy system to limit player loadouts.
-- Assumes a single player slot per group and it is the first slot.
--]]

require("lfs")
local enum     = require("dct.enum")
local dctutils = require("dct.utils")
local settings = _G.dct.settings

-- returns totals for all weapon types, returns nil if the group
-- does not exist
local function totalPayload(grp, limits)
	local unit = grp:getUnit(1)
	local restrictedWeapons = settings.restrictedweapons
	local payload = unit:getAmmo()
	local nuke = false
	local total = {}
	for _, v in pairs(enum.weaponCategory) do
		total[v] = {
			["current"] = 0,
			["max"]     = limits[v] or 0,
			["payload"] = {}
		}
	end

	-- tally weapon costs
	for _, wpn in ipairs(payload or {}) do
		local wpnname = dctutils.trimTypeName(wpn.desc.typeName)
		local wpncnt  = wpn.count
		local restriction = restrictedWeapons[wpnname] or {}
		local cost = restriction.cost or 0
		local category = restriction.category
			or enum.weaponCategory.UNRESTRICTED

		total[category].current =
			total[category].current + (wpncnt * cost)

		if restriction.nuclear then
			env.info("NUCLEAR WEAPON DETECTED")
			nuke = true
		end

		-- TODO: it seems cannons have an internal category of 0,
		-- what are the other categories?
		if wpn.desc.category > 0 then
			table.insert(total[category].payload, {
				["name"] = wpn.desc.displayName,
				["count"] = wpncnt,
				["cost"] = cost,
			})
		end
	end
	return total, nuke
end

-- returns a triple:
--   first arg (boolean) is payload valid
--   second arg (table) total cost per category of the payload, also
--       includes the max allowed for the airframe
--   third arg (boolean) payload contains a nuclear weapon
local function validatePayload(grp, limits)
	local total, nuke = totalPayload(grp, limits)

	for _, cost in pairs(total) do
		if cost.current > cost.max then
			return false, total, nuke
		end
	end

	return true, total, nuke
end

local loadout = {}

function loadout.check(player)
	local group = Group.getByName(player.name)
	if group ~= nil then
		return validatePayload(Group.getByName(player.name),
			player.payloadlimits)
	else
		-- TODO: log something here
		return true, {}, false
	end
end

function loadout.addmenu(asset, menu, handler, context)
	local gid  = asset.groupId
	local name = asset.name
	missionCommands.addCommandForGroup(gid,
		"Check Payload", menu, handler, context, {
			["name"]   = name,
			["type"]   = enum.uiRequestType.CHECKPAYLOAD,
		})
end

return loadout
