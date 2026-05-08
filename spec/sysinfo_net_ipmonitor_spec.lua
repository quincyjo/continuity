-- spec/sysinfo_net_ipmonitor_spec.lua
require("spec.support.awesome_mocks")

describe("net.backends.ipmonitor", function()
	local ipmonitor, awful, gears_mod
	local wlc_calls, easy_cmds, kill_count

	local function find_timer(timeout)
		for _, t in ipairs(gears_mod._created) do
			if t._opts.timeout == timeout then
				return t
			end
		end
	end

	before_each(function()
		package.loaded["continuity.sysinfo.net.backends.ipmonitor"] = nil
		kill_count = 0
		wlc_calls = {}
		easy_cmds = {}
		awful = require("awful")
		gears_mod = require("gears")
		gears_mod._created = {}
		awful.spawn.with_line_callback = function(cmd, cbs)
			wlc_calls[#wlc_calls + 1] = { cmd = cmd, cbs = cbs }
			return #wlc_calls * 100
		end
		awesome.kill = function(_pid, _sig)
			kill_count = kill_count + 1
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

	describe("_parse_proc_net_dev_line", function()
		it("parses a valid stat line into name, rx_bytes, tx_bytes", function()
			local r = ipmonitor._parse_proc_net_dev_line("eth0 2000000 1000000")
			assert.equals("eth0", r.name)
			assert.equals(2000000, r.rx_bytes)
			assert.equals(1000000, r.tx_bytes)
		end)

		it("returns nil for empty line", function()
			assert.is_nil(ipmonitor._parse_proc_net_dev_line(""))
		end)

		it("returns nil for lines with non-numeric byte fields", function()
			assert.is_nil(ipmonitor._parse_proc_net_dev_line("sig wlan0 -62"))
		end)

		it("returns nil for lines with missing fields", function()
			assert.is_nil(ipmonitor._parse_proc_net_dev_line("eth0 2000000"))
		end)
	end)

	it("starts ip link discovery on start", function()
		local b = ipmonitor({ interval = 2 })
		b:start(function() end)
		assert.equals(1, #easy_cmds)
	end)

	it("starts both processes after discovery completes", function()
		local b = ipmonitor({ interval = 2 })
		b:start(function() end)
		easy_cmds[1].cb(IP_LINK_OUTPUT, "", "", 0)
		assert.equals(2, #wlc_calls)
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

	it("ip monitor link event triggers on_update with updated device state", function()
		local updates = {}
		local b = ipmonitor({ interval = 2 })
		b:start(function(s)
			updates[#updates + 1] = s
		end)
		easy_cmds[1].cb(IP_LINK_OUTPUT, "", "", 0)
		wlc_calls[1].cbs.stdout("3: wlan0: <BROADCAST,MULTICAST> mtu 1500 state DOWN")
		local last = updates[#updates]
		assert.equals("down", last.devices["wlan0"].state)
	end)

	it("deleted device is removed from state on ip monitor Deleted event", function()
		local updates = {}
		local b = ipmonitor({ interval = 2 })
		b:start(function(s)
			updates[#updates + 1] = s
		end)
		easy_cmds[1].cb(IP_LINK_OUTPUT, "", "", 0)
		wlc_calls[1].cbs.stdout("Deleted 2: eth0: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 state UP")
		local last = updates[#updates]
		assert.is_nil(last.devices["eth0"])
	end)

	it("stats process stdout triggers on_update with zero rates on first tick", function()
		local updates = {}
		local b = ipmonitor({ interval = 2 })
		b:start(function(s)
			updates[#updates + 1] = s
		end)
		easy_cmds[1].cb(IP_LINK_OUTPUT, "", "", 0)
		wlc_calls[2].cbs.stdout("eth0 2000000 1000000")
		local last = updates[#updates]
		assert.equals(0, last.devices["eth0"].tx_rate)
		assert.equals(0, last.devices["eth0"].rx_rate)
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

		-- Tick 1: establish prev_bytes baseline (zero rates)
		wlc_calls[2].cbs.stdout("eth0 2000000 1000000")

		-- Advance time by 2 seconds; eth0 tx +2000, rx +4000
		fake_time = 1002
		wlc_calls[2].cbs.stdout("eth0 2004000 1002000")

		os.time = real_time

		local last = updates[#updates]
		assert.equals(1000, last.devices["eth0"].tx_rate)
		assert.equals(2000, last.devices["eth0"].rx_rate)
	end)

	it("computes zero tx_rate and rx_rate when byte counts unchanged", function()
		local updates = {}
		local b = ipmonitor({ interval = 2 })
		b:start(function(s)
			updates[#updates + 1] = s
		end)
		easy_cmds[1].cb(IP_LINK_OUTPUT, "", "", 0)
		wlc_calls[2].cbs.stdout("eth0 2000000 1000000")
		wlc_calls[2].cbs.stdout("eth0 2000000 1000000")
		local last = updates[#updates]
		assert.equals(0, last.devices["eth0"].tx_rate)
		assert.equals(0, last.devices["eth0"].rx_rate)
	end)

	it("stats process silently ignores interfaces not in the device table", function()
		local updates = {}
		local b = ipmonitor({ interval = 2 })
		b:start(function(s)
			updates[#updates + 1] = s
		end)
		easy_cmds[1].cb(IP_LINK_OUTPUT, "", "", 0)
		local count_before = #updates
		wlc_calls[2].cbs.stdout("lo 69090840 69090840")
		wlc_calls[2].cbs.stdout("virbr0 0 0")
		assert.equals(count_before, #updates)
	end)

	it("signal line updates device.signal incorporated in next stat on_update", function()
		local updates = {}
		local b = ipmonitor({ interval = 2 })
		b:start(function(s)
			updates[#updates + 1] = s
		end)
		easy_cmds[1].cb(IP_LINK_OUTPUT, "", "", 0)
		wlc_calls[2].cbs.stdout("sig wlan0 -62")
		wlc_calls[2].cbs.stdout("wlan0 800000 500000") -- triggers on_update
		local last = updates[#updates]
		assert.equals(-62, last.devices["wlan0"].signal)
	end)

	it("signal value 0 is stored as nil (not-associated sentinel)", function()
		local updates = {}
		local b = ipmonitor({ interval = 2 })
		b:start(function(s)
			updates[#updates + 1] = s
		end)
		easy_cmds[1].cb(IP_LINK_OUTPUT, "", "", 0)
		wlc_calls[2].cbs.stdout("sig wlan0 0")
		wlc_calls[2].cbs.stdout("wlan0 800000 500000")
		local last = updates[#updates]
		assert.is_nil(last.devices["wlan0"].signal)
	end)

	it("stop() kills both processes", function()
		local b = ipmonitor({ interval = 2 })
		b:start(function() end)
		easy_cmds[1].cb(IP_LINK_OUTPUT, "", "", 0)
		b:stop()
		assert.equals(2, kill_count)
	end)

	it("ip monitor exit schedules retry timer", function()
		local b = ipmonitor({ interval = 2 })
		b:start(function() end)
		easy_cmds[1].cb(IP_LINK_OUTPUT, "", "", 0)
		wlc_calls[1].cbs.exit("exit", 1)
		assert.is_not_nil(find_timer(10))
	end)

	it("stop() prevents exit callback from scheduling a retry", function()
		local b = ipmonitor({ interval = 2 })
		b:start(function() end)
		easy_cmds[1].cb(IP_LINK_OUTPUT, "", "", 0)
		b:stop()
		wlc_calls[1].cbs.exit("exit", 1)
		assert.is_nil(find_timer(10))
	end)

	it("ip monitor retry timer restarts the process", function()
		local b = ipmonitor({ interval = 2 })
		b:start(function() end)
		easy_cmds[1].cb(IP_LINK_OUTPUT, "", "", 0)
		wlc_calls[1].cbs.exit("exit", 1)
		find_timer(10):fire()
		assert.equals(3, #wlc_calls)
	end)
end)
