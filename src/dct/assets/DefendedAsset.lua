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

local function getAssetMgr()
    return require("dct.Theater").singleton():getAssetMgr()
end

local DefendedAsset = class("DefendedAsset", StaticAsset, Subordinates)
function DefendedAsset:__init(template)
    self._logger = Logger("Asset: DefendedAsset("..template.name..")")
    if template ~= nil then
        template.subordinates = {}
        self:_modifyTemplate(template)
    end
	Subordinates.__init(self)
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

function DefendedAsset:_completeinit(template)
    StaticAsset._completeinit(self, template)
    self._subordinates = template.subordinates
end

function DefendedAsset:_setup()
    StaticAsset._setup(self)
    local assetmgr = getAssetMgr()
	for _, name in pairs(self._subordinates) do
        local asset = assetmgr:getAsset(name)
        if asset then
            self:addSubordinate(asset)
        end
    end
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
			   desc.attributes["MANDPADS"] then
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
		if #originalGroup.units == 0 then
			self._logger:debug("%s group removed", template.name)
			table.remove(template.tpldata, g)
		end
		if #shoradGroup.units == 0 then
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
	-- spawn the new shorad asset if it's not empty
	if #shorad.tpldata > 0 then
		table.insert(template.subordinates, shorad.name)
        local assetmgr = getAssetMgr()
		local shoradAsset = assetmgr:factory(shorad.objtype)(shorad)
        assetmgr:add(shoradAsset)
	else
		self._logger:debug("%s template removed", shorad.name)
	end
end

return DefendedAsset
