version := scm-1
rock_name := errors

.PHONY: all doc
.SILENT:

LDOC := $(shell command -v ldoc 2> /dev/null)

ifdef LDOC
    ALL_TARGETS += doc
else
    $(info "ldoc is not found. Skipping doc build")
    ALL_TARGETS += .SILENT
endif


all: $(ALL_TARGETS)

doc:
	mkdir -p doc
	ldoc -t "${rock_name}-${version}" -p "${rock_name} (${version})" --all .
