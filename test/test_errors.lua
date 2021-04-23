#!/usr/bin/env tarantool

local fio = require('fio')
local tap = require('tap')
local json = require('json')
local fiber = require('fiber')
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
    test:like(tostring(got), expected.str, 'tostring()')
    test:is(tostring(got), got:tostring(), ':tostring')
end

test:plan(52)

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
local _, err2 = get_line(), my_error:new(err1)
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
        err = [["127.0.0.1:3301": eval:1: unexpected symbol near '=']],
        str = '^NetboxEvalError: .+\n' ..
            'stack traceback:\n' ..
            '.+\n' ..
                string.format('\t%s:%d: in main chunk$', current_file, _l)
    }
)

local _l, _, err = get_line(), errors.netbox_eval(conn, 'error("Olive Brass")')
test:test('netbox_eval("error(string)")', check_error, err,
    {
        file = 'builtin/box/net_box.lua',
        err = '"127.0.0.1:3301": eval:1: Olive Brass',
        str = '^NetboxEvalError: "127.0.0.1:3301": eval:1: Olive Brass\n' ..
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
        err = '"127.0.0.1:3301": {"metal":"mercury"}',
        str = '^NetboxEvalError: "127.0.0.1:3301": {%"metal%":%"mercury%"}\n' ..
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
        err = '"127.0.0.1:3301": Aqua Steel',
        str = '^My error: "127.0.0.1:3301": Aqua Steel\n' ..
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
        err = '"127.0.0.1:3301": White Zinc',
        str = '^My error: "127.0.0.1:3301": White Zinc\n' ..
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
        err = '"127.0.0.1:3301": Fuschia Platinum',
        str = '^My error: "127.0.0.1:3301": Fuschia Platinum\n' ..
            'stack traceback:\n' ..
                string.format('\t%s:%d: ', current_file, _l1) ..
            '.+\n' ..
            'during net.box eval on 127.0.0.1:3301\n' ..
            'stack traceback:\n'..
                string.format('\t%s:%d: ', current_file, _l2)
    }
)
local _l2, _, err = get_line(), errors.netbox_eval(netbox.connect(3301), 'return remote_fn()')
test:test('netbox_eval(nohost, "return remote_fn()")', check_error, err,
    {
        file = current_file,
        line = _l1,
        err = '":3301": Fuschia Platinum',
        str = '^My error: ":3301": Fuschia Platinum\n' ..
            'stack traceback:\n' ..
                string.format('\t%s:%d: ', current_file, _l1) ..
            '.+\n' ..
            'during net.box eval on :3301\n' ..
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
        err = '"127.0.0.1:3301": Connection closed',
        str = '^NetboxEvalError: "127.0.0.1:3301": Connection closed\n' ..
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
        err = '"127.0.0.1:9": Connection refused',
        str = '^NetboxEvalError: "127.0.0.1:9": Connection refused\n' ..
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
        err = [["127.0.0.1:3301": Procedure 'fn_undefined' is not defined]],
        str = '^NetboxCallError: "127.0.0.1:3301": Procedure \'fn_undefined\' is not defined\n' ..
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
        err = '"127.0.0.1:3301": Yellow Iron',
        str = '^My error: "127.0.0.1:3301": Yellow Iron\n' ..
            'stack traceback:\n' ..
                string.format('\t%s:%d: ', current_file, _l1) ..
            '.+\n' ..
            'during net.box call to 127.0.0.1:3301, function "remote_fn"\n' ..
            'stack traceback:\n'..
                string.format('\t%s:%d: ', current_file, _l2)
    }
)
local _l2, _, err = get_line(), errors.netbox_call(netbox.connect(3301), 'remote_fn')
test:test('netbox_call(nohost, return nil, e:new(string))', check_error, err,
    {
        file = current_file,
        line = _l1,
        err = '":3301": Yellow Iron',
        str = '^My error: ":3301": Yellow Iron\n' ..
            'stack traceback:\n' ..
                string.format('\t%s:%d: ', current_file, _l1) ..
            '.+\n' ..
            'during net.box call to :3301, function "remote_fn"\n' ..
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


--- errors.netbox_wait_async() -------------------------------------------
-------------------------------------------------------------------------------

local conn = netbox.connect('127.0.0.1:3301')
conn:wait_connected()

-- future raises (bad timeout)
local future = conn:call('math.abs', {-1}, {is_async = true})
local _l, _, err = get_line(), errors.netbox_wait_async(future, -1, '127.0.0.1:3301', 'math.abs')
test:test('future of netbox.call *invalid timeout)', function(t)
    t:plan(4)
    t:is(err.file, 'builtin/box/net_box.lua', 'file')
    t:like(err.err,
        '^"127.0.0.1:3301": builtin/box/net_box.lua:%d+:' ..
        ' Usage: future:wait_result%(timeout%)$', 'err'
    )
    t:like(tostring(err),
        '^NetboxCallError: "127.0.0.1:3301": builtin/box/net_box.lua:%d+:' ..
        ' Usage: future:wait_result%(timeout%)\nstack traceback' ..
        ('.+\n\t%s:%d: in main chunk$'):format(current_file, _l), 'tostring()'
    )
    t:is(tostring(err), err:tostring(), ':tostring()')
end)

local future = conn:eval('return math.abs(...)', {-1}, {is_async = true})
local _l, _, err = get_line(), errors.netbox_wait_async(future, -1, '127.0.0.1:3301')
test:test('future of netbox.eval (invalid timeout)', function(t)
    t:plan(4)
    t:is(err.file, 'builtin/box/net_box.lua', 'file')
    t:like(err.err,
        '^"127.0.0.1:3301": builtin/box/net_box.lua:%d+:' ..
        ' Usage: future:wait_result%(timeout%)$', 'err'
    )
    t:like(tostring(err),
        '^NetboxEvalError: "127.0.0.1:3301": builtin/box/net_box.lua:%d+:' ..
        ' Usage: future:wait_result%(timeout%)\nstack traceback' ..
        ('.+\n\t%s:%d: in main chunk$'):format(current_file, _l), 'tostring()'
    )
    t:is(tostring(err), err:tostring(), ':tostring()')
end)


-- future returns error
local long_call = function() fiber.sleep(10) return 5 end
_G.long_call = long_call

local future_call = conn:call('_G.long_call', nil, {is_async = true})
local _l, _, err = get_line(), errors.netbox_wait_async(future_call, 0, '127.0.0.1:3301', '_G.long_call')
test:test('netbox_wait_async (call request timed out)', check_error, err,
    {
        file = debug.getinfo(errors.netbox_wait_async).source:gsub('@', ''),
        err = '"127.0.0.1:3301": Timeout exceeded',
        str = '^NetboxCallError: "127.0.0.1:3301": Timeout exceeded\nstack traceback' ..
            ('.+\n\t%s:%d: in main chunk$'):format(current_file, _l)
    }
)

local future_eval = conn:eval('fiber.sleep(10) return 5', nil, {is_async = true})
local _l, _, err = get_line(), errors.netbox_wait_async(future_eval, 0, '127.0.0.1:3301')
test:test('netbox_wait_async (eval request timed out)', check_error, err,
    {
        file = debug.getinfo(errors.netbox_wait_async).source:gsub('@', ''),
        err = '"127.0.0.1:3301": Timeout exceeded',
        str = '^NetboxEvalError: "127.0.0.1:3301": Timeout exceeded\nstack traceback' ..
                ('.+\n\t%s:%d: in main chunk$'):format(current_file, _l)
    }
)

conn:close()
local _l, _, err = get_line(), errors.netbox_wait_async(future_call, 5, 'localhost:3301', '_G.long_call')
test:test('netbox_wait_async (call connection closed)', check_error, err,
    {
        file = debug.getinfo(errors.netbox_wait_async).source:gsub('@', ''),
        err = '"localhost:3301": Connection closed',
        str = '^NetboxCallError: "localhost:3301": Connection closed\nstack traceback' ..
            ('.+\n\t%s:%d: in main chunk$'):format(current_file, _l)
    }
)

local _l, _, err = get_line(), errors.netbox_wait_async(future_eval, 5, 'localhost:3301')
test:test('netbox_wait_async (eval connection closed)', check_error, err,
    {
        file = debug.getinfo(errors.netbox_wait_async).source:gsub('@', ''),
        err = '"localhost:3301": Connection closed',
        str = '^NetboxEvalError: "localhost:3301": Connection closed\nstack traceback' ..
            ('.+\n\t%s:%d: in main chunk$'):format(current_file, _l)
    }
)


local conn = netbox.connect('127.0.0.1:3301')
conn:wait_connected()

local future = conn:call('_G.fn_undefined', nil, {is_async = true})
local _l, _, err = get_line(), errors.netbox_wait_async(future, 10, '127.0.0.1:3301', '_G.fn_undefined')
test:test('netbox_wait_async (call not defined function)', check_error, err,
    {
        file = debug.getinfo(errors.netbox_wait_async).source:gsub('@', ''),
        err = [["127.0.0.1:3301": Procedure '_G.fn_undefined' is not defined]],
        str = [[^NetboxCallError: "127.0.0.1:3301": Procedure '_G.fn_undefined' is not defined]] ..
              ('\nstack traceback:\n.+\n\t%s:%d: in main chunk$'):format(current_file, _l)
    }
)


-- test netbox_wait_async (remote raises)
local fn_raises = function() error('New error', 2) end
_G.fn_raises = fn_raises
local future = conn:call('_G.fn_raises', nil, {is_async = true})
local _l, _, err = get_line(), errors.netbox_wait_async(future, 10, '127.0.0.1:3301', '_G.fn_raises')
test:test('netbox_wait_async (call remote fn raises)', check_error, err,
    {
        file = debug.getinfo(errors.netbox_wait_async).source:gsub('@', ''),
        err = '"127.0.0.1:3301": New error',
        str = '^NetboxCallError: "127.0.0.1:3301": New error\nstack traceback:\n' ..
              ('.+\n\t%s:%d: in main chunk$'):format(current_file, _l)
    }
)

local future = conn:eval('return _G.fn_raises()', nil, {is_async = true})
local _l, _, err = get_line(), errors.netbox_wait_async(future, 10, '127.0.0.1:3301')
test:test('netbox_wait_async (eval raises)', check_error, err,
    {
        file = debug.getinfo(errors.netbox_wait_async).source:gsub('@', ''),
        err = '"127.0.0.1:3301": New error',
        str = '^NetboxEvalError: "127.0.0.1:3301": New error' ..
              ('\nstack traceback:\n.+\n\t%s:%d: in main chunk$'):format(current_file, _l)
    }
)


-- test netbox_wait_async (remote returns nil, error descrption)
local remote_fn1 = function() return nil, 'String error' end
_G.remote_fn1 = remote_fn1
local future = conn:call('_G.remote_fn1', nil, {is_async = true})
local _l, _, err = get_line(), errors.netbox_wait_async(future, 10, '127.0.0.1:3301', '_G.remote_fn1')
test:test('netbox_wait_async (call remote fn return nil, error description)', check_error, err,
    {
        file = debug.getinfo(errors.netbox_wait_async).source:gsub('@', ''),
        err = '"127.0.0.1:3301": String error',
        str = '^NetboxCallError: "127.0.0.1:3301": String error\nstack traceback:\n' ..
              ('.+\n\t%s:%d: in main chunk$'):format(current_file, _l)
    }

)

local future = conn:eval('return _G.remote_fn1()', nil, {is_async = true})
local _l, _, err = get_line(), errors.netbox_wait_async(future, 10, '127.0.0.1:3301')
test:test('netbox_wait_async (eval returns nil, error description)', check_error, err,
    {
        file = debug.getinfo(errors.netbox_wait_async).source:gsub('@', ''),
        err = '"127.0.0.1:3301": String error',
        str = '^NetboxEvalError: "127.0.0.1:3301": String error' ..
              ('\nstack traceback:\n.+\n\t%s:%d: in main chunk$'):format(current_file, _l)
    }
)


-- test netbox_wait_async (remote returns nil, error object)
local _l, remote_fn2 = get_line(), function() return nil, my_error:new('Error obj') end
_G.remote_fn2 = remote_fn2
local future = conn:call('_G.remote_fn2', nil, {is_async = true})
local _l1, _, err = get_line(), errors.netbox_wait_async(future, 10, '127.0.0.1:3301', '_G.remote_fn2')
test:test('netbox_wait_async (call remote fn returns nil, error_obj)', check_error, err,
    {
        file = current_file,
        line = _l,
        err = '"127.0.0.1:3301": Error obj',
        str = 'My error: "127.0.0.1:3301": Error obj\nstack traceback:\n' ..
              '.+during async net.box call to 127.0.0.1:3301 "_G.remote_fn2"' ..
              ('.+\n\t%s:%d: in main chunk$'):format(current_file, _l1)
    }
)

local future = conn:eval('return _G.remote_fn2()', nil, {is_async = true})
local _l1, _, err = get_line(), errors.netbox_wait_async(future, 10, '127.0.0.1:3301', 'return _G.remote_fn2()')
test:test('netbox_wait_async (eval returns nil, error object)', check_error, err,
    {
        file = current_file,
        err = '"127.0.0.1:3301": Error obj',
        str = 'My error: "127.0.0.1:3301": Error obj\nstack traceback:\n' ..
              '.+during async net.box eval to 127.0.0.1:3301 "return _G.remote_fn2%(%)"' ..
              ('.+\n\t%s:%d: in main chunk$'):format(current_file, _l1)
    }
)


-- test netbox_wait_async (correct multireturn)
local return_vals = function(...) return {...} end
_G.return_vals = return_vals
local future = conn:call('_G.return_vals', fn_4args, {is_async = true})
local ret = errors.netbox_wait_async(future, 10, '127.0.0.1:3301', '_G.return_vals')
test:test('netbox_wait_async (call return {"1", nil, false, nil})', function(test)
    test:plan(4)
    test:is(ret[1], '1',         '[1] == "1"')
    test:is(ret[2], box.NULL,    '[2] == box.NULL')
    test:is(ret[3], false,       '[3] == false')
    test:is(type(ret[4]), 'nil', '[4] == nil')
end)

local future = conn:eval('return _G.return_vals(...)', fn_4args, {is_async = true})
local ret = errors.netbox_wait_async(future, 10, '127.0.0.1:3301')
test:test('netbox_wait_async (eval return {"1", nil, false, nil})', function(test)
    test:plan(4)
    test:is(ret[1], '1',         '[1] == "1"')
    test:is(ret[2], box.NULL,    '[2] == box.NULL')
    test:is(ret[3], false,       '[3] == false')
    test:is(type(ret[4]), 'nil', '[4] == nil')
end)

-- test netbox_wait_async empty return
local empty_return = function() return end
_G.empty_return = empty_return
local future = conn:call('_G.empty_return', nil, {is_async = true})
test:is_deeply(
    {errors.netbox_wait_async(future, 10, '127.0.0.1:3301', '_G.empty_return')},
    {nil, nil},
    'netbox_wait_async (call Empty return)'
)

local future = conn:eval('return nil', nil, {is_async = true})
test:is_deeply(
    {errors.netbox_wait_async(future, 10, '127.0.0.1:3301')},
    {nil, nil},
    'netbox_wait_async (eval Empty return)'
)

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

--- is_error_object() -------------------------------------------------------------
-------------------------------------------------------------------------------

test:test('errors.is_error_object(err)', function(subtest)
    subtest:plan(4)
    local err = errors.new('error')
    subtest:isnt(errors.is_error_object, nil)
    subtest:is(errors.is_error_object(err), true)
    subtest:is(errors.is_error_object({err = 'str'}), false)
    subtest:is(errors.is_error_object(5), false)
end)

os.exit(test:check() and 0 or 1)
