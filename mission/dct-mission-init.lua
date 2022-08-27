--[[
-- SPDX-License-Identifier: LGPL-3.0
--
-- DCT mission script
--
-- This script is intended to be included in a DCS mission file via
-- the trigger system. This file will test and verify the server's
-- environment supports the calls required by DCT framework. It will
-- then setup and start the framework.
--]]

do
	if require == nil or require("lfs") == nil or require("io") == nil then
		local msg
		local playerCount = #net.get_player_list()
		if playerCount > 1 then
			-- This message will be shown to connected clients if they are reloading
			-- the mission locally during a server restart.
			msg = "Oops! DCS is trying to run server scripts locally,"..
				" but they are not designed to do so, and show error messages."..
				" Please leave and re-join the server to work around this bug."
		else
			-- This message will be shown in singleplayer and when first loading
			-- the mission in multiplayer.
			msg = "DCT requires the DCS mission scripting environment"..
				" to be modified, the file needing to be changed can be found"..
				" at $DCS_ROOT\\Scripts\\MissionScripting.lua. Comment out"..
				" the removal of lfs and io and the setting of 'require' to"..
				" nil."
		end
		error(msg)
	end

	-- 'dctsettings' can be defined in the mission to set nomodlog
	dctsettings = dctsettings or {}

	-- Check that DCT mod is installed
	local modpath = lfs.writedir() .. "Mods\\tech\\DCT"
	if lfs.attributes(modpath) == nil then
		local errmsg = "DCT: module not installed, mission not DCT enabled"
		if dctsettings.nomodlog then
			env.error(errmsg)
		else
			assert(false, errmsg)
		end
	else
		package.path = package.path .. ";" .. modpath .. "\\lua\\?.lua;"
		require("dct")
		dct.init()
	end
end
