--[[
-- SPDX-License-Identifier: LGPL-3.0
--
-- Name lists for various asset types
--]]

local tntrel = {
	["H6"]  = 1.356,
	["TNT"] = 1,
	["Tritonal"] = 1.05,
}

local function tnt_equiv_mass(exmass, tntfactor)
	return exmass * tntfactor
end

local wpnmass = {
	["Mk_82"] = tnt_equiv_mass( 87, tntrel.H6),
	["Mk_84"] = tnt_equiv_mass(443, tntrel.H6),
}

return wpnmass
