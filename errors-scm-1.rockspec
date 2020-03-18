package = 'errors'
version = 'scm-1'
source = {
    url = 'git+https://github.com/tarantool/errors.git',
    branch = 'master',
}

description = {
    summary = 'Convenient error handling in tarantool',
    homepage = 'https://github.com/tarantool/errors',
    license = 'BSD',
}

dependencies = {
    'lua >= 5.1',
}

build = {
    type = 'cmake',
    build_target = 'all',
    variables = {
        version = 'scm-1',
        TARANTOOL_DIR = '$(TARANTOOL_DIR)',
        TARANTOOL_INSTALL_LIBDIR = '$(LIBDIR)',
        TARANTOOL_INSTALL_LUADIR = '$(LUADIR)',
    },
    copy_directories = {'doc'},
}

