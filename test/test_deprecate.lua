#!/usr/bin/env tarantool
pcall(require, "luacov")

local log = require('log')
local tap = require('tap')
local errors = require('errors')

local test = tap.test('deprecate')

test:plan(8)

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

local function check_warning(test, got, expected_line)
    test:plan(3)

    if not test:ok(got ~= nil, 'warning issued') then
        test:diag('Got %s', got)
        test:skip('line')
        test:skip('file')
        return
    end

    test:diag('%s', tostring(got):gsub('\n', '\n    # '):gsub('\t', '        '))

    test:is(got.line, expected_line, 'line')
    test:is(got.file, current_file, 'file')
    -- test:is(_l[1], err.file, 'file')
end

-- deprecate.warn() tests -----------------------------------------------------
-------------------------------------------------------------------------------

test:diag('fn_one(); fn_two();')
local _l = get_line(); fn_one(); fn_two();
test:test('fn_one', check_warning, warnings[1], _l)
test:test('fn_two', check_warning, warnings[2], _l)
test:is(#warnings, 2, '2 warnings so far')

test:diag('fn_three()')
fn_three()
test:test('fn_three -> fn_one', check_warning, warnings[3], _l_fn_three+1)
test:test('fn_three -> fn_two', check_warning, warnings[4], _l_fn_three+2)
test:is(#warnings, 4, '4 warnings so far')

test:diag('fn_three()')
fn_three()
test:is(#warnings, 4, 'still 4 warnings')

-- default handler is log.warn ------------------------------------------------
-------------------------------------------------------------------------------

test:diag('set_deprecation_handler(nil)')
errors.set_deprecation_handler(nil)

local err
log.warn = function(_, arg)
    err = arg
end

local _l = get_line(); fn_one()
test:test('default handler', check_warning, err, _l)

os.exit(test:check() and 0 or 1)
