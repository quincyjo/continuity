.PHONY: test test-luajit test-all lint fmt-check

test:
	busted

test-luajit:
	busted --run=luajit

test-all:
	busted && busted --run=luajit

lint:
	luacheck .

fmt-check:
	stylua . --check
