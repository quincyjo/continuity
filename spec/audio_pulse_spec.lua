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

	describe("parse_all_devices", function()
		local SINGLE_SINK_OUTPUT = table.concat({
			"alsa_output.pci-0000_00_1f.3.analog-stereo",
			"---",
			"Sink #57",
			"\tState: SUSPENDED",
			"\tName: alsa_output.pci-0000_00_1f.3.analog-stereo",
			"\tDescription: Built-in Audio Analog Stereo",
			"\tMute: no",
			"\tVolume: front-left: 26216 /  40% / -23.87 dB,   front-right: 26216 /  40% / -23.87 dB",
			"\tActive Port: analog-output-speaker",
		}, "\n") .. "\n"

		local MULTI_SINK_OUTPUT = table.concat({
			"alsa_output.pci-0000_00_1f.3.analog-stereo",
			"---",
			"Sink #55",
			"\tName: alsa_output.pci-0000_00_1f.3.hdmi-stereo",
			"\tDescription: Built-in Audio HDMI",
			"\tMute: no",
			"\tVolume: front-left: 65536 / 100% / 0.00 dB",
			"\tActive Port: hdmi-output-0",
			"Sink #57",
			"\tName: alsa_output.pci-0000_00_1f.3.analog-stereo",
			"\tDescription: Built-in Audio Analog Stereo",
			"\tMute: yes",
			"\tVolume: front-left: 26216 /  40% / -23.87 dB",
			"\tActive Port: analog-output-headphones",
		}, "\n") .. "\n"

		it("returns one entry for a single sink", function()
			local entries = pulse._private.parse_all_devices(SINGLE_SINK_OUTPUT)
			assert.equals(1, #entries)
		end)

		it("entry id is the numeric index string", function()
			local entries = pulse._private.parse_all_devices(SINGLE_SINK_OUTPUT)
			assert.equals("57", entries[1].id)
		end)

		it("entry meta.name is the Name: field", function()
			local entries = pulse._private.parse_all_devices(SINGLE_SINK_OUTPUT)
			assert.equals("alsa_output.pci-0000_00_1f.3.analog-stereo", entries[1].meta.name)
		end)

		it("entry meta.description is the Description: field", function()
			local entries = pulse._private.parse_all_devices(SINGLE_SINK_OUTPUT)
			assert.equals("Built-in Audio Analog Stereo", entries[1].meta.description)
		end)

		it("entry state has correct level, muted, port, port_type, connection", function()
			local entries = pulse._private.parse_all_devices(SINGLE_SINK_OUTPUT)
			local s = entries[1].state
			assert.equals(40, s.level)
			assert.is_false(s.muted)
			assert.equals("analog-output-speaker", s.port)
			assert.equals("speaker", s.port_type)
			assert.equals("analog", s.connection)
		end)

		it("is_default is true for the default device", function()
			local entries = pulse._private.parse_all_devices(SINGLE_SINK_OUTPUT)
			assert.is_true(entries[1].state.is_default)
		end)

		it("returns one entry per sink when multiple sinks are present", function()
			local entries = pulse._private.parse_all_devices(MULTI_SINK_OUTPUT)
			assert.equals(2, #entries)
		end)

		it("assigns correct ids and names for multiple sinks", function()
			local entries = pulse._private.parse_all_devices(MULTI_SINK_OUTPUT)
			local by_id = {}
			for _, e in ipairs(entries) do
				by_id[e.id] = e
			end
			assert.is_not_nil(by_id["55"])
			assert.equals("alsa_output.pci-0000_00_1f.3.hdmi-stereo", by_id["55"].meta.name)
			assert.is_not_nil(by_id["57"])
			assert.equals("alsa_output.pci-0000_00_1f.3.analog-stereo", by_id["57"].meta.name)
		end)

		it("is_default is true only for the default sink", function()
			local entries = pulse._private.parse_all_devices(MULTI_SINK_OUTPUT)
			local by_id = {}
			for _, e in ipairs(entries) do
				by_id[e.id] = e
			end
			assert.is_false(by_id["55"].state.is_default)
			assert.is_true(by_id["57"].state.is_default)
		end)

		it("returns empty table when no devices are present", function()
			local entries = pulse._private.parse_all_devices("alsa_output.pci\n---\n")
			assert.equals(0, #entries)
		end)

		it("meta.description is nil when Description: is absent", function()
			local output = table.concat({
				"bluez_output.AA_BB_CC_DD_EE_FF.1",
				"---",
				"Sink #60",
				"\tName: bluez_output.AA_BB_CC_DD_EE_FF.1",
				"\tMute: no",
				"\tVolume: front-left: 32768 /  50% / -18.06 dB",
			}, "\n") .. "\n"
			local entries = pulse._private.parse_all_devices(output)
			assert.equals(1, #entries)
			assert.is_nil(entries[1].meta.description)
		end)
	end)

	describe("find_device_block_by_index", function()
		local LIST = table.concat({
			"Sink #55",
			"\tName: alsa_output.pci-0000_00_1f.3.hdmi-stereo",
			"\tDescription: Built-in HDMI",
			"\tMute: no",
			"\tVolume: front-left: 65536 / 100% / 0.00 dB",
			"\tActive Port: hdmi-output-0",
			"Sink #57",
			"\tName: alsa_output.pci-0000_00_1f.3.analog-stereo",
			"\tDescription: Built-in Analog",
			"\tMute: yes",
			"\tVolume: front-left: 26216 /  40% / -23.87 dB",
			"\tActive Port: analog-output-speaker",
		}, "\n") .. "\n"

		it("returns the block for the first device", function()
			local block = pulse._private.find_device_block_by_index(LIST, "55")
			assert.is_not_nil(block)
			assert.truthy(block:find("hdmi-stereo", 1, true))
		end)

		it("returns the block for the second device", function()
			local block = pulse._private.find_device_block_by_index(LIST, "57")
			assert.is_not_nil(block)
			assert.truthy(block:find("analog-stereo", 1, true))
		end)

		it("returns nil for an unknown index", function()
			assert.is_nil(pulse._private.find_device_block_by_index(LIST, "99"))
		end)

		it("block contains the Name: line for the matched device only", function()
			local block = pulse._private.find_device_block_by_index(LIST, "55")
			assert.truthy(block:find("alsa_output.pci-0000_00_1f.3.hdmi-stereo", 1, true))
			assert.falsy(block:find("analog-stereo", 1, true))
		end)
	end)

	describe("parse_device_block", function()
		local BLOCK = table.concat({
			"\tName: alsa_output.pci-0000_00_1f.3.analog-stereo",
			"\tDescription: Built-in Audio Analog Stereo",
			"\tMute: no",
			"\tVolume: front-left: 26216 /  40% / -23.87 dB",
			"\tActive Port: analog-output-speaker",
		}, "\n") .. "\n"

		local DEFAULT_NAME = "alsa_output.pci-0000_00_1f.3.analog-stereo"

		it("parses level, muted, port, port_type, connection", function()
			local parsed = pulse._private.parse_device_block(BLOCK, DEFAULT_NAME)
			assert.equals(40, parsed.state.level)
			assert.is_false(parsed.state.muted)
			assert.equals("analog-output-speaker", parsed.state.port)
			assert.equals("speaker", parsed.state.port_type)
			assert.equals("analog", parsed.state.connection)
		end)

		it("is_default is true when name matches default_name", function()
			local parsed = pulse._private.parse_device_block(BLOCK, DEFAULT_NAME)
			assert.is_true(parsed.state.is_default)
		end)

		it("is_default is false when name does not match default_name", function()
			local parsed = pulse._private.parse_device_block(BLOCK, "alsa_output.pci-0000_00_1f.3.hdmi-stereo")
			assert.is_false(parsed.state.is_default)
		end)

		it("meta.name is the Name: field", function()
			local parsed = pulse._private.parse_device_block(BLOCK, DEFAULT_NAME)
			assert.equals("alsa_output.pci-0000_00_1f.3.analog-stereo", parsed.meta.name)
		end)

		it("meta.description is the Description: field", function()
			local parsed = pulse._private.parse_device_block(BLOCK, DEFAULT_NAME)
			assert.equals("Built-in Audio Analog Stereo", parsed.meta.description)
		end)

		it("meta.description is nil when Description: is absent", function()
			local block_no_desc = table.concat({
				"\tName: bluez_output.AA_BB_CC_DD_EE_FF.1",
				"\tMute: no",
				"\tVolume: front-left: 32768 /  50% / -18.06 dB",
			}, "\n") .. "\n"
			local parsed = pulse._private.parse_device_block(block_no_desc, "bluez_output.AA_BB_CC_DD_EE_FF.1")
			assert.is_nil(parsed.meta.description)
		end)

		it("level defaults to 0 when Volume: is absent", function()
			local block_no_vol = "\tName: alsa_output.pci\n\tMute: no\n"
			local parsed = pulse._private.parse_device_block(block_no_vol, "other")
			assert.equals(0, parsed.state.level)
		end)
	end)

	describe("parse_all_devices_json", function()
		local SINGLE_SINK_JSON = "alsa_output.pci-0000_00_1f.3.analog-stereo\n---\n"
			.. [=[
[{"index":57,"name":"alsa_output.pci-0000_00_1f.3.analog-stereo","description":"Built-in Audio Analog Stereo","mute":false,"volume":{"front-left":{"value":26216,"value_percent":"40%","db":"-23.87 dB"}},"active_port":"analog-output-speaker"}]
]=]

		local SINGLE_SINK_NO_PORT_JSON = "alsa_output.pci-0000_00_1f.3.analog-stereo\n---\n"
			.. [=[
[{"index":57,"name":"alsa_output.pci-0000_00_1f.3.analog-stereo","description":"Built-in Audio Analog Stereo","mute":false,"volume":{"front-left":{"value":26216,"value_percent":"40%","db":"-23.87 dB"}},"active_port":null}]
]=]

		local MULTI_SINK_JSON = "alsa_output.pci-0000_00_1f.3.analog-stereo\n---\n"
			.. [=[
[{"index":55,"name":"alsa_output.pci-0000_00_1f.3.hdmi-stereo","description":"Built-in Audio HDMI","mute":false,"volume":{"front-left":{"value":65536,"value_percent":"100%","db":"0.00 dB"}},"active_port":"hdmi-output-0"},{"index":57,"name":"alsa_output.pci-0000_00_1f.3.analog-stereo","description":"Built-in Audio Analog Stereo","mute":true,"volume":{"front-left":{"value":26216,"value_percent":"40%","db":"-23.87 dB"}},"active_port":"analog-output-headphones"}]
]=]

		it("returns one entry for a single sink", function()
			local entries = pulse._private.parse_all_devices_json(SINGLE_SINK_JSON)
			assert.equals(1, #entries)
		end)

		it("entry id is the numeric index string", function()
			local entries = pulse._private.parse_all_devices_json(SINGLE_SINK_JSON)
			assert.equals("57", entries[1].id)
		end)

		it("entry meta.name is the name field", function()
			local entries = pulse._private.parse_all_devices_json(SINGLE_SINK_JSON)
			assert.equals("alsa_output.pci-0000_00_1f.3.analog-stereo", entries[1].meta.name)
		end)

		it("entry meta.description is the description field", function()
			local entries = pulse._private.parse_all_devices_json(SINGLE_SINK_JSON)
			assert.equals("Built-in Audio Analog Stereo", entries[1].meta.description)
		end)

		it("entry state has correct level, muted, port, port_type, connection", function()
			local entries = pulse._private.parse_all_devices_json(SINGLE_SINK_JSON)
			local s = entries[1].state
			assert.equals(40, s.level)
			assert.is_false(s.muted)
			assert.equals("analog-output-speaker", s.port)
			assert.equals("speaker", s.port_type)
			assert.equals("analog", s.connection)
		end)

		it("is_default is true for the default device", function()
			local entries = pulse._private.parse_all_devices_json(SINGLE_SINK_JSON)
			assert.is_true(entries[1].state.is_default)
		end)

		it("returns one entry per sink when multiple sinks are present", function()
			local entries = pulse._private.parse_all_devices_json(MULTI_SINK_JSON)
			assert.equals(2, #entries)
		end)

		it("assigns correct ids and names for multiple sinks", function()
			local entries = pulse._private.parse_all_devices_json(MULTI_SINK_JSON)
			local by_id = {}
			for _, e in ipairs(entries) do
				by_id[e.id] = e
			end
			assert.is_not_nil(by_id["55"])
			assert.equals("alsa_output.pci-0000_00_1f.3.hdmi-stereo", by_id["55"].meta.name)
			assert.is_not_nil(by_id["57"])
			assert.equals("alsa_output.pci-0000_00_1f.3.analog-stereo", by_id["57"].meta.name)
		end)

		it("is_default is true only for the default sink", function()
			local entries = pulse._private.parse_all_devices_json(MULTI_SINK_JSON)
			local by_id = {}
			for _, e in ipairs(entries) do
				by_id[e.id] = e
			end
			assert.is_false(by_id["55"].state.is_default)
			assert.is_true(by_id["57"].state.is_default)
		end)

		it("returns empty table when sentinel is missing", function()
			local entries = pulse._private.parse_all_devices_json("alsa_output.pci\n---\nnot-json\n")
			assert.equals(0, #entries)
		end)

		it("meta.description is nil when description is absent from JSON", function()
			local output = "bluez_output.AA_BB_CC.1\n---\n"
				.. '[{"index":60,"name":"bluez_output.AA_BB_CC.1","mute":false,"volume":{"front-left":{"value":32768,"value_percent":"50%","db":"-18.06 dB"}},"active_port":"headphones-output"}]\n' -- luacheck: ignore
			local entries = pulse._private.parse_all_devices_json(output)
			assert.equals(1, #entries)
			assert.is_nil(entries[1].meta.description)
		end)

		it("derives bluetooth connection from device name", function()
			local output = "bluez_output.AA_BB_CC.1\n---\n"
				.. '[{"index":60,"name":"bluez_output.AA_BB_CC.1","mute":false,"volume":{"front-left":{"value":32768,"value_percent":"50%","db":"-18.06 dB"}},"active_port":"headphones-output"}]\n' -- luacheck: ignore
			local entries = pulse._private.parse_all_devices_json(output)
			assert.equals("bluetooth", entries[1].state.connection)
			assert.equals(50, entries[1].state.level)
		end)

		it("handles null port", function()
			local entries = pulse._private.parse_all_devices_json(SINGLE_SINK_NO_PORT_JSON)
			assert.is_nil(entries[1].state.port)
			assert.is_nil(entries[1].state.port_type)
		end)
	end)

	describe("parse_device_by_index_json", function()
		local MULTI_SINK_JSON = "alsa_output.pci-0000_00_1f.3.analog-stereo\n---\n"
			.. [=[
[{"index":55,"name":"alsa_output.pci-0000_00_1f.3.hdmi-stereo","description":"Built-in HDMI","mute":false,"volume":{"front-left":{"value":65536,"value_percent":"100%","db":"0.00 dB"}},"active_port":"hdmi-output-0"},{"index":57,"name":"alsa_output.pci-0000_00_1f.3.analog-stereo","description":"Built-in Analog","mute":true,"volume":{"front-left":{"value":26216,"value_percent":"40%","db":"-23.87 dB"}},"active_port":"analog-output-speaker"}]
]=]

		it("returns state and meta for a known index", function()
			local parsed = pulse._private.parse_device_by_index_json(MULTI_SINK_JSON, "55")
			assert.is_not_nil(parsed)
			assert.equals("alsa_output.pci-0000_00_1f.3.hdmi-stereo", parsed.meta.name)
			assert.equals(100, parsed.state.level)
			assert.is_false(parsed.state.muted)
			assert.equals("hdmi-output-0", parsed.state.port)
		end)

		it("returns the correct entry when multiple sinks exist", function()
			local parsed = pulse._private.parse_device_by_index_json(MULTI_SINK_JSON, "57")
			assert.is_not_nil(parsed)
			assert.equals("alsa_output.pci-0000_00_1f.3.analog-stereo", parsed.meta.name)
			assert.equals(40, parsed.state.level)
			assert.is_true(parsed.state.muted)
		end)

		it("is_default is true when the device is the default", function()
			local parsed = pulse._private.parse_device_by_index_json(MULTI_SINK_JSON, "57")
			assert.is_true(parsed.state.is_default)
		end)

		it("is_default is false when the device is not the default", function()
			local parsed = pulse._private.parse_device_by_index_json(MULTI_SINK_JSON, "55")
			assert.is_false(parsed.state.is_default)
		end)

		it("returns nil for an unknown index", function()
			local parsed = pulse._private.parse_device_by_index_json(MULTI_SINK_JSON, "99")
			assert.is_nil(parsed)
		end)

		it("returns nil when sentinel is missing", function()
			local parsed = pulse._private.parse_device_by_index_json("alsa_output.pci\n", "57")
			assert.is_nil(parsed)
		end)
	end)
end)

describe("audio.backends.pulse (instance)", function()
	local pulse, awful, wlc_cbs, easy_cmds

	local SINK_POLL_OUTPUT = table.concat({
		"alsa_output.pci-0000_00_1f.3.analog-stereo",
		"---",
		"Sink #57",
		"\tName: alsa_output.pci-0000_00_1f.3.analog-stereo",
		"\tMute: no",
		"\tVolume: front-left: 26216 /  40% / -23.87 dB",
		"\tActive Port: analog-output-speaker",
	}, "\n") .. "\n"

	local function make_sink_handles()
		return { add = function() end, update = function() end, remove = function() end }
	end

	local function make_source_handles()
		return { add = function() end, update = function() end, remove = function() end }
	end

	before_each(function()
		package.loaded["continuity.audio.backends.pulse"] = nil
		package.loaded["continuity.util.json"] = nil
		local saved_json = package.loaded["json"]
		package.loaded["json"] = nil
		package.preload["json"] = function()
			error("disabled")
		end -- luacheck: ignore
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
		package.preload["json"] = nil
		package.loaded["json"] = saved_json
	end)

	describe("start", function()
		it("polls sinks on start when sinks handle is provided", function()
			local added = {}
			local sh = {
				add = function(id)
					added[#added + 1] = { id = id }
				end,
				update = function() end,
				remove = function() end,
			}
			pulse():start({ sinks = sh })
			assert.equals(1, #easy_cmds)
			assert.equals("sh", easy_cmds[1].cmd[1])
			assert.truthy(easy_cmds[1].cmd[3]:find("list sinks"))
			easy_cmds[1].cb(SINK_POLL_OUTPUT, "", "", 0)
			assert.equals(1, #added)
			assert.equals("57", added[1].id)
		end)

		it("polls sources on start when sources handle is provided", function()
			pulse():start({ sources = make_source_handles() })
			assert.equals(1, #easy_cmds)
			assert.truthy(easy_cmds[1].cmd[3]:find("list sources"))
		end)

		it("polls both when both handles are provided", function()
			pulse():start({ sinks = make_sink_handles(), sources = make_source_handles() })
			assert.equals(2, #easy_cmds)
		end)

		it("polls neither when no handles are provided", function()
			pulse():start({})
			assert.equals(0, #easy_cmds)
		end)

		it("starts the subscribe process", function()
			pulse():start({})
			assert.not_nil(wlc_cbs)
			assert.is_function(wlc_cbs.stdout)
		end)

		it("calls on_sink with the real numeric sink idx", function()
			local results = {}
			pulse():start({
				on_sink = function(id, s)
					results[#results + 1] = { id = id, state = s }
				end,
				sinks = make_sink_handles(),
			})
			easy_cmds[1].cb(SINK_POLL_OUTPUT, "", "", 0)
			assert.equals(1, #results)
			assert.equals("57", results[1].id)
			assert.equals(40, results[1].state.level)
			assert.is_false(results[1].state.muted)
		end)

		it("does not call sinks.add when poll exits with non-zero", function()
			local added = {}
			local sh = {
				add = function(id)
					added[#added + 1] = id
				end,
				update = function() end,
				remove = function() end,
			}
			pulse():start({ sinks = sh })
			easy_cmds[1].cb("", "", "", 1)
			assert.equals(0, #added)
		end)
	end)

	describe("stop", function()
		it("clears callbacks so events after stop do not trigger polls", function()
			local backend = pulse()
			backend:start({ sinks = make_sink_handles() })
			easy_cmds[1].cb(SINK_POLL_OUTPUT, "", "", 0)
			local count_after_start = #easy_cmds
			backend:stop()
			wlc_cbs.stdout("Event 'change' on sink #57")
			assert.equals(count_after_start, #easy_cmds)
		end)
	end)

	describe("event dispatch", function()
		it("polls sinks on sink change event when sink handles are registered", function()
			local backend = pulse()
			backend:start({ sinks = make_sink_handles() })
			local count = #easy_cmds
			wlc_cbs.stdout("Event 'change' on sink #57")
			assert.equals(count + 1, #easy_cmds)
			assert.truthy(easy_cmds[#easy_cmds].cmd[3]:find("list sinks"))
		end)

		it("polls sources on source change event when source handles are registered", function()
			local backend = pulse()
			backend:start({ sources = make_source_handles() })
			local count = #easy_cmds
			wlc_cbs.stdout("Event 'change' on source #58")
			assert.equals(count + 1, #easy_cmds)
			assert.truthy(easy_cmds[#easy_cmds].cmd[3]:find("list sources"))
		end)

		it("polls both sinks and sources on server change event", function()
			local backend = pulse()
			backend:start({ sinks = make_sink_handles(), sources = make_source_handles() })
			local count = #easy_cmds
			wlc_cbs.stdout("Event 'change' on server #0")
			assert.equals(count + 2, #easy_cmds)
		end)

		it("does not poll sink on sink event when no sink handles are registered", function()
			local backend = pulse()
			backend:start({})
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

		local function cs(cmd)
			return type(cmd) == "table" and table.concat(cmd, " ") or cmd
		end

		it("api.sink.adjust_perc calls set-sink-volume and returns parsed volume via cb", function()
			local backend = pulse()
			backend:start({ sinks = make_sink_handles() })
			local count = #easy_cmds
			local cb_result = nil
			backend.api.sink.adjust_perc("57", 10, function(level, muted)
				cb_result = { level = level, muted = muted }
			end)
			assert.equals(count + 1, #easy_cmds)
			assert.truthy(cs(easy_cmds[#easy_cmds].cmd):find("set%-sink%-volume"))
			assert.truthy(cs(easy_cmds[#easy_cmds].cmd):find("57"))
			fire(#easy_cmds, "")
			assert.equals(count + 2, #easy_cmds)
			fire(#easy_cmds, VOLUME_MUTE_OUTPUT)
			assert.not_nil(cb_result)
			assert.equals(50, cb_result.level)
			assert.is_false(cb_result.muted)
		end)

		it("api.sink.adjust_perc increments pending_sinks[idx] so sink event is suppressed", function()
			local backend = pulse()
			backend:start({ sinks = make_sink_handles() })
			backend.api.sink.adjust_perc("57", 5, function() end)
			local count = #easy_cmds
			-- First sink event: pending_sinks["57"] > 0, should decrement and NOT poll
			wlc_cbs.stdout("Event 'change' on sink #57")
			assert.equals(count, #easy_cmds)
			-- Second sink event: pending_sinks["57"] == 0, SHOULD poll
			wlc_cbs.stdout("Event 'change' on sink #57")
			assert.equals(count + 1, #easy_cmds)
		end)

		it("api.sink.set_perc calls pactl set-sink-volume with absolute percent", function()
			local backend = pulse()
			backend:start({})
			backend.api.sink.set_perc("57", 75, function() end)
			assert.equals(1, #easy_cmds)
			assert.truthy(cs(easy_cmds[1].cmd):find("75%%"))
		end)

		it("api.sink.toggle calls pactl set-sink-mute with toggle", function()
			local backend = pulse()
			backend:start({})
			backend.api.sink.toggle("57", function() end)
			assert.equals(1, #easy_cmds)
			assert.truthy(cs(easy_cmds[1].cmd):find("toggle"))
		end)

		it("api.sink.mute calls pactl set-sink-mute with 1", function()
			local backend = pulse()
			backend:start({})
			backend.api.sink.mute("57", function() end)
			assert.truthy(cs(easy_cmds[1].cmd):find("set%-sink%-mute") and cs(easy_cmds[1].cmd):find(" 1"))
		end)

		it("api.sink.unmute calls pactl set-sink-mute with 0", function()
			local backend = pulse()
			backend:start({})
			backend.api.sink.unmute("57", function() end)
			assert.truthy(cs(easy_cmds[1].cmd):find("mute") and cs(easy_cmds[1].cmd):find(" 0"))
		end)

		it("api.source.adjust_perc increments pending_sources not pending_sinks", function()
			local backend = pulse()
			backend:start({ sinks = make_sink_handles(), sources = make_source_handles() })
			backend.api.source.adjust_perc("58", 5, function() end)
			local count = #easy_cmds
			-- Sink event for #57: pending_sinks["57"] == nil/0, SHOULD poll
			wlc_cbs.stdout("Event 'change' on sink #57")
			assert.equals(count + 1, #easy_cmds)
			-- Source event for #58: pending_sources["58"] > 0, should NOT poll
			wlc_cbs.stdout("Event 'change' on source #58")
			assert.equals(count + 1, #easy_cmds)
		end)
	end)
end)
