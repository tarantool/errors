local fiber = require('fiber')

local function get_line()
    return debug.getinfo(2, 'l').currentline
end

local function fiber_csw()
    return fiber.info()[fiber.id()].csw
end

local function check_error(actual, expected, subtest_name)
    local err_msg = ''
    local pattern = table.concat({
        'Unexpected %s',
        'expected: %s (%s)',
        '  actual: %s (%s)',
        ''
    }, '\n')

    if expected.file and expected.file ~= actual.file then
        err_msg = err_msg .. pattern:format('file',
            expected.file, type(expected.file),
            actual.file, type(actual.file)
        )
    end

    if expected.line and expected.line ~= actual.line then
        err_msg = err_msg .. pattern:format('line',
            expected.line, type(expected.line),
            actual.line, type(actual.line)
        )
    end

    if actual.err ~= expected.err then
        err_msg =  err_msg .. pattern:format('err',
            expected.err, type(expected.err),
            actual.err, type(actual.err)
        )
    end

    local err_str = tostring(actual)
    if err_str:match(expected.str) == nil then
        err_msg =  err_msg .. pattern:format('tostring()',
            expected.str, type(expected.str),
            err_str, type(err_str)
        )
    end

    if tostring(actual) ~= actual:tostring() then
        err_msg =  err_msg .. pattern:format('tostring()',
            actual:tostring(), '',
            tostring(actual), ''
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
