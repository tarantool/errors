version := scm-1

.PHONY: all doc test
all:
	mkdir -p doc

doc:
	ldoc -t "errors-${version}" -p "errors (${version})" --all .

test:
	tarantool taptest.lua

coverage: test
	luacov-coveralls -v
