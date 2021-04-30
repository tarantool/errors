local log = require('log')
local errors = require('errors')

local t = require('luatest')
local g = t.group()

function g.test_errors_new_class_ok()
    local e_nostack = errors.new_class('No-stack error', {capture_stack = false})
    local err = e_nostack:new()
    t.assert_not(err.stack, 'check stack is nil')
    t.assert_equals(err:tostring(), 'No-stack error: ',
        "check tostring() doesn't contains stacktrace"
    )

    local _log
    log.error = function(arg)
        _log = arg
    end

    local e_logged = errors.new_class('Logged error', {log_on_creation = true})
    local err = e_logged:new()
    t.assert_equals(_log, tostring(err), 'log_on_creation = true')
end

function g.test_errors_new_class_raise()
    t.assert_error_msg_contains(
        'Unexpected argument options.unknown_option to errors.new_class',
        errors.new_class, 'Unknown-option error', {unknown_option = true}
    )

    t.assert_error_msg_contains(
        'Bad argument options.capture_stack to errors.new_class' ..
        ' (boolean expected, got number)',
        errors.new_class, 'Bad-option error', {capture_stack = 1}
    )
end

function g.test_errors_methods_raise()
    local my_error = errors.new_class('My error')

    t.assert_error_msg_contains(
        'Use error_class:new() instead of error_class.new()',
        my_error.new
    )

    t.assert_error_msg_contains(
        'Use error_class:new() instead of error_class.new()',
        my_error.new
    )

    t.assert_error_msg_contains(
        'Use error_class:pcall() instead of error_class.pcall()',
        my_error.pcall
    )

    t.assert_error_msg_contains(
        'Use error_class:assert() instead of error_class.assert()',
        my_error.assert
    )
end
