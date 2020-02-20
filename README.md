# Convenient error handling in tarantool

Because Lua code deserves better error handling. This module helps you
understand what code path lead to creation of a particular exception
object.

## Example

```lua
errors = require('errors')

DoSomethingError = errors.new_class("DoSomethingError")

function do_something()
    local failure_condition = true
    local result = "bar"

    if failure_condition then
        return nil, DoSomethingError:new("failure_condition is true")
    end

    return result
end

res, err = do_something()

if err ~= nil then
    print(err)
end
```

This code will print:

```console
DoSomethingError: failure_condition is true
stack traceback:
    test.lua:10: in function 'do_something'
    test.lua:16: in main chunk
```

See that you have an exception type, message and traceback recorded
inside the exception object. It can be converted to string using the
`tostring()` function.

## Uniform error handling

The module praises uniform error handling and provides `pcall` API,
which unifies return values:

```console
> print( DoSomethingError:pcall(do_something) )
nil     DoSomethingError: failure_condition is true
stack traceback:
    test.lua:10: in function 'do_something'
    test.lua:16: in main chunk

> print( DoSomethingError:pcall(error, 'some functions still raise') )
nil     DoSomethingError: some functions still raise
stack traceback:
        [C]: in function 'xpcall'
        /opt/errors/errors.lua:139: in function 'pcall'
        [string "return print( DoSomethingEr"]:1: in main chunk
```

In both cases `pcall` returns the same pattern `nil, err`.

If there were no error raised, `pcall` doesn't modify any return values:

```console
> print( DoSomethingError:pcall(function() return nil, "foo", "bar" end) )
nil     foo     bar
```

## Uniform API for net.box stuff

It may be tricky to debug errors, when they arise on a remote host:
`net.box` throws an exception and doesn't keep stack trace from the remote.

To simplify debugging in this case use `return nil, err` pattern with
conjunction of `errors.netbox_eval` or `netbox_call`. It'll collect
stacktrace from both local and remote hosts and restore metatables
(which can't be transfed over network).

```console
> conn = require('net.box').connect('localhost:3301')
> print( errors.netbox_eval(conn, 'return nil, DoSomethingError:new("oops")') )
nil     DoSomethingError: oops
stack traceback:
        eval:1: in main chunk
during net.box eval on localhost:3301
stack traceback:
        [string "return print( errors.netbox_eval("]:1: in main chunk
        [C]: in function 'pcall'
```

## Naming conventions

* Error class should be named in `CamelCase`.
* Error class should end with suffix `Error`.
* See examples: `ReadFileError`, `DecodeYamlError`, `CheckSchemaError`.
