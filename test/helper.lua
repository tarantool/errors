local fiber = require('fiber')

local function get_line()
    return debug.getinfo(2, 'l').currentline
end

local function fiber_csw()
    return fiber.info()[fiber.id()].csw
end

local function check_error(got, expected, subtest_name)
    local err_msg = ''
    local pattern = table.concat({
        'Unexpected %s',
        '     got: %s (%s)',
        'expected: %s (%s)',
        '', ''
    }, '\n')

    if expected.file and expected.file ~= got.file then
        err_msg = err_msg .. pattern:format('file',
            got.file, type(got.file),
            expected.file, type(expected.file)
        )
    end

    if expected.line and expected.line ~= got.line then
        err_msg = err_msg .. pattern:format('line',
            got.line, type(got.line),
            expected.line, type(expected.line)
        )
    end

    if got.err ~= expected.err then
        err_msg =  err_msg .. pattern:format('err',
            got.err, type(got.err),
            expected.err, type(expected.err)
        )
    end

    local err_str = tostring(got)
    if err_str:match(expected.str) == nil then
        err_msg =  err_msg .. pattern:format('tostring()',
            err_str, type(err_str),
            expected.str, type(expected.str)
        )
    end

    if tostring(got) ~= got:tostring() then
        err_msg =  err_msg .. pattern:format('tostring()',
            tostring(got), '',
            got:tostring(), ''
        )
    end

    if #err_msg ~= 0 then
        err_msg = '\n' .. err_msg
        if subtest_name then
            err_msg = ('subtest %q:%s'):format(subtest_name, err_msg)
        end
        error(err_msg, 2)
    end
end

return {
    check_error = check_error,
    get_line = get_line,
    fiber_csw = fiber_csw
}
