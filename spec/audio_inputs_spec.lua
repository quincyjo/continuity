require("spec.support.awesome_mocks")

local inputs_mod

local function make_mock_api_sub()
	return {
		adjust_perc = function() end,
		set_perc = function() end,
		toggle = function() end,
		move = function() end,
	}
end

describe("audio.inputs registry", function()
	local inst, handles, api_sub, bind

	before_each(function()
		package.loaded["continuity.audio.inputs"] = nil
		inputs_mod = require("continuity.audio.inputs")
		api_sub = make_mock_api_sub()
		inst, bind = inputs_mod.new()
		handles = bind(api_sub)
	end)

	describe("handles.add", function()
		it("fires on_input_added with the handle", function()
			local received
			inst.on_added(function(h)
				received = h
			end)
			handles.add("263", { level = 41, muted = false, name = "Spotify", sink = 57 }, { app_name = "spotify" })
			assert.is_not_nil(received)
			assert.equals("263", received.id)
			assert.equals(41, received.state.level)
			assert.equals("spotify", received.app_name)
		end)

		it("makes handle visible via all()", function()
			handles.add("263", { level = 41, muted = false })
			local all = inst.all()
			assert.equals(1, #all)
			assert.equals("263", all[1].id)
		end)

		it("all() returns a snapshot — not a live reference", function()
			handles.add("263", { level = 41, muted = false })
			local snap = inst.all()
			handles.add("264", { level = 50, muted = false })
			assert.equals(1, #snap)
			assert.equals(2, #inst.all())
		end)

		it("handle has correct initial state and metadata", function()
			handles.add(
				"263",
				{ level = 41, muted = false, name = "Spotify", sink = 57 },
				{ app_name = "spotify", icon_name = "spotify-client" }
			)
			local h = inst.all()[1]
			assert.equals("263", h.id)
			assert.equals(41, h.state.level)
			assert.is_false(h.state.muted)
			assert.equals("Spotify", h.state.name)
			assert.equals(57, h.state.sink)
			assert.equals("spotify", h.app_name)
			assert.equals("spotify-client", h.icon_name)
		end)
	end)

	describe("handles.remove", function()
		before_each(function()
			handles.add("263", { level = 41, muted = false })
		end)

		it("fires on_input_removed with the id", function()
			local removed_id
			inst.on_removed(function(id)
				removed_id = id
			end)
			handles.remove("263")
			assert.equals("263", removed_id)
		end)

		it("removes handle from all()", function()
			handles.remove("263")
			assert.equals(0, #inst.all())
		end)

		it("does nothing for unknown id", function()
			local called = false
			inst.on_removed(function()
				called = true
			end)
			handles.remove("999")
			assert.is_false(called)
		end)
	end)

	describe("on_input_added / on_input_removed unsubscribe", function()
		it("on_input_added returns an unsubscribe function that stops callbacks", function()
			local count = 0
			local unsub = inst.on_added(function()
				count = count + 1
			end)
			handles.add("263", { level = 41, muted = false })
			unsub()
			handles.add("264", { level = 50, muted = false })
			assert.equals(1, count)
		end)

		it("on_input_removed returns an unsubscribe function", function()
			local count = 0
			local unsub = inst.on_removed(function()
				count = count + 1
			end)
			handles.add("263", { level = 41, muted = false })
			handles.remove("263")
			unsub()
			handles.add("264", { level = 50, muted = false })
			handles.remove("264")
			assert.equals(1, count)
		end)
	end)

	describe("handles.update", function()
		before_each(function()
			handles.add("263", { level = 41, muted = false })
		end)

		it("merges partial state into the handle", function()
			handles.update("263", { level = 60 })
			assert.equals(60, inst.all()[1].state.level)
			assert.is_false(inst.all()[1].state.muted) -- unchanged
		end)

		it("fires per-handle subscribe callback when state changes", function()
			local received
			inst.all()[1]:subscribe(function(s)
				received = s
			end)
			handles.update("263", { level = 60 })
			assert.is_not_nil(received)
			assert.equals(60, received.level)
		end)

		it("does not fire subscribe when state is unchanged", function()
			local count = 0
			inst.all()[1]:subscribe(function()
				count = count + 1
			end)
			handles.update("263", { level = 41 }) -- same value
			assert.equals(0, count)
		end)

		it("fires on_input_updated with the handle", function()
			local updated
			inst.on_updated(function(h)
				updated = h
			end)
			handles.update("263", { level = 60 })
			assert.is_not_nil(updated)
			assert.equals("263", updated.id)
		end)

		it("does not fire on_input_updated when state is unchanged", function()
			local count = 0
			inst.on_updated(function()
				count = count + 1
			end)
			handles.update("263", { level = 41 })
			assert.equals(0, count)
		end)

		it("does nothing for unknown id", function()
			local count = 0
			inst.on_updated(function()
				count = count + 1
			end)
			handles.update("999", { level = 50 })
			assert.equals(0, count)
		end)

		it("subscribe returns an unsubscribe function", function()
			local count = 0
			local h = inst.all()[1]
			local unsub = h:subscribe(function()
				count = count + 1
			end)
			handles.update("263", { level = 60 })
			unsub()
			handles.update("263", { level = 70 })
			assert.equals(1, count)
		end)
	end)

	describe("handle:on_removed", function()
		before_each(function()
			handles.add("263", { level = 41, muted = false })
		end)

		it("fires when handles.remove is called for this handle", function()
			local called_id
			inst.all()[1]:on_removed(function(id)
				called_id = id
			end)
			handles.remove("263")
			assert.equals("263", called_id)
		end)

		it("does not fire when a different handle is removed", function()
			local called = false
			inst.all()[1]:on_removed(function()
				called = true
			end)
			handles.add("264", { level = 50, muted = false })
			handles.remove("264")
			assert.is_false(called)
		end)

		it("returns an unsubscribe function", function()
			local count = 0
			local unsub = inst.all()[1]:on_removed(function()
				count = count + 1
			end)
			unsub()
			handles.remove("263")
			assert.equals(0, count)
		end)
	end)

	describe("handle control methods", function()
		local calls

		before_each(function()
			calls = {}
			api_sub = {
				adjust_perc = function(id, delta, cb)
					calls[#calls + 1] = { method = "adjust", id = id, delta = delta, cb = cb }
				end,
				set_perc = function(id, value, cb)
					calls[#calls + 1] = { method = "set", id = id, value = value, cb = cb }
				end,
				toggle = function(id, cb)
					calls[#calls + 1] = { method = "toggle", id = id, cb = cb }
				end,
				move = function(input_id, sink_id, cb)
					calls[#calls + 1] = { method = "move", input_id = input_id, sink_id = sink_id, cb = cb }
				end,
			}
			package.loaded["continuity.audio.inputs"] = nil
			inputs_mod = require("continuity.audio.inputs")
			inst, bind = inputs_mod.new()
			handles = bind(api_sub)
			handles.add("263", { level = 50, muted = false })
		end)

		local function handle()
			return inst.all()[1]
		end

		it("adjust_perc calls api_sub.adjust_perc with clamped delta", function()
			handle():adjust_perc(10)
			assert.equals(1, #calls)
			assert.equals("adjust", calls[1].method)
			assert.equals("263", calls[1].id)
			assert.equals(10, calls[1].delta)
		end)

		it("adjust_perc clamps delta to not exceed 100", function()
			handle():adjust_perc(60) -- level=50, delta=60 would exceed 100
			assert.equals(50, calls[1].delta) -- clamped to 50
		end)

		it("adjust_perc fires on_control without calling api_sub when clamped delta is 0", function()
			handles.update("263", { level = 100 })
			local control_count = 0
			handle():on_control(function()
				control_count = control_count + 1
			end)
			handle():adjust_perc(10) -- already at 100
			assert.equals(0, #calls) -- api_sub not called
			assert.equals(1, control_count)
		end)

		it("set_perc clamps to [0, 100] and calls api_sub", function()
			handle():set_perc(150)
			assert.equals("set", calls[1].method)
			assert.equals(100, calls[1].value)
		end)

		it("toggle_mute calls api_sub.toggle", function()
			handle():toggle_mute()
			assert.equals("toggle", calls[1].method)
			assert.equals("263", calls[1].id)
		end)

		it("on_control fires after successful control callback", function()
			local control_states = {}
			handle():on_control(function(s)
				control_states[#control_states + 1] = s
			end)
			handle():adjust_perc(10)
			calls[1].cb(60, false) -- simulate api_sub response
			assert.equals(1, #control_states)
			assert.equals(60, control_states[1].level)
		end)

		it("on_control fires even when state is unchanged", function()
			local count = 0
			handle():on_control(function()
				count = count + 1
			end)
			handle():adjust_perc(10)
			calls[1].cb(50, false) -- same level
			assert.equals(1, count)
		end)

		it("subscribe fires only when state changes after control", function()
			local sub_count = 0
			handle():subscribe(function()
				sub_count = sub_count + 1
			end)
			handle():adjust_perc(10)
			calls[1].cb(50, false) -- unchanged
			assert.equals(0, sub_count)
			handle():adjust_perc(10)
			calls[2].cb(60, false) -- changed
			assert.equals(1, sub_count)
		end)

		it("on_control returns an unsubscribe function", function()
			local count = 0
			local unsub = handle():on_control(function()
				count = count + 1
			end)
			handle():adjust_perc(5)
			calls[1].cb(55, false) -- fires on_control
			unsub()
			handle():adjust_perc(5)
			calls[2].cb(60, false) -- should not fire since unsubscribed
			assert.equals(1, count)
		end)

		it("move_to with a handle target calls api_sub.move with handle id", function()
			local sink_handle = { id = "alsa_output.usb" }
			handle():move_to(sink_handle)
			assert.equals(1, #calls)
			assert.equals("move", calls[1].method)
			assert.equals("263", calls[1].input_id)
			assert.equals("alsa_output.usb", calls[1].sink_id)
		end)

		it("move_to with a string target passes it through directly", function()
			handle():move_to("alsa_output.pci")
			assert.equals("263", calls[1].input_id)
			assert.equals("alsa_output.pci", calls[1].sink_id)
		end)

		it("move_to with an integer target passes it through directly", function()
			handle():move_to(57)
			assert.equals("263", calls[1].input_id)
			assert.equals(57, calls[1].sink_id)
		end)

		it("move_to fires on_control in the callback", function()
			local count = 0
			handle():on_control(function()
				count = count + 1
			end)
			handle():move_to("alsa_output.pci")
			calls[1].cb()
			assert.equals(1, count)
		end)
	end)
end)
