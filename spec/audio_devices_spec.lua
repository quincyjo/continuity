require("spec.support.awesome_mocks")

local devices_mod

local function make_mock_api_sub()
	return {
		set_default = function(_idx, cb)
			if cb then
				cb()
			end
		end,
		set_port = function() end,
		adjust_perc = function() end,
		set_perc = function() end,
		toggle = function() end,
	}
end

describe("audio.devices registry", function()
	local inst, handles, api_sub, bind

	before_each(function()
		package.loaded["continuity.audio.devices"] = nil
		devices_mod = require("continuity.audio.devices")
		api_sub = make_mock_api_sub()
		inst, bind = devices_mod.new()
		handles = bind(api_sub)
	end)

	describe("pre-instantiation", function()
		it("inst is non-nil before bind", function()
			local inst2 = devices_mod.new()
			assert.is_not_nil(inst2)
		end)

		it("on_added can be registered before bind", function()
			local inst2, bind2 = devices_mod.new()
			local called = false
			inst2:on_added(function()
				called = true
			end)
			local handles2 = bind2(api_sub)
			handles2.add("a", { level = 50, muted = false, is_default = true })
			assert.is_true(called)
		end)
	end)

	describe("handles.add", function()
		it("fires on_added with the handle", function()
			local received
			inst:on_added(function(h)
				received = h
			end)
			handles.add(
				"57",
				{ level = 50, muted = false, is_default = true },
				{ name = "alsa_output.pci", description = "Built-in Audio" }
			)
			assert.is_not_nil(received)
			assert.equals("57", received.id)
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
			local h = inst:all()[1]
			assert.equals(50, h.state.level)
			assert.is_false(h.state.muted)
			assert.is_true(h.state.is_default)
			assert.equals("analog-output-speaker", h.state.port)
			assert.equals("speaker", h.state.port_type)
			assert.equals("analog", h.state.connection)
		end)

		it("handle.name is set from meta", function()
			handles.add(
				"57",
				{ level = 50, muted = false, is_default = true },
				{ name = "alsa_output.pci", description = "Built-in Audio" }
			)
			assert.equals("alsa_output.pci", inst:all()[1].name)
		end)

		it("handle.description is set from meta", function()
			handles.add(
				"57",
				{ level = 50, muted = false, is_default = true },
				{ name = "alsa_output.pci", description = "Built-in Audio" }
			)
			assert.equals("Built-in Audio", inst:all()[1].description)
		end)

		it("handle.name is nil when meta is absent", function()
			handles.add("57", { level = 50, muted = false, is_default = true })
			assert.is_nil(inst:all()[1].name)
		end)

		it("handle.description is nil when meta is absent", function()
			handles.add("57", { level = 50, muted = false, is_default = true })
			assert.is_nil(inst:all()[1].description)
		end)

		it("makes handle visible in all()", function()
			handles.add("alsa_output.pci", { level = 50, muted = false, is_default = true })
			assert.equals(1, #inst:all())
			assert.equals("alsa_output.pci", inst:all()[1].id)
		end)

		it("all() returns a snapshot, not a live reference", function()
			handles.add("a", { level = 50, muted = false, is_default = true })
			local snap = inst:all()
			handles.add("b", { level = 60, muted = false, is_default = false })
			assert.equals(1, #snap)
			assert.equals(2, #inst:all())
		end)

		it("get() returns the handle for a known id", function()
			handles.add("alsa_output.pci", { level = 50, muted = false, is_default = true })
			local handle = inst:get("alsa_output.pci")
			assert.is_not_nil(handle)
			assert.equals("alsa_output.pci", handle.id)
		end)

		it("get() returns nil for an unknown id", function()
			assert.is_nil(inst:get("does_not_exist"))
		end)

		describe("idempotent (handle already exists)", function()
			local meta = { name = "alsa_output.pci", description = "Built-in Audio" }

			before_each(function()
				handles.add("57", { level = 40, muted = false, is_default = true }, meta)
			end)

			it("does not fire on_added a second time", function()
				local count = 0
				inst:on_added(function()
					count = count + 1
				end)
				handles.add("57", { level = 50, muted = false, is_default = true }, meta)
				assert.equals(0, count)
			end)

			it("fires subscribe when state changes on second add", function()
				local received
				inst:all()[1]:subscribe(function(s)
					received = s
				end)
				handles.add("57", { level = 50, muted = false, is_default = true }, meta)
				assert.is_not_nil(received)
				assert.equals(50, received.level)
			end)

			it("does not fire subscribe when state is unchanged on second add", function()
				local count = 0
				inst:all()[1]:subscribe(function()
					count = count + 1
				end)
				handles.add("57", { level = 40, muted = false, is_default = true }, meta)
				assert.equals(0, count)
			end)

			it("updates name and description from meta on second add", function()
				handles.add(
					"57",
					{ level = 40, muted = false, is_default = true },
					{ name = "new_name", description = "New Desc" }
				)
				assert.equals("new_name", inst:all()[1].name)
				assert.equals("New Desc", inst:all()[1].description)
			end)

			it("all() still contains exactly one handle after second add", function()
				handles.add("57", { level = 50, muted = false, is_default = true }, meta)
				assert.equals(1, #inst:all())
			end)

			it("subscriber registered before second add is not dropped", function()
				local count = 0
				inst:all()[1]:subscribe(function()
					count = count + 1
				end)
				handles.add("57", { level = 50, muted = false, is_default = true }, meta)
				handles.update("57", { level = 60, muted = false, is_default = true })
				assert.equals(2, count)
			end)
		end)
	end)

	describe("handles.remove", function()
		before_each(function()
			handles.add("alsa_output.pci", { level = 50, muted = false, is_default = true })
		end)

		it("fires on_removed with the id", function()
			local removed_id
			inst:on_removed(function(id)
				removed_id = id
			end)
			handles.remove("alsa_output.pci")
			assert.equals("alsa_output.pci", removed_id)
		end)

		it("removes the handle from all()", function()
			handles.remove("alsa_output.pci")
			assert.equals(0, #inst:all())
		end)

		it("fires per-handle on_removed callback", function()
			local called_id
			inst:all()[1]:on_removed(function(id)
				called_id = id
			end)
			handles.remove("alsa_output.pci")
			assert.equals("alsa_output.pci", called_id)
		end)

		it("does nothing for unknown id", function()
			local count = 0
			inst:on_removed(function()
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
			inst:all()[1]:subscribe(function(s)
				received = s
			end)
			handles.update("alsa_output.pci", { level = 60, muted = false, is_default = true })
			assert.is_not_nil(received)
			assert.equals(60, received.level)
		end)

		it("fires subscribe when is_default changes", function()
			local received
			inst:all()[1]:subscribe(function(s)
				received = s
			end)
			handles.update("alsa_output.pci", { level = 50, muted = false, is_default = false })
			assert.is_not_nil(received)
			assert.is_false(received.is_default)
		end)

		it("does not fire subscribe when state is unchanged", function()
			local count = 0
			inst:all()[1]:subscribe(function()
				count = count + 1
			end)
			handles.update("alsa_output.pci", { level = 50, muted = false, is_default = true })
			assert.equals(0, count)
		end)

		it("fires on_updated with the handle when state changes", function()
			local updated
			inst:on_updated(function(h)
				updated = h
			end)
			handles.update("alsa_output.pci", { level = 60, muted = false, is_default = true })
			assert.is_not_nil(updated)
			assert.equals("alsa_output.pci", updated.id)
		end)

		it("does not fire on_updated when state is unchanged", function()
			local count = 0
			inst:on_updated(function()
				count = count + 1
			end)
			handles.update("alsa_output.pci", { level = 50, muted = false, is_default = true })
			assert.equals(0, count)
		end)

		it("does nothing for unknown id", function()
			local count = 0
			inst:on_updated(function()
				count = count + 1
			end)
			handles.update("unknown", { level = 60, muted = false, is_default = false })
			assert.equals(0, count)
		end)

		it("subscribe returns an unsubscribe function", function()
			local count = 0
			local unsub = inst:all()[1]:subscribe(function()
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
			local unsub = inst:on_added(function()
				count = count + 1
			end)
			handles.add("a", { level = 50, muted = false, is_default = true })
			unsub()
			handles.add("b", { level = 60, muted = false, is_default = false })
			assert.equals(1, count)
		end)

		it("on_removed returns an unsubscribe function", function()
			local count = 0
			local unsub = inst:on_removed(function()
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
			for _, h in ipairs(inst:all()) do
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
			local inst2, bind2 = devices_mod.new()
			local noop = {
				set_default = function() end,
				adjust_perc = function() end,
				set_perc = function() end,
				toggle = function() end,
			}
			local handles2 = bind2(noop)
			handles2.add("x", { level = 0, muted = false, is_default = false })
			assert.is_not_nil(inst2.on_added)
			assert.is_not_nil(inst2.on_removed)
			assert.is_not_nil(inst2.all)
		end)
	end)

	describe("handle control methods (post-bind)", function()
		local calls

		before_each(function()
			calls = {}
			api_sub = {
				set_default = function(idx, cb)
					calls[#calls + 1] = { method = "set_default", idx = idx, cb = cb }
				end,
				adjust_perc = function(idx, delta, cb)
					calls[#calls + 1] = { method = "adjust_perc", idx = idx, delta = delta, cb = cb }
				end,
				set_perc = function(idx, value, cb)
					calls[#calls + 1] = { method = "set_perc", idx = idx, value = value, cb = cb }
				end,
				toggle = function(idx, cb)
					calls[#calls + 1] = { method = "toggle", idx = idx, cb = cb }
				end,
			}
			package.loaded["continuity.audio.devices"] = nil
			devices_mod = require("continuity.audio.devices")
			inst, bind = devices_mod.new()
			handles = bind(api_sub)
			handles.add("alsa_output.pci", { level = 50, muted = false, is_default = false })
		end)

		local function handle()
			return inst:all()[1]
		end

		it("set_default calls api_sub.set_default with handle idx", function()
			handle():set_default()
			assert.equals(1, #calls)
			assert.equals("set_default", calls[1].method)
			assert.equals("alsa_output.pci", calls[1].idx)
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

		it("adjust_perc calls api_sub.adjust_perc with handle idx and delta", function()
			handle():adjust_perc(10)
			assert.equals(1, #calls)
			assert.equals("adjust_perc", calls[1].method)
			assert.equals("alsa_output.pci", calls[1].idx)
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

		it("set_perc clamps to [0,100] and calls api_sub", function()
			handle():set_perc(150)
			assert.equals("set_perc", calls[1].method)
			assert.equals(100, calls[1].value)
		end)

		it("toggle_mute calls api_sub.toggle with handle idx", function()
			handle():toggle_mute()
			assert.equals("toggle", calls[1].method)
			assert.equals("alsa_output.pci", calls[1].idx)
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

		it("on_updated fires on inst when state changes after control", function()
			local updated
			inst:on_updated(function(h)
				updated = h
			end)
			handle():adjust_perc(10)
			calls[1].cb(60, false)
			assert.is_not_nil(updated)
			assert.equals("alsa_output.pci", updated.id)
			assert.equals(60, updated.state.level)
		end)

		it("on_updated does not fire when state is unchanged after control", function()
			local count = 0
			inst:on_updated(function()
				count = count + 1
			end)
			handle():adjust_perc(10)
			calls[1].cb(50, false) -- unchanged
			assert.equals(0, count)
		end)
	end)

	describe("handles.patch", function()
		it("fires subscriber when field changes and preserves other fields", function()
			local states = {}
			handles.add("57", { level = 40, muted = false, is_default = false })
			inst:all()[1]:subscribe(function(s)
				states[#states + 1] = s
			end)
			handles.patch("57", { is_default = true })
			assert.equals(1, #states)
			assert.is_true(states[1].is_default)
			assert.equals(40, states[1].level)
			assert.is_false(states[1].muted)
		end)

		it("does not fire subscriber when value is unchanged", function()
			local count = 0
			handles.add("57", { level = 40, muted = false, is_default = true })
			inst:all()[1]:subscribe(function()
				count = count + 1
			end)
			handles.patch("57", { is_default = true })
			assert.equals(0, count)
		end)

		it("fires on_updated when changed, not when unchanged", function()
			local updated = {}
			inst:on_updated(function(h)
				updated[#updated + 1] = h
			end)
			handles.add("57", { level = 40, muted = false, is_default = false })
			handles.patch("57", { is_default = true })
			assert.equals(1, #updated)
			handles.patch("57", { is_default = true })
			assert.equals(1, #updated)
		end)

		it("returns current state and meta when handle exists", function()
			handles.add("57", { level = 40, muted = false }, { name = "alsa_out", description = "Built-in" })
			local s, meta = handles.patch("57", { is_default = true })
			assert.is_not_nil(s)
			assert.is_true(s.is_default)
			assert.equals(40, s.level)
			assert.equals("alsa_out", meta.name)
			assert.equals("Built-in", meta.description)
		end)

		it("returns nil, nil for unknown id", function()
			local s, meta = handles.patch("unknown", { is_default = true })
			assert.is_nil(s)
			assert.is_nil(meta)
		end)
	end)

	describe("set_default uses api_sub regardless of device type", function()
		it("set_default calls api_sub.set_default with handle idx", function()
			local calls = {}
			local source_api = {
				set_default = function(idx, cb)
					calls[#calls + 1] = { idx = idx, cb = cb }
				end,
				adjust_perc = function() end,
				set_perc = function() end,
				toggle = function() end,
			}
			package.loaded["continuity.audio.devices"] = nil
			devices_mod = require("continuity.audio.devices")
			local sinst, sbind = devices_mod.new()
			local shandles = sbind(source_api)
			shandles.add("alsa_input.pci", { level = 80, muted = false, is_default = true })
			sinst:all()[1]:set_default()
			assert.equals(1, #calls)
			assert.equals("alsa_input.pci", calls[1].idx)
		end)
	end)

	describe("ports_changed detection", function()
		it("no change when both old and new ports are nil", function()
			local sub_count = 0
			inst:on_added(function(h)
				h:subscribe(function()
					sub_count = sub_count + 1
				end)
			end)
			handles.add("57", { level = 50, muted = false, ports = nil })
			sub_count = 0
			handles.update("57", { level = 50, muted = false, ports = nil })
			assert.equals(0, sub_count)
		end)

		it("fires subscriber when ports count changes", function()
			local sub_count = 0
			inst:on_added(function(h)
				h:subscribe(function()
					sub_count = sub_count + 1
				end)
			end)
			handles.add("57", { level = 50, muted = false, ports = { { name = "a", availability = "unknown" } } })
			sub_count = 0
			handles.update("57", {
				level = 50,
				muted = false,
				ports = {
					{ name = "a", availability = "unknown" },
					{ name = "b", availability = "available" },
				},
			})
			assert.equals(1, sub_count)
		end)

		it("fires subscriber when port availability changes", function()
			local sub_count = 0
			inst:on_added(function(h)
				h:subscribe(function()
					sub_count = sub_count + 1
				end)
			end)
			handles.add("57", { level = 50, muted = false, ports = { { name = "a", availability = "not available" } } })
			sub_count = 0
			handles.update("57", { level = 50, muted = false, ports = { { name = "a", availability = "available" } } })
			assert.equals(1, sub_count)
		end)

		it("no change when ports are identical", function()
			local sub_count = 0
			inst:on_added(function(h)
				h:subscribe(function()
					sub_count = sub_count + 1
				end)
			end)
			local ports = { { name = "a", availability = "unknown" } }
			handles.add("57", { level = 50, muted = false, ports = ports })
			sub_count = 0
			handles.update("57", { level = 50, muted = false, ports = { { name = "a", availability = "unknown" } } })
			assert.equals(0, sub_count)
		end)
	end)

	describe("set_port dispatch", function()
		it("set_port calls api_sub.set_port with the handle id and port name", function()
			local calls = {}
			api_sub.set_port = function(idx, port_name, cb)
				calls[#calls + 1] = { idx = idx, port_name = port_name }
				if cb then
					cb()
				end
			end
			handles.add("57", { level = 50, muted = false })
			inst:all()[1]:set_port("analog-output-headphones")
			assert.equals(1, #calls)
			assert.equals("57", calls[1].idx)
			assert.equals("analog-output-headphones", calls[1].port_name)
		end)

		it("set_port cb fires on_control", function()
			local control_count = 0
			api_sub.set_port = function(_idx, _port, cb)
				if cb then
					cb()
				end
			end
			handles.add("57", { level = 50, muted = false })
			inst:all()[1]:on_control(function()
				control_count = control_count + 1
			end)
			inst:all()[1]:set_port("analog-output-headphones")
			assert.equals(1, control_count)
		end)

		it("set_port accepts an AudioPort table and extracts .name", function()
			local calls = {}
			api_sub.set_port = function(idx, port_name, cb)
				calls[#calls + 1] = { idx = idx, port_name = port_name }
				if cb then
					cb()
				end
			end
			handles.add("57", { level = 50, muted = false })
			inst:all()[1]:set_port({ name = "analog-output-headphones", availability = "available" })
			assert.equals(1, #calls)
			assert.equals("analog-output-headphones", calls[1].port_name)
		end)

		it("set_port is a no-op before bind", function()
			local inst2, bind2 = devices_mod.new()
			inst2:on_added(function() end)
			local handles2 = bind2(api_sub)
			handles2.add("57", { level = 50, muted = false })
			-- Should not error
			assert.has_no_errors(function()
				inst2:all()[1]:set_port("analog-output-headphones")
			end)
		end)
	end)
end)
