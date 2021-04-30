local json = require('json')
local errors = require('errors')

local t = require('luatest')
local h = require('test.helper')
local g = t.group()

local my_error = errors.new_class('My error')
local current_file = debug.getinfo(1, 'S').short_src

g.before_all = function()
    _G.my_error = my_error
end

function g.test_error_new()
    local _l, err = h.get_line(), my_error:new()
    h.check_error(err, {
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

    local _l, err = h.get_line(), lvl2()
    h.check_error(err, {
        file = current_file,
        line = _l,
        err = '',
        str = '^My error: \n' ..
            'stack traceback:\n' ..
            ('\t%s:%d: .*$'):format(current_file, _l)
    }, 'return e:new(level)')

    local _l, err = h.get_line(), my_error:new('Green %s %X', 'Bronze', 175)
    h.check_error(err, {
        file = current_file,
        line = _l,
        err = 'Green Bronze AF',
        str = '^My error: Green Bronze AF\n' ..
            'stack traceback:\n'
    }, 'return e:new(fmt, str)')

    local _l, err = h.get_line(), my_error:new('Bad format %s')
    h.check_error(err, {
        file = current_file,
        line = _l,
        err = 'Bad format %s',
        str = '^My error: Bad format %%s\n' ..
            'stack traceback:\n'
    }, 'return e:new(bad_format)')

    local tbl = setmetatable({color = 'black'}, {__tostring = json.encode})
    local _l, err = h.get_line(), my_error:new(tbl)
    h.check_error(err, {
        file = current_file,
        line = _l,
        err = tbl,
        str = '^My error: ' .. tostring(tbl) .. '\n' ..
            'stack traceback:\n'
    }, 'return e:new(table)')

    local _l1, err1 = h.get_line(), my_error:new('Inner error')
    local _, err2 = h.get_line(), my_error:new(err1)
    h.check_error(err2, {
        file = current_file,
        line = _l1,
        err = 'Inner error',
        str = '^My error: Inner error\n' ..
            'stack traceback:\n'
    }, 'return e:new(e:new())')
end

function g.test_error_pcall()
    local _, err = my_error:pcall(error, nil)
    h.check_error(err, {
        file = '[C]',
        line = -1,
        err = 'nil',
        str = '^My error: nil\n' ..
            'stack traceback:\n'
    }, 'e:pcall(error, nil)')

    local _l, fn = h.get_line(), function() error(nil) end
    local _, err = my_error:pcall(fn)
    h.check_error(err, {
        file = current_file,
        line = _l,
        err = 'nil',
        str = '^My error: nil\n' ..
            'stack traceback:\n'
    }, 'e:pcall(fn() error(nil) end')

    local _l, fn = h.get_line(), function() error('Olive Nickel') end
    local _, etxt = pcall(fn)
    local _, err = my_error:pcall(fn)
    h.check_error(err, {
        file = current_file,
        line = _l,
        err = etxt,
        str = '^My error: '..etxt..'\n' ..
            'stack traceback:\n'
    }, 'e:pcall(fn() error(string) end)')

    local _l, err = h.get_line(), my_error:new('Red Steel')
    local _, err = my_error:pcall(function() error(err) end)
    h.check_error(err, {
        file = current_file,
        line = _l,
        err = 'Red Steel',
        str = '^My error: Red Steel\n' ..
            'stack traceback:\n'
    }, 'e:pcall(fn() error(e:new(string)) end)')

    local _l, err = h.get_line(), my_error:new('Lime Silver')
    local _, err = my_error:pcall(function() return nil, err end)
    h.check_error(err, {
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

function g.test_error_assert()
    local _l, fn = h.get_line(), function() my_error:assert() end
    local _, err = pcall(fn)
    h.check_error(err, {
        file = current_file,
        line = _l,
        err = 'assertion failed!',
        str = '^My error: assertion failed!\n' ..
            'stack traceback:\n'
    }, 'e:assert()')

    local _l, fn = h.get_line(), function() my_error:assert(false) end
    local _, err = pcall(fn)
    h.check_error(err, {
        file = current_file,
        line = _l,
        err = 'assertion failed!',
        str = '^My error: assertion failed!\n' ..
            'stack traceback:\n'
    }, 'e:assert(false)')

    local _l, fn = h.get_line(), function() my_error:assert(false, 'White %s', 'Titanium') end
    local _, err = pcall(fn)
    h.check_error(err, {
        file = current_file,
        line = _l,
        err = 'White Titanium',
        str = '^My error: White Titanium\n' ..
            'stack traceback:\n'
    }, 'e:assert(false, fmt, str)')

    local _l, fn = h.get_line(), function() my_error:assert(false, 'Bad format %d', {}) end
    local _, err = pcall(fn)
    h.check_error(err, {
        file = current_file,
        line = _l,
        err = 'Bad format %d',
        str = '^My error: Bad format %%d\n' ..
            'stack traceback:\n'
    }, 'e:assert(false, bad_format)')

    local _l, err = h.get_line(), my_error:new('Purple Zinc')
    local fn = function() my_error:assert((function() return nil, err end)()) end
    local _, err = pcall(fn)
    h.check_error(err, {
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

function g.test_errros_wrap()
    local tbl = {}
    local _l, err = h.get_line(), errors.wrap(my_error:new())
    h.check_error(err, {
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
end

function g.test_shortcuts()
    local _l, err = h.get_line(), errors.new('ErrorNew', 'Grey Zinc')
    h.check_error(err, {
        file = current_file,
        line = _l,
        err = 'Grey Zinc',
        str = '^ErrorNew: Grey Zinc\n' ..
            'stack traceback:\n' ..
            ('\t%s:%d: .*$'):format(current_file, _l)
    }, 'return errors.new(class_name, message)')

    local _l, fn = h.get_line(), function() error('Teal Brass') end
    local _, etxt = pcall(fn)
    local _, err = errors.pcall('ErrorPCall', fn)
    h.check_error(err, {
        file = current_file,
        line = _l,
        err = etxt,
        str = '^ErrorPCall: ' .. etxt .. '\n' ..
            'stack traceback:\n' ..
            ('\t%s:%d: .*$'):format(current_file, _l)
    }, 'errors.pcall(error, message)')

    local _l, fn = h.get_line(), function() errors.assert('ErrorAssert', false, 'Maroon Silver') end
    local _, err = pcall(fn)
    h.check_error(err,{
        file = current_file,
        line = _l,
        err = 'Maroon Silver',
        str = '^ErrorAssert: Maroon Silver\n' ..
            'stack traceback:\n' ..
            ('\t%s:%d: .*$'):format(current_file, _l)
    }, 'errors.assert(class_name, false, message)')
end

function g.test_is_error_object()
    local err = errors.new('error')
    t.assert(errors.is_error_object)
    t.assert_equals(errors.is_error_object(err), true)
    t.assert_equals(errors.is_error_object({err = 'str'}), false)
    t.assert_equals(errors.is_error_object(5), false)
end
