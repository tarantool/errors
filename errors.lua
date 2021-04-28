#!/usr/bin/env tarantool

local log = require('log')
local debug = require('debug')
local deprecate = require('errors.deprecate')

--- Convenient error handling in Tarantool.
-- @module errors

--- Functions.
-- @section functions

--- Functions (shortcuts).
-- @section shortcuts

if rawget(_G, "_error_classes") == nil then
    _G._error_classes = {}
end

---
-- @type error_class
local error_class = {
    __type = 'error_class'
}
error_class.__index = error_class

--- Check if the argument is an error object.
--
-- The check is positive if it's a table with mandatory fields:
-- `err`, `str`, `line`, `file`, `class_name`. Their types aren't
-- checked. Other fields are ignored.
--
-- @function is_error_object
-- @within Functions
-- @param obj
-- @treturn boolean true/false
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
    local self_mt = getmetatable(self)
    if not self_mt or self_mt.__type ~= 'error_class' then
        error('Use error_class:new() instead of error_class.new()', 2)
    end

    local level, shift
    if type(nil or ...) == 'number' then
        shift = 2
        level = ...
    else
        shift = 1
        level = 1
    end
    level = level + 1 -- escape current stackframe

    local err
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

    if self.log_on_creation then
        log.error(e:tostring())
    end

    return e
end

local function pack(...)
    return select('#', ...), {...}
end

local function pcall_tail(status, ...)
    if not status then
        return nil, ...
    end
    return ...
end

--- Perform protected Lua call, gathering error as object.
-- @tparam function fn called function
-- @param[opt] ... call arguments
-- @return[1] `fn(...)` if the call succeeds without errors
-- @treturn[2] nil
-- @treturn[2] error_object
function error_class:pcall(fn, ...)
    local self_mt = getmetatable(self)
    if not self_mt or self_mt.__type ~= 'error_class' then
        error('Use error_class:pcall() instead of error_class.pcall()', 2)
    end

    return pcall_tail(xpcall(fn, self.__collect_fn, ...))
end

--- Raise an error object unless condition is true.
-- @param cond condition to be checked
-- @param[opt] ... `error_class:new` args
-- @return cond
-- @return ...
-- @raise (`error_object`) `error_class:new(...)`
function error_class:assert(cond, ...)
    local self_mt = getmetatable(self)
    if not self_mt or self_mt.__type ~= 'error_class' then
        error('Use error_class:assert() instead of error_class.assert()', 2)
    end

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

--- A particular error object.
-- Represented as a Lua table with the following fields:
--
-- * class_name: (`string`)
-- * err: (`string`)
-- * file: (`string`)
-- * line: (`number`)
-- * stack: (`string`)
--
-- @type error_object

--- Get string representation.
-- Including `class_name` and `err`.
-- And optional `stack`, if it was not disabled for this class.
--
-- @function tostring
-- @treturn string
function error_class.tostring(err)
    local ret = err.str
    if err.stack ~= nil then
        ret = ret .. '\n' .. err.stack
    end
    return ret
end

--- Functions.
-- @section functions

--- Create new error class.
-- @function new_class
-- @tparam string class_name
-- @tparam[opt] table options
-- @tparam boolean options.capture_stack
--   Capture backtrace at creation.
--   (default: **true**)
-- @tparam boolean options.log_on_creation
--   Produce error log at creation.
--   (default: **false**)
-- @treturn error_class
local function new_class(class_name, options)
    if type(class_name) ~= 'string' then
        error('Bad argument #1 to errors.new_class' ..
            ' (string expected, got ' .. type(class_name) .. ')', 2)
    end

    if options == nil then
        options = {}
    elseif type(options) ~= 'table' then
        error('Bad argument #2 to errors.new_class' ..
            ' (?table expected, got ' .. type(options) .. ')', 2)
    end

    local _opts = {
        capture_stack = true,
        log_on_creation = false,
    }
    for opt, value in pairs(options) do
        if type(_opts[opt]) == 'nil' then
            error('Unexpected argument options.' .. opt ..
                ' to errors.new_class', 2)
        elseif value ~= nil and type(value) ~= 'boolean' then
            error('Bad argument options.' .. opt ..
                ' to errors.new_class' ..
                ' (boolean expected, got ' .. type(value) .. ')', 2)
        end

        if value ~= nil then
            _opts[opt] = value
        end
    end

    local self = {
        name = class_name,
        capture_stack = _opts.capture_stack,
        log_on_creation = _opts.log_on_creation,
        __instance_mt = {
            __type = class_name,
            __tostring = error_class.tostring,
            __index = {
                tostring = error_class.tostring,
            },
        }
    }
    self.__collect_fn = function(estr)
        if estr == nil
        or type(estr) == 'string'
        or type(estr) == 'cdata' then
            return self:new(2, tostring(estr))
        else
            return estr
        end
    end
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

local function string_format(fmt)
    if type(fmt) == 'string' then
        return fmt
    else
        return string.format(unpack(fmt))
    end
end

local function _wrap(prefix_format, suffix_format, ...)
    local n, ret = pack(...)
    for i = 1, n do
        local obj = ret[i]
        if obj == box.NULL then
            ret[i] = nil
        elseif is_error_object(obj) then
            if prefix_format ~= nil then
                local error_prefix = string_format(prefix_format)
                obj.err = error_prefix .. ': ' .. obj.err
                obj.str = obj.class_name .. ': ' .. obj.err
            end

            if restore_mt(obj) and obj.stack ~= nil then
                local local_stack = string.strip(debug.traceback("", 2))
                local stack_suffix = string_format(suffix_format)
                obj.stack = obj.stack .. '\n' .. stack_suffix .. '\n' .. local_stack
            end
        end
    end

    return unpack(ret, 1, n)
end

local NetboxEvalError = new_class('NetboxEvalError')
--- Do protected net.box evaluation.
-- Execute code on remote server using Tarantool built-in [`net.box` `conn:eval`](
-- https://tarantool.io/en/doc/latest/reference/reference_lua/net_box/#net-box-eval).
-- Additionally postprocess returned values with `wrap`.
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
    if type(conn) ~= 'table' then
        error('Bad argument #1 to errors.netbox_eval' ..
            ' (net.box connection expected, got ' .. type(conn) .. ')', 2)
    elseif type(code) ~= 'string' then
        error('Bad argument #2 to errors.netbox_eval' ..
            ' (string expected, got ' .. type(code) .. ')', 2)
    end

    return _wrap(
        {'"%s:%s"', conn.host or "", conn.port},
        {'during net.box eval on %s:%s', conn.host or "", conn.port},
        NetboxEvalError:pcall(conn.eval, conn, code, ...)
    )
end

local NetboxCallError = new_class('NetboxCallError')
--- Perform protected net.box call.
-- Similar to `netbox_eval`,
-- execute code on remote server using Tarantool built-in [`net.box` `conn:call`](
-- https://tarantool.io/en/doc/latest/reference/reference_lua/net_box/#net-box-call).
-- Additionally postprocess returned values with `wrap`.
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
    if type(conn) ~= 'table' then
        error('Bad argument #1 to errors.netbox_call' ..
            ' (net.box connection expected, got ' .. type(conn) .. ')', 2)
    elseif type(func_name) ~= 'string' then
        error('Bad argument #2 to errors.netbox_call' ..
            ' (string expected, got ' .. type(func_name) .. ')', 2)
    end

    return _wrap(
        {'"%s:%s"', conn.host or "", conn.port},
        {'during net.box call to %s:%s, function %q', conn.host or "", conn.port, func_name},
        NetboxCallError:pcall(conn.call, conn, func_name, ...)
    )
end


local function _wrap_future_result(err_class, prefix, suffix, res, err)
    if err == nil then
        return res
    end

    if not is_error_object(err) then
        err = err_class:new(err)
    end

    return _wrap(prefix, suffix, nil, err)
end

--- Perform protected wait of async net.box call/eval.
-- Note: function passed to net.box call/eval must not return multiple values.
-- It should return only tuple res, error (also raising an error is acceptable)
-- Similar to `netbox_call`,
-- execute code on remote server using Tarantool built-in [`net.box` `conn:call` `is_async = true`](
-- https://tarantool.io/en/doc/latest/reference/reference_lua/net_box/#net-box-call).
-- Additionally postprocess returned values with `wrap`.
-- @see netbox_call
-- @function netbox_wait_async
-- @param future net.box future object
-- @tparam number timeout
-- @tparam ?string call_uri - async call uri (to increase error verbosity)
-- @tparam ?string activity_name - name of operation (for ex. function name in case of call)
--   To increase error verbosity
-- @return[1] Postprocessed `future:wait_result()` result
-- @treturn[2] nil
-- @treturn[2] error_object Error description
local function netbox_wait_async(future, timeout, call_uri, activity_name)
    if type(future) ~= 'table' then
        error('Bad argument #1 to errors.netbox_wait_async' ..
            ' (net.box future expected, got ' .. type(future) .. ')', 2)
    elseif type(timeout) ~= 'number' then
        error('Bad argument #2 to errors.netbox_wait_async' ..
            ' (number expected, got ' .. type(timeout) .. ')', 2)
    elseif call_uri and type(call_uri) ~= 'string' then
        error('Bad argument #3 to errors.netbox_wait_async' ..
            ' (?string expected, got ' .. type(call_uri) .. ')', 2)
    elseif activity_name and type(activity_name) ~= 'string' then
        error('Bad argument #4 to errors.netbox_wait_async' ..
        ' (?string expected, got ' .. type(activity_name) .. ')', 2)
    end

    local suffix = 'during async net.box call'
    local err_class = NetboxCallError
    if future.method == 'eval' then
        err_class = NetboxEvalError
        suffix = 'during async net.box eval'
    end

    local prefix = ''
    if call_uri then
        prefix = ('%q'):format(call_uri)
        suffix = suffix .. (' to %s'):format(call_uri)
    end
    if activity_name then
        suffix = suffix .. (' %q'):format(activity_name)
    end


    -- wait_result behaviour:
    -- - may raise an error (if timeout ~= number or timeout < 0)
    -- - return nil, err as string:
    --     - if there is no result with fixed timeout (Timeout exceeded)
    --     - peer closed
    --     - error was raised in remote function
    -- - return res as array:
    --     - res[1] - result or nil
    --     - res[2] - error or nil (error maybe as object or string)
    -- (wait_result(0) won't yeild)
    local res, err = _wrap_future_result(err_class, prefix, suffix,
        err_class:pcall(future.wait_result, future, timeout)
    )
    if res == nil then
        return nil, err
    end

    return _wrap_future_result(err_class, prefix, suffix, res[1], res[2])
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
-- @function wrap
-- @param[opt] ...
-- @return Postprocessed values
local function wrap(...)
    return _wrap(nil, 'during wrapped call', ...)
end

--- Functions (shortcuts).
-- @section shortcuts

--- Shortcut for `error_class:new`.
--    errors.new_class(class_name):new(...)
--
-- @function new
-- @tparam string class_name
-- @tparam[opt] number level
-- @tparam string fmt
-- @param[opt] ...
local function errors_new(class_name, ...)
    local error_class = _G._error_classes[class_name] or new_class(class_name)
    return error_class:new(...)
end

--- Shortcut for `error_class:pcall`.
-- Equivalent for
--    errors.new_class(class_name):pcall(...)
--
-- @function pcall
-- @tparam string class_name
-- @tparam function fn
-- @param[opt] ...
local function errors_pcall(class_name, ...)
    local error_class = _G._error_classes[class_name] or new_class(class_name)
    return error_class:pcall(...)
end

--- Shortcut for `error_class:assert`.
--    errors.new_class(class_name):assert(...)
--
-- @function assert
-- @tparam string class_name
-- @param cond condition to be checked
-- @param[opt] ... `error_class:new` args
local function errors_assert(class_name, ...)
    local error_class = _G._error_classes[class_name] or new_class(class_name)
    return error_class:assert(...)
end

return {
    list = list,
    new_class = new_class,
    netbox_call = netbox_call,
    netbox_eval = netbox_eval,
    netbox_wait_async = netbox_wait_async,
    wrap = wrap,

    new = errors_new,
    pcall = errors_pcall,
    assert = errors_assert,
    is_error_object = is_error_object,

--- Tools for API deprecation.
-- @section deprecate

    --- Issue deprecation error.
    -- Do it once for every location in code,
    -- which points on the second-level caller.
    --
    -- @function deprecate
    -- @tparam string message
    -- @treturn error_object
    deprecate = deprecate.warn,

    --- Set new deprecation handler.
    -- It may be used in tests and development environment
    -- to turn warnings into noticable errors.
    --
    -- By default (if handler is `nil`) all errors are logged using `log.warn()`.
    --
    -- @function set_deprecation_handler
    -- @tparam nil|functon fn
    set_deprecation_handler = deprecate.set_handler,
}
