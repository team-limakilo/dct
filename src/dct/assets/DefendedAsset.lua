--[[
-- SPDX-License-Identifier: LGPL-3.0
--
-- Subtype of StaticAsset that includes defenses which disband
-- when the parent asset dies.
--]]

local utils        = require("libs.utils")
local class        = require("libs.namedclass")
local enum         = require("dct.enum")
local StaticAsset  = require("dct.assets.StaticAsset")
local Subordinates = require("dct.libs.Subordinates")
local Logger       = require("dct.libs.Logger")

local DefendedAsset = class("DefendedAsset", StaticAsset, Subordinates)
function DefendedAsset:__init(template)
    Subordinates.__init(self)
    if template ~= nil then
        self._logger = Logger("Asset: DefendedAsset("..template.name..")")
        self:_modifyTemplate(template)
    end
	StaticAsset.__init(self, template)
	self:_addMarshalNames({
		"_subordinates",
	})
end

function DefendedAsset.assettypes()
	return {
		enum.assetType.EWR,
		enum.assetType.SAM,
	}
end

-- splits SHORAD out of the template and spawns it as a separate asset
function DefendedAsset:_modifyTemplate(template)
    local shorad = utils.deepcopy(template)
	shorad.hasDeathGoals = false
	shorad.objtype = enum.assetType.SHORAD
	shorad.name = template.name.."-SHORAD"
	shorad.desc = nil
	shorad.cost = 0
	for g = #template.tpldata, 1, -1 do
		self._logger:debug("%s group = %d", template.name, g)
		local originalGroup = template.tpldata[g].data
		local shoradGroup = shorad.tpldata[g].data
		-- rename SHORAD group to avoid spawn conflicts
		shoradGroup.name = originalGroup.name.."-SHORAD"
		-- remove SHORAD from SAM/EWR, keep in the new template
		for un = #originalGroup.units, 1, -1  do
			self._logger:debug("%s unit %d", template.name, un)
			local unit = originalGroup.units[un]
			local desc = Unit.getDescByName(unit.type)
			if desc.attributes["AAA"] or
			   desc.attributes["SR SAM"] or
			   desc.attributes["MANPADS"] then
				-- delete from original, keep in SHORAD
				self._logger:debug("%s unit removed", template.name)
				table.remove(originalGroup.units, un)
			else
				-- delete from SHORAD, keep in original
				self._logger:debug("%s unit removed", shorad.name)
				table.remove(shoradGroup.units, un)
			end
		end
		-- prune empty groups
		if next(originalGroup.units) == nil then
			self._logger:debug("%s group removed", template.name)
			table.remove(template.tpldata, g)
		end
		if next(shoradGroup.units) == nil then
			self._logger:debug("%s group removed", shorad.name)
			table.remove(shorad.tpldata, g)
		end
	end
	-- remove waypoints from the SHORAD template
	for g = 1, #shorad.tpldata do
		shorad.tpldata[g].data.route = {
			points = {},
			spans  = {},
		}
	end
	-- spawn the new shorad asset as a subordinate if it's not empty
	if next(shorad.tpldata) ~= nil then
        local assetmgr = _G.dct.Theater.singleton():getAssetMgr()
		local shoradAsset = assetmgr:factory(shorad.objtype)(shorad)
        assetmgr:add(shoradAsset)
        self:addSubordinate(shoradAsset)
	else
		self._logger:debug("%s dropped", shorad.name)
	end
end

return DefendedAsset
