local fio = require('fio')
local json = require('json')
local errors = require('errors')
local netbox = require('net.box')

local t = require('luatest')
local g = t.group()

local my_error = errors.new_class('My error')

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


g.before_all = function()
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

    _G.my_error = my_error
    _G.remote_4args_fn = remote_4args_fn
end

g.before_each(function()
    g.conn = netbox.connect('127.0.0.1:3301')
end)

local function check_error(got, expected, subtest_name)
    local err_msg = ''
    local pattern = '%q\ngot: %s\nexpected: %s\n'

    if expected.file and expected.file ~= got.file then
        err_msg = err_msg .. pattern:format('file', got.file, expected.file)
    end

    if expected.line and expected.line ~= got.line then
        err_msg = err_msg .. pattern:format('line', got.line, expected.line)
    end

    if got.err ~= expected.err then
        err_msg =  err_msg .. pattern:format('err', got.err, expected.err)
    end

    local err_str = tostring(got)
    if err_str:match(expected.str) == nil then
        err_msg =  err_msg .. pattern:format('tostring()', err_str, expected.str)
    end

    if tostring(got) ~= got:tostring() then
        err_msg =  err_msg .. pattern:format('tostring()', tostring(got), got:tostring())
    end

    if #err_msg ~= 0 then
        if subtest_name then
            err_msg = ('subtest %q: %s'):format(subtest_name, err_msg)
        end
        error(err_msg, 2)
    end
end

--- e:new() -------------------------------------------------------------------
-------------------------------------------------------------------------------

function g.test_error_new()
    local _l, err = get_line(), my_error:new()
    check_error(err, {
        file = current_file,
        line = _l,
        err = '',
        str = '^My error: \n' ..
            'stack traceback:\n'
    }, 'return e:new()')

    local function lvl1()
        local e = my_error:new(3)
        return e
    end

    local function lvl2()
        local e = lvl1()
        return e
    end

    local _l, err = get_line(), lvl2()
    check_error(err, {
        file = current_file,
        line = _l,
        err = '',
        str = '^My error: \n' ..
            'stack traceback:\n' ..
                string.format('\t%s:%d: ', current_file, _l)
    }, 'return e:new(level)')

    local _l, err = get_line(), my_error:new('Green %s %X', 'Bronze', 175)
    check_error(err, {
        file = current_file,
        line = _l,
        err = 'Green Bronze AF',
        str = '^My error: Green Bronze AF\n' ..
            'stack traceback:\n'
    }, 'return e:new(fmt, str)')

    local _l, err = get_line(), my_error:new('Bad format %s')
    check_error(err, {
        file = current_file,
        line = _l,
        err = 'Bad format %s',
        str = '^My error: Bad format %%s\n' ..
            'stack traceback:\n'
    }, 'return e:new(bad_format)')

    local tbl = setmetatable({color = 'black'}, {__tostring = json.encode})
    local _l, err = get_line(), my_error:new(tbl)
    check_error(err, {
        file = current_file,
        line = _l,
        err = tbl,
        str = '^My error: ' .. tostring(tbl) .. '\n' ..
            'stack traceback:\n'
    }, 'return e:new(table)')

    local _l1, err1 = get_line(), my_error:new('Inner error')
    local _, err2 = get_line(), my_error:new(err1)
    check_error(err2, {
        file = current_file,
        line = _l1,
        err = 'Inner error',
        str = '^My error: Inner error\n' ..
            'stack traceback:\n'
    }, 'return e:new(e:new())')
end

--- e:pcall() -----------------------------------------------------------------
-------------------------------------------------------------------------------
function g.test_error_pcall()
    local _, err = my_error:pcall(error, nil)
    check_error(err, {
        file = '[C]',
        line = -1,
        err = 'nil',
        str = '^My error: nil\n' ..
            'stack traceback:\n'
    }, 'e:pcall(error, nil)')

    local _l, fn = get_line(), function() error(nil) end
    local _, err = my_error:pcall(fn)
    check_error(err, {
        file = current_file,
        line = _l,
        err = 'nil',
        str = '^My error: nil\n' ..
            'stack traceback:\n'
    }, 'e:pcall(fn() error(nil) end')

    local _l, fn = get_line(), function() error('Olive Nickel') end
    local _, etxt = pcall(fn)
    local _, err = my_error:pcall(fn)
    check_error(err, {
        file = current_file,
        line = _l,
        err = etxt,
        str = '^My error: '..etxt..'\n' ..
            'stack traceback:\n'
    }, 'e:pcall(fn() error(string) end)')

    local _l, err = get_line(), my_error:new('Red Steel')
    local _, err = my_error:pcall(function() error(err) end)
    check_error(err, {
        file = current_file,
        line = _l,
        err = 'Red Steel',
        str = '^My error: Red Steel\n' ..
            'stack traceback:\n'
    }, 'e:pcall(fn() error(e:new(string)) end)')

    local _l, err = get_line(), my_error:new('Lime Silver')
    local _, err = my_error:pcall(function() return nil, err end)
    check_error(err, {
        file = current_file,
        line = _l,
        err = 'Lime Silver',
        str = '^My error: Lime Silver\n' ..
            'stack traceback:\n'
    }, 'e:pcall(fn() return nil, e:new(string) end)')

    local tbl = {}
    local ret = {my_error:pcall(function() return 1, false, tbl, nil, '5', true end)}
    t.assert_equals(ret, {1, false, tbl, nil, '5', true},
        'e:pcall(fn() return 1, false, {}, nil, "5", true end)'
    )
    t.assert_equals(type(ret[4]), 'nil', '[4] == nil')
end
--- e:assert() ----------------------------------------------------------------
-------------------------------------------------------------------------------

function g.test_error_assert()
    local _l, fn = get_line(), function() my_error:assert() end
    local _, err = pcall(fn)
    check_error(err, {
        file = current_file,
        line = _l,
        err = 'assertion failed!',
        str = '^My error: assertion failed!\n' ..
            'stack traceback:\n'
    }, 'e:assert()')

    local _l, fn = get_line(), function() my_error:assert(false) end
    local _, err = pcall(fn)
    check_error(err, {
        file = current_file,
        line = _l,
        err = 'assertion failed!',
        str = '^My error: assertion failed!\n' ..
            'stack traceback:\n'
    }, 'e:assert(false)')

    local _l, fn = get_line(), function() my_error:assert(false, 'White %s', 'Titanium') end
    local _, err = pcall(fn)
    check_error(err, {
        file = current_file,
        line = _l,
        err = 'White Titanium',
        str = '^My error: White Titanium\n' ..
            'stack traceback:\n'
    }, 'e:assert(false, fmt, str)')

    local _l, fn = get_line(), function() my_error:assert(false, 'Bad format %d', {}) end
    local _, err = pcall(fn)
    check_error(err, {
        file = current_file,
        line = _l,
        err = 'Bad format %d',
        str = '^My error: Bad format %%d\n' ..
            'stack traceback:\n'
    }, 'e:assert(false, bad_format)')

    local _l, err = get_line(), my_error:new('Purple Zinc')
    local fn = function() my_error:assert((function() return nil, err end)()) end
    local _, err = pcall(fn)
    check_error(err, {
        file = current_file,
        line = _l,
        err = 'Purple Zinc',
        str = '^My error: Purple Zinc\n' ..
            'stack traceback:\n'
    }, 'e:assert((fn() return nil, e:new("") end)())')

    local tbl = {}
    local ret = {my_error:assert(1, true, nil, '4', tbl, false)}
    t.assert_equals(ret, {1, true, nil, '4', tbl, false},
        'e:assert(1, true, nil, "4", {}, false'
    )
    t.assert_equals(type(ret[3]), 'nil', '[3] == nil')
end

-- --- errors.netbox_eval() ------------------------------------------------------
-- -------------------------------------------------------------------------------

function g.test_errors_netbox_eval()
    local _l, _, err = get_line(), errors.netbox_eval(g.conn, '=')
    check_error(err, {
        file = 'builtin/box/net_box.lua',
        err = [["127.0.0.1:3301": eval:1: unexpected symbol near '=']],
        str = '^NetboxEvalError: .+\n' ..
            'stack traceback:\n' ..
            '.+\n' ..
                string.format('\t%s:%d: in main chunk$', current_file, _l)
    }, 'netbox_eval(invalid_syntax)')

    local _l, _, err = get_line(), errors.netbox_eval(g.conn, 'error("Olive Brass")')
    check_error(err, {
        file = 'builtin/box/net_box.lua',
        err = '"127.0.0.1:3301": eval:1: Olive Brass',
        str = '^NetboxEvalError: "127.0.0.1:3301": eval:1: Olive Brass\n' ..
            'stack traceback:\n' ..
            '.+\n' ..
                string.format('\t%s:%d: in main chunk$', current_file, _l)
    }, 'netbox_eval("error(string)")')

    local _l, _, err = get_line(), errors.netbox_eval(g.conn, [[
        local json = require('json')
        local tbl = setmetatable({metal = 'mercury'}, {__tostring = json.encode})
        error(tbl)
    ]])
    -- netbox.eval renders exceptions with `tostring` methed
    check_error(err, {
        file = 'builtin/box/net_box.lua',
        err = '"127.0.0.1:3301": {"metal":"mercury"}',
        str = '^NetboxEvalError: "127.0.0.1:3301": {%"metal%":%"mercury%"}\n' ..
            'stack traceback:\n' ..
            '.+\n' ..
                string.format('\t%s:%d: in main chunk$', current_file, _l)
    }, 'netbox_eval("error(table)")')

    local _l, err = get_line(), errors.netbox_eval(g.conn, 'local err = my_error:new("Aqua Steel") return err')
    check_error(err, {
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
    }, 'netbox_eval("return e:new()")')

    local _l, _, err = get_line(), errors.netbox_eval(g.conn, 'return nil, my_error:new("White Zinc")')
    check_error(err, {
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
    }, 'netbox_eval("return nil, e:new()")')


    local _l1, remote_fn = get_line(), function() return nil, my_error:new('Fuschia Platinum') end
    _G.remote_fn = remote_fn

    local _l2, _, err = get_line(), errors.netbox_eval(g.conn, 'return remote_fn()')
    check_error(err, {
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
    }, 'netbox_eval("return remote_fn()")')

    local _l2, _, err = get_line(), errors.netbox_eval(netbox.connect(3301), 'return remote_fn()')
    check_error(err, {
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
    }, 'netbox_eval(nohost, "return remote_fn()")')

    local ret = {errors.netbox_eval(g.conn, 'return ...', {true, "2", 3})}
    t.assert_equals(ret, {true, '2', 3},
        'netbox_eval(return true, "2", 3)'
    )

    g.conn:close()
    local _l, _, err = get_line(), errors.netbox_eval(g.conn, 'return true')
    check_error(err,  {
        file = 'builtin/box/net_box.lua',
        err = '"127.0.0.1:3301": Connection closed',
        str = '^NetboxEvalError: "127.0.0.1:3301": Connection closed\n' ..
            'stack traceback:\n' ..
            '.+\n' ..
                string.format('\t%s:%d: in main chunk$', current_file, _l)
    }, 'netbox_eval(closed_connection)')

    local conn = netbox.connect('127.0.0.1:9')
    local _l, _, err = get_line(), errors.netbox_eval(conn, 'return true')
    check_error(err, {
        file = 'builtin/box/net_box.lua',
        err = '"127.0.0.1:9": Connection refused',
        str = '^NetboxEvalError: "127.0.0.1:9": Connection refused\n' ..
            'stack traceback:\n' ..
            '.+\n' ..
                string.format('\t%s:%d: in main chunk$', current_file, _l)
    }, 'netbox_eval(connection_refused)')
end

-- --- errors.netbox_call() ------------------------------------------------------
-- -------------------------------------------------------------------------------

function g.test_errors_netbox_call()
    local _l, _, err = get_line(), errors.netbox_call(g.conn, 'fn_undefined')
    check_error(err, {
        file = 'builtin/box/net_box.lua',
        err = [["127.0.0.1:3301": Procedure 'fn_undefined' is not defined]],
        str = '^NetboxCallError: "127.0.0.1:3301": Procedure \'fn_undefined\' is not defined\n' ..
            'stack traceback:\n' ..
            '.+\n' ..
                string.format('\t%s:%d: in main chunk$', current_file, _l)
    }, 'netbox_call(fn_undefined)')

    local _l1, remote_fn = get_line(), function() return nil, my_error:new('Yellow Iron') end
    _G.remote_fn = remote_fn

    local _l2, _, err = get_line(), errors.netbox_call(g.conn, 'remote_fn')
    check_error(err, {
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
    }, 'netbox_call(return nil, e:new(string))')

    local _l2, _, err = get_line(), errors.netbox_call(netbox.connect(3301), 'remote_fn')
    check_error(err, {
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
    }, 'netbox_call(nohost, return nil, e:new(string))')

    local ret = {errors.netbox_call(g.conn, 'remote_4args_fn', fn_4args)}
    t.assert_equals(ret, {'1', nil, false, nil},
        'netbox_call(return "1", nil, false, nil)'
    )
    t.assert_equals(type(ret[2]), 'nil', '[2] == nil')
    t.assert_equals(type(ret[4]), 'nil', '[4] == nil')
end

-- --- errors.wrap() -------------------------------------------------------------
-- -------------------------------------------------------------------------------

function g.test_errros_wrap()
    local tbl = {}
    local _l, err = get_line(), errors.wrap(my_error:new())
    check_error(err, {
        file = current_file,
        line = _l,
        err = '',
        str = '^My error: \n' ..
            'stack traceback:\n'
    }, 'wrap e:new()')

    local ret = {errors.wrap(1, true, nil, '4', err, box.NULL, tbl, false)}
    t.assert_equals(ret, {1, true, nil, '4', err, nil, tbl, false},
        'wrap fn() return 1, true, nil, "4", e:new(), box.NULL, {}, false end'
    )
    t.assert_equals(type(ret[3]), 'nil', '[3] == nil')
    t.assert_equals(type(ret[6]), 'nil', '[6] == nil')

    local _l, _, err = get_line(), errors.wrap(g.conn:eval('return nil, my_error:new("Aqua Aluminium")'))
    check_error(err, {
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
    }, 'wrap conn:eval("return nil, e:new()")')

    local _l1, remote_fn = get_line(), function() return nil, my_error:new('Fuschia Platinum') end
    _G.remote_fn = remote_fn

    local _l2, _, err = get_line(), errors.wrap(g.conn:eval('return remote_fn()'))
    check_error(err, {
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
    }, 'wrap conn:eval("return remote_fn()")')

    local _l1, remote_fn = get_line(), function() return nil, my_error:new('Yellow Iron') end
    _G.remote_fn = remote_fn

    local _l2, _, err = get_line(), errors.wrap(g.conn:call('remote_fn'))
    check_error(err, {
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
    }, 'warp conn:call(return nil, e:new(string))')

    local ret = {errors.wrap(g.conn:call('remote_4args_fn', fn_4args))}
    t.assert_equals(ret, {'1', nil, false, nil})
    t.assert_equals(type(ret[2]), 'nil', '[2] == nil')
    t.assert_equals(type(ret[4]), 'nil', '[4] == nil')
end
-- --- shortcuts -----------------------------------------------------------------
-- -------------------------------------------------------------------------------

function g.test_shortcuts()
    local _l, err = get_line(), errors.new('ErrorNew', 'Grey Zinc')
    check_error(err, {
        file = current_file,
        line = _l,
        err = 'Grey Zinc',
        str = '^ErrorNew: Grey Zinc\n' ..
            'stack traceback:\n' ..
                string.format('\t%s:%d: ', current_file, _l)
    }, 'return errors.new(class_name, message)')

    local _l, fn = get_line(), function() error('Teal Brass') end
    local _, etxt = pcall(fn)
    local _, err = errors.pcall('ErrorPCall', fn)
    check_error(err, {
        file = current_file,
        line = _l,
        err = etxt,
        str = '^ErrorPCall: ' .. etxt .. '\n' ..
            'stack traceback:\n' ..
                string.format('\t%s:%d: ', current_file, _l)
    }, 'errors.pcall(error, message)')

    local _l, fn = get_line(), function() errors.assert('ErrorAssert', false, 'Maroon Silver') end
    local _, err = pcall(fn)
    check_error(err,{
        file = current_file,
        line = _l,
        err = 'Maroon Silver',
        str = '^ErrorAssert: Maroon Silver\n' ..
            'stack traceback:\n' ..
                string.format('\t%s:%d: ', current_file, _l)
    }, 'errors.assert(class_name, false, message)')
end
-- --- is_error_object() -------------------------------------------------------------
-- -------------------------------------------------------------------------------

function g.test_is_error_object()
    local err = errors.new('error')
    t.assert(errors.is_error_object)
    t.assert_equals(errors.is_error_object(err), true)
    t.assert_equals(errors.is_error_object({err = 'str'}), false)
    t.assert_equals(errors.is_error_object(5), false)
end
