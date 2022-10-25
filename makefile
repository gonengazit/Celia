.PHONY: run all lint build clean format test

project_name := "Celia"

run:
	@love . --test

all: format lint test build

# run specific love version
# setup environment variable with path to love executable first

lint:
	luacheck .

format:
	@sed -i s/0x1234\.abcd/0x1234abcd/g test.lua
	stylua .
	@sed -i s/0x1234abcd/0x1234\.abcd/g test.lua

clean:
	@echo "deleting \"build/${project_name}.love\" ..."
	@rm -f build/${project_name}.love

test:
	# todo implement test running

build: clean
	@echo "building \"build/${project_name}.love\" ..."
	@zip -9 -r build/"${project_name}".love ./nocart.p8
	@zip -9 -r -x@excludelist.txt build/${project_name}.love .

run_build:
	@echo "executing \"build/${project_name}.love\" ..."
	@love build/${project_name}.love
