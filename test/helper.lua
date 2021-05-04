local function get_line()
    return debug.getinfo(2, 'l').currentline
end

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
}
