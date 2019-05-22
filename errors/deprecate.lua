#!/usr/bin/env tarantool

local log = require('log')

local handler = nil
local errors_issued = {}

local function set_handler(fn)
    if fn ~= nil and type(fn) ~= 'function' then
        error('Bad argument #1 to errors.set_deprecation_handler' ..
            ' (?function expected, got ' .. type(fn) .. ')', 2)
    end

    if fn == nil then
        handler = nil
    else
        handler = fn
    end
end

local function warn(message)
    if type(message) ~= 'string' then
        error('Bad argument #1 to errors.deprecate' ..
            ' (string expected, got ' .. type(message) .. ')', 2)
    end

    local level = 3 -- the function above the caller
    local frame = debug.getinfo(level, "Sl")

    local line = 0
    local file = 'eval'

    if type(frame) == 'table' then
        line = frame.currentline or 0
        file = frame.short_src or frame.source or 'eval'
    end

    if errors_issued[message] == nil then
        errors_issued[message] = {}
    end

    if errors_issued[message][file] == nil then
        errors_issued[message][file] = {}
    end

    -- Don't issue same warning twice
    if errors_issued[message][file][line] then
        return nil
    end

    local errors = require('errors')
    local err = errors.new('DeprecationError', level,
        '%s (%s:%s)', message, file, line
    )

    errors_issued[message][file][line] = err
    if handler ~= nil then
        handler(err)
    else
        log.warn('%s', err)
    end

    return err
end

return {
    warn = warn,
    set_handler = set_handler,
}
