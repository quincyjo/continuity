require("spec.support.awesome_mocks")

describe("audio.backends.pulse", function()
	local pulse

	before_each(function()
		package.loaded["continuity.audio.backends.pulse"] = nil
		pulse = require("continuity.audio.backends.pulse")
	end)

	describe("_derive_port_type", function()
		it("returns 'headset' for headset ports", function()
			assert.equals("headset", pulse._private.derive_port_type("analog-output-headset"))
		end)

		it("returns 'headphones' for headphone ports", function()
			assert.equals("headphones", pulse._private.derive_port_type("analog-output-headphones"))
		end)

		it("prefers headset over headphones when both substrings match", function()
			assert.equals("headset", pulse._private.derive_port_type("analog-output-headset-headphones"))
		end)

		it("returns 'speaker' for speaker ports", function()
			assert.equals("speaker", pulse._private.derive_port_type("analog-output-speaker"))
		end)

		it("returns 'hdmi' for HDMI ports", function()
			assert.equals("hdmi", pulse._private.derive_port_type("hdmi-output-0"))
		end)

		it("returns nil for unrecognized port", function()
			assert.is_nil(pulse._private.derive_port_type("unknown-output"))
		end)

		it("returns 'headset-mic' for headset mic ports", function()
			assert.equals("headset-mic", pulse._private.derive_port_type("analog-input-headset-mic"))
		end)

		it("prefers headset-mic over headset when both match", function()
			assert.equals("headset-mic", pulse._private.derive_port_type("headset-mic-input"))
		end)

		it("returns 'mic' for generic mic ports", function()
			assert.equals("mic", pulse._private.derive_port_type("analog-input-internal-mic"))
		end)

		it("returns nil for nil input", function()
			assert.is_nil(pulse._private.derive_port_type(nil))
		end)
	end)

	describe("_derive_connection", function()
		it("returns 'bluetooth' for bluez devices", function()
			assert.equals("bluetooth", pulse._private.derive_connection("bluez_output.AA_BB_CC.1"))
		end)

		it("returns nil for non-bluez prefix even if device contains bluez elsewhere", function()
			assert.is_nil(pulse._private.derive_connection("alsa_output.bluez_card.analog"))
		end)

		it("returns 'hdmi' for HDMI devices", function()
			assert.equals("hdmi", pulse._private.derive_connection("alsa_output.pci-0000_00_1f.3.hdmi-stereo"))
		end)

		it("returns 'usb' for USB devices", function()
			assert.equals("usb", pulse._private.derive_connection("alsa_output.usb-Focusrite.analog-stereo"))
		end)

		it("returns 'analog' for analog devices", function()
			assert.equals("analog", pulse._private.derive_connection("alsa_output.pci-0000_00_1f.3.analog-stereo"))
		end)

		it("returns nil for unrecognized device", function()
			assert.is_nil(pulse._private.derive_connection("unknown_device"))
		end)

		it("returns nil for nil input", function()
			assert.is_nil(pulse._private.derive_connection(nil))
		end)
	end)

	describe("_parse_volume_mute", function()
		local VOLUME_MUTE_OUTPUT = table.concat({
			"Volume: front-left: 26216 /  40% / -23.87 dB,   front-right: 26216 /  40% / -23.87 dB",
			"        balance 0.00",
			"Mute: no",
		}, "\n") .. "\n"

		local VOLUME_MUTE_MUTED_OUTPUT = table.concat({
			"Volume: front-left: 65536 / 100% / 0.00 dB,   front-right: 65536 / 100% / 0.00 dB",
			"        balance 0.00",
			"Mute: yes",
		}, "\n") .. "\n"

		it("parses level and muted=false", function()
			local level, muted = pulse._private.parse_volume_mute(VOLUME_MUTE_OUTPUT)
			assert.equals(40, level)
			assert.is_false(muted)
		end)

		it("parses level and muted=true", function()
			local level, muted = pulse._private.parse_volume_mute(VOLUME_MUTE_MUTED_OUTPUT)
			assert.equals(100, level)
			assert.is_true(muted)
		end)

		it("returns nil, nil for empty input", function()
			local level, muted = pulse._private.parse_volume_mute("")
			assert.is_nil(level)
			assert.is_nil(muted)
		end)
	end)

	describe("_parse_list", function()
		-- Output of: pactl get-default-sink; echo "---"; pactl list sinks
		local SINK_POLL_OUTPUT = table.concat({
			"alsa_output.pci-0000_00_1f.3.analog-stereo",
			"---",
			"Sink #57",
			"\tState: SUSPENDED",
			"\tName: alsa_output.pci-0000_00_1f.3.analog-stereo",
			"\tDescription: Built-in Audio Analog Stereo",
			"\tMute: no",
			"\tVolume: front-left: 26216 /  40% / -23.87 dB,   front-right: 26216 /  40% / -23.87 dB",
			"\t        balance 0.00",
			"\tBase Volume: 65536 / 100% / 0.00 dB",
			"\tActive Port: analog-output-speaker",
			"\tFormats:",
			"\t\tpcm",
		}, "\n") .. "\n"

		-- Two sinks; default is the second one, active port is headphones
		local MULTI_SINK_HEADPHONES_OUTPUT = table.concat({
			"alsa_output.pci-0000_00_1f.3.analog-stereo",
			"---",
			"Sink #55",
			"\tName: alsa_output.pci-0000_00_1f.3.hdmi-stereo",
			"\tMute: no",
			"\tVolume: front-left: 65536 / 100% / 0.00 dB",
			"\tActive Port: hdmi-output-0",
			"Sink #57",
			"\tName: alsa_output.pci-0000_00_1f.3.analog-stereo",
			"\tMute: yes",
			"\tVolume: front-left: 26216 /  40% / -23.87 dB",
			"\tActive Port: analog-output-headphones",
		}, "\n") .. "\n"

		-- Bluetooth sink
		local BLUETOOTH_SINK_OUTPUT = table.concat({
			"bluez_output.AA_BB_CC_DD_EE_FF.1",
			"---",
			"Sink #60",
			"\tName: bluez_output.AA_BB_CC_DD_EE_FF.1",
			"\tMute: no",
			"\tVolume: front-left: 32768 /  50% / -18.06 dB",
			"\tActive Port: headphones-output",
		}, "\n") .. "\n"

		it("parses level, muted, port, port_type, and connection", function()
			local state = pulse._private.parse_list(SINK_POLL_OUTPUT)
			assert.not_nil(state)
			assert.equals(40, state.level)
			assert.is_false(state.muted)
			assert.equals("analog-output-speaker", state.port)
			assert.equals("speaker", state.port_type)
			assert.equals("analog", state.connection)
		end)

		it("finds the correct sink when multiple sinks are present", function()
			local state = pulse._private.parse_list(MULTI_SINK_HEADPHONES_OUTPUT)
			assert.not_nil(state)
			assert.equals(40, state.level)
			assert.is_true(state.muted)
			assert.equals("analog-output-headphones", state.port)
			assert.equals("headphones", state.port_type)
			assert.equals("analog", state.connection)
		end)

		it("derives bluetooth connection from device name", function()
			local state = pulse._private.parse_list(BLUETOOTH_SINK_OUTPUT)
			assert.not_nil(state)
			assert.equals("bluetooth", state.connection)
			assert.equals(50, state.level)
		end)

		it("returns nil when sentinel is missing", function()
			assert.is_nil(pulse._private.parse_list("alsa_output.pci\nSink #57\n"))
		end)

		it("returns nil when default device is not in the list", function()
			local output = table.concat({
				"alsa_output.pci-0000_00_1f.3.analog-stereo",
				"---",
				"Sink #57",
				"\tName: alsa_output.pci-0000_00_1f.3.hdmi-stereo",
				"\tMute: no",
				"\tVolume: front-left: 65536 / 100% / 0.00 dB",
				"\tActive Port: hdmi-output-0",
			}, "\n") .. "\n"
			assert.is_nil(pulse._private.parse_list(output))
		end)
	end)
end)

describe("audio.backends.pulse (instance)", function()
	local pulse, awful, wlc_cbs, easy_cmds

	-- Minimal output of: pactl get-default-sink; echo "---"; pactl list sinks
	local SINK_POLL_OUTPUT = table.concat({
		"alsa_output.pci-0000_00_1f.3.analog-stereo",
		"---",
		"Sink #57",
		"\tName: alsa_output.pci-0000_00_1f.3.analog-stereo",
		"\tMute: no",
		"\tVolume: front-left: 26216 /  40% / -23.87 dB",
		"\tActive Port: analog-output-speaker",
	}, "\n") .. "\n"

	local SOURCE_POLL_OUTPUT = table.concat({
		"alsa_input.pci-0000_00_1f.3.analog-stereo",
		"---",
		"Source #58",
		"\tName: alsa_input.pci-0000_00_1f.3.analog-stereo",
		"\tMute: no",
		"\tVolume: front-left: 11796 /  18% / -44.68 dB",
		"\tActive Port: analog-input-internal-mic",
	}, "\n") .. "\n"

	before_each(function()
		package.loaded["continuity.audio.backends.pulse"] = nil
		easy_cmds = {}
		wlc_cbs = nil
		awful = require("awful")
		awful.spawn.easy_async = function(cmd, cb)
			easy_cmds[#easy_cmds + 1] = { cmd = cmd, cb = cb }
		end
		awful.spawn.with_line_callback = function(_cmd, cbs) -- luacheck: ignore _cmd
			wlc_cbs = cbs
			return 0
		end
		pulse = require("continuity.audio.backends.pulse")
	end)

	describe("start", function()
		it("polls sink on start when on_sink is provided", function()
			local results = {}
			pulse():start({
				on_sink = function(id, s)
					results[#results + 1] = { id = id, state = s }
				end,
			})
			assert.equals(1, #easy_cmds)
			assert.equals("sh", easy_cmds[1].cmd[1])
			assert.truthy(easy_cmds[1].cmd[3]:find("list sinks"))
			easy_cmds[1].cb(SINK_POLL_OUTPUT, "", "", 0)
			assert.equals(1, #results)
			assert.equals("@DEFAULT_SINK@", results[1].id)
			assert.equals(40, results[1].state.level)
			assert.is_false(results[1].state.muted)
		end)

		it("polls source on start when on_source is provided", function()
			local results = {}
			pulse():start({
				on_source = function(id, s)
					results[#results + 1] = { id = id, state = s }
				end,
			})
			assert.equals(1, #easy_cmds)
			assert.truthy(easy_cmds[1].cmd[3]:find("list sources"))
			easy_cmds[1].cb(SOURCE_POLL_OUTPUT, "", "", 0)
			assert.equals(1, #results)
			assert.equals("@DEFAULT_SOURCE@", results[1].id)
			assert.equals(18, results[1].state.level)
		end)

		it("polls both when both callbacks are provided", function()
			pulse():start({
				on_sink = function() end,
				on_source = function() end,
			})
			assert.equals(2, #easy_cmds)
		end)

		it("polls neither when no callbacks are provided", function()
			pulse():start({})
			assert.equals(0, #easy_cmds)
		end)

		it("starts the subscribe process", function()
			pulse():start({ on_sink = function() end })
			assert.not_nil(wlc_cbs)
			assert.is_function(wlc_cbs.stdout)
		end)

		it("does not call callback when poll exits with non-zero", function()
			local called = false
			pulse():start({
				on_sink = function()
					called = true
				end,
			})
			easy_cmds[1].cb("", "", "", 1)
			assert.is_false(called)
		end)
	end)

	describe("stop", function()
		it("clears callbacks so events after stop do not trigger polls", function()
			local backend = pulse()
			backend:start({ on_sink = function() end })
			local count_after_start = #easy_cmds
			backend:stop()
			wlc_cbs.stdout("Event 'change' on sink #57")
			assert.equals(count_after_start, #easy_cmds)
		end)
	end)

	describe("event dispatch", function()
		it("polls sink on sink change event when pending_sink is zero", function()
			local backend = pulse()
			backend:start({ on_sink = function() end })
			local count = #easy_cmds
			wlc_cbs.stdout("Event 'change' on sink #57")
			assert.equals(count + 1, #easy_cmds)
			assert.truthy(easy_cmds[#easy_cmds].cmd[3]:find("list sinks"))
		end)

		it("polls source on source change event when pending_source is zero", function()
			local backend = pulse()
			backend:start({ on_source = function() end })
			local count = #easy_cmds
			wlc_cbs.stdout("Event 'change' on source #58")
			assert.equals(count + 1, #easy_cmds)
			assert.truthy(easy_cmds[#easy_cmds].cmd[3]:find("list sources"))
		end)

		it("polls both on server change event regardless of pending", function()
			local backend = pulse()
			backend:start({ on_sink = function() end, on_source = function() end })
			local count = #easy_cmds
			wlc_cbs.stdout("Event 'change' on server #0")
			assert.equals(count + 2, #easy_cmds)
		end)

		it("skips poll and decrements pending_sink when pending > 0 on sink event", function()
			local backend = pulse()
			backend:start({ on_sink = function() end })
			-- Two consecutive events when pending=0: both poll
			local count = #easy_cmds
			wlc_cbs.stdout("Event 'change' on sink #57")
			wlc_cbs.stdout("Event 'change' on sink #57")
			assert.equals(count + 2, #easy_cmds)
		end)

		it("does not poll sink on sink event when on_sink is nil", function()
			local backend = pulse()
			backend:start({ on_source = function() end })
			local count = #easy_cmds
			wlc_cbs.stdout("Event 'change' on sink #57")
			assert.equals(count, #easy_cmds)
		end)
	end)

	local VOLUME_MUTE_OUTPUT = table.concat({
		"Volume: front-left: 32768 /  50% / -18.06 dB,   front-right: 32768 /  50% / -18.06 dB",
		"        balance 0.00",
		"Mute: no",
	}, "\n") .. "\n"

	describe("control API", function()
		local function fire(n, stdout)
			easy_cmds[n].cb(stdout or "", "", "", 0)
		end

		it("adjust_perc increments pending_sink and calls cb with parsed state", function()
			local backend = pulse()
			backend:start({ on_sink = function() end })
			local count = #easy_cmds
			local cb_result = nil
			backend:adjust_perc("@DEFAULT_SINK@", 10, function(level, muted)
				cb_result = { level = level, muted = muted }
			end)
			assert.equals(count + 1, #easy_cmds)
			local set_cmd = easy_cmds[#easy_cmds].cmd
			local cmd_str = type(set_cmd) == "table" and table.concat(set_cmd, " ") or set_cmd
			assert.truthy(cmd_str:find("set%-sink%-volume"))
			fire(#easy_cmds, "")
			assert.equals(count + 2, #easy_cmds)
			fire(#easy_cmds, VOLUME_MUTE_OUTPUT)
			assert.not_nil(cb_result)
			assert.equals(50, cb_result.level)
			assert.is_false(cb_result.muted)
		end)

		it("pending_sink is decremented by subscribe event, not the cb", function()
			local backend = pulse()
			backend:start({ on_sink = function() end })
			backend:adjust_perc("@DEFAULT_SINK@", 5, function() end)
			local count = #easy_cmds
			-- First sink event: pending > 0, should decrement and NOT poll
			wlc_cbs.stdout("Event 'change' on sink #57")
			assert.equals(count, #easy_cmds)
			-- Second sink event: pending == 0, should poll
			wlc_cbs.stdout("Event 'change' on sink #57")
			assert.equals(count + 1, #easy_cmds)
		end)

		it("set_perc calls pactl set-sink-volume with absolute percent", function()
			local backend = pulse()
			backend:start({})
			backend:set_perc("@DEFAULT_SINK@", 75, function() end)
			assert.equals(1, #easy_cmds)
			local cmd = easy_cmds[1].cmd
			local cmd_str = type(cmd) == "table" and table.concat(cmd, " ") or cmd
			assert.truthy(cmd_str:find("75%%"))
		end)

		it("toggle calls pactl set-sink-mute with toggle", function()
			local backend = pulse()
			backend:start({})
			backend:toggle("@DEFAULT_SINK@", function() end)
			assert.equals(1, #easy_cmds)
			local cmd = easy_cmds[1].cmd
			local cmd_str = type(cmd) == "table" and table.concat(cmd, " ") or cmd
			assert.truthy(cmd_str:find("toggle"))
		end)

		it("mute calls pactl set-sink-mute with 1", function()
			local backend = pulse()
			backend:start({})
			backend:mute("@DEFAULT_SINK@", function() end)
			local cmd = easy_cmds[1].cmd
			local cmd_str = type(cmd) == "table" and table.concat(cmd, " ") or cmd
			assert.truthy(cmd_str:find("set%-sink%-mute") and cmd_str:find(" 1"))
		end)

		it("unmute calls pactl set-sink-mute with 0", function()
			local backend = pulse()
			backend:start({})
			backend:unmute("@DEFAULT_SINK@", function() end)
			local cmd = easy_cmds[1].cmd
			local cmd_str = type(cmd) == "table" and table.concat(cmd, " ") or cmd
			assert.truthy(cmd_str:find("mute") and cmd_str:find(" 0"))
		end)

		it("source control increments pending_source not pending_sink", function()
			local backend = pulse()
			backend:start({ on_sink = function() end, on_source = function() end })
			backend:adjust_perc("@DEFAULT_SOURCE@", 5, function() end)
			local count = #easy_cmds
			-- Sink event: pending_sink == 0, SHOULD poll
			wlc_cbs.stdout("Event 'change' on sink #57")
			assert.equals(count + 1, #easy_cmds)
			-- Source event: pending_source == 1, should NOT poll
			wlc_cbs.stdout("Event 'change' on source #58")
			assert.equals(count + 1, #easy_cmds)
		end)
	end)
end)
