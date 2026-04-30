-- spec/sysinfo_cpu_procstat_spec.lua
require("spec.support.awesome_mocks")

describe("cpu.backends.procstat", function()
	local procstat, awful, gears_mod
	local captured_cbs, kill_called

	before_each(function()
		package.loaded["continuity.sysinfo.cpu.backends.procstat"] = nil
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
		procstat = require("continuity.sysinfo.cpu.backends.procstat")
	end)

	-- Feed a complete batch of /proc/stat lines followed by delimiter.
	local function feed(lines)
		for _, l in ipairs(lines) do
			captured_cbs.stdout(l)
		end
		captured_cbs.stdout("---")
	end

	local SNAP1 = {
		"cpu  500 100 200 8000 50 10 10 0 0 0",
		"cpu0 250  50 100 4000 25  5  5 0 0 0",
		"cpu1 250  50 100 4000 25  5  5 0 0 0",
	}
	local SNAP2 = {
		-- delta per field: user+100, nice+0, system+100, idle+400, iowait+0, irq+0, softirq+0, steal+0
		-- dtotal=600, didle=400 -> usage=200/600≈33.3%
		"cpu  600 100 300 8400 50 10 10 0 0 0",
		"cpu0 300  50 150 4200 25  5  5 0 0 0",
		"cpu1 300  50 150 4200 25  5  5 0 0 0",
	}

	describe("_parse_stat_line", function()
		it("parses aggregate cpu line", function()
			local name, f = procstat._parse_stat_line("cpu  100 20 50 800 10 5 5 2 0 0")
			assert.equals("cpu", name)
			assert.equals(100, f.user)
			assert.equals(50, f.system)
			assert.equals(800, f.idle)
			assert.equals(10, f.iowait)
			assert.equals(2, f.steal)
		end)

		it("parses per-core cpu line", function()
			local name, f = procstat._parse_stat_line("cpu3 50 0 25 400 5 0 0 0 0 0")
			assert.equals("cpu3", name)
			assert.equals(50, f.user)
		end)

		it("returns nil for non-cpu lines", function()
			local name = procstat._parse_stat_line("intr 12345 0 1 2")
			assert.is_nil(name)
		end)
	end)

	describe("_compute_usage", function()
		it("computes usage % from two snapshots", function()
			local a =
				{ user = 500, nice = 0, system = 200, idle = 8000, iowait = 50, irq = 10, softirq = 10, steal = 0 }
			local b =
				{ user = 600, nice = 0, system = 300, idle = 8400, iowait = 50, irq = 10, softirq = 10, steal = 0 }
			-- dtotal=600, didle=400, active=200 -> usage≈33.3
			local usage = procstat._compute_usage(a, b)
			assert.is_near(33.3, usage, 0.5)
		end)

		it("returns 0 usage when dtotal is 0", function()
			local snap = { user = 100, nice = 0, system = 50, idle = 800, iowait = 10, irq = 5, softirq = 5, steal = 0 }
			local usage = procstat._compute_usage(snap, snap)
			assert.equals(0, usage)
		end)
	end)

	it("spawns a process on start", function()
		local b = procstat({ interval = 2 })
		b:start(function() end)
		assert.is_not_nil(captured_cbs)
	end)

	it("calls on_update on first batch with cumulative-since-boot usage", function()
		local updates = {}
		local b = procstat({ interval = 2 })
		b:start(function(s)
			updates[#updates + 1] = s
		end)
		feed(SNAP1)
		assert.equals(1, #updates)
		assert.is_number(updates[1].usage)
		assert.equals(0, #updates[1].cores) -- no per-core prev yet
	end)

	it("calls on_update with CpuState on second batch", function()
		local updates = {}
		local b = procstat({ interval = 2 })
		b:start(function(s)
			updates[#updates + 1] = s
		end)
		feed(SNAP1)
		feed(SNAP2)
		assert.equals(2, #updates)
		local s = updates[2]
		assert.is_number(s.usage)
		assert.is_number(s.user)
		assert.is_number(s.system)
		assert.is_number(s.idle)
		assert.is_number(s.iowait)
		assert.is_number(s.steal)
		assert.equals(2, #s.cores)
	end)

	it("per-core usage is populated from second batch onward", function()
		local updates = {}
		local b = procstat({ interval = 2 })
		b:start(function(s)
			updates[#updates + 1] = s
		end)
		feed(SNAP1)
		feed(SNAP2)
		assert.is_number(updates[2].cores[1].usage)
		assert.is_number(updates[2].cores[2].usage)
	end)

	it("stop() kills the spawned process", function()
		local b = procstat({ interval = 2 })
		b:start(function() end)
		b:stop()
		assert.is_true(kill_called)
	end)

	it("process exit schedules a retry timer", function()
		local b = procstat({ interval = 2 })
		b:start(function() end)
		captured_cbs.exit()
		assert.equals(1, #gears_mod._created)
		assert.equals(10, gears_mod._created[1]._opts.timeout)
	end)

	it("retry timer restarts the process", function()
		local spawn_count = 0
		awful.spawn.with_line_callback = function(cmd, cbs)
			spawn_count = spawn_count + 1
			captured_cbs = cbs
			return spawn_count * 100
		end
		local b = procstat({ interval = 2 })
		b:start(function() end)
		captured_cbs.exit()
		gears_mod._created[1]:fire()
		assert.equals(2, spawn_count)
	end)

	it("stop() prevents exit callback from scheduling a retry", function()
		local b = procstat({ interval = 2 })
		b:start(function() end)
		b:stop()
		captured_cbs.exit()
		assert.equals(0, #gears_mod._created)
	end)
end)
