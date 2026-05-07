require("spec.support.awesome_mocks")

describe("audio.backends.pulse (device dispatch)", function()
	local pulse, awful, wlc_cbs, easy_cmds

	local function cmd_str(cmd)
		return type(cmd) == "table" and table.concat(cmd, " ") or cmd
	end

	-- Combined: alsa=default (#57), hdmi (#55)
	local SINKS_ALSA_DEFAULT = table.concat({
		"alsa_output.pci-0000_00_1f.3.analog-stereo",
		"---",
		"Sink #55",
		"\tName: alsa_output.pci-0000_00_1f.3.hdmi-stereo",
		"\tDescription: Built-in HDMI",
		"\tMute: no",
		"\tVolume: front-left: 65536 / 100% / 0.00 dB",
		"\tActive Port: hdmi-output-0",
		"Sink #57",
		"\tName: alsa_output.pci-0000_00_1f.3.analog-stereo",
		"\tDescription: Built-in Analog",
		"\tMute: no",
		"\tVolume: front-left: 26216 /  40% / -23.87 dB",
		"\tActive Port: analog-output-speaker",
	}, "\n") .. "\n"

	-- Combined: hdmi=default (#55), alsa (#57) — for server change tests
	local SINKS_HDMI_DEFAULT = table.concat({
		"alsa_output.pci-0000_00_1f.3.hdmi-stereo",
		"---",
		"Sink #55",
		"\tName: alsa_output.pci-0000_00_1f.3.hdmi-stereo",
		"\tDescription: Built-in HDMI",
		"\tMute: no",
		"\tVolume: front-left: 65536 / 100% / 0.00 dB",
		"\tActive Port: hdmi-output-0",
		"Sink #57",
		"\tName: alsa_output.pci-0000_00_1f.3.analog-stereo",
		"\tDescription: Built-in Analog",
		"\tMute: no",
		"\tVolume: front-left: 26216 /  40% / -23.87 dB",
		"\tActive Port: analog-output-speaker",
	}, "\n") .. "\n"

	-- Combined: alsa=default plus new bluetooth #60
	local SINKS_WITH_BT = table.concat({
		"alsa_output.pci-0000_00_1f.3.analog-stereo",
		"---",
		"Sink #57",
		"\tName: alsa_output.pci-0000_00_1f.3.analog-stereo",
		"\tDescription: Built-in Analog",
		"\tMute: no",
		"\tVolume: front-left: 26216 /  40% / -23.87 dB",
		"\tActive Port: analog-output-speaker",
		"Sink #60",
		"\tName: bluez_output.AA_BB_CC_DD_EE_FF.1",
		"\tDescription: Bluetooth Headphones",
		"\tMute: no",
		"\tVolume: front-left: 32768 /  50% / -18.06 dB",
	}, "\n") .. "\n"

	-- Source
	local SOURCES_INTERNAL_DEFAULT = table.concat({
		"alsa_input.pci-0000_00_1f.3.analog-stereo",
		"---",
		"Source #6",
		"\tName: alsa_input.pci-0000_00_1f.3.analog-stereo",
		"\tDescription: Built-in Mic",
		"\tMute: no",
		"\tVolume: front-left: 65536 / 100% / 0.00 dB",
		"\tActive Port: analog-input-internal-mic",
	}, "\n") .. "\n"

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
		awful.spawn.with_line_callback = function(_cmd, cbs)
			wlc_cbs = cbs
			return 0
		end
		pulse = require("continuity.audio.backends.pulse")
		package.preload["json"] = nil
		package.loaded["json"] = saved_json
	end)

	local function make_sink_handles(added, updated, removed)
		return {
			add = function(id, state, meta)
				if added then
					added[#added + 1] = { id = id, state = state, meta = meta }
				end
			end,
			update = function(id, state)
				if updated then
					updated[#updated + 1] = { id = id, state = state }
				end
			end,
			remove = function(id)
				if removed then
					removed[#removed + 1] = id
				end
			end,
		}
	end

	describe("startup poll", function()
		it("polls sinks on start when sinks handle is provided", function()
			pulse():start({ sinks = make_sink_handles() })
			assert.equals(1, #easy_cmds)
			assert.truthy(cmd_str(easy_cmds[1].cmd):find("list sinks"))
		end)

		it("calls sinks.add for each device in poll output", function()
			local added = {}
			pulse():start({ sinks = make_sink_handles(added) })
			easy_cmds[1].cb(SINKS_ALSA_DEFAULT, "", "", 0)
			assert.equals(2, #added)
		end)

		it("sinks.add id is the numeric index string", function()
			local added = {}
			pulse():start({ sinks = make_sink_handles(added) })
			easy_cmds[1].cb(SINKS_ALSA_DEFAULT, "", "", 0)
			local by_id = {}
			for _, a in ipairs(added) do
				by_id[a.id] = a
			end
			assert.is_not_nil(by_id["55"])
			assert.is_not_nil(by_id["57"])
		end)

		it("sinks.add meta.name is the Name: field", function()
			local added = {}
			pulse():start({ sinks = make_sink_handles(added) })
			easy_cmds[1].cb(SINKS_ALSA_DEFAULT, "", "", 0)
			local by_id = {}
			for _, a in ipairs(added) do
				by_id[a.id] = a
			end
			assert.equals("alsa_output.pci-0000_00_1f.3.analog-stereo", by_id["57"].meta.name)
			assert.equals("alsa_output.pci-0000_00_1f.3.hdmi-stereo", by_id["55"].meta.name)
		end)

		it("is_default is true only for the default sink", function()
			local added = {}
			pulse():start({ sinks = make_sink_handles(added) })
			easy_cmds[1].cb(SINKS_ALSA_DEFAULT, "", "", 0)
			local by_id = {}
			for _, a in ipairs(added) do
				by_id[a.id] = a
			end
			assert.is_true(by_id["57"].state.is_default)
			assert.is_false(by_id["55"].state.is_default)
		end)

		it("calls on_sink with the real numeric sink idx", function()
			local on_sink_calls = {}
			pulse():start({
				on_sink = function(id, state)
					on_sink_calls[#on_sink_calls + 1] = { id = id, state = state }
				end,
				sinks = make_sink_handles(),
			})
			easy_cmds[1].cb(SINKS_ALSA_DEFAULT, "", "", 0)
			assert.equals(1, #on_sink_calls)
			assert.equals("57", on_sink_calls[1].id)
			assert.equals(40, on_sink_calls[1].state.level)
		end)
	end)

	describe("'new' sink event", function()
		it("calls sinks.add with the new sink's index and state", function()
			local added = {}
			pulse():start({ sinks = make_sink_handles(added) })
			easy_cmds[1].cb(SINKS_ALSA_DEFAULT, "", "", 0)
			local count = #easy_cmds
			wlc_cbs.stdout("Event 'new' on sink #60")
			assert.equals(count + 1, #easy_cmds)
			easy_cmds[#easy_cmds].cb(SINKS_WITH_BT, "", "", 0)
			local by_id = {}
			for _, a in ipairs(added) do
				by_id[a.id] = a
			end
			assert.is_not_nil(by_id["60"])
			assert.equals("bluez_output.AA_BB_CC_DD_EE_FF.1", by_id["60"].meta.name)
			assert.equals("bluetooth", by_id["60"].state.connection)
		end)
	end)

	describe("'change' sink event", function()
		it("calls sinks.update with the sink's index and new state", function()
			local updated = {}
			pulse():start({ sinks = make_sink_handles(nil, updated) })
			easy_cmds[1].cb(SINKS_ALSA_DEFAULT, "", "", 0)
			local count = #easy_cmds
			wlc_cbs.stdout("Event 'change' on sink #57")
			assert.equals(count + 1, #easy_cmds)
			easy_cmds[#easy_cmds].cb(SINKS_ALSA_DEFAULT, "", "", 0)
			assert.equals(1, #updated)
			assert.equals("57", updated[1].id)
		end)

		it("is suppressed when pending_sinks[idx] > 0", function()
			local updated = {}
			local b = pulse()
			b:start({ sinks = make_sink_handles(nil, updated) })
			easy_cmds[1].cb(SINKS_ALSA_DEFAULT, "", "", 0)
			b.api.sink.adjust_perc("57", 5, function() end)
			local count = #easy_cmds
			wlc_cbs.stdout("Event 'change' on sink #57")
			assert.equals(count, #easy_cmds)
			assert.equals(0, #updated)
		end)

		it("does not suppress change events for a non-default sink", function()
			local updated = {}
			local b = pulse()
			b:start({ sinks = make_sink_handles(nil, updated) })
			easy_cmds[1].cb(SINKS_ALSA_DEFAULT, "", "", 0) -- default is #57
			b.api.sink.adjust_perc("57", 5, function() end)
			local count = #easy_cmds
			wlc_cbs.stdout("Event 'change' on sink #55") -- non-default sink
			assert.equals(count + 1, #easy_cmds) -- poll was triggered
			assert.equals(0, #updated) -- update not yet dispatched (poll in flight)
		end)

		it("calls on_sink when the changed sink is the default", function()
			local on_sink_calls = {}
			pulse():start({
				on_sink = function(id, state)
					on_sink_calls[#on_sink_calls + 1] = { id = id, state = state }
				end,
				sinks = make_sink_handles(),
			})
			easy_cmds[1].cb(SINKS_ALSA_DEFAULT, "", "", 0)
			on_sink_calls = {}
			wlc_cbs.stdout("Event 'change' on sink #57")
			easy_cmds[#easy_cmds].cb(SINKS_ALSA_DEFAULT, "", "", 0)
			assert.equals(1, #on_sink_calls)
			assert.equals("57", on_sink_calls[1].id)
		end)

		it("does not call on_sink when the changed sink is not the default", function()
			local on_sink_calls = {}
			pulse():start({
				on_sink = function(id, state)
					on_sink_calls[#on_sink_calls + 1] = { id = id, state = state }
				end,
				sinks = make_sink_handles(),
			})
			easy_cmds[1].cb(SINKS_ALSA_DEFAULT, "", "", 0)
			on_sink_calls = {}
			wlc_cbs.stdout("Event 'change' on sink #55")
			easy_cmds[#easy_cmds].cb(SINKS_ALSA_DEFAULT, "", "", 0)
			assert.equals(0, #on_sink_calls)
		end)
	end)

	describe("'remove' sink event", function()
		it("calls sinks.remove with the index string and does not poll", function()
			local removed = {}
			pulse():start({ sinks = make_sink_handles(nil, nil, removed) })
			easy_cmds[1].cb(SINKS_ALSA_DEFAULT, "", "", 0)
			local count = #easy_cmds
			wlc_cbs.stdout("Event 'remove' on sink #55")
			assert.equals(count, #easy_cmds)
			assert.equals(1, #removed)
			assert.equals("55", removed[1])
		end)
	end)

	describe("'change' server event", function()
		it("calls sinks.update for old and new defaults when default changes", function()
			local updated = {}
			pulse():start({ sinks = make_sink_handles(nil, updated) })
			easy_cmds[1].cb(SINKS_ALSA_DEFAULT, "", "", 0)
			local count = #easy_cmds
			wlc_cbs.stdout("Event 'change' on server #4294967295")
			assert.equals(count + 1, #easy_cmds)
			easy_cmds[#easy_cmds].cb(SINKS_HDMI_DEFAULT, "", "", 0)
			local by_id = {}
			for _, u in ipairs(updated) do
				by_id[u.id] = u
			end
			assert.is_not_nil(by_id["57"])
			assert.is_false(by_id["57"].state.is_default)
			assert.is_not_nil(by_id["55"])
			assert.is_true(by_id["55"].state.is_default)
		end)

		it("calls on_sink with the new default's numeric idx", function()
			local on_sink_calls = {}
			pulse():start({
				on_sink = function(id, state)
					on_sink_calls[#on_sink_calls + 1] = { id = id, state = state }
				end,
				sinks = make_sink_handles(),
			})
			easy_cmds[1].cb(SINKS_ALSA_DEFAULT, "", "", 0)
			on_sink_calls = {}
			wlc_cbs.stdout("Event 'change' on server #4294967295")
			easy_cmds[#easy_cmds].cb(SINKS_HDMI_DEFAULT, "", "", 0)
			assert.equals(1, #on_sink_calls)
			assert.equals("55", on_sink_calls[1].id)
			assert.is_true(on_sink_calls[1].state.is_default)
		end)

		it("does not poll when default is unchanged", function()
			pulse():start({ sinks = make_sink_handles() })
			easy_cmds[1].cb(SINKS_ALSA_DEFAULT, "", "", 0)
			local count = #easy_cmds
			wlc_cbs.stdout("Event 'change' on server #4294967295")
			easy_cmds[#easy_cmds].cb(SINKS_ALSA_DEFAULT, "", "", 0) -- same default
			assert.equals(count + 1, #easy_cmds) -- exactly one server poll, no extra sink poll
		end)

		it("is suppressed when pending.server > 0", function()
			local b = pulse()
			b:start({
				on_sink = function() end,
				sinks = make_sink_handles(),
			})
			easy_cmds[1].cb(SINKS_ALSA_DEFAULT, "", "", 0)
			b.api.sink.set_default("55", function() end)
			local count = #easy_cmds -- startup poll + set_default cmd
			wlc_cbs.stdout("Event 'change' on server #4294967295")
			assert.equals(count, #easy_cmds)
		end)
	end)

	describe("api.sink.set_default", function()
		it("issues pactl set-default-sink command", function()
			local b = pulse()
			b:start({ on_sink = function() end, sinks = make_sink_handles() })
			easy_cmds[1].cb(SINKS_ALSA_DEFAULT, "", "", 0)
			b.api.sink.set_default("alsa_output.pci", function() end)
			assert.truthy(cmd_str(easy_cmds[#easy_cmds].cmd):find("set%-default%-sink"))
			assert.truthy(cmd_str(easy_cmds[#easy_cmds].cmd):find("alsa_output.pci"))
		end)

		it("calls cb on exit 0", function()
			local called = false
			local b = pulse()
			b:start({ on_sink = function() end, sinks = make_sink_handles() })
			easy_cmds[1].cb(SINKS_ALSA_DEFAULT, "", "", 0)
			b.api.sink.set_default("55", function()
				called = true
			end)
			easy_cmds[#easy_cmds].cb("", "", "", 0)
			assert.is_true(called)
		end)

		it("does not call cb on non-zero exit", function()
			local called = false
			local b = pulse()
			b:start({ on_sink = function() end, sinks = make_sink_handles() })
			easy_cmds[1].cb(SINKS_ALSA_DEFAULT, "", "", 0)
			b.api.sink.set_default("55", function()
				called = true
			end)
			easy_cmds[#easy_cmds].cb("", "", "", 1)
			assert.is_false(called)
		end)

		it("decrements pending.server on non-zero exit so subsequent server events are not suppressed", function()
			local b = pulse()
			b:start({ on_sink = function() end, sinks = make_sink_handles() })
			easy_cmds[1].cb(SINKS_ALSA_DEFAULT, "", "", 0)
			b.api.sink.set_default("55", function() end)
			easy_cmds[#easy_cmds].cb("", "", "", 1) -- fail → decrement
			local count = #easy_cmds
			wlc_cbs.stdout("Event 'change' on server #4294967295")
			assert.equals(count + 1, #easy_cmds) -- not suppressed
		end)
	end)

	describe("source dispatch", function()
		local function make_source_handles(added, updated, removed)
			return {
				add = function(id, state, meta)
					if added then
						added[#added + 1] = { id = id, state = state, meta = meta }
					end
				end,
				update = function(id, state)
					if updated then
						updated[#updated + 1] = { id = id, state = state }
					end
				end,
				remove = function(id)
					if removed then
						removed[#removed + 1] = id
					end
				end,
			}
		end

		it("polls sources on start when sources handle is provided", function()
			pulse():start({ sources = make_source_handles() })
			assert.equals(1, #easy_cmds)
			assert.truthy(cmd_str(easy_cmds[1].cmd):find("list sources"))
		end)

		it("calls sources.add for each device and on_source with real numeric idx", function()
			local added, on_source_calls = {}, {}
			pulse():start({
				on_source = function(id, state)
					on_source_calls[#on_source_calls + 1] = { id = id, state = state }
				end,
				sources = make_source_handles(added),
			})
			easy_cmds[1].cb(SOURCES_INTERNAL_DEFAULT, "", "", 0)
			assert.equals(1, #added)
			assert.equals("6", added[1].id)
			assert.equals("alsa_input.pci-0000_00_1f.3.analog-stereo", added[1].meta.name)
			assert.equals(1, #on_source_calls)
			assert.equals("6", on_source_calls[1].id)
		end)

		it("calls sources.update on 'change' source event", function()
			local updated = {}
			pulse():start({ sources = make_source_handles(nil, updated) })
			easy_cmds[1].cb(SOURCES_INTERNAL_DEFAULT, "", "", 0)
			local count = #easy_cmds
			wlc_cbs.stdout("Event 'change' on source #6")
			assert.equals(count + 1, #easy_cmds)
			easy_cmds[#easy_cmds].cb(SOURCES_INTERNAL_DEFAULT, "", "", 0)
			assert.equals(1, #updated)
			assert.equals("6", updated[1].id)
		end)

		it("calls sources.remove with index string on 'remove' event without polling", function()
			local removed = {}
			pulse():start({ sources = make_source_handles(nil, nil, removed) })
			easy_cmds[1].cb(SOURCES_INTERNAL_DEFAULT, "", "", 0)
			local count = #easy_cmds
			wlc_cbs.stdout("Event 'remove' on source #6")
			assert.equals(count, #easy_cmds)
			assert.equals(1, #removed)
			assert.equals("6", removed[1])
		end)
	end)
end)
