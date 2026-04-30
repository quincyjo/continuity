-- spec/sysinfo_net_ipmonitor_spec.lua
require("spec.support.awesome_mocks")

describe("net.backends.ipmonitor", function()
	local ipmonitor, awful, gears_mod
	local wlc_cbs, easy_cmds, kill_called

	local function find_timer(timeout)
		for _, t in ipairs(gears_mod._created) do
			if t._opts.timeout == timeout then
				return t
			end
		end
	end

	before_each(function()
		package.loaded["continuity.sysinfo.net.backends.ipmonitor"] = nil
		kill_called = false
		wlc_cbs = nil
		easy_cmds = {}
		awful = require("awful")
		gears_mod = require("gears")
		gears_mod._created = {}
		awful.spawn.with_line_callback = function(_cmd, cbs)
			wlc_cbs = cbs
			return 12345
		end
		awesome.kill = function(_pid, _sig)
			kill_called = true
		end
		awful.spawn.easy_async = function(cmd, cb)
			easy_cmds[#easy_cmds + 1] = { cmd = cmd, cb = cb }
		end
		ipmonitor = require("continuity.sysinfo.net.backends.ipmonitor")
	end)

	local IP_LINK_OUTPUT = table.concat({
		"1: lo: <LOOPBACK,UP,LOWER_UP> mtu 65536 state UNKNOWN",
		"    link/loopback 00:00:00:00:00:00",
		"2: eth0: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 state UP",
		"    link/ether aa:bb:cc:dd:ee:ff brd ff:ff:ff:ff:ff:ff",
		"3: wlan0: <BROADCAST,MULTICAST> mtu 1500 state DOWN",
		"    link/ether 11:22:33:44:55:66 brd ff:ff:ff:ff:ff:ff",
		"wifi:wlan0",
	}, "\n") .. "\n"

	local STATS_OUTPUT = table.concat({
		"dev:eth0:tx:1000000",
		"dev:eth0:rx:2000000",
		"dev:eth0:state:up",
		"dev:eth0:carrier:1",
		"dev:eth0:wifi:0",
		"dev:wlan0:tx:500000",
		"dev:wlan0:rx:800000",
		"dev:wlan0:state:up",
		"dev:wlan0:carrier:1",
		"dev:wlan0:wifi:1",
		"dev:wlan0:signal:-62",
	}, "\n") .. "\n"

	describe("_parse_ip_link_line", function()
		it("parses an UP interface line", function()
			local r = ipmonitor._parse_ip_link_line("2: eth0: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 state UP")
			assert.equals("eth0", r.name)
			assert.equals("up", r.state)
			assert.is_true(r.carrier)
			assert.is_false(r.deleted)
		end)

		it("parses a DOWN interface line", function()
			local r = ipmonitor._parse_ip_link_line("3: wlan0: <BROADCAST,MULTICAST> mtu 1500 state DOWN")
			assert.equals("wlan0", r.name)
			assert.equals("down", r.state)
			assert.is_false(r.carrier)
		end)

		it("parses a Deleted line", function()
			local r = ipmonitor._parse_ip_link_line("Deleted 3: wlan0: <BROADCAST,MULTICAST> mtu 1500 state DOWN")
			assert.equals("wlan0", r.name)
			assert.is_true(r.deleted)
		end)

		it("returns nil for link-layer lines (indented)", function()
			local r = ipmonitor._parse_ip_link_line("    link/ether aa:bb:cc:dd:ee:ff brd ff:ff:ff:ff:ff:ff")
			assert.is_nil(r)
		end)

		it("strips @ifN suffix from interface name", function()
			local r = ipmonitor._parse_ip_link_line("5: eth0@if2: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 state UP")
			assert.equals("eth0", r.name)
		end)

		it("excludes loopback interfaces", function()
			local r = ipmonitor._parse_ip_link_line("1: lo: <LOOPBACK,UP,LOWER_UP> mtu 65536 state UNKNOWN")
			assert.is_nil(r)
		end)
	end)

	describe("_parse_stats_output", function()
		it("parses tx/rx bytes per device", function()
			local devs = ipmonitor._parse_stats_output(STATS_OUTPUT)
			assert.equals(1000000, devs["eth0"].tx_bytes)
			assert.equals(2000000, devs["eth0"].rx_bytes)
		end)

		it("marks wifi devices", function()
			local devs = ipmonitor._parse_stats_output(STATS_OUTPUT)
			assert.is_false(devs["eth0"].wifi)
			assert.is_true(devs["wlan0"].wifi)
		end)

		it("parses state and carrier", function()
			local devs = ipmonitor._parse_stats_output(STATS_OUTPUT)
			assert.equals("up", devs["eth0"].state)
			assert.is_true(devs["eth0"].carrier)
		end)

		it("parses wifi signal level in dBm", function()
			local devs = ipmonitor._parse_stats_output(STATS_OUTPUT)
			assert.equals(-62, devs["wlan0"].signal)
			assert.is_nil(devs["eth0"].signal)
		end)

		it("stores nil for signal value 0 (not associated sentinel)", function()
			local out = STATS_OUTPUT .. "dev:wlan0:signal:0\n"
			local devs = ipmonitor._parse_stats_output(out)
			assert.is_nil(devs["wlan0"].signal)
		end)
	end)

	it("starts ip link discovery and ip monitor on start", function()
		local b = ipmonitor({ interval = 2 })
		b:start(function() end)
		assert.equals(1, #easy_cmds)
		easy_cmds[1].cb(IP_LINK_OUTPUT, "", "", 0)
		assert.is_not_nil(wlc_cbs)
	end)

	it("calls on_update immediately after ip link discovery with zero rates", function()
		local updates = {}
		local b = ipmonitor({ interval = 2 })
		b:start(function(s)
			updates[#updates + 1] = s
		end)
		easy_cmds[1].cb(IP_LINK_OUTPUT, "", "", 0)
		assert.equals(1, #updates)
		assert.equals(0, updates[1].devices["eth0"].tx_rate)
		assert.equals(0, updates[1].devices["eth0"].rx_rate)
	end)

	it("sets wifi=true for wifi interfaces on eager dispatch", function()
		local updates = {}
		local b = ipmonitor({ interval = 2 })
		b:start(function(s)
			updates[#updates + 1] = s
		end)
		easy_cmds[1].cb(IP_LINK_OUTPUT, "", "", 0)
		assert.is_false(updates[1].devices["eth0"].wifi)
		assert.is_true(updates[1].devices["wlan0"].wifi)
	end)

	it("creates rate-sampling timer after discovery", function()
		local b = ipmonitor({ interval = 2 })
		b:start(function() end)
		easy_cmds[1].cb(IP_LINK_OUTPUT, "", "", 0)
		assert.is_not_nil(find_timer(2))
	end)

	it("rate timer tick triggers stats read", function()
		local b = ipmonitor({ interval = 2 })
		b:start(function() end)
		easy_cmds[1].cb(IP_LINK_OUTPUT, "", "", 0)
		local before = #easy_cmds
		find_timer(2):fire()
		assert.equals(before + 1, #easy_cmds)
	end)

	it("computes zero tx_rate and rx_rate when byte counts unchanged", function()
		local updates = {}
		local b = ipmonitor({ interval = 2 })
		b:start(function(s)
			updates[#updates + 1] = s
		end)
		easy_cmds[1].cb(IP_LINK_OUTPUT, "", "", 0) -- eager dispatch (#1)
		local rate_timer = find_timer(2)
		rate_timer:fire()
		easy_cmds[#easy_cmds].cb(STATS_OUTPUT, "", "", 0) -- tick 1 (#2)
		rate_timer:fire()
		easy_cmds[#easy_cmds].cb(STATS_OUTPUT, "", "", 0) -- tick 2 (#3)
		assert.equals(3, #updates)
		assert.equals(0, updates[3].tx_rate)
		assert.equals(0, updates[3].rx_rate)
	end)

	it("computes non-zero tx_rate and rx_rate from increasing byte counts", function()
		local updates = {}
		local fake_time = 1000
		local real_time = os.time
		os.time = function()
			return fake_time
		end

		local b = ipmonitor({ interval = 2 })
		b:start(function(s)
			updates[#updates + 1] = s
		end)
		easy_cmds[1].cb(IP_LINK_OUTPUT, "", "", 0)
		local rate_timer = find_timer(2)

		-- First tick: establishes prev_bytes baseline (dispatches with zero rates)
		rate_timer:fire()
		easy_cmds[#easy_cmds].cb(STATS_OUTPUT, "", "", 0)

		-- Advance time by 2 seconds, increase eth0 tx by 2000, rx by 4000
		fake_time = 1002
		local STATS_OUTPUT_2 = table.concat({
			"dev:eth0:tx:1002000",
			"dev:eth0:rx:2004000",
			"dev:eth0:state:up",
			"dev:eth0:carrier:1",
			"dev:eth0:wifi:0",
			"dev:wlan0:tx:500000",
			"dev:wlan0:rx:800000",
			"dev:wlan0:state:up",
			"dev:wlan0:carrier:1",
			"dev:wlan0:wifi:1",
		}, "\n") .. "\n"

		rate_timer:fire()
		easy_cmds[#easy_cmds].cb(STATS_OUTPUT_2, "", "", 0)

		os.time = real_time

		-- updates: #1 eager, #2 tick-1 (zero rates), #3 tick-2 (computed rates)
		assert.equals(3, #updates)
		-- eth0: 2000 bytes / 2 seconds = 1000 bytes/sec tx, 2000 bytes/sec rx
		assert.equals(1000, updates[3].devices["eth0"].tx_rate)
		assert.equals(2000, updates[3].devices["eth0"].rx_rate)
	end)

	it("ip monitor link event triggers immediate stats read", function()
		local b = ipmonitor({ interval = 2 })
		b:start(function() end)
		easy_cmds[1].cb(IP_LINK_OUTPUT, "", "", 0)
		local before = #easy_cmds
		wlc_cbs.stdout("2: eth0: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 state UP")
		assert.equals(before + 1, #easy_cmds)
	end)

	it("stop() kills the monitor and stops the timer", function()
		local b = ipmonitor({ interval = 2 })
		b:start(function() end)
		easy_cmds[1].cb(IP_LINK_OUTPUT, "", "", 0)
		b:stop()
		assert.is_true(kill_called)
		assert.is_true(find_timer(2).stopped)
	end)

	it("monitor exit schedules retry", function()
		local b = ipmonitor({ interval = 2 })
		b:start(function() end)
		easy_cmds[1].cb(IP_LINK_OUTPUT, "", "", 0)
		wlc_cbs.exit()
		assert.is_not_nil(find_timer(10))
	end)

	it("stop() prevents exit callback from scheduling a retry", function()
		local b = ipmonitor({ interval = 2 })
		b:start(function() end)
		easy_cmds[1].cb(IP_LINK_OUTPUT, "", "", 0)
		b:stop()
		wlc_cbs.exit()
		assert.is_nil(find_timer(10))
	end)

	it("retry timer restarts the monitor process", function()
		local spawn_count = 0
		awful.spawn.with_line_callback = function(_cmd, cbs)
			spawn_count = spawn_count + 1
			wlc_cbs = cbs
			return spawn_count * 100
		end
		local b = ipmonitor({ interval = 2 })
		b:start(function() end)
		easy_cmds[1].cb(IP_LINK_OUTPUT, "", "", 0)
		wlc_cbs.exit()
		find_timer(10):fire()
		assert.equals(2, spawn_count)
	end)
end)
