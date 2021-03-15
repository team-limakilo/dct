--[[
-- SPDX-License-Identifier: LGPL-3.0
--
-- Weapon blasteffect and enhacement system
--
-- This listens for DCT impact events and trigger enhanced
-- explosions based on those impact events. This also searches
-- for airbases within the area of the impact and will send
-- a DCT hit event to the airbase if found.
--]]

--[[
-- return the distance in meters from the center of a blast from an
-- explosive charge of mass(kg) that will cause leathal damage to an
-- unarmored target
-- Assume a normalized TNT equivalent mass
-- sources:
--   https://www.fema.gov/pdf/plan/prevent/rms/428/fema428_ch4.pdf
--   https://www.fourmilab.ch/etexts/www/effects/eonw_3.pdf

local function calcRadiusFromMass(mass)
	return math.ceil(11.338 * math.pow(mass, .281))
end
--]]

local dctenum = require("dct.enum")
local class   = require("libs.namedclass")
local Logger  = require("dct.libs.Logger").getByName("System")

local function getCorrectedExplosiveMass(wpntypename)
	return dct.settings.blasteffects[wpntypename]
end

--[[
-- If there is a DCT asset of the same name as the DCS base,
-- notify the DCT asset it has been hit.
--]]
local function handlebase(base, wpn, theater)
	local basename = base:getName()
	local asset = theater:getAssetMgr():getAsset(basename)

	if asset == nil then
		return
	end

	asset:onDCTEvent(dctenum.buildevent.hit(wpn:getImpactPoint(), wpn))
end

local BlastEffects = class("BlastEffects")
function BlastEffects:__init(theater)
	self._theater = theater
	theater:addObserver(self.event, self, self.__clsname..".event")
	Logger:debug("init "..self.__clsname)
end

function BlastEffects:event(event)
	if not event.id == dctenum.event.DCT_EVENT_IMPACT then
		return
	end

	local power = getCorrectedExplosiveMass(event.initiator.type)
	if power ~= nil then
		trigger.action.explosion(event.point, power)
	end

	local vol = {
		id = world.VolumeType.SPHERE,
		params = {
			point = event.point,
			radius = 6000, -- allows for > 15000ft runway
		},
	}
	world.searchObjects(Object.Category.BASE, vol, handlebase,
		event.initiator, self._theater)
end

return BlastEffects
