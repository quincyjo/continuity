-- spec/sysinfo_mem_procmeminfo_spec.lua
require("spec.support.awesome_mocks")

describe("mem.backends.procmeminfo", function()
	local procmeminfo, awful, gears_mod
	local captured_cbs, kill_called

	before_each(function()
		package.loaded["continuity.sysinfo.mem.backends.procmeminfo"] = nil
		kill_called = false
		captured_cbs = nil
		awful = require("awful")
		gears_mod = require("gears")
		gears_mod._created = {}
		awful.spawn.with_line_callback = function(cmd, cbs)
			captured_cbs = cbs
			return 12345
		end
		awesome.kill = function(pid, sig)
			kill_called = true
		end
		procmeminfo = require("continuity.sysinfo.mem.backends.procmeminfo")
	end)

	local MEMINFO_LINES = {
		"MemTotal:       16000000 kB",
		"MemFree:         4000000 kB",
		"MemAvailable:    8000000 kB",
		"Buffers:          500000 kB",
		"Cached:          2000000 kB",
		"SwapTotal:       2097148 kB",
		"SwapFree:        2000000 kB",
		"SReclaimable:     300000 kB",
	}

	describe("_parse_meminfo_lines", function()
		it("computes used = total - MemAvailable", function()
			local s = procmeminfo._parse_meminfo_lines(MEMINFO_LINES)
			local expected_total = math.floor(16000000 / 1024 + 0.5)
			local expected_avail = math.floor(8000000 / 1024 + 0.5)
			assert.equals(expected_total, s.total)
			assert.equals(expected_total - expected_avail, s.used)
			assert.equals(math.floor(4000000 / 1024 + 0.5), s.free)
			assert.equals(math.floor(500000 / 1024 + 0.5), s.buffers)
			assert.equals(math.floor(2000000 / 1024 + 0.5), s.cached)
		end)

		it("computes perc as used/total*100", function()
			local s = procmeminfo._parse_meminfo_lines(MEMINFO_LINES)
			assert.equals(49.996800000000000352, s.perc)
		end)

		it("computes swap_used = swap_total - swap_free", function()
			local s = procmeminfo._parse_meminfo_lines(MEMINFO_LINES)
			assert.equals(s.swap_total - s.swap_free, s.swap_used)
		end)
	end)

	it("spawns process on start", function()
		local b = procmeminfo({ interval = 5 })
		b:start(function() end)
		assert.is_not_nil(captured_cbs)
	end)

	it("calls on_update with MemState when batch completes", function()
		local updates = {}
		local b = procmeminfo({ interval = 5 })
		b:start(function(s)
			updates[#updates + 1] = s
		end)
		for _, l in ipairs(MEMINFO_LINES) do
			captured_cbs.stdout(l)
		end
		captured_cbs.stdout("---")
		assert.equals(1, #updates)
		assert.is_number(updates[1].total)
		assert.is_number(updates[1].used)
		assert.is_number(updates[1].perc)
	end)

	it("stop() kills the process", function()
		local b = procmeminfo({ interval = 5 })
		b:start(function() end)
		b:stop()
		assert.is_true(kill_called)
	end)

	it("process exit schedules retry timer", function()
		local b = procmeminfo({ interval = 5 })
		b:start(function() end)
		captured_cbs.exit()
		assert.equals(1, #gears_mod._created)
	end)

	it("stop() prevents exit callback from scheduling a retry", function()
		local b = procmeminfo({ interval = 5 })
		b:start(function() end)
		b:stop()
		captured_cbs.exit()
		assert.equals(0, #gears_mod._created)
	end)

	it("retry timer restarts the process", function()
		local spawn_count = 0
		awful.spawn.with_line_callback = function(cmd, cbs)
			spawn_count = spawn_count + 1
			captured_cbs = cbs
			return spawn_count * 100
		end
		local b = procmeminfo({ interval = 5 })
		b:start(function() end)
		captured_cbs.exit()
		gears_mod._created[1]:fire()
		assert.equals(2, spawn_count)
	end)
end)
