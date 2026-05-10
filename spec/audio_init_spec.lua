require("spec.support.awesome_mocks")

describe("audio (init)", function()
	local Audio
	local on_sink, on_source
	local start_cbs
	local sink_api_calls, source_api_calls

	local function make_backend()
		sink_api_calls = {}
		source_api_calls = {}
		return {
			api = {
				sink = {
					adjust_perc = function(idx, delta, cb)
						sink_api_calls[#sink_api_calls + 1] =
							{ method = "adjust_perc", idx = idx, delta = delta, cb = cb }
					end,
					set_perc = function(idx, value, cb)
						sink_api_calls[#sink_api_calls + 1] = { method = "set_perc", idx = idx, value = value, cb = cb }
					end,
					toggle = function(idx, cb)
						sink_api_calls[#sink_api_calls + 1] = { method = "toggle", idx = idx, cb = cb }
					end,
					mute = function() end,
					unmute = function() end,
					set_default = function() end,
				},
				source = {
					adjust_perc = function(idx, delta, cb)
						source_api_calls[#source_api_calls + 1] =
							{ method = "adjust_perc", idx = idx, delta = delta, cb = cb }
					end,
					set_perc = function(idx, value, cb)
						source_api_calls[#source_api_calls + 1] =
							{ method = "set_perc", idx = idx, value = value, cb = cb }
					end,
					toggle = function(idx, cb)
						source_api_calls[#source_api_calls + 1] = { method = "toggle", idx = idx, cb = cb }
					end,
					mute = function() end,
					unmute = function() end,
					set_default = function() end,
				},
				sink_input = {
					adjust_perc = function() end,
					set_perc = function() end,
					toggle = function() end,
					move = function() end,
				},
			},
			start = function(_self, cbs)
				start_cbs = cbs
				on_sink = cbs.on_sink
				on_source = cbs.on_source
			end,
		}
	end

	before_each(function()
		package.loaded["continuity.audio"] = nil
		package.loaded["continuity.audio.inputs"] = nil
		package.loaded["continuity.audio.devices"] = nil
		on_sink = nil
		on_source = nil
		start_cbs = nil
		Audio = require("continuity.audio")
	end)

	describe("pre-instantiation", function()
		it("Audio.inputs is non-nil before setup()", function()
			assert.is_not_nil(Audio.inputs)
		end)

		it("Audio.sinks is non-nil before setup()", function()
			assert.is_not_nil(Audio.sinks)
		end)

		it("Audio.sources is non-nil before setup()", function()
			assert.is_not_nil(Audio.sources)
		end)

		it("Audio.inputs.on_added can be registered before setup() and fires after bind", function()
			local received
			Audio.inputs.on_added(function(h)
				received = h
			end)
			Audio.setup({ backend = make_backend() })
			start_cbs.inputs.add("263", { level = 50, muted = false })
			assert.is_not_nil(received)
			assert.equals("263", received.id)
		end)

		it("Audio.sinks.on_added can be registered before setup() and fires after bind", function()
			local received
			Audio.sinks.on_added(function(h)
				received = h
			end)
			Audio.setup({ backend = make_backend() })
			local s = { level = 50, muted = false, is_default = true }
			start_cbs.sinks.add("alsa_output.pci", s, { description = "Built-in" })
			assert.is_not_nil(received)
			assert.equals("alsa_output.pci", received.id)
		end)

		it("Audio.sources.on_added can be registered before setup() and fires after bind", function()
			local received
			Audio.sources.on_added(function(h)
				received = h
			end)
			Audio.setup({ backend = make_backend() })
			start_cbs.sources.add("alsa_input.pci", { level = 80, muted = false, is_default = true })
			assert.is_not_nil(received)
			assert.equals("alsa_input.pci", received.id)
		end)
	end)

	describe("setup() wires collections to backend", function()
		before_each(function()
			Audio.setup({ backend = make_backend() })
		end)

		it("backend.start receives inputs handles", function()
			assert.is_not_nil(start_cbs.inputs)
			assert.is_function(start_cbs.inputs.add)
		end)

		it("backend.start receives sinks handles", function()
			assert.is_not_nil(start_cbs.sinks)
			assert.is_function(start_cbs.sinks.add)
		end)

		it("backend.start receives sources handles", function()
			assert.is_not_nil(start_cbs.sources)
			assert.is_function(start_cbs.sources.add)
		end)
	end)

	describe("Audio.Volume.id and Audio.Capture.id reflect real backend idx", function()
		before_each(function()
			Audio.setup({ backend = make_backend() })
		end)

		it("Audio.Volume.id is updated to the idx from on_sink", function()
			on_sink("57", { level = 40, muted = false }, {})
			assert.equals("57", Audio.Volume.id)
		end)

		it("Audio.Volume.id updates when default sink changes", function()
			on_sink("57", { level = 40, muted = false }, {})
			on_sink("55", { level = 20, muted = false }, {})
			assert.equals("55", Audio.Volume.id)
		end)

		it("Audio.Capture.id is updated to the idx from on_source", function()
			on_source("12", { level = 80, muted = false }, {})
			assert.equals("12", Audio.Capture.id)
		end)
	end)

	describe("Audio.Volume control methods use api.sink with real idx", function()
		before_each(function()
			Audio.setup({ backend = make_backend() })
			on_sink("57", { level = 40, muted = false }, {})
		end)

		it("adjust_perc calls backend.api.sink.adjust_perc with real idx", function()
			Audio.Volume:adjust_perc(5)
			assert.equals(1, #sink_api_calls)
			assert.equals("adjust_perc", sink_api_calls[1].method)
			assert.equals("57", sink_api_calls[1].idx)
			assert.equals(5, sink_api_calls[1].delta)
		end)

		it("set_perc calls backend.api.sink.set_perc with real idx", function()
			Audio.Volume:set_perc(50)
			assert.equals("set_perc", sink_api_calls[1].method)
			assert.equals("57", sink_api_calls[1].idx)
		end)

		it("toggle_mute calls backend.api.sink.toggle with real idx", function()
			Audio.Volume:toggle_mute()
			assert.equals("toggle", sink_api_calls[1].method)
			assert.equals("57", sink_api_calls[1].idx)
		end)

		it("adjust_perc does NOT call source api", function()
			Audio.Volume:adjust_perc(5)
			assert.equals(0, #source_api_calls)
		end)
	end)

	describe("Audio.Capture control methods use api.source with real idx", function()
		before_each(function()
			Audio.setup({ backend = make_backend() })
			on_source("12", { level = 80, muted = false }, {})
		end)

		it("toggle_mute calls backend.api.source.toggle with real idx", function()
			Audio.Capture:toggle_mute()
			assert.equals(1, #source_api_calls)
			assert.equals("toggle", source_api_calls[1].method)
			assert.equals("12", source_api_calls[1].idx)
		end)

		it("toggle_mute does NOT call sink api", function()
			Audio.Capture:toggle_mute()
			assert.equals(0, #sink_api_calls)
		end)
	end)

	describe("Audio.Volume on_ready", function()
		it("queues callback when not yet initialized", function()
			local called = false
			Audio.Volume:on_ready(function()
				called = true
			end)
			assert.is_false(called)
		end)

		it("fires queued callback when on_sink fires", function()
			local got = nil
			Audio.Volume:on_ready(function(s)
				got = s
			end)
			Audio.setup({ backend = make_backend() })
			on_sink("57", { level = 40, muted = false }, {})
			assert.is_not_nil(got)
			assert.equals(40, got.level)
		end)

		it("fires immediately when already initialized", function()
			Audio.setup({ backend = make_backend() })
			on_sink("57", { level = 40, muted = false }, {})
			local got = nil
			Audio.Volume:on_ready(function(s)
				got = s
			end)
			assert.is_not_nil(got)
			assert.equals(40, got.level)
		end)
	end)

	describe("Audio.Capture on_ready", function()
		it("queues callback when not yet initialized", function()
			local called = false
			Audio.Capture:on_ready(function()
				called = true
			end)
			assert.is_false(called)
		end)

		it("fires queued callback when on_source fires", function()
			local got = nil
			Audio.Capture:on_ready(function(s)
				got = s
			end)
			Audio.setup({ backend = make_backend() })
			on_source("12", { level = 80, muted = false }, {})
			assert.is_not_nil(got)
			assert.equals(80, got.level)
		end)

		it("fires immediately when already initialized", function()
			Audio.setup({ backend = make_backend() })
			on_source("12", { level = 80, muted = false }, {})
			local got = nil
			Audio.Capture:on_ready(function(s)
				got = s
			end)
			assert.is_not_nil(got)
			assert.equals(80, got.level)
		end)
	end)

	describe("Audio.Volume refresh (post-init change detection)", function()
		before_each(function()
			Audio.setup({ backend = make_backend() })
		end)

		it("does not fire subscribers when backend repeats the same state", function()
			local s = {
				level = 50,
				muted = false,
				port = "analog-output-speaker",
				port_type = "speaker",
				connection = "analog",
			}
			on_sink("57", s, {})
			local count = 0
			Audio.Volume:subscribe(function()
				count = count + 1
			end)
			on_sink("57", s, {})
			assert.equals(0, count)
		end)

		it("fires subscribers when level changes", function()
			local s = {
				level = 50,
				muted = false,
				port = "analog-output-speaker",
				port_type = "speaker",
				connection = "analog",
			}
			on_sink("57", s, {})
			local count = 0
			Audio.Volume:subscribe(function()
				count = count + 1
			end)
			on_sink("57", {
				level = 60,
				muted = false,
				port = "analog-output-speaker",
				port_type = "speaker",
				connection = "analog",
			}, {})
			assert.equals(1, count)
		end)

		it("fires subscribers when muted changes", function()
			local s = { level = 50, muted = false, port = nil, port_type = nil, connection = nil }
			on_sink("57", s, {})
			local count = 0
			Audio.Volume:subscribe(function()
				count = count + 1
			end)
			on_sink("57", { level = 50, muted = true, port = nil, port_type = nil, connection = nil }, {})
			assert.equals(1, count)
		end)

		it("fires subscribers when port changes", function()
			local s = {
				level = 50,
				muted = false,
				port = "analog-output-speaker",
				port_type = "speaker",
				connection = "analog",
			}
			on_sink("57", s, {})
			local count = 0
			Audio.Volume:subscribe(function()
				count = count + 1
			end)
			on_sink("57", {
				level = 50,
				muted = false,
				port = "analog-output-headphones",
				port_type = "headphones",
				connection = "analog",
			}, {})
			assert.equals(1, count)
		end)

		it("does not fire on_control on backend re-event (only update() fires on_control)", function()
			local s = { level = 50, muted = false, port = nil, port_type = nil, connection = nil }
			on_sink("57", s, {})
			local count = 0
			Audio.Volume:on_control(function()
				count = count + 1
			end)
			on_sink("57", s, {})
			assert.equals(0, count)
		end)

		it("refresh() sets name and description from meta", function()
			on_sink("57", { level = 50, muted = false }, { name = "alsa_output.pci", description = "Built-in Audio" })
			assert.equals("alsa_output.pci", Audio.Volume.name)
			assert.equals("Built-in Audio", Audio.Volume.description)
		end)

		it("refresh() clears name and description when meta omits them", function()
			on_sink("57", { level = 50, muted = false }, { name = "alsa_output.pci", description = "Built-in Audio" })
			on_sink("57", { level = 50, muted = false }, { name = nil, description = nil })
			assert.is_nil(Audio.Volume.name)
			assert.is_nil(Audio.Volume.description)
		end)

		it("fires subscribers when description changes", function()
			local s = { level = 50, muted = false }
			on_sink("57", s, { name = "dev", description = "Old" })
			local count = 0
			Audio.Volume:subscribe(function()
				count = count + 1
			end)
			on_sink("57", s, { name = "dev", description = "New" })
			assert.equals(1, count)
		end)

		it("fires subscribers when name changes", function()
			local s = { level = 50, muted = false }
			on_sink("57", s, { name = "dev.a", description = "Audio" })
			local count = 0
			Audio.Volume:subscribe(function()
				count = count + 1
			end)
			on_sink("57", s, { name = "dev.b", description = "Audio" })
			assert.equals(1, count)
		end)

		it("does not fire subscribers when meta is repeated unchanged", function()
			local s = { level = 50, muted = false }
			local meta = { name = "dev", description = "Audio" }
			on_sink("57", s, meta)
			local count = 0
			Audio.Volume:subscribe(function()
				count = count + 1
			end)
			on_sink("57", s, meta)
			assert.equals(0, count)
		end)
	end)
end)
