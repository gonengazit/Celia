.PHONY: run all lint build clean format test web run_build

project_name := celia

run:
	@love . --test

all: format lint test build

# run specific love version
# setup environment variable with path to love executable first

lint:
	luacheck .

format:
	sed -i s/0x1234\.abcd/0x1234abcd/g test.lua
	stylua .
	sed -i s/0x1234abcd/0x1234\.abcd/g test.lua

clean:
	rm -rf build/*

test:
	# todo implement test running

build: clean
	@echo "building \"build/${project_name}.love\" ..."
	# include .lua, .p8, and .png files (needed for icon and font)
	# exclude tests
	find . \( -name '*.lua' -or -name '*.png' -or -name '*.p8' \) \
		-not -path '*test/*' \
		-print0 \
		| cut -z -c3- \
		| xargs -0 zip -9 build/${project_name}.love

web: build
	@command -v love.js \
		&& love.js -c -t ${project_name} build/${project_name}.love build/__site/ \
		|| ( echo "love.js not found in PATH"; exit 1 )
	cp -f res/index.html build/__site/index.html
	cp -f -r res/theme/ build/__site/
	cd build/__site/ && node ../../Love.js-Api-Player/globalizeFS.js

run_build:
	@echo "executing \"build/${project_name}.love\" ..."
	@love build/${project_name}.love
