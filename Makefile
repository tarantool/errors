.PHONY: all

LDOC := $(shell which ldoc)
all:
ifdef LDOC
	ldoc .
endif
