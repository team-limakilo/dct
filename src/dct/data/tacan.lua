--[[
-- SPDX-License-Identifier: LGPL-3.0
--
-- Validates and decodes TACAN channels into radio frequencies
--]]

local Tacan = {}

Tacan.MHZ = 1000 * 1000
Tacan.GND_BASE_X = 961
Tacan.GND_BASE_Y = 1087
Tacan.GND_BASE_INV = 64
Tacan.MIN_CHANNEL = 1
Tacan.MAX_CHANNEL = 127
Tacan.MODE = {
	["X"] = "X",
	["Y"] = "Y",
}

function Tacan.getChannelNumber(channel)
	return tonumber(string.match(channel, "^(%d+)%a"))
end

function Tacan.getChannelMode(channel)
	return string.match(channel, "^%d+(%a)")
end

function Tacan.getCallsign(channel)
	return string.match(channel, "^%d+%a%s+(%w.+)$")
end

function Tacan.isValidChannel(channel)
	local number = Tacan.getChannelNumber(channel)
	local mode = Tacan.getChannelMode(channel)
	local valid = Tacan.MODE[mode] ~= nil
	  and number >= Tacan.MIN_CHANNEL
	  and number <= Tacan.MAX_CHANNEL
	if valid then
		return true, number, mode
	else
		return false
	end
end

function Tacan.getFrequencyBase(number, mode)
	if number < Tacan.GND_BASE_INV then
		if mode == Tacan.MODE.X then
			return Tacan.GND_BASE_X
		elseif mode == Tacan.MODE.Y then
			return Tacan.GND_BASE_Y
		end
	else
		-- starting from channel 64, X and Y bases are swapped
		if mode == Tacan.MODE.X then
			return Tacan.GND_BASE_Y
		elseif mode == Tacan.MODE.Y then
			return Tacan.GND_BASE_X
		end
	end
end

function Tacan.decodeChannel(channel)
	local valid, number, mode = Tacan.isValidChannel(channel)
	if not valid then
		return nil
	end
	local base = Tacan.getFrequencyBase(number, mode)
	return {
		callsign = Tacan.getCallsign(channel),
		frequency = (number + base) * Tacan.MHZ,
		number = number,
		mode = mode,
	}
end

return Tacan
