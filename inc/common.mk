# inc/common.mk -- Shared Make configuration, included by the top-level Makefile.
# inc/ contains Makefile include fragments. It is not a subproject.

# Use absolute path to mks-bash (Make SHELL doesn't support /usr/bin/env)
SHELL        := $(CURDIR)/vendor/bin/mks-bash
.SHELLFLAGS  := -e -c
.ONESHELL:
.DELETE_ON_ERROR:
.DEFAULT_GOAL := help

.PHONY: help
help:
	@$(CURDIR)/inc/make-help $(MAKEFILE_LIST)
