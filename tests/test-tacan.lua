#!/usr/bin/lua

require("os")
local Tacan = require("dct.data.tacan")

local function assert_equal(a, b)
	assert(a == b, string.format(
		"assertion failed! values not equal:\na: %s\nb: %s",
		tostring(a), tostring(b)))
end

local function main()
	assert_equal(Tacan.getChannelNumber("59X"), 59)
	assert_equal(Tacan.getChannelMode("59X"), "X")
	assert_equal(Tacan.isValidChannel("126Y"), true)
	assert_equal(Tacan.isValidChannel("126Y TKR"), true)
	assert_equal(Tacan.isValidChannel("128X"), false)
	assert_equal(Tacan.isValidChannel("35A"), false)
	assert_equal(Tacan.decodeChannel("35A"), nil)
	assert_equal(Tacan.decodeChannel("59X QJ").number, 59)
	assert_equal(Tacan.decodeChannel("59X QJ").mode, "X")
	assert_equal(Tacan.decodeChannel("59X QJ").frequency, 1020000000)
	assert_equal(Tacan.decodeChannel("59X QJ").callsign, "QJ")
	assert_equal(Tacan.decodeChannel("73X GW").frequency, 1160000000)
	assert_equal(Tacan.decodeChannel("16Y").frequency, 1103000000)
	assert_equal(Tacan.decodeChannel("16Y").callsign, nil)
	return 0
end

os.exit(main())
