[![pipeline status](https://gitlab.com/tarantool/enterprise/errors/badges/master/pipeline.svg)](https://gitlab.com/tarantool/enterprise/errors/commits/master)

# Convenient error handling in tarantool

Because Lua code deserves better error handling. This module helps you
understand what code path lead to creation of a particular exception
object.

## Example

```lua
local errors = require 'errors'

local WTF = errors.new_class("WhataTerribleFailure")

local function foo()
    local failure_condition = true
    local result = "bar"

    if failure_condition then
        return nil, WTF:new("failure_condition is true")
    end

    return result
end

local res, err = foo()

if err ~= nil then
    print(err)
end
```

This code will print:

```lua
WhataTerribleFailure: failure_condition is true
stack traceback:
    test.lua:10: in function 'foo'
    test.lua:16: in main chunk
```

See that you have an exception type, message and traceback recorded
inside the exception object. It can be converted to string using the
`tostring()` function.
