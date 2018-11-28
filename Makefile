.PHONY: all install

LDOC := $(shell which ldoc)
all:
ifdef LDOC
	ldoc .
endif

install: ;
