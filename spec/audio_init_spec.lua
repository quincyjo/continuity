require("spec.support.awesome_mocks")

describe("audio (init)", function()
	local Audio
	local on_sink

	local function make_backend()
		return {
			start = function(_self, cbs)
				on_sink = cbs.on_sink
			end,
			adjust_perc = function() end,
			set_perc = function() end,
			toggle = function() end,
		}
	end

	before_each(function()
		package.loaded["continuity.audio"] = nil
		package.loaded["continuity.audio.inputs"] = nil
		on_sink = nil
		Audio = require("continuity.audio")
		Audio.setup({ backend = make_backend() })
	end)

	describe("Audio.Volume refresh (post-init change detection)", function()
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
	end)
end)
