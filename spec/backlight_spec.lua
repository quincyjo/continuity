-- spec/backlight_spec.lua
require("spec.support.awesome_mocks")

describe("backlight module", function()
	local backlight, mock_backend

	before_each(function()
		package.loaded["continuity.backlight"] = nil
		backlight = require("continuity.backlight")
		mock_backend = {
			set_perc_calls = {},
			adjust_perc_calls = {},
			_cbs = nil,
			start = function(self, cbs)
				self._cbs = cbs
			end,
			stop = function(self) end, -- luacheck: ignore 212
			set_perc = function(self, id, brightness, cb)
				self.set_perc_calls[#self.set_perc_calls + 1] = { id = id, brightness = brightness, cb = cb }
			end,
			adjust_perc = function(self, id, delta, cb)
				self.adjust_perc_calls[#self.adjust_perc_calls + 1] = { id = id, delta = delta, cb = cb }
			end,
		}
	end)

	local function add_device(id, kind, brightness, steps)
		mock_backend._cbs.on_device_added({ id = id, kind = kind, brightness = brightness, steps = steps })
	end
	local function remove_device(id)
		mock_backend._cbs.on_device_removed(id)
	end
	local function change(id, brightness)
		mock_backend._cbs.on_change(id, brightness)
	end
	local function display_devices()
		local result = {}
		for _, h in ipairs(backlight.devices.all()) do
			if h.kind == "display" then
				result[#result + 1] = h
			end
		end
		return result
	end

	describe("primary_display", function()
		it("exists before setup()", function()
			assert.is_not_nil(backlight.primary_display)
		end)

		it("has kind 'display'", function()
			assert.equals("display", backlight.primary_display.kind)
		end)

		it("set_perc is a no-op before wired — no error", function()
			assert.has_no_errors(function()
				backlight.primary_display:set_perc(50)
			end)
		end)

		it("adjust_perc is a no-op before wired — no error", function()
			assert.has_no_errors(function()
				backlight.primary_display:adjust_perc(10)
			end)
		end)

		it("set is a no-op before wired — no error", function()
			assert.has_no_errors(function()
				backlight.primary_display:set(5)
			end)
		end)

		it("adjust is a no-op before wired — no error", function()
			assert.has_no_errors(function()
				backlight.primary_display:adjust(1)
			end)
		end)
	end)

	describe("on_ready", function()
		it("queues callback when not yet initialized", function()
			local called = false
			backlight.primary_display:on_ready(function()
				called = true
			end)
			assert.is_false(called)
		end)

		it("fires queued callback when device is wired", function()
			local got = nil
			backlight.primary_display:on_ready(function(b)
				got = b
			end)
			backlight.setup({ backend = mock_backend })
			add_device("intel_backlight", "display", 75)
			assert.equals(75, got.brightness)
			assert.is_nil(got.raw)
		end)

		it("fires immediately when already initialized", function()
			backlight.setup({ backend = mock_backend })
			add_device("intel_backlight", "display", 75)
			local got = nil
			backlight.primary_display:on_ready(function(b)
				got = b
			end)
			assert.equals(75, got.brightness)
		end)
	end)

	describe("subscribe", function()
		it("does not fire on registration", function()
			backlight.setup({ backend = mock_backend })
			add_device("intel_backlight", "display", 75)
			local called = false
			backlight.primary_display:subscribe(function()
				called = true
			end)
			assert.is_false(called)
		end)

		it("fires on brightness change", function()
			backlight.setup({ backend = mock_backend })
			add_device("intel_backlight", "display", 75)
			local got = nil
			backlight.primary_display:subscribe(function(b)
				got = b
			end)
			change("intel_backlight", 50)
			assert.equals(50, got.brightness)
		end)

		it("does not fire when brightness unchanged", function()
			backlight.setup({ backend = mock_backend })
			add_device("intel_backlight", "display", 75)
			local count = 0
			backlight.primary_display:subscribe(function()
				count = count + 1
			end)
			change("intel_backlight", 75)
			assert.equals(0, count)
		end)

		it("returns an unsubscribe function", function()
			backlight.setup({ backend = mock_backend })
			add_device("intel_backlight", "display", 75)
			local count = 0
			local unsub = backlight.primary_display:subscribe(function()
				count = count + 1
			end)
			unsub()
			change("intel_backlight", 50)
			assert.equals(0, count)
		end)
	end)

	describe("on_control", function()
		it("fires when set_perc control cb fires", function()
			backlight.setup({ backend = mock_backend })
			add_device("intel_backlight", "display", 50)
			local got = nil
			backlight.primary_display:on_control(function(b)
				got = b
			end)
			backlight.primary_display:set_perc(80)
			mock_backend.set_perc_calls[1].cb(80)
			assert.equals(80, got.brightness)
		end)

		it("fires when adjust_perc control cb fires", function()
			backlight.setup({ backend = mock_backend })
			add_device("intel_backlight", "display", 50)
			local got = nil
			backlight.primary_display:on_control(function(b)
				got = b
			end)
			backlight.primary_display:adjust_perc(10)
			mock_backend.adjust_perc_calls[1].cb(60)
			assert.equals(60, got.brightness)
		end)

		it("fires even when brightness is unchanged", function()
			backlight.setup({ backend = mock_backend })
			add_device("intel_backlight", "display", 100)
			local count = 0
			backlight.primary_display:on_control(function()
				count = count + 1
			end)
			backlight.primary_display:set_perc(100)
			mock_backend.set_perc_calls[1].cb(100)
			assert.equals(1, count)
		end)

		it("fires subscribe when brightness changes via control", function()
			backlight.setup({ backend = mock_backend })
			add_device("intel_backlight", "display", 50)
			local sub_got = nil
			backlight.primary_display:subscribe(function(b)
				sub_got = b
			end)
			backlight.primary_display:set_perc(80)
			mock_backend.set_perc_calls[1].cb(80)
			assert.equals(80, sub_got.brightness)
		end)

		it("does not fire subscribe when brightness is unchanged via control", function()
			backlight.setup({ backend = mock_backend })
			add_device("intel_backlight", "display", 80)
			local count = 0
			backlight.primary_display:subscribe(function()
				count = count + 1
			end)
			backlight.primary_display:set_perc(80)
			mock_backend.set_perc_calls[1].cb(80)
			assert.equals(0, count)
		end)

		it("returns an unsubscribe function", function()
			backlight.setup({ backend = mock_backend })
			add_device("intel_backlight", "display", 50)
			local count = 0
			local unsub = backlight.primary_display:on_control(function()
				count = count + 1
			end)
			unsub()
			backlight.primary_display:set_perc(80)
			mock_backend.set_perc_calls[1].cb(80)
			assert.equals(0, count)
		end)
	end)

	describe("unsubscribe", function()
		it("handle:unsubscribe is idempotent", function()
			backlight.setup({ backend = mock_backend })
			add_device("intel_backlight", "display", 75)
			local count = 0
			local cb = function()
				count = count + 1
			end
			backlight.primary_display:subscribe(cb)
			backlight.primary_display:unsubscribe(cb)
			backlight.primary_display:unsubscribe(cb)
			change("intel_backlight", 50)
			assert.equals(0, count)
		end)

		it("returned unsubscribe fn is idempotent", function()
			backlight.setup({ backend = mock_backend })
			add_device("intel_backlight", "display", 75)
			local count = 0
			local unsub = backlight.primary_display:subscribe(function()
				count = count + 1
			end)
			unsub()
			unsub()
			change("intel_backlight", 50)
			assert.equals(0, count)
		end)
	end)

	describe("setup", function()
		it("starts the backend", function()
			backlight.setup({ backend = mock_backend })
			assert.is_not_nil(mock_backend._cbs)
		end)

		it("second call logs a warning and is a no-op", function()
			local warned = false
			require("gears").debug.print_warning = function()
				warned = true
			end
			local start_count = 0
			local counting_backend = {
				set_perc_calls = {},
				_cbs = nil,
				start = function(self, cbs) -- luacheck: ignore 212
					start_count = start_count + 1
					self._cbs = cbs
				end,
				stop = function(self) end, -- luacheck: ignore 212
				set_perc = function(self, id, brightness) end, -- luacheck: ignore 212
				adjust_perc = function(self, id, delta) end, -- luacheck: ignore 212
			}
			backlight.setup({ backend = counting_backend })
			backlight.setup({ backend = counting_backend })
			assert.is_true(warned)
			assert.equals(1, start_count)
		end)
	end)

	describe("devices.on_added", function()
		it("fires with handle when backend adds device", function()
			backlight.setup({ backend = mock_backend })
			local got = nil
			backlight.devices.on_added(function(h)
				got = h
			end)
			add_device("intel_backlight", "display", 50)
			assert.equals("intel_backlight", got.id)
			assert.equals("display", got.kind)
		end)

		it("wires primary_display to first display device", function()
			backlight.setup({ backend = mock_backend })
			add_device("intel_backlight", "display", 50)
			assert.equals("intel_backlight", backlight.primary_display.id)
			assert.equals(50, backlight.primary_display.state.brightness)
		end)

		it("populates steps on handle when provided", function()
			backlight.setup({ backend = mock_backend })
			add_device("intel_backlight", "display", 50, 20)
			assert.equals(20, backlight.primary_display.steps)
		end)

		it("leaves steps nil when not provided", function()
			backlight.setup({ backend = mock_backend })
			add_device("intel_backlight", "display", 50)
			assert.is_nil(backlight.primary_display.steps)
		end)

		it("populates display devices", function()
			backlight.setup({ backend = mock_backend })
			add_device("intel_backlight", "display", 50)
			local displays = display_devices()
			assert.equals(1, #displays)
			assert.equals("intel_backlight", displays[1].id)
		end)

		it("does not rewire primary_display for a second display device", function()
			backlight.setup({ backend = mock_backend })
			add_device("intel_backlight", "display", 50)
			add_device("acpi_video0", "display", 30)
			assert.equals("intel_backlight", backlight.primary_display.id)
			assert.equals(2, #display_devices())
		end)

		it("does not wire primary_display for keyboard devices", function()
			backlight.setup({ backend = mock_backend })
			add_device("kbd_backlight", "keyboard", 66)
			assert.is_nil(backlight.primary_display.id)
		end)

		it("does not include keyboard devices in display_devices", function()
			backlight.setup({ backend = mock_backend })
			add_device("kbd_backlight", "keyboard", 66)
			assert.equals(0, #display_devices())
		end)

		it("returns unsubscribe function", function()
			backlight.setup({ backend = mock_backend })
			local count = 0
			local unsub = backlight.devices.on_added(function()
				count = count + 1
			end)
			unsub()
			add_device("intel_backlight", "display", 50)
			assert.equals(0, count)
		end)
	end)

	describe("devices.on_removed", function()
		it("fires with id when backend removes device", function()
			backlight.setup({ backend = mock_backend })
			add_device("intel_backlight", "display", 50)
			local removed = nil
			backlight.devices.on_removed(function(id)
				removed = id
			end)
			remove_device("intel_backlight")
			assert.equals("intel_backlight", removed)
		end)

		it("removes device from devices.all()", function()
			backlight.setup({ backend = mock_backend })
			add_device("intel_backlight", "display", 50)
			remove_device("intel_backlight")
			assert.equals(0, #backlight.devices.all())
		end)

		it("returns unsubscribe function", function()
			backlight.setup({ backend = mock_backend })
			add_device("intel_backlight", "display", 50)
			local count = 0
			local unsub = backlight.devices.on_removed(function()
				count = count + 1
			end)
			unsub()
			remove_device("intel_backlight")
			assert.equals(0, count)
		end)

		it("fires subscriber when a keyboard device is removed", function()
			backlight.setup({ backend = mock_backend })
			add_device("kbd_backlight", "keyboard", 66)
			local removed = nil
			backlight.devices.on_removed(function(id)
				removed = id
			end)
			remove_device("kbd_backlight")
			assert.equals("kbd_backlight", removed)
		end)
	end)

	describe("devices.on_updated", function()
		it("fires with the handle when brightness changes via backend", function()
			backlight.setup({ backend = mock_backend })
			add_device("intel_backlight", "display", 75)
			local updated = nil
			backlight.devices.on_updated(function(h)
				updated = h
			end)
			change("intel_backlight", 50)
			assert.is_not_nil(updated)
			assert.equals(50, updated.state.brightness)
		end)

		it("does not fire when brightness is unchanged", function()
			backlight.setup({ backend = mock_backend })
			add_device("intel_backlight", "display", 75)
			local fired = false
			backlight.devices.on_updated(function()
				fired = true
			end)
			change("intel_backlight", 75)
			assert.is_false(fired)
		end)

		it("returns unsubscribe function", function()
			backlight.setup({ backend = mock_backend })
			add_device("intel_backlight", "display", 75)
			local count = 0
			local unsub = backlight.devices.on_updated(function()
				count = count + 1
			end)
			change("intel_backlight", 50)
			assert.equals(1, count)
			unsub()
			change("intel_backlight", 60)
			assert.equals(1, count)
		end)
	end)

	describe("devices.all()", function()
		it("returns empty table before any devices", function()
			backlight.setup({ backend = mock_backend })
			assert.same({}, backlight.devices.all())
		end)

		it("returns devices as array after add", function()
			backlight.setup({ backend = mock_backend })
			add_device("intel_backlight", "display", 75)
			local all = backlight.devices.all()
			assert.equals(1, #all)
			assert.equals("intel_backlight", all[1].id)
			assert.equals(75, all[1].state.brightness)
			assert.equals("display", all[1].kind)
		end)

		it("reflects brightness changes via handle.state", function()
			backlight.setup({ backend = mock_backend })
			add_device("intel_backlight", "display", 75)
			change("intel_backlight", 50)
			assert.equals(50, backlight.devices.all()[1].state.brightness)
		end)

		it("removes device after on_device_removed", function()
			backlight.setup({ backend = mock_backend })
			add_device("intel_backlight", "display", 75)
			remove_device("intel_backlight")
			assert.equals(0, #backlight.devices.all())
		end)
	end)

	describe("devices.get()", function()
		it("returns the handle for a known id", function()
			backlight.setup({ backend = mock_backend })
			add_device("intel_backlight", "display", 50)
			local handle = backlight.devices.get("intel_backlight")
			assert.is_not_nil(handle)
			assert.equals("intel_backlight", handle.id)
		end)

		it("returns nil for an unknown id", function()
			backlight.setup({ backend = mock_backend })
			assert.is_nil(backlight.devices.get("does_not_exist"))
		end)
	end)

	describe("stop()", function()
		it("resets state and allows re-setup", function()
			backlight.setup({ backend = mock_backend })
			add_device("intel_backlight", "display", 75)
			backlight.stop()
			assert.same({}, backlight.devices.all())
		end)

		it("resets primary_display to unwired handle", function()
			backlight.setup({ backend = mock_backend })
			add_device("intel_backlight", "display", 75)
			backlight.stop()
			assert.is_nil(backlight.primary_display.id)
			assert.equals("display", backlight.primary_display.kind)
		end)

		it("calls stop() on the backend", function()
			local stop_called = false
			local stoppable_backend = {
				_cbs = nil,
				set_perc_calls = {},
				start = function(self, cbs)
					self._cbs = cbs
				end, -- luacheck: ignore 212
				stop = function(_)
					stop_called = true
				end,
				set_perc = function(self, id, brightness) end, -- luacheck: ignore 212
				adjust_perc = function(self, id, delta) end, -- luacheck: ignore 212
			}
			backlight.setup({ backend = stoppable_backend })
			backlight.stop()
			assert.is_true(stop_called)
		end)

		it("allows setup() to be called again after stop()", function()
			backlight.setup({ backend = mock_backend })
			backlight.stop()
			local new_backend = {
				_cbs = nil,
				set_perc_calls = {},
				start = function(self, cbs) -- luacheck: ignore 212
					self._cbs = cbs
				end,
				stop = function(self) end, -- luacheck: ignore 212
				set_perc = function(self, id, b) -- luacheck: ignore 212
					self.set_perc_calls[#self.set_perc_calls + 1] = { id = id, brightness = b }
				end,
				adjust_perc = function(self, id, delta) end, -- luacheck: ignore 212
			}
			assert.has_no_errors(function()
				backlight.setup({ backend = new_backend })
			end)
			new_backend._cbs.on_device_added({ id = "intel_backlight", kind = "display", brightness = 50 })
			assert.equals("intel_backlight", backlight.primary_display.id)
		end)
	end)

	describe("set_perc / adjust_perc", function()
		it("set_perc delegates to backend with clamped percentage", function()
			backlight.setup({ backend = mock_backend })
			add_device("intel_backlight", "display", 50)
			backlight.primary_display:set_perc(80)
			assert.equals(1, #mock_backend.set_perc_calls)
			assert.equals("intel_backlight", mock_backend.set_perc_calls[1].id)
			assert.equals(80, mock_backend.set_perc_calls[1].brightness)
		end)

		it("set_perc clamps to 100", function()
			backlight.setup({ backend = mock_backend })
			add_device("intel_backlight", "display", 50)
			backlight.primary_display:set_perc(150)
			assert.equals(100, mock_backend.set_perc_calls[1].brightness)
		end)

		it("set_perc clamps to 0", function()
			backlight.setup({ backend = mock_backend })
			add_device("intel_backlight", "display", 50)
			backlight.primary_display:set_perc(-10)
			assert.equals(0, mock_backend.set_perc_calls[1].brightness)
		end)

		it("adjust_perc delegates delta to backend:adjust_perc", function()
			backlight.setup({ backend = mock_backend })
			add_device("intel_backlight", "display", 90)
			backlight.primary_display:adjust_perc(20)
			assert.equals(1, #mock_backend.adjust_perc_calls)
			assert.equals("intel_backlight", mock_backend.adjust_perc_calls[1].id)
			assert.equals(20, mock_backend.adjust_perc_calls[1].delta)
		end)

		it("adjust_perc passes negative delta unchanged", function()
			backlight.setup({ backend = mock_backend })
			add_device("intel_backlight", "display", 5)
			backlight.primary_display:adjust_perc(-20)
			assert.equals(-20, mock_backend.adjust_perc_calls[1].delta)
		end)
	end)

	describe("set / adjust (step-based)", function()
		local step_backend

		before_each(function()
			step_backend = {
				set_perc_calls = {},
				adjust_perc_calls = {},
				set_calls = {},
				adjust_calls = {},
				_cbs = nil,
				start = function(self, cbs)
					self._cbs = cbs
				end,
				stop = function(self) end, -- luacheck: ignore 212
				set_perc = function(self, id, v, cb)
					self.set_perc_calls[#self.set_perc_calls + 1] = { id = id, brightness = v, cb = cb }
				end,
				adjust_perc = function(self, id, d, cb)
					self.adjust_perc_calls[#self.adjust_perc_calls + 1] = { id = id, delta = d, cb = cb }
				end,
				set = function(self, id, step, cb)
					self.set_calls[#self.set_calls + 1] = { id = id, step = step, cb = cb }
				end,
				adjust = function(self, id, delta, cb)
					self.adjust_calls[#self.adjust_calls + 1] = { id = id, delta = delta, cb = cb }
				end,
			}
		end)

		it("set delegates to backend:set when backend supports it", function()
			backlight.setup({ backend = step_backend })
			step_backend._cbs.on_device_added({ id = "intel_backlight", kind = "display", brightness = 50, steps = 20 })
			backlight.primary_display:set(10)
			assert.equals(1, #step_backend.set_calls)
			assert.equals("intel_backlight", step_backend.set_calls[1].id)
			assert.equals(10, step_backend.set_calls[1].step)
		end)

		it("adjust delegates to backend:adjust when backend supports it", function()
			backlight.setup({ backend = step_backend })
			step_backend._cbs.on_device_added({ id = "intel_backlight", kind = "display", brightness = 50, steps = 20 })
			backlight.primary_display:adjust(2)
			assert.equals(1, #step_backend.adjust_calls)
			assert.equals("intel_backlight", step_backend.adjust_calls[1].id)
			assert.equals(2, step_backend.adjust_calls[1].delta)
		end)

		it("set is a no-op when backend has no set — no error", function()
			backlight.setup({ backend = mock_backend })
			add_device("intel_backlight", "display", 50)
			assert.has_no_errors(function()
				backlight.primary_display:set(5)
			end)
			assert.equals(0, #mock_backend.set_perc_calls)
		end)

		it("adjust is a no-op when backend has no adjust — no error", function()
			backlight.setup({ backend = mock_backend })
			add_device("intel_backlight", "display", 50)
			assert.has_no_errors(function()
				backlight.primary_display:adjust(1)
			end)
			assert.equals(0, #mock_backend.adjust_perc_calls)
		end)
	end)
end)
