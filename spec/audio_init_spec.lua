require("spec.support.awesome_mocks")

describe("audio (init)", function()
	local Audio
	local on_sink
	local start_cbs

	local function make_backend()
		return {
			start = function(_self, cbs)
				start_cbs = cbs
				on_sink = cbs.on_sink
			end,
			adjust_perc = function() end,
			set_perc = function() end,
			toggle = function() end,
			set_default_sink = function() end,
			set_default_source = function() end,
		}
	end

	before_each(function()
		package.loaded["continuity.audio"] = nil
		package.loaded["continuity.audio.inputs"] = nil
		package.loaded["continuity.audio.devices"] = nil
		on_sink = nil
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
			on_sink("Master", s)
			local count = 0
			Audio.Volume:subscribe(function()
				count = count + 1
			end)
			on_sink("Master", s)
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
			on_sink("Master", s)
			local count = 0
			Audio.Volume:subscribe(function()
				count = count + 1
			end)
			on_sink("Master", {
				level = 60,
				muted = false,
				port = "analog-output-speaker",
				port_type = "speaker",
				connection = "analog",
			})
			assert.equals(1, count)
		end)

		it("fires subscribers when muted changes", function()
			local s = { level = 50, muted = false, port = nil, port_type = nil, connection = nil }
			on_sink("Master", s)
			local count = 0
			Audio.Volume:subscribe(function()
				count = count + 1
			end)
			on_sink("Master", { level = 50, muted = true, port = nil, port_type = nil, connection = nil })
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
			on_sink("Master", s)
			local count = 0
			Audio.Volume:subscribe(function()
				count = count + 1
			end)
			on_sink("Master", {
				level = 50,
				muted = false,
				port = "analog-output-headphones",
				port_type = "headphones",
				connection = "analog",
			})
			assert.equals(1, count)
		end)

		it("does not fire on_control on backend re-event (only update() fires on_control)", function()
			local s = { level = 50, muted = false, port = nil, port_type = nil, connection = nil }
			on_sink("Master", s)
			local count = 0
			Audio.Volume:on_control(function()
				count = count + 1
			end)
			on_sink("Master", s)
			assert.equals(0, count)
		end)

		it("refresh() updates Audio.Volume.description from state meta", function()
			on_sink("Master", { level = 50, muted = false, description = "Built-in Audio" })
			assert.equals("Built-in Audio", Audio.Volume.description)
		end)
	end)
end)
