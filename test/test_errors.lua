#!/usr/bin/env tarantool

local fio = require('fio')
local tap = require('tap')
local json = require('json')
local errors = require('errors')
local netbox = require('net.box')
local tempdir = fio.tempdir()
box.cfg({
    wal_dir = tempdir,
    memtx_dir = tempdir,
    log = fio.pathjoin(tempdir, 'main.log'),
    listen = 3301,
})
box.schema.user.grant(
    'guest',
    'read,write,execute',
    'universe', nil, {if_not_exists = true}
)
local my_error = errors.new_class('My error')
_G.my_error = my_error

local test = tap.test('errors')
local current_file = debug.getinfo(1, 'S').short_src
local function get_line()
    return debug.getinfo(2, 'l').currentline
end

local fn_4args = {"1", nil, false, nil}
local remote_4args_fn = function(a1, a2, a3, a4)
    -- during netbox call fn_args are converted to
    -- "1", box.NULL, false, nil
    assert(a1 == fn_4args[1] and type(a1) == 'string')
    assert(a2 == fn_4args[2] and type(a2) == 'cdata')
    assert(a3 == fn_4args[3] and type(a3) == 'boolean')
    assert(a4 == fn_4args[4] and type(a4) == 'nil')
    return a1, a2, a3, a4
end
_G.remote_4args_fn = remote_4args_fn

local function check_error(test, got, expected)
    test:plan(6)

    if not test:ok(got, 'have error') then
        test:diag('Got %s', got)
        test:skip('file')
        test:skip('line')
        test:skip('err')
        test:skip('str')
        test:skip('tostring')
        return
    end

    test:diag('%s', tostring(got):gsub('\n', '\n    # '):gsub('\t', '        '))

    if not expected.file then
        test:skip('file')
    else
        test:is(got.file, expected.file, 'file ' .. tostring(got.file))
    end

    if not expected.line then
        test:skip('line')
    else
        test:is(got.line, expected.line, 'line ' .. tostring(got.line))
    end

    test:is(got.err, expected.err, 'err')
    test:like(got.str, expected.str, 'str')
    test:is(got.str, tostring(got.str), 'tostring')
end

test:plan(39)

--- e:new() -------------------------------------------------------------------
-------------------------------------------------------------------------------

local _l, err = get_line(), my_error:new()
test:test('return e:new()', check_error, err,
    {
        file = current_file,
        line = _l,
        err = '',
        str = '^My error: \n' ..
            'stack traceback:\n'
    }
)

local function lvl1()
    local e = my_error:new(3)
    return e
end
local function lvl2()
    local e = lvl1()
    return e
end
local _l, err = get_line(), lvl2()
test:test('return e:new(level)', check_error, err,
    {
        file = current_file,
        line = _l,
        err = '',
        str = '^My error: \n' ..
            'stack traceback:\n' ..
                string.format('\t%s:%d: ', current_file, _l)
    }
)

local _l, err = get_line(), my_error:new('Green %s %X', 'Bronze', 175)
test:test('return e:new(fmt, str)', check_error, err,
    {
        file = current_file,
        line = _l,
        err = 'Green Bronze AF',
        str = '^My error: Green Bronze AF\n' ..
            'stack traceback:\n'
    }
)

local _l, err = get_line(), my_error:new('Bad format %s')
test:test('return e:new(bad_format)', check_error, err,
    {
        file = current_file,
        line = _l,
        err = 'Bad format %s',
        str = '^My error: Bad format %%s\n' ..
            'stack traceback:\n'
    }
)

local tbl = setmetatable({color = 'black'}, {__tostring = json.encode})
local _l, err = get_line(), my_error:new(tbl)
test:test('return e:new(table)', check_error, err,
    {
        file = current_file,
        line = _l,
        err = tbl,
        str = '^My error: ' .. tostring(tbl) .. '\n' ..
            'stack traceback:\n'
    }
)

local _l1, err1 = get_line(), my_error:new('Inner error')
local _l2, err2 = get_line(), my_error:new(err1)
test:test('return e:new(e:new())', check_error, err2,
    {
        file = current_file,
        line = _l1,
        err = 'Inner error',
        str = '^My error: Inner error\n' ..
            'stack traceback:\n'
    }
)

--- e:pcall() -----------------------------------------------------------------
-------------------------------------------------------------------------------

local _, err = my_error:pcall(error, nil)
test:test('e:pcall(error, nil)', check_error, err,
    {
        file = '[C]',
        line = -1,
        err = 'nil',
        str = '^My error: nil\n' ..
            'stack traceback:\n'
    }
)

local _l, fn = get_line(), function() error(nil) end
local _, err = my_error:pcall(fn)
test:test('e:pcall(fn() error(nil) end)', check_error, err,
    {
        file = current_file,
        line = _l,
        err = 'nil',
        str = '^My error: nil\n' ..
            'stack traceback:\n'
    }
)

local _l, fn = get_line(), function() error('Olive Nickel') end
local _, etxt = pcall(fn)
local _, err = my_error:pcall(fn)
test:test('e:pcall(fn() error(string) end)', check_error, err,
    {
        file = current_file,
        line = _l,
        err = etxt,
        str = '^My error: '..etxt..'\n' ..
            'stack traceback:\n'
    }
)

local _l, err = get_line(), my_error:new('Red Steel')
local _, err = my_error:pcall(function() error(err) end)
test:test('e:pcall(fn() error(e:new(string)) end)', check_error, err,
    {
        file = current_file,
        line = _l,
        err = 'Red Steel',
        str = '^My error: Red Steel\n' ..
            'stack traceback:\n'
    }
)

local _l, err = get_line(), my_error:new('Lime Silver')
local _, err = my_error:pcall(function() return nil, err end)
test:test('e:pcall(fn() return nil, e:new(string) end)', check_error, err,
    {
        file = current_file,
        line = _l,
        err = 'Lime Silver',
        str = '^My error: Lime Silver\n' ..
            'stack traceback:\n'
    }
)

local tbl = {}
local ret = {my_error:pcall(function() return 1, false, tbl, nil, '5', true end)}
test:test('e:pcall(fn() return 1, false, {}, nil, "5", true end)', function(test)
    test:plan(6)
    test:is(ret[1], 1,     '[1] == 1')
    test:is(ret[2], false, '[2] == false')
    test:is(ret[3], tbl,   '[3] == {}')
    test:is(type(ret[4]), 'nil',
                           '[4] == nil')
    test:is(ret[5], '5',   '[5] == "5"')
    test:is(ret[6], true,  '[6] == true')
end)

--- e:assert() ----------------------------------------------------------------
-------------------------------------------------------------------------------

local _l, fn = get_line(), function() my_error:assert() end
local _, err = pcall(fn)
test:test('e:assert()', check_error, err,
    {
        file = current_file,
        line = _l,
        err = 'assertion failed!',
        str = '^My error: assertion failed!\n' ..
            'stack traceback:\n'
    }
)

local _l, fn = get_line(), function() my_error:assert(false) end
local _, err = pcall(fn)
test:test('e:assert(false)', check_error, err,
    {
        file = current_file,
        line = _l,
        err = 'assertion failed!',
        str = '^My error: assertion failed!\n' ..
            'stack traceback:\n'
    }
)

local _l, fn = get_line(), function() my_error:assert(false, 'White %s', 'Titanium') end
local _, err = pcall(fn)
test:test('e:assert(false, fmt, str)', check_error, err,
    {
        file = current_file,
        line = _l,
        err = 'White Titanium',
        str = '^My error: White Titanium\n' ..
            'stack traceback:\n'
    }
)

local _l, fn = get_line(), function() my_error:assert(false, 'Bad format %d', {}) end
local _, err = pcall(fn)
test:test('e:assert(false, bad_format)', check_error, err,
    {
        file = current_file,
        line = _l,
        err = 'Bad format %d',
        str = '^My error: Bad format %%d\n' ..
            'stack traceback:\n'
    }
)

local _l, err = get_line(), my_error:new('Purple Zinc')
local fn = function() my_error:assert((function() return nil, err end)()) end
local _, err = pcall(fn)
test:test('e:assert((fn() return nil, e:new("") end)())', check_error, err,
    {
        file = current_file,
        line = _l,
        err = 'Purple Zinc',
        str = '^My error: Purple Zinc\n' ..
            'stack traceback:\n'
    }
)

local tbl = {}
local ret = {my_error:assert(1, true, nil, '4', tbl, false)}
test:test('e:assert(1, true, nil, "4", {}, false', function(test)
    test:plan(6)
    test:is(ret[1], 1,     '[1] == 1')
    test:is(ret[2], true,  '[2] == true')
    test:is(type(ret[3]), 'nil',
                           '[3] == nil')
    test:is(ret[4], '4',   '[4] == "4"')
    test:is(ret[5], tbl,   '[5] == {}')
    test:is(ret[6], false, '[6] == false')
end)


--- errors.netbox_eval() ------------------------------------------------------
-------------------------------------------------------------------------------

local conn = netbox.connect('127.0.0.1:3301')
conn:wait_connected()

local _l, _, err = get_line(), errors.netbox_eval(conn, '=')
test:test('netbox_eval(invalid_syntax)', check_error, err,
    {
        file = 'builtin/box/net_box.lua',
        err = [[eval:1: unexpected symbol near '=']],
        str = '^Net.box eval failed: .+\n' ..
            'stack traceback:\n' ..
            '.+\n' ..
                string.format('\t%s:%d: in main chunk$', current_file, _l)
    }
)

local _l, _, err = get_line(), errors.netbox_eval(conn, 'error("Olive Brass")')
test:test('netbox_eval("error(string)")', check_error, err,
    {
        file = 'builtin/box/net_box.lua',
        err = 'eval:1: Olive Brass',
        str = '^Net.box eval failed: eval:1: Olive Brass\n' ..
            'stack traceback:\n' ..
            '.+\n' ..
                string.format('\t%s:%d: in main chunk$', current_file, _l)
    }
)

local _l, _, err = get_line(), errors.netbox_eval(conn, [[
    local json = require('json')
    local tbl = setmetatable({metal = 'mercury'}, {__tostring = json.encode})
    error(tbl)
]])
-- netbox.eval renders exceptions with `tostring` methed
test:test('netbox_eval("error(table)")', check_error, err,
    {
        file = 'builtin/box/net_box.lua',
        err = '{"metal":"mercury"}',
        str = '^Net.box eval failed: {%"metal%":%"mercury%"}\n' ..
            'stack traceback:\n' ..
            '.+\n' ..
                string.format('\t%s:%d: in main chunk$', current_file, _l)
    }
)

local _l, err = get_line(), errors.netbox_eval(conn, 'local err = my_error:new("Aqua Steel") return err')
test:test('netbox_eval("return e:new()")', check_error, err,
    {
        file = 'eval',
        line = 1,
        err = 'Aqua Steel',
        str = '^My error: Aqua Steel\n' ..
            'stack traceback:\n' ..
                '\teval:1: in main chunk\n' ..
            '.+\n' ..
            'during net.box eval on 127.0.0.1:3301\n' ..
            'stack traceback:\n'..
                string.format('\t%s:%d: ', current_file, _l)
    }
)

local _l, _, err = get_line(), errors.netbox_eval(conn, 'return nil, my_error:new("White Zinc")')
test:test('netbox_eval("return nil, e:new()")', check_error, err,
    {
        file = 'eval',
        line = 1,
        err = 'White Zinc',
        str = '^My error: White Zinc\n' ..
            'stack traceback:\n' ..
                '\teval:1: in main chunk\n' ..
            '.+\n' ..
            'during net.box eval on 127.0.0.1:3301\n' ..
            'stack traceback:\n'..
                -- string.format('\t%s:%d: in main chunk$', current_file, _l)
                string.format('\t%s:%d: ', current_file, _l)
    }
)

local _l1, remote_fn = get_line(), function() return nil, my_error:new('Fuschia Platinum') end
_G.remote_fn = remote_fn
local _l2, _, err = get_line(), errors.netbox_eval(conn, 'return remote_fn()')
test:test('netbox_eval("return remote_fn()")', check_error, err,
    {
        file = current_file,
        line = _l1,
        err = 'Fuschia Platinum',
        str = '^My error: Fuschia Platinum\n' ..
            'stack traceback:\n' ..
                string.format('\t%s:%d: ', current_file, _l1) ..
            '.+\n' ..
            'during net.box eval on 127.0.0.1:3301\n' ..
            'stack traceback:\n'..
                string.format('\t%s:%d: ', current_file, _l2)
    }
)

local ret = {errors.netbox_eval(conn, 'return ...', {true, "2", 3})}
test:test('netbox_eval(return true, "2", 3)', function(test)
    test:plan(3)
    test:is(ret[1], true,  '[1] == true')
    test:is(ret[2], '2',   '[2] == "2"')
    test:is(ret[3], 3,     '[3] == 3')
end)

conn:close()
local _l, _, err = get_line(), errors.netbox_eval(conn, 'return true')
test:test('netbox_eval(closed_connection)', check_error, err,
    {
        file = 'builtin/box/net_box.lua',
        err = 'Connection closed',
        str = '^Net.box eval failed: Connection closed\n' ..
            'stack traceback:\n' ..
            '.+\n' ..
                string.format('\t%s:%d: in main chunk$', current_file, _l)
    }
)

local conn = netbox.connect('127.0.0.1:9')
local _l, _, err = get_line(), errors.netbox_eval(conn, 'return true')
test:test('netbox_eval(connection_refused)', check_error, err,
    {
        file = 'builtin/box/net_box.lua',
        err = 'Connection refused',
        str = '^Net.box eval failed: Connection refused\n' ..
            'stack traceback:\n' ..
            '.+\n' ..
                string.format('\t%s:%d: in main chunk$', current_file, _l)
    }
)

--- errors.netbox_call() ------------------------------------------------------
-------------------------------------------------------------------------------

local conn = netbox.connect('127.0.0.1:3301')
conn:wait_connected()

local _l, _, err = get_line(), errors.netbox_call(conn, 'fn_undefined')
test:test('netbox_call(fn_undefined)', check_error, err,
    {
        file = 'builtin/box/net_box.lua',
        err = [[Procedure 'fn_undefined' is not defined]],
        str = '^Net.box call failed: .+\n' ..
            'stack traceback:\n' ..
            '.+\n' ..
                string.format('\t%s:%d: in main chunk$', current_file, _l)
    }
)

local _l1, remote_fn = get_line(), function() return nil, my_error:new('Yellow Iron') end
_G.remote_fn = remote_fn
local _l2, _, err = get_line(), errors.netbox_call(conn, 'remote_fn')
test:test('netbox_call(return nil, e:new(string))', check_error, err,
    {
        file = current_file,
        line = _l1,
        err = 'Yellow Iron',
        str = '^My error: Yellow Iron\n' ..
            'stack traceback:\n' ..
                string.format('\t%s:%d: ', current_file, _l1) ..
            '.+\n' ..
            'during net.box call to 127.0.0.1:3301, function "remote_fn"\n' ..
            'stack traceback:\n'..
                string.format('\t%s:%d: ', current_file, _l2)
    }
)

local ret = {errors.netbox_call(conn, 'remote_4args_fn', fn_4args)}
test:test('netbox_call(return "1", nil, false, nil)', function(test)
    test:plan(4)
    test:is(ret[1], '1',   '[1] == "1"')
    test:is(type(ret[2]), 'nil',
                           '[2] == nil')
    test:is(ret[3], false, '[3] == false')
    test:is(type(ret[4]), 'nil',
                           '[4] == nil')
end)

--- errors.wrap() -------------------------------------------------------------
-------------------------------------------------------------------------------

local tbl = {}
local _l, err = get_line(), errors.wrap(my_error:new())
test:test('wrap e:new()', check_error, err,
    {
        file = current_file,
        line = _l,
        err = '',
        str = '^My error: \n' ..
            'stack traceback:\n'
    }
)
local ret = {errors.wrap(1, true, nil, '4', err, box.NULL, tbl, false)}
test:test('wrap fn() return 1, true, nil, "4", e:new(), box.NULL, {}, false end', function(test)
    test:plan(8)
    test:is(ret[1], 1,     '[1] == 1')
    test:is(ret[2], true,  '[2] == true')
    test:is(type(ret[3]), 'nil',
                           '[3] == nil')
    test:is(ret[4], '4',   '[4] == "4"')
    test:is(ret[5], err,   '[5] == e:new()')
    test:is(type(ret[6]), 'nil',
                           '[6] == e:new()')
    test:is(ret[7], tbl,   '[7] == {}')
    test:is(ret[8], false, '[8] == false')
end)

local _l, _, err = get_line(), errors.wrap(conn:eval('return nil, my_error:new("Aqua Aluminium")'))
test:test('wrap conn:eval("return nil, e:new()")', check_error, err,
    {
        file = 'eval',
        line = 1,
        err = 'Aqua Aluminium',
        str = '^My error: Aqua Aluminium\n' ..
            'stack traceback:\n' ..
                '\teval:1: in main chunk\n' ..
            '.+\n' ..
            'during wrapped call\n' ..
            'stack traceback:\n'..
                -- string.format('\t%s:%d: in main chunk$', current_file, _l)
                string.format('\t%s:%d: ', current_file, _l)
    }
)

local _l1, remote_fn = get_line(), function() return nil, my_error:new('Fuschia Platinum') end
_G.remote_fn = remote_fn
local _l2, _, err = get_line(), errors.wrap(conn:eval('return remote_fn()'))
test:test('wrap conn:eval("return remote_fn()")', check_error, err,
    {
        file = current_file,
        line = _l1,
        err = 'Fuschia Platinum',
        str = '^My error: Fuschia Platinum\n' ..
            'stack traceback:\n' ..
                string.format('\t%s:%d: ', current_file, _l1) ..
            '.+\n' ..
            'during wrapped call\n' ..
            'stack traceback:\n'..
                string.format('\t%s:%d: ', current_file, _l2)
    }
)

local _l1, remote_fn = get_line(), function() return nil, my_error:new('Yellow Iron') end
_G.remote_fn = remote_fn
local _l2, _, err = get_line(), errors.wrap(conn:call('remote_fn'))
test:test('warp conn:call(return nil, e:new(string))', check_error, err,
    {
        file = current_file,
        line = _l1,
        err = 'Yellow Iron',
        str = '^My error: Yellow Iron\n' ..
            'stack traceback:\n' ..
                string.format('\t%s:%d: ', current_file, _l1) ..
            '.+\n' ..
            'during wrapped call\n' ..
            'stack traceback:\n'..
                string.format('\t%s:%d: ', current_file, _l2)
    }
)

local ret = {errors.wrap(conn:call('remote_4args_fn', fn_4args))}
test:test('wrap conn:call(return "1", nil, false, nil)', function(test)
    test:plan(4)
    test:is(ret[1], '1',   '[1] == "1"')
    test:is(type(ret[2]), 'nil',
                           '[2] == nil')
    test:is(ret[3], false, '[3] == false')
    test:is(type(ret[4]), 'nil',
                           '[4] == nil')
end)

--- shortcuts -----------------------------------------------------------------
-------------------------------------------------------------------------------

local _l, err = get_line(), errors.new('ErrorNew', 'Grey Zinc')
test:test('return errors.new(class_name, message)', check_error, err,
    {
        file = current_file,
        line = _l,
        err = 'Grey Zinc',
        str = '^ErrorNew: Grey Zinc\n' ..
            'stack traceback:\n' ..
                string.format('\t%s:%d: ', current_file, _l)
    }
)

local _l, fn = get_line(), function() error('Teal Brass') end
local _, etxt = pcall(fn)
local _, err = errors.pcall('ErrorPCall', fn)
test:test('errors.pcall(error, message)', check_error, err,
    {
        file = current_file,
        line = _l,
        err = etxt,
        str = '^ErrorPCall: ' .. etxt .. '\n' ..
            'stack traceback:\n' ..
                string.format('\t%s:%d: ', current_file, _l)
    }
)

local _l, fn = get_line(), function() errors.assert('ErrorAssert', false, 'Maroon Silver') end
local _, err = pcall(fn)
test:test('errors.assert(class_name, false, message)', check_error, err,
    {
        file = current_file,
        line = _l,
        err = 'Maroon Silver',
        str = '^ErrorAssert: Maroon Silver\n' ..
            'stack traceback:\n' ..
                string.format('\t%s:%d: ', current_file, _l)
    }
)

os.exit(test:check() and 0 or 1)
