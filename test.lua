#!/usr/bin/env tarantool

local tempdir = require('fio').tempdir()
box.cfg({
    wal_dir = tempdir,
    memtx_dir = tempdir,
    listen = 3301,
})

local errors = require('errors')
local my_error = errors.new_class('My error')

local tap = require('tap')
local log = require('log')
local yaml = require('yaml')
local net = require('net.box')
local test = tap.test('errors')

local _l_assert = 2 + debug.getinfo(1).currentline
local function ret_assert(str)
    assert(false, str)
end

local _l_nilerr = 2 + debug.getinfo(1).currentline
local function ret_nilerr(...)
    return nil, my_error:new(...)
end

local function ret_error(str)
    local ok, err = ret_nilerr(str)
    if not ok then
        error(err)
    end
end

local function ret_success(...)
    return ...
end

local function _log(...)
    local tbl = {}
    for i = 1, select('#', ...) do
        tbl[i] = tostring(select(i, ...))
    end
    log.info(table.concat(tbl, ', '))
end

test:plan(43)

box.schema.user.grant(
    'guest',
    'read,write,execute',
    'universe', nil, {if_not_exists = true}
)

local ret, err = my_error:pcall(ret_assert, 'test_err_1')
_log(ret, err)
test:is(ret, nil, 'assert: status')
test:like(err.file, '.+/test.lua', 'assert: file')
test:is(err.line, _l_assert, 'assert: line')
test:like(err.err, 'test.lua:.+: test_err_1', 'assert: message')
test:is(err.str, tostring(err), 'assert: tostring')

local ret, err = my_error:pcall(ret_error, 'test_err_3')
_log(ret, err)
test:is(ret, nil, 'error: status')
test:like(err.file, '.+/test.lua', 'error: file')
test:is(err.line, _l_nilerr, 'error: line')
test:like(err.err, 'test_err_3', 'error: message')
test:is(err.str, tostring(err), 'error: tostring')

local ret, err = my_error:pcall(ret_nilerr, 'test_err_%d', 2)
_log(ret, err)
test:is(ret, nil, 'return nil, error(str): status')
test:like(err.file, '.+/test.lua', 'return nil, error(str): file')
test:is(err.line, _l_nilerr, 'return nil, error(str): line')
test:like(err.err, 'test_err_2', 'return nil, error(str): message')
test:is(err.str, tostring(err), 'return nil, error(str): tostring')
test:like(err.str, '^My error: test_err_2\n', 'return nil, error(str): tostring')

local ret, err = my_error:pcall(ret_nilerr)
_log(ret, err)
test:is(ret, nil, 'return nil, error(): status')
test:like(err.file, '.+/test.lua', 'return nil, error(): file')
test:is(err.line, _l_nilerr, 'return nil, error(): line')
test:is(err.err, nil, 'return nil, error(): message')
test:like(err.str, '^My error: nil\n', 'return nil, error(): tostring')

local tbl = {foo='bar'}
local ret, err = my_error:pcall(ret_nilerr, tbl)
_log(ret, err)
test:is(ret, nil, 'return nil, error(tbl): status')
test:like(err.file, '.+/test.lua', 'return nil, error(tbl): file')
test:is(err.line, _l_nilerr, 'return nil, error(tbl): line')
test:is(err.err, tbl, 'return nil, error(tbl): message')
test:like(err.str, '^My error: table: 0x(.-)\n', 'return nil, error(tbl): tostring')

local ret, err = my_error:pcall(ret_success, 'test_success_3')
_log(ret, err)
test:is(ret, 'test_success_3', 'return str: ret')
test:is(err, nil, 'return str: err')

local ret, err = pcall(function() my_error:assert(ret_nilerr('test_err_4')) end)
_log(ret, err)
test:ok(not ret, 'assert(nil, error): status')
test:like(err.file, '.+/test.lua', 'assert(nil, error): file')
test:is(err.line, _l_nilerr, 'assert(nil, error): line')
test:like(err.err, 'test_err_4', 'assert(nil, error): message')
test:is(err.str, tostring(err), 'assert(nil, error): tostring')

local _l_eclass_assert = 1 + debug.getinfo(1).currentline
local ret, err = pcall(function() my_error:assert(false) end)
_log(ret, err)
test:ok(not ret, 'assert(false): status')
test:like(err.file, '.+/test.lua', 'assert(false): file')
test:is(err.line, _l_eclass_assert, 'assert(false): line')
test:like(err.err, 'assertion failed!', 'assert(false): message')
test:is(err.str, tostring(err), 'assert(false): tostring')

local ret, err = my_error:assert(ret_success('test_success_5'))
test:is(ret, 'test_success_5', 'assert(str, nil): ret')
test:is(err, nil, 'assert(str, nil): err')
_log(ret, err)

errors.monkeypatch_netbox_call()

function netbox_return_error(param)
    return nil, my_error:new("test_netbox_error: %s", param)
end

local conn = net.connect('localhost:3301')

local ret, err = conn:call('netbox_return_error', {'foo'})
_log(ret, err)

test:like(err.err,
    'test_netbox_error: foo',
    'exception name is present in net.box error string'
)

test:like(err.str,
    'during remote call to localhost:3301, function "netbox_return_error"',
    'node uri is present in net.box error string'
)

test:like(err.stack,
    'in main chunk',
    'Stack trace from client node is visible in net.box error string'
)

os.execute('rm -r ' .. tempdir)
os.exit(test:check() and 0 or 1)
