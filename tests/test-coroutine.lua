#!/usr/bin/lua

require("dcttestlibs")
require("dct")
local CoroutineCommand = require("dct.CoroutineCommand")

local function assert_equal(actual, expected)
	assert(actual == expected, string.format(
		"assertion failed! values not equal:\nexpected: %s\nactual: %s",
		tostring(expected), tostring(actual)))
end

local TIME = 0

local testfn = function(foo, time)
	assert_equal(foo, "arg1")
	assert_equal(time, TIME)
	return coroutine.yield()
end

local function main()
	local cmd = CoroutineCommand("testCommand", testfn, "arg1")
	TIME = 1
	assert_equal(cmd:isDone(), false)
	assert_equal(cmd:execute(TIME), nil)
	TIME = 2
	assert_equal(cmd:isDone(), false)
	assert_equal(cmd:execute(TIME), 2)
	assert_equal(cmd:isDone(), true)
	TIME = 3
	assert_equal(cmd:execute(TIME), nil)
	assert_equal(cmd:isDone(), false)
	assert_equal(cmd:execute(TIME), 3)
	assert_equal(cmd:isDone(), true)
end

os.exit(main())
