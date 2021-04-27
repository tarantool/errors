#!/usr/bin/env tarantool

local log = require('log')
local tap = require('tap')
local errors = require('errors')

local test = tap.test('errors.new_class')
test:plan(7)

--- errors.new_class() --------------------------------------------------------
-------------------------------------------------------------------------------

local e_nostack = errors.new_class('No-stack error', {capture_stack = false})
local err = e_nostack:new()
test:test('capture_stack = false', function(subtest)
    subtest:plan(2)
    subtest:is(err.stack, nil, 'check stack is nil')
    subtest:is(err:tostring(), 'No-stack error: ', "check tostring() doesn't contains stacktrace")
end)
-------------------------------------------------------------------------------

local _log
log.error = function(arg)
    _log = arg
end

local e_logged = errors.new_class('Logged error', {log_on_creation = true})
local err = e_logged:new()
test:is(_log, tostring(err), 'log_on_creation = true')

-------------------------------------------------------------------------------

local _, err = pcall(errors.new_class, 'Unknown-option error', {unknown_option = true})
test:is(err, 'Unexpected argument options.unknown_option to errors.new_class',
    'unknown_option = false'
)

local _, err = pcall(errors.new_class, 'Bad-option error', {capture_stack = 1})
test:is(err, 'Bad argument options.capture_stack to errors.new_class' ..
    ' (boolean expected, got number)', 'capture_stack = 1'
)

-------------------------------------------------------------------------------

local my_error = errors.new_class('My error')
local _, err = pcall(my_error.new)
test:is(err, 'Use error_class:new() instead of error_class.new()',
    'my_error.new()'
)

local _, err = pcall(my_error.pcall)
test:is(err, 'Use error_class:pcall() instead of error_class.pcall()',
    'my_error.pcall()'
)

local _, err = pcall(my_error.assert)
test:is(err, 'Use error_class:assert() instead of error_class.assert()',
    'my_error.assert()'
)

os.exit(test:check() and 0 or 1)
