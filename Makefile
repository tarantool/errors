version := scm-1

.PHONY: all doc
all:
	mkdir -p doc

doc:
	ldoc -t "errors-${version}" -p "errors (${version})" --all .
