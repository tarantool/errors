#!/usr/bin/env tarantool

local log = require('log')
local debug = require('debug')
local checks = require('checks')

--- Convenient error handling in Tarantool.
-- @module errors

if rawget(_G, "_error_classes") == nil then
    _G._error_classes = {}
end

--- The errors are represented as Lua tables of the following structure.
-- @type error_object

--- Class name.
-- @field error_object.class_name

--- Error payload.
-- Either formatted string or any other payload passed at object creation.
-- @field error_object.err

--- String representation.
-- This includes `class_name` and `err`.
-- And optional `stack`, if it was not disabled for this class.
-- @field error_object.str

--- Stacktrace recordered at creation.
-- @field error_object.stack

--- Filename issued an error.
-- @field error_object.file

--- Line number issued an error.
-- @field error_object.line

--- Get string representation.
-- The same as `tostring(error_object)`.
-- @see error_class.tostring
-- @function error_object:tostring
-- @treturn string `error_object.str`

--- An error class
-- @field __type error class name
-- @type error_class
local error_class = {
    __type = 'error_class'
}
error_class.__index = error_class


local function is_error_object(err)
    return (type(err) == 'table'
        and err.err ~= nil
        and err.str ~= nil
        and err.line ~= nil
        and err.file ~= nil
        and err.class_name ~= nil
    )
end

--- Create error object.
-- Error payload is formatted by `string.format`
-- @tparam[opt] number level within the meaning of Lua `debug.getinfo(level)`
-- @tparam string fmt used for `string.format(fmt, ...)`
-- @param[opt] ... formatting arguments
-- @treturn error_object
function error_class:new(...)
    checks('error_class')

    local level, shift
    if type(nil or ...) == 'number' then
        shift = 2
        level = ...
    else
        shift = 1
        level = 1
    end
    level = level + 1 -- escape current stackframe

    local err = nil
    if (select('#', ...) < shift) then
        err = nil
    elseif (type(select(shift, ...)) == 'string') then
        local ok, _err = pcall(string.format, select(shift, ...))
        if ok then
            err = _err
        else
            err = select(shift, ...)
        end
    elseif is_error_object(select(shift, ...)) then
        return select(shift, ...)
    else
        err = select(shift, ...)
    end

    if err == nil then
        err = ''
    end

    local frame = debug.getinfo(level, "Sl")
    local line = 0
    local file = 'eval'

    if type(frame) == 'table' then
        line = frame.currentline or 0
        file = frame.short_src or frame.source or 'eval'
    end

    local str = string.format("%s: %s", self.name, err)
    local stack = nil

    if self.capture_stack then
        stack = string.strip(debug.traceback("", level))
        str = str .. '\n' .. stack
    end

    if self.log_on_creation then
        log.error(str)
    end

    local e = {
        err = err,
        str = str,
        line = line,
        file = file,
        stack = stack,
        class_name = self.name
    }
    setmetatable(e, self.__instance_mt)
    return e
end

local function pack(...)
    return select('#', ...), {...}
end

--- Perform protected Lua call, gathering error as object
-- @tparam function fn called function
-- @param[opt] ... call arguments
-- @return[1] `fn(...)` if the call succeeds without errors
-- @treturn[2] nil
-- @treturn[2] error_object
function error_class:pcall(fn, ...)
    checks('error_class', '?')

    local function collect(estr)
        if estr == nil
        or type(estr) == 'string'
        or type(estr) == 'cdata' then
            return self:new(2, tostring(estr))
        else
            return estr
        end
    end

    local n, ret = pack(xpcall(fn, collect, ...))
    if not ret[1] then
        -- fn did raise an error
        -- xpcall return false, error_object
        return nil, unpack(ret, 2, n)
    else
        -- fn did not raise
        -- xpcall return true, ...
        return unpack(ret, 2, n)
    end
end

--- Raise an error object unless condition is true.
-- @param cond condition to be checked
-- @param[opt] ... `error_class:new` args
-- @return cond
-- @return ...
-- @raise (`error_object`) `error_class:new(fmt, ...)`
function error_class:assert(cond, ...)
    checks('error_class', '?')

    if not cond then
        if select('#', ...) == 0 then
            error(self:new(2, 'assertion failed!'))
        elseif type(...) == 'string' then
            error(self:new(2, ...))
        else
            error(..., nil)
        end
    end

    return cond, ...
end

--- Get string representation.
-- Due to the nature of Lua, any class_name inconsistencies are ignored.
-- @see error_object:tostring
-- @tparam error_object err
-- @treturn string `error_object.str`
function error_class.tostring(err)
    return err.str
end

--- Create new error class.
-- @within errors
-- @function new_class
-- @tparam string class_name
-- @tparam ?table options Behaviour tuning options
-- @tparam ?boolean options.capture_stack Capture backtrace at creation
-- @tparam ?boolean options.log_on_creation Produce error log at creation
-- @treturn error_class
local function new_class(class_name, options)
    checks('string', {
        capture_stack = '?boolean',
        log_on_creation = '?boolean',
    })

    local capture_stack = options and options.capture_stack
    if capture_stack == nil then
        capture_stack = true
    end

    local log_on_creation = options and options.log_on_creation
    if log_on_creation == nil then
        log_on_creation = false
    end

    local self = {
        name = class_name,
        capture_stack = capture_stack,
        log_on_creation = log_on_creation,
        __instance_mt = {
            __type = class_name,
            __tostring = error_class.tostring,
            __index = {
                tostring = error_class.tostring,
            },
        }
    }
    setmetatable(self, error_class)

    _G._error_classes[class_name] = self
    return self
end

local function restore_mt(err)
    local err_class = _G._error_classes[err.class_name]
    local mt
    if err_class then
        mt = err_class.__instance_mt
    else
        mt = {
            __type = err.class_name,
            __tostring = error_class.tostring,
            __index = {
                tostring = error_class.tostring,
            },
        }
    end
    if getmetatable(err) ~= mt then
        return setmetatable(err, mt)
    else
        return nil
    end
end

local function wrap_with_suffix(suffix_format, ...)
    checks('string|table')
    local n, ret = pack(...)
    for i = 1, n do
        local obj = ret[i]
        if obj == box.NULL then
            ret[i] = nil
        elseif is_error_object(obj) then
            if restore_mt(obj) and obj.stack ~= nil then
                local stack_suffix
                local stack = string.strip(debug.traceback("", 2))

                if type(suffix_format) == 'string' then
                    stack_suffix = suffix_format
                else
                    stack_suffix = string.format(unpack(suffix_format))
                end

                obj.str = obj.str .. '\n' .. stack_suffix .. '\n' .. stack
                obj.stack = obj.stack .. '\n' .. stack_suffix .. '\n' .. stack
            end
        end
    end

    return unpack(ret, 1, n)
end

local e_netbox_eval = new_class('Net.box eval failed')
--- Do protected net.box evaluation.
-- Execute code on remote server using Tarantool built-in [`net.box` `conn:eval`](
-- https://tarantool.io/en/doc/latest/reference/reference_lua/net_box/#net-box-eval).
-- Additionally postprocess returned values with `wrap`.
-- @within errors
-- @see netbox_call
-- @function netbox_eval
-- @param conn net.box connection object
-- @tparam string code
-- @param[opt] arguments passed to `net.box` `eval`
-- @param[opt] options passed to `net.box` `eval`
-- @return[1] Postprocessed `conn:eval()` result
-- @treturn[2] nil
-- @treturn[2] error_object Error description
local function netbox_eval(conn, code, ...)
    checks('table', 'string')

    return wrap_with_suffix(
        {'during net.box eval on %s:%s', conn.host, conn.port},
        e_netbox_eval:pcall(conn.eval, conn, code, ...)
    )
end

local e_netbox_call = new_class('Net.box call failed')
--- Perform protected net.box call.
-- Similar to `netbox_eval`,
-- execute code on remote server using Tarantool built-in [`net.box` `conn:call`](
-- https://tarantool.io/en/doc/latest/reference/reference_lua/net_box/#net-box-call).
-- Additionally postprocess returned values with `wrap`.
-- @within errors
-- @see netbox_eval
-- @function netbox_call
-- @param conn net.box connection object
-- @tparam string function_name
-- @param[opt] arguments passed to `net.box` `call`
-- @param[opt] options passed to `net.box` `call`
-- @return[1] Postprocessed `conn:call()` result
-- @treturn[2] nil
-- @treturn[2] error_object Error description
local function netbox_call(conn, func_name, ...)
    checks('table', 'string')
    return wrap_with_suffix(
        {'during net.box call to %s:%s, function %q', conn.host, conn.port, func_name},
        e_netbox_call:pcall(conn.call, conn, func_name, ...)
    )
end

local function list()
    local res = {}

    for k, _ in pairs(_G._error_classes) do
        table.insert(res, k)
    end

    return res
end

--- Postprocess arguments.
-- Mostly useful for postprocessing net.box and vshard call results.
--
-- * Substitute all `box.NULL` with `nil`;
-- * Repair metatables of error objects because they are not transfered over network;
-- * Extend stacktrace of remote call if possible;
--
-- @within errors
-- @function wrap
-- @param[opt] ...
-- @return Postprocessed values
local function wrap(...)
    return wrap_with_suffix('during wrapped call', ...)
end

return {
    list = list,
    new_class = new_class,
    netbox_call = netbox_call,
    netbox_eval = netbox_eval,
    wrap = wrap,
}
