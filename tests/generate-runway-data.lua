#!/usr/bin/lua

require("os")
require("io")
require("dcttestlibs")
local utils = require("libs.utils")
local STM = require("dct.templates.STM")

local function allGroups(grp)
	if grp.units then
		return true
	end
	return false
end

local function main()
	local runwayinfo = {}
	for _, coa_data in pairs(env.mission.coalition) do
		local grps = STM.processCoalition(coa_data,
			env.getValueDictByKey,
			allGroups,
			nil)
		for _, grp in ipairs(grps) do
			local split = string.gmatch(grp.data.name, "[^_]+")
			local ab = split()
			local rwyname = split() or "default"

			if not runwayinfo[ab] then
				runwayinfo[ab] = {}
			end
			local rwy = {}
			rwy.name = rwyname
			rwy.geometry = {}
			for _, unit in ipairs(grp.data.units) do
				local pt = {}
				pt.name = unit.name
				pt.x = unit.x
				pt.y = unit.y
				table.insert(rwy.geometry, pt)
			end
			runwayinfo[ab][rwy.name] = rwy
		end
	end

	print(require("libs.json"):encode_pretty(runwayinfo))
end

os.exit(main())
