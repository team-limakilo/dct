--[[
-- SPDX-License-Identifier: LGPL-3.0
--
-- Creates a container for managing region objects.
--]]

local lfs          = require("lfs")
local utils        = require("libs.utils")
local dctenum      = require("dct.enum")
local geometry     = require("dct.libs.geometry")
local human        = require("dct.ui.human")
local vector       = require("dct.libs.vector")
local Marshallable = require("dct.libs.Marshallable")
local Region       = require("dct.templates.Region")
local STM          = require("dct.templates.STM")
local Logger       = dct.Logger.getByName("RegionManager")
local settings     = dct.settings.server

local RegionManager = require("libs.namedclass")("RegionManager",
	Marshallable)
function RegionManager:__init(theater)
	self.regions = {}
	self.borders = {}
	self:loadRegions()
	self:loadBorders()
	theater:getAssetMgr():addObserver(self.onDCTEvent, self,
		self.__clsname..".onDCTEvent")
end

function RegionManager:getRegion(name)
	return self.regions[name]
end

-- Create a polygon from a group's waypoint route.
local function createPolygon(grpdata)
	local polygon = {}
	if grpdata.route ~= nil and grpdata.route.points ~= nil then
		for _, point in ipairs(grpdata.route.points) do
			table.insert(polygon, {
				x = point.x,
				y = point.y,
			})
		end
	end
	return polygon, geometry.triangulate(polygon)
end

function RegionManager:loadBorders()
	local fpath = settings.theaterpath..utils.sep.."borders.stm"
	local file, err = io.open(fpath)
	if err ~= nil then
		Logger:warn("could not open borders file: %s", tostring(err))
		return
	end
	file:close()
	local data = utils.readlua(fpath, "staticTemplate")
	local tpl = STM.transform(data)
	for _, grp in ipairs(tpl.tpldata) do
		for rgnname, _ in pairs(self.regions) do
			if grp.data.name:match(rgnname) then
				local polygon, triangles = createPolygon(grp.data)
				if polygon ~= nil then
					table.insert(self.borders[rgnname], {
						center = geometry.meanCenter2D(polygon),
						title = grp.data.name,
						triangles = triangles,
						polygon = polygon,
					})
				end
			end
		end
	end
end

function RegionManager:loadRegions()
	for filename in lfs.dir(settings.theaterpath) do
		if filename ~= "." and filename ~= ".." and
			filename ~= ".git" and filename ~= "settings" then
			local fpath = settings.theaterpath..utils.sep..filename
			local fattr = lfs.attributes(fpath)
			if fattr.mode == "directory" then
				local r = Region(fpath)
				assert(self.regions[r.name] == nil, "duplicate regions " ..
					"defined for theater: " .. settings.theaterpath)
				self.regions[r.name] = r
				self.borders[r.name] = {}
			end
		end
	end
end

local function cost(thisrgn, otherrgn)
	if thisrgn == nil or otherrgn == nil then
		return nil
	end
	return vector.distance(vector.Vector2D(thisrgn:getPoint()),
		vector.Vector2D(otherrgn:getPoint()))
end

function RegionManager:validateEdges()
	for _, thisrgn in pairs(self.regions) do
		local links = {}
		for domain, lnks in pairs(thisrgn.links) do
			links[domain] = {}
			for _, rgnname in pairs(lnks) do
				if rgnname ~= thisrgn.name then
					links[domain][rgnname] =
						cost(thisrgn, self.regions[rgnname])
				end
			end
		end
		thisrgn.links = links
	end
end

function RegionManager:generate()
	for _, r in pairs(self.regions) do
		r:generate()
	end
	self:validateEdges()
end

function RegionManager:postinit()
	human.updateBorders(self.regions, self.borders)
end

function RegionManager:marshal()
	local tbl = {}
	tbl.regions = {}

	for rgnname, region in pairs(self.regions) do
		tbl.regions[rgnname] = region:marshal()
	end
	return tbl
end

function RegionManager:unmarshal(data)
	if data.regions == nil then
		return
	end
	for rgnname, region in pairs(self.regions) do
		region:unmarshal(data.regions[rgnname])
	end
end

local relevants = {
	[dctenum.event.DCT_EVENT_DEAD]      = true,
	[dctenum.event.DCT_EVENT_ADD_ASSET] = true,
}

function RegionManager:onDCTEvent(event)
	if relevants[event.id] == nil then
		return
	end

	local region = self.regions[event.initiator.rgnname]
	if region then
		region:onDCTEvent(event)
	end
end

return RegionManager
