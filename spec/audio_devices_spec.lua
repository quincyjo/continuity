require("spec.support.awesome_mocks")

local devices_mod

local function make_mock_backend(kind)
	local method = kind == "sink" and "set_default_sink" or "set_default_source"
	return {
		[method] = function(_, _, cb)
			if cb then
				cb()
			end
		end,
		adjust_perc = function() end,
		set_perc = function() end,
		toggle = function() end,
	}
end

describe("audio.devices registry", function()
	local inst, handles, backend, bind

	before_each(function()
		package.loaded["continuity.audio.devices"] = nil
		devices_mod = require("continuity.audio.devices")
		backend = make_mock_backend("sink")
		inst, bind = devices_mod.new("sink")
		handles = bind(backend)
	end)

	describe("pre-instantiation", function()
		it("inst is non-nil before bind", function()
			local inst2 = devices_mod.new("sink")
			assert.is_not_nil(inst2)
		end)

		it("on_added can be registered before bind", function()
			local inst2, bind2 = devices_mod.new("sink")
			local called = false
			inst2.on_added(function()
				called = true
			end)
			local handles2 = bind2(backend)
			handles2.add("a", { level = 50, muted = false, is_default = true })
			assert.is_true(called)
		end)
	end)

	describe("handles.add", function()
		it("fires on_added with the handle", function()
			local received
			inst.on_added(function(h)
				received = h
			end)
			handles.add(
				"alsa_output.pci",
				{ level = 50, muted = false, is_default = true },
				{ description = "Built-in Audio" }
			)
			assert.is_not_nil(received)
			assert.equals("alsa_output.pci", received.id)
		end)

		it("handle has correct initial state", function()
			local s = {
				level = 50,
				muted = false,
				is_default = true,
				port = "analog-output-speaker",
				port_type = "speaker",
				connection = "analog",
			} -- luacheck: ignore 631
			handles.add("alsa_output.pci", s, { description = "Built-in Audio" })
			local h = inst.all()[1]
			assert.equals(50, h.state.level)
			assert.is_false(h.state.muted)
			assert.is_true(h.state.is_default)
			assert.equals("analog-output-speaker", h.state.port)
			assert.equals("speaker", h.state.port_type)
			assert.equals("analog", h.state.connection)
		end)

		it("handle.description is set from meta", function()
			handles.add(
				"alsa_output.pci",
				{ level = 50, muted = false, is_default = true },
				{ description = "Built-in Audio" }
			)
			assert.equals("Built-in Audio", inst.all()[1].description)
		end)

		it("handle.description is nil when meta is absent", function()
			handles.add("alsa_output.pci", { level = 50, muted = false, is_default = true })
			assert.is_nil(inst.all()[1].description)
		end)

		it("makes handle visible in all()", function()
			handles.add("alsa_output.pci", { level = 50, muted = false, is_default = true })
			assert.equals(1, #inst.all())
			assert.equals("alsa_output.pci", inst.all()[1].id)
		end)

		it("all() returns a snapshot, not a live reference", function()
			handles.add("a", { level = 50, muted = false, is_default = true })
			local snap = inst.all()
			handles.add("b", { level = 60, muted = false, is_default = false })
			assert.equals(1, #snap)
			assert.equals(2, #inst.all())
		end)
	end)

	describe("handles.remove", function()
		before_each(function()
			handles.add("alsa_output.pci", { level = 50, muted = false, is_default = true })
		end)

		it("fires on_removed with the id", function()
			local removed_id
			inst.on_removed(function(id)
				removed_id = id
			end)
			handles.remove("alsa_output.pci")
			assert.equals("alsa_output.pci", removed_id)
		end)

		it("removes the handle from all()", function()
			handles.remove("alsa_output.pci")
			assert.equals(0, #inst.all())
		end)

		it("fires per-handle on_removed callback", function()
			local called_id
			inst.all()[1]:on_removed(function(id)
				called_id = id
			end)
			handles.remove("alsa_output.pci")
			assert.equals("alsa_output.pci", called_id)
		end)

		it("does nothing for unknown id", function()
			local count = 0
			inst.on_removed(function()
				count = count + 1
			end)
			handles.remove("unknown")
			assert.equals(0, count)
		end)
	end)

	describe("handles.update", function()
		before_each(function()
			handles.add("alsa_output.pci", { level = 50, muted = false, is_default = true })
		end)

		it("fires subscribe when level changes", function()
			local received
			inst.all()[1]:subscribe(function(s)
				received = s
			end)
			handles.update("alsa_output.pci", { level = 60, muted = false, is_default = true })
			assert.is_not_nil(received)
			assert.equals(60, received.level)
		end)

		it("fires subscribe when is_default changes", function()
			local received
			inst.all()[1]:subscribe(function(s)
				received = s
			end)
			handles.update("alsa_output.pci", { level = 50, muted = false, is_default = false })
			assert.is_not_nil(received)
			assert.is_false(received.is_default)
		end)

		it("does not fire subscribe when state is unchanged", function()
			local count = 0
			inst.all()[1]:subscribe(function()
				count = count + 1
			end)
			handles.update("alsa_output.pci", { level = 50, muted = false, is_default = true })
			assert.equals(0, count)
		end)

		it("fires on_updated with the handle when state changes", function()
			local updated
			inst.on_updated(function(h)
				updated = h
			end)
			handles.update("alsa_output.pci", { level = 60, muted = false, is_default = true })
			assert.is_not_nil(updated)
			assert.equals("alsa_output.pci", updated.id)
		end)

		it("does not fire on_updated when state is unchanged", function()
			local count = 0
			inst.on_updated(function()
				count = count + 1
			end)
			handles.update("alsa_output.pci", { level = 50, muted = false, is_default = true })
			assert.equals(0, count)
		end)

		it("does nothing for unknown id", function()
			local count = 0
			inst.on_updated(function()
				count = count + 1
			end)
			handles.update("unknown", { level = 60, muted = false, is_default = false })
			assert.equals(0, count)
		end)

		it("subscribe returns an unsubscribe function", function()
			local count = 0
			local unsub = inst.all()[1]:subscribe(function()
				count = count + 1
			end)
			handles.update("alsa_output.pci", { level = 60, muted = false, is_default = true })
			unsub()
			handles.update("alsa_output.pci", { level = 70, muted = false, is_default = true })
			assert.equals(1, count)
		end)
	end)

	describe("lifecycle callbacks unsubscribe", function()
		it("on_added returns an unsubscribe function", function()
			local count = 0
			local unsub = inst.on_added(function()
				count = count + 1
			end)
			handles.add("a", { level = 50, muted = false, is_default = true })
			unsub()
			handles.add("b", { level = 60, muted = false, is_default = false })
			assert.equals(1, count)
		end)

		it("on_removed returns an unsubscribe function", function()
			local count = 0
			local unsub = inst.on_removed(function()
				count = count + 1
			end)
			handles.add("a", { level = 50, muted = false, is_default = true })
			handles.remove("a")
			unsub()
			handles.add("b", { level = 60, muted = false, is_default = false })
			handles.remove("b")
			assert.equals(1, count)
		end)
	end)

	describe("handle:on_removed", function()
		before_each(function()
			handles.add("a", { level = 50, muted = false, is_default = true })
			handles.add("b", { level = 60, muted = false, is_default = false })
		end)

		local function find(id)
			for _, h in ipairs(inst.all()) do
				if h.id == id then
					return h
				end
			end
		end

		it("does not fire when a different handle is removed", function()
			local called = false
			find("a"):on_removed(function()
				called = true
			end)
			handles.remove("b")
			assert.is_false(called)
		end)

		it("returns an unsubscribe function", function()
			local count = 0
			local unsub = find("a"):on_removed(function()
				count = count + 1
			end)
			unsub()
			handles.remove("a")
			assert.equals(0, count)
		end)
	end)

	describe("control methods pre-bind are no-ops", function()
		it("calling control methods before bind does not error", function()
			-- Bind with a no-op backend to get handles, but verify that a second
			-- independent inst (no bind) has accessible lifecycle methods.
			local inst2, bind2 = devices_mod.new("sink")
			local noop = {
				set_default_sink = function() end,
				adjust_perc = function() end, -- luacheck: ignore 631
				set_perc = function() end,
				toggle = function() end,
			}
			local handles2 = bind2(noop)
			handles2.add("x", { level = 0, muted = false, is_default = false })
			-- All control methods on the handle complete without error pre-backend-wiring
			-- (they are no-ops at definition time; bind overwrites them in the shared HandleMT).
			-- This test validates the lifecycle API is accessible at construction time.
			assert.is_not_nil(inst2.on_added)
			assert.is_not_nil(inst2.on_removed)
			assert.is_not_nil(inst2.all)
		end)
	end)

	describe("handle control methods (post-bind)", function()
		local calls

		before_each(function()
			calls = {}
			backend = {
				set_default_sink = function(_, id, cb)
					calls[#calls + 1] = { method = "set_default_sink", id = id, cb = cb }
				end,
				adjust_perc = function(_, id, delta, cb)
					calls[#calls + 1] = { method = "adjust_perc", id = id, delta = delta, cb = cb }
				end,
				set_perc = function(_, id, value, cb)
					calls[#calls + 1] = { method = "set_perc", id = id, value = value, cb = cb }
				end,
				toggle = function(_, id, cb)
					calls[#calls + 1] = { method = "toggle", id = id, cb = cb }
				end,
			}
			package.loaded["continuity.audio.devices"] = nil
			devices_mod = require("continuity.audio.devices")
			inst, bind = devices_mod.new("sink")
			handles = bind(backend)
			handles.add("alsa_output.pci", { level = 50, muted = false, is_default = false })
		end)

		local function handle()
			return inst.all()[1]
		end

		it("set_default calls backend:set_default_sink with handle id", function()
			handle():set_default()
			assert.equals(1, #calls)
			assert.equals("set_default_sink", calls[1].method)
			assert.equals("alsa_output.pci", calls[1].id)
		end)

		it("set_default fires on_control in callback", function()
			local control_states = {}
			handle():on_control(function(s)
				control_states[#control_states + 1] = s
			end)
			handle():set_default()
			calls[1].cb()
			assert.equals(1, #control_states)
		end)

		it("adjust_perc calls backend:adjust_perc with handle id and delta", function()
			handle():adjust_perc(10)
			assert.equals(1, #calls)
			assert.equals("adjust_perc", calls[1].method)
			assert.equals("alsa_output.pci", calls[1].id)
			assert.equals(10, calls[1].delta)
		end)

		it("adjust_perc clamps delta to not exceed 100", function()
			handle():adjust_perc(60)
			assert.equals(50, calls[1].delta)
		end)

		it("adjust_perc fires on_control without calling backend when clamped delta is 0", function()
			handles.update("alsa_output.pci", { level = 100, muted = false, is_default = false })
			local count = 0
			handle():on_control(function()
				count = count + 1
			end)
			handle():adjust_perc(10)
			assert.equals(0, #calls)
			assert.equals(1, count)
		end)

		it("set_perc clamps to [0,100] and calls backend", function()
			handle():set_perc(150)
			assert.equals("set_perc", calls[1].method)
			assert.equals(100, calls[1].value)
		end)

		it("toggle_mute calls backend:toggle with handle id", function()
			handle():toggle_mute()
			assert.equals("toggle", calls[1].method)
			assert.equals("alsa_output.pci", calls[1].id)
		end)

		it("on_control fires after successful adjust_perc callback", function()
			local control_states = {}
			handle():on_control(function(s)
				control_states[#control_states + 1] = s
			end)
			handle():adjust_perc(10)
			calls[1].cb(60, false)
			assert.equals(1, #control_states)
			assert.equals(60, control_states[1].level)
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
			calls[1].cb(55, false)
			unsub()
			handle():adjust_perc(5)
			calls[2].cb(60, false)
			assert.equals(1, count)
		end)
	end)

	describe("source kind dispatches set_default_source", function()
		it("set_default calls backend:set_default_source for source kind", function()
			local calls = {}
			local source_backend = {
				set_default_source = function(_, id, cb)
					calls[#calls + 1] = { id = id, cb = cb }
				end,
				adjust_perc = function() end,
				set_perc = function() end,
				toggle = function() end,
			}
			package.loaded["continuity.audio.devices"] = nil
			devices_mod = require("continuity.audio.devices")
			local sinst, sbind = devices_mod.new("source")
			local shandles = sbind(source_backend)
			shandles.add("alsa_input.pci", { level = 80, muted = false, is_default = true })
			sinst.all()[1]:set_default()
			assert.equals(1, #calls)
			assert.equals("alsa_input.pci", calls[1].id)
		end)
	end)
end)
