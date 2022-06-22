local fio = require('fio')
local fiber = require('fiber')
local errors = require('errors')
local netbox = require('net.box')

local t = require('luatest')
local h = require('test.helper')
local g = t.group()

local my_error = errors.new_class('My error')
local current_file = debug.getinfo(1, 'S').short_src

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

    rawset(_G, 'my_error', my_error)
    rawset(_G, 'remote_4args_fn', remote_4args_fn)
end

g.before_each(function()
    g.conn = netbox.connect('127.0.0.1:3301')
end)

function g.test_errors_netbox_eval()
    local _l, _, err = h.get_line(), errors.netbox_eval(g.conn, '=')
    h.check_error(err, {
        file = 'builtin/box/net_box.lua',
        err = [["127.0.0.1:3301": eval:1: unexpected symbol near '=']],
        str = '^NetboxEvalError: .+\n' ..
            'stack traceback:\n' ..
            '.+\n' ..
            ('\t%s:%d: .*$'):format(current_file, _l)
    }, 'netbox_eval(invalid_syntax)')

    local _l, _, err = h.get_line(), errors.netbox_eval(g.conn, 'error("Olive Brass")')
    h.check_error(err, {
        file = 'builtin/box/net_box.lua',
        err = '"127.0.0.1:3301": eval:1: Olive Brass',
        str = '^NetboxEvalError: "127.0.0.1:3301": eval:1: Olive Brass\n' ..
            'stack traceback:\n' ..
            '.+\n' ..
            ('\t%s:%d: .*$'):format(current_file, _l)
    }, 'netbox_eval("error(string)")')

    local _l, _, err = h.get_line(), errors.netbox_eval(g.conn, [[
        local json = require('json')
        local tbl = setmetatable({metal = 'mercury'}, {__tostring = json.encode})
        error(tbl)
    ]])
    -- netbox.eval renders exceptions with `tostring` methed
    h.check_error(err, {
        file = 'builtin/box/net_box.lua',
        err = '"127.0.0.1:3301": {"metal":"mercury"}',
        str = '^NetboxEvalError: "127.0.0.1:3301": {%"metal%":%"mercury%"}\n' ..
            'stack traceback:\n' ..
            '.+\n' ..
            ('\t%s:%d: .*$'):format(current_file, _l)
    }, 'netbox_eval("error(table)")')

    local _l, err = h.get_line(), errors.netbox_eval(g.conn, 'local err = my_error:new("Aqua Steel") return err')
    h.check_error(err, {
        file = 'eval',
        line = 1,
        err = '"127.0.0.1:3301": Aqua Steel',
        str = '^My error: "127.0.0.1:3301": Aqua Steel\n' ..
            'stack traceback:\n' ..
                '\teval:1: in main chunk\n' ..
            '.+\n' ..
            'during net.box eval on 127.0.0.1:3301\n' ..
            'stack traceback:\n'..
            ('\t%s:%d: .*$'):format(current_file, _l)
    }, 'netbox_eval("return e:new()")')

    local _l, _, err = h.get_line(), errors.netbox_eval(g.conn, 'return nil, my_error:new("White Zinc")')
    h.check_error(err, {
        file = 'eval',
        line = 1,
        err = '"127.0.0.1:3301": White Zinc',
        str = '^My error: "127.0.0.1:3301": White Zinc\n' ..
            'stack traceback:\n' ..
                '\teval:1: in main chunk\n' ..
            '.+\n' ..
            'during net.box eval on 127.0.0.1:3301\n' ..
            'stack traceback:\n'..
            ('\t%s:%d: .*$'):format(current_file, _l)
    }, 'netbox_eval("return nil, e:new()")')


    local _l1, remote_fn = h.get_line(), function() return nil, my_error:new('Fuschia Platinum') end
    rawset(_G, 'remote_fn', remote_fn)

    local _l2, _, err = h.get_line(), errors.netbox_eval(g.conn, 'return remote_fn()')
    h.check_error(err, {
        file = current_file,
        line = _l1,
        err = '"127.0.0.1:3301": Fuschia Platinum',
        str = '^My error: "127.0.0.1:3301": Fuschia Platinum\n' ..
            'stack traceback:\n' ..
            ('\t%s:%d: '):format(current_file, _l1) ..
            '.+\n' ..
            'during net.box eval on 127.0.0.1:3301\n' ..
            'stack traceback:\n' ..
            ('\t%s:%d: .*$'):format(current_file, _l2)
    }, 'netbox_eval("return remote_fn()")')

    local _l2, _, err = h.get_line(), errors.netbox_eval(netbox.connect(3301), 'return remote_fn()')
    h.check_error(err, {
        file = current_file,
        line = _l1,
        err = '":3301": Fuschia Platinum',
        str = '^My error: ":3301": Fuschia Platinum\n' ..
            'stack traceback:\n' ..
            ('\t%s:%d: '):format(current_file, _l1) ..
            '.+\n' ..
            'during net.box eval on :3301\n' ..
            'stack traceback:\n'..
            ('\t%s:%d: .*$'):format(current_file, _l2)
    }, 'netbox_eval(nohost, "return remote_fn()")')

    local ret = {errors.netbox_eval(g.conn, 'return ...', {true, "2", 3})}
    t.assert_equals(ret, {true, '2', 3},
        'netbox_eval(return true, "2", 3)'
    )

    g.conn:close()
    local _l, _, err = h.get_line(), errors.netbox_eval(g.conn, 'return true')
    h.check_error(err,  {
        file = 'builtin/box/net_box.lua',
        err = '"127.0.0.1:3301": Connection closed',
        str = '^NetboxEvalError: "127.0.0.1:3301": Connection closed\n' ..
            'stack traceback:\n' ..
            '.+\n' ..
            ('\t%s:%d: .*$'):format(current_file, _l)
    }, 'netbox_eval(closed_connection)')

    local conn = netbox.connect('127.0.0.1:9')
    local _l, _, err = h.get_line(), errors.netbox_eval(conn, 'return true')
    h.check_error(err, {
        file = 'builtin/box/net_box.lua',
        err = '"127.0.0.1:9": Connection refused',
        str = '^NetboxEvalError: "127.0.0.1:9": Connection refused\n' ..
            'stack traceback:\n' ..
            '.+\n' ..
            ('\t%s:%d: .*$'):format(current_file, _l)
    }, 'netbox_eval(connection_refused)')
end

function g.test_errors_netbox_call()
    local _l, _, err = h.get_line(), errors.netbox_call(g.conn, 'fn_undefined')
    h.check_error(err, {
        file = 'builtin/box/net_box.lua',
        err = [["127.0.0.1:3301": Procedure 'fn_undefined' is not defined]],
        str = '^NetboxCallError: "127.0.0.1:3301": Procedure \'fn_undefined\' is not defined\n' ..
            'stack traceback:\n' ..
            '.+\n' ..
            ('\t%s:%d: .*$'):format(current_file, _l)
    }, 'netbox_call(fn_undefined)')

    local _l1, remote_fn = h.get_line(), function() return nil, my_error:new('Yellow Iron') end
    rawset(_G, 'remote_fn', remote_fn)

    local _l2, _, err = h.get_line(), errors.netbox_call(g.conn, 'remote_fn')
    h.check_error(err, {
        file = current_file,
        line = _l1,
        err = '"127.0.0.1:3301": Yellow Iron',
        str = '^My error: "127.0.0.1:3301": Yellow Iron\n' ..
            'stack traceback:\n' ..
            ('\t%s:%d: '):format(current_file, _l1) ..
            '.+\n' ..
            'during net.box call to 127.0.0.1:3301, function "remote_fn"\n' ..
            'stack traceback:\n'..
            ('\t%s:%d: .*$'):format(current_file, _l2)
    }, 'netbox_call(return nil, e:new(string))')

    local _l2, _, err = h.get_line(), errors.netbox_call(netbox.connect(3301), 'remote_fn')
    h.check_error(err, {
        file = current_file,
        line = _l1,
        err = '":3301": Yellow Iron',
        str = '^My error: ":3301": Yellow Iron\n' ..
            'stack traceback:\n' ..
            ('\t%s:%d: '):format(current_file, _l1) ..
            '.+\n' ..
            'during net.box call to :3301, function "remote_fn"\n' ..
            'stack traceback:\n'..
            ('\t%s:%d: .*$'):format(current_file, _l2)
    }, 'netbox_call(nohost, return nil, e:new(string))')

    local ret = {errors.netbox_call(g.conn, 'remote_4args_fn', fn_4args)}
    t.assert_equals(ret, {'1', nil, false, nil},
        'netbox_call(return "1", nil, false, nil)'
    )
    t.assert_equals(type(ret[2]), 'nil', '[2] == nil')
    t.assert_equals(type(ret[4]), 'nil', '[4] == nil')
end

function g.test_errors_netbox_wait_async()
    -- future returns error
    local long_call = function() fiber.sleep(10) return 5 end
    rawset(_G, 'long_call', long_call)

    local csw1 = h.fiber_csw()

    local future_call = errors.netbox_call(g.conn, '_G.long_call', nil, {is_async = true})
    local _l, _, err = h.get_line(), errors.netbox_wait_async(future_call, 0)
    h.check_error(err, {
        file = debug.getinfo(errors.netbox_wait_async).source:gsub('@', ''),
        err = '"127.0.0.1:3301": Timeout exceeded',
        str = '^NetboxCallError: "127.0.0.1:3301": Timeout exceeded\n' ..
            'stack traceback:\n' ..
            '.+\n' ..
            ('\t%s:%d: .*$'):format(current_file, _l)
    }, 'netbox_wait_async (call request timed out)')

    local future_eval = errors.netbox_eval(g.conn, 'fiber.sleep(10) return 5', nil, {is_async = true})
    local _l, _, err = h.get_line(), errors.netbox_wait_async(future_eval, 0)
    h.check_error(err, {
        file = debug.getinfo(errors.netbox_wait_async).source:gsub('@', ''),
        err = '"127.0.0.1:3301": Timeout exceeded',
        str = '^NetboxEvalError: "127.0.0.1:3301": Timeout exceeded\n' ..
            'stack traceback:\n' ..
            '.+\n' ..
            ('\t%s:%d: .*$'):format(current_file, _l)
    }, 'netbox_wait_async (eval request timed out)')

    local csw2 = h.fiber_csw()
    t.assert_equals(csw2, csw1, 'Unnecessary yield')

    g.conn:close()
    local _l, _, err = h.get_line(), errors.netbox_wait_async(future_call, 5)
    h.check_error(err, {
        file = debug.getinfo(errors.netbox_wait_async).source:gsub('@', ''),
        err = '"127.0.0.1:3301": Connection closed',
        str = '^NetboxCallError: "127.0.0.1:3301": Connection closed\n' ..
            'stack traceback:\n' ..
            '.+\n' ..
            ('\t%s:%d: .*$'):format(current_file, _l)
    }, 'netbox_wait_async (call connection closed)')

    local _l, _, err = h.get_line(), errors.netbox_wait_async(future_eval, 5)
    h.check_error(err, {
        file = debug.getinfo(errors.netbox_wait_async).source:gsub('@', ''),
        err = '"127.0.0.1:3301": Connection closed',
        str = '^NetboxEvalError: "127.0.0.1:3301": Connection closed\n' ..
            'stack traceback:\n' ..
            '.+\n' ..
            ('\t%s:%d: .*$'):format(current_file, _l)
    }, 'netbox_wait_async (eval connection closed)')


    g.conn = netbox.connect('127.0.0.1:3301')
    g.conn:wait_connected()

    local future = errors.netbox_call(g.conn, '_G.fn_undefined', nil, {is_async = true})
    local _l, _, err = h.get_line(), errors.netbox_wait_async(future, 10)
    h.check_error(err, {
        file = debug.getinfo(errors.netbox_wait_async).source:gsub('@', ''),
        err = [["127.0.0.1:3301": Procedure '_G.fn_undefined' is not defined]],
        str = '^NetboxCallError: "127.0.0.1:3301": Procedure \'_G.fn_undefined\' is not defined\n' ..
            'stack traceback:\n' ..
            '.+\n' ..
            ('\t%s:%d: .*$'):format(current_file, _l)
    }, 'netbox_wait_async (call undefined function)')


    local future = g.conn:eval('error("Artificial", 0)', nil, {is_async = true})
    future:wait_result()
    t.assert_equals(future:is_ready(), true)

    local csw1 = h.fiber_csw()

    local _l, _, err = h.get_line(), errors.netbox_wait_async(future, 0)
    err.err = tostring(err.err)
    h.check_error(err, {
        file = debug.getinfo(errors.netbox_wait_async).source:gsub('@', ''),
        err = 'Artificial',
        str = '^NetboxCallError: Artificial\n' ..
            'stack traceback:\n' ..
            '.+\n' ..
            ('\t%s:%d: .*$'):format(current_file, _l)
    }, 'netbox_wait_async (wait on bare future)')

    local csw2 = h.fiber_csw()
    t.assert_equals(csw2, csw1, 'Unnecessary yield')

    -- test netbox_wait_async (remote raises)
    local remote_fn = function() error('New error', 0) end
    _G.remote_fn = remote_fn

    local future = errors.netbox_call(g.conn, '_G.remote_fn', nil, {is_async = true})
    local _l, _, err = h.get_line(), errors.netbox_wait_async(future, 10)
    h.check_error(err, {
        file = debug.getinfo(errors.netbox_wait_async).source:gsub('@', ''),
        err = '"127.0.0.1:3301": New error',
        str = '^NetboxCallError: "127.0.0.1:3301": New error\n' ..
            'stack traceback:\n' ..
            '.+\n' ..
            ('\t%s:%d: .*$'):format(current_file, _l)
    }, 'netbox_wait_async (call remote fn raises)')

    local future = errors.netbox_eval(g.conn, 'return _G.remote_fn()', nil, {is_async = true})
    local _l, _, err = h.get_line(), errors.netbox_wait_async(future, 10)
    h.check_error(err, {
        file = debug.getinfo(errors.netbox_wait_async).source:gsub('@', ''),
        err = '"127.0.0.1:3301": New error',
        str = '^NetboxEvalError: "127.0.0.1:3301": New error\n' ..
            'stack traceback:\n' ..
            '.+\n' ..
            ('\t%s:%d: .*$'):format(current_file, _l)
    }, 'netbox_wait_async (eval raises)')

    -- test netbox_wait_async (remote returns nil, error object)
    local _l1, remote_fn = h.get_line(), function() return nil, my_error:new('Error obj') end
    _G.remote_fn = remote_fn

    local future = errors.netbox_call(g.conn, '_G.remote_fn', nil, {is_async = true})
    local _l2, _, err = h.get_line(), errors.netbox_wait_async(future, 10)
    h.check_error(err, {
        file = current_file,
        line = _l1,
        err = '"127.0.0.1:3301": Error obj',
        str = '^My error: "127.0.0.1:3301": Error obj\n' ..
            'stack traceback:\n' ..
            ('\t%s:%d: '):format(current_file, _l1) ..
            '.+\n' ..
            'during async net.box call to 127.0.0.1:3301, function "_G.remote_fn"\n' ..
            'stack traceback:\n' ..
            ('\t%s:%d: .*$'):format(current_file, _l2)
    }, 'netbox_wait_async (call remote fn returns nil, error_obj)')

    local future = errors.netbox_eval(g.conn, 'return _G.remote_fn()', nil, {is_async = true})
    local _l2, _, err = h.get_line(), errors.netbox_wait_async(future, 10)

    h.check_error(err, {
        file = current_file,
        line = _l1,
        err = '"127.0.0.1:3301": Error obj',
        str = '^My error: "127.0.0.1:3301": Error obj\n' ..
            'stack traceback:\n' ..
            ('\t%s:%d: '):format(current_file, _l1) ..
            '.+\n' ..
            'during async net.box eval on 127.0.0.1:3301\n' ..
            'stack traceback:\n' ..
            ('\t%s:%d: .*$'):format(current_file, _l2)
    }, 'netbox_wait_async (eval returns nil, error_obj)')

    local future = g.conn:eval('return _G.remote_fn()', nil, {is_async = true})
    local _l2, _, err = h.get_line(), errors.netbox_wait_async(future, 10)

    h.check_error(err, {
        file = current_file,
        line = _l1,
        err = 'Error obj',
        str = '^My error: Error obj\n' ..
            'stack traceback:\n' ..
            ('\t%s:%d: '):format(current_file, _l1) ..
            '.+\n' ..
            'during async net.box request\n' ..
            'stack traceback:\n' ..
            ('\t%s:%d: .*$'):format(current_file, _l2)
    }, 'netbox_wait_async (wait on bare future returns nil, error_obj)')

    -- test netbox_wait_async (correct multireturn)
    local future = errors.netbox_call(g.conn, 'remote_4args_fn', fn_4args, {is_async = true})
    local ret = {errors.netbox_wait_async(future, 10)}
    t.assert_equals(ret, {'1', nil, false, nil},
        'netbox_wait_async (call return {"1", box.NULL, false, nil})'
    )

    local future = errors.netbox_eval(g.conn, 'return remote_4args_fn(...)', fn_4args, {is_async = true})
    local ret = {errors.netbox_wait_async(future, 10)}
    t.assert_equals(ret, {'1', nil, false, nil},
        'netbox_wait_async (eval return {"1", box.NULL, false, nil})'
    )

    local csw1 = h.fiber_csw()
    local ret = {errors.netbox_wait_async(future, 0)}
    t.assert_equals(ret, {'1', nil, false, nil},
        'netbox_wait_async (wait again on ready future)'
    )
    local csw2 = h.fiber_csw()
    t.assert_equals(csw2, csw1, 'Unnecessary yield')
end

function g.test_errors_wrap_remote()
    local _l, _, err = h.get_line(), errors.wrap(g.conn:eval('return nil, my_error:new("Aqua Aluminium")'))
    h.check_error(err, {
        file = 'eval',
        line = 1,
        err = 'Aqua Aluminium',
        str = '^My error: Aqua Aluminium\n' ..
            'stack traceback:\n' ..
                '\teval:1: in main chunk\n' ..
            '.+\n' ..
            'during wrapped call\n' ..
            'stack traceback:\n'..
            ('\t%s:%d: .*$'):format(current_file, _l)
    }, 'wrap conn:eval("return nil, e:new()")')

    local _l1, remote_fn = h.get_line(), function() return nil, my_error:new('Fuschia Platinum') end
    rawset(_G, 'remote_fn', remote_fn)

    local _l2, _, err = h.get_line(), errors.wrap(g.conn:eval('return remote_fn()'))
    h.check_error(err, {
        file = current_file,
        line = _l1,
        err = 'Fuschia Platinum',
        str = '^My error: Fuschia Platinum\n' ..
            'stack traceback:\n' ..
            ('\t%s:%d: '):format(current_file, _l1) ..
            '.+\n' ..
            'during wrapped call\n' ..
            'stack traceback:\n'..
            ('\t%s:%d: .*$'):format(current_file, _l2)
    }, 'wrap conn:eval("return remote_fn()")')

    local _l1, remote_fn = h.get_line(), function() return nil, my_error:new('Yellow Iron') end
    rawset(_G, 'remote_fn', remote_fn)

    local _l2, _, err = h.get_line(), errors.wrap(g.conn:call('remote_fn'))
    h.check_error(err, {
        file = current_file,
        line = _l1,
        err = 'Yellow Iron',
        str = '^My error: Yellow Iron\n' ..
            'stack traceback:\n' ..
            ('\t%s:%d: '):format(current_file, _l1) ..
            '.+\n' ..
            'during wrapped call\n' ..
            'stack traceback:\n'..
            ('\t%s:%d: .*$'):format(current_file, _l2)
    }, 'warp conn:call(return nil, e:new(string))')

    local ret = {errors.wrap(g.conn:call('remote_4args_fn', fn_4args))}
    t.assert_equals(ret, {'1', nil, false, nil})
    t.assert_equals(type(ret[2]), 'nil', '[2] == nil')
    t.assert_equals(type(ret[4]), 'nil', '[4] == nil')
end
