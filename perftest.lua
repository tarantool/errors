#!/usr/bin/env tarantool

require('strict').on()
local tap = require('tap')
local fio = require('fio')
local errors = require('errors')
local test = tap.test('performance_test')

box.cfg{
    listen = '127.0.0.1:13301',
    wal_mode = 'none',
    work_dir = fio.tempdir(),
    log_level = 0,
}
box.schema.user.grant('guest', 'super')
fio.rmtree(box.cfg.work_dir)

local function perftest(testname, fn, ...)
    local cnt = 0
    local batch_size = 1000
    local stop
    local start = os.clock()
    repeat
        for _ = 1, batch_size do
            fn(...)
        end
        cnt = cnt + batch_size
        batch_size = math.floor(batch_size * 1.2)
        stop = os.clock()
    until stop - start > 1

    test:diag(string.format("%-35s: %.2f calls/s", testname, cnt/(stop-start) ))
end

local conn = require('net.box').connect(box.cfg.listen)

test:diag('Errors perftest')

test:diag('')
test:diag(' Wrap pcall')
local E = errors.new_class('E')

test:diag('  return true')
local function f() return true end
perftest('  - native pcall', pcall, f)
perftest('  - errors.pcall', errors.pcall, 'E', f)
perftest('  -      E:pcall', E.pcall, E, f)

test:diag('  raise error')
local function f() error('Artificial error', 0) end
perftest('  - native pcall', pcall, f)
perftest('  - errors.pcall', errors.pcall, 'E', f)
perftest('  -      E:pcall', E.pcall, E, f)

test:diag('')
test:diag(' Wrap netbox calls')

test:diag('  return true')
function _G.f() return 1 end
perftest('  - netbox', conn.call, conn, 'f')
perftest('  - errors', errors.netbox_call, conn, 'f')

test:diag('  return multiret')
function _G.f() return 1, nil, 2, nil, 3, nil end
perftest('  - netbox', conn.call, conn, 'f')
perftest('  - errors', errors.netbox_call, conn, 'f')

test:diag('  return nil, err')
local err = errors.new('TestError', 'Artificial error')
function _G.f() return nil, err end
perftest('  - netbox', conn.call, conn, 'f')
perftest('  - errors', errors.netbox_call, conn, 'f')

test:diag('  throw error')
function _G.f() error('Artificial error', 0) end
perftest('  - netbox', pcall, conn.call, conn, 'f')
perftest('  - errors', errors.netbox_call, conn, 'f')

os.exit(0)
