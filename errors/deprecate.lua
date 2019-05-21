#!/usr/bin/env tarantool

local log = require('log')
local checks = require('checks')

local handler = nil
local errors_issued = {}

local function set_handler(fn)
    checks('?function')
    handler = fn
end

local function warn(message)
    checks('string')
    local level = 3 -- the function above the caller
    local errors = require('errors')
    local err = errors.new('DeprecationError', level, message)

    if errors_issued[message] == nil then
        errors_issued[message] = {}
    end

    if errors_issued[message][err.file] == nil then
        errors_issued[message][err.file] = {}
    end

    -- Don't issue same warning twice
    if errors_issued[message][err.file][err.line] then
        return nil
    end

    errors_issued[message][err.file][err.line] = err
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
