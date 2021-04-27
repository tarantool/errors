local log = require('log')
local errors = require('errors')

local t = require('luatest')
local g = t.group()

local current_file = debug.getinfo(1, 'S').short_src
local function get_line()
    return debug.getinfo(2, 'l').currentline
end

local warnings = {}
errors.set_deprecation_handler(function(err)
    table.insert(warnings, err)
end)

local function fn_one()
    errors.deprecate('Function "fn_one" is tested')
end

local function fn_two()
    errors.deprecate('Function "fn_two" is tested')
end

local _l_fn_three = get_line() + 1
local function fn_three()
    fn_one()
    fn_two()
end

function g.test_deprecate_warn()
    local _l = get_line(); fn_one(); fn_two();
    t.assert_equals(#warnings, 2, '2 warnings so far')
    t.assert_covers(warnings[1], {
        line = _l,
        file = current_file
    })
    t.assert_covers(warnings[2], {
        line = _l,
        file = current_file
    })

    fn_three()
    t.assert_equals(#warnings, 4, '4 warnings so far')
    t.assert_covers(warnings[3], {
        line = _l_fn_three + 1,
        file = current_file
    })
    t.assert_covers(warnings[4], {
        line = _l_fn_three + 2,
        file = current_file
    })

    fn_three()
    t.assert_equals(#warnings, 4, 'still 4 warnings')
end

function g.test_default_deprecation_handler()
    errors.set_deprecation_handler(nil)

    local err
    log.warn = function(_, arg)
        err = arg
    end

    local _l = get_line(); fn_one()
    t.assert_covers(err, {
        line = _l,
        file = current_file
    })
end
