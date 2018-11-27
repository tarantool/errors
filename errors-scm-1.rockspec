package = 'errors'
version = 'scm-1'
source = {
    url = 'git+ssh://git@gitlab.com/tarantool/enterprise/errors.git',
    branch = 'master',
}

description = {
    summary = 'Convenient error handling in tarantool',
    homepage = 'https://gitlab.com/tarantool/enterprise/errors',
    license = 'BSD',
}

dependencies = {
    'lua >= 5.1',
    'checks == 3.0.0-1',
}

build = {
    type = 'make',
    modules = {
        ['errors'] = 'errors.lua',
    },
}

