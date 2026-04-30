-- Shared mock stubs for AwesomeWM modules.
-- Require this at the top of each spec file before requiring modules under test.
--
-- Stubbed sub-APIs:
--   awful.spawn.easy_async        — no-op by default; replace in spec as needed
--   awful.spawn.with_line_callback — returns {} by default
--   gears.debug.print_warning     — no-op by default; replace in spec as needed
--   gears.timer                   — constructor returns a table with start/stop/again;
--                                    fire() triggers the callback manually (test-only);
--                                    _created list tracks all instances (reset with
--                                    require("gears")._created = {} in before_each);
--                                    autostart/single_shot accepted but ignored —
--                                    timers do NOT fire automatically in tests
--   naughty.notify                — returns { id = 1 } by default
--
-- NOT stubbed (add here if a spec requires them):
--   awful.util, awful.screen, wibox, beautiful, gears.filesystem, etc.
--
-- Global stubs (set directly, not via package.preload):
--   awesome.kill(pid, signal) — no-op by default; replace in spec as needed

-- awesome is a global in AwesomeWM, not a module.
awesome = { kill = function(pid, signal) end, connect_signal = function(name, cb) end } -- luacheck: globals awesome

package.preload["awful"] = function()
	return {
		spawn = {
			easy_async = function(cmd, cb) end,
			-- Returns a fake PID integer, matching the real awful.spawn.with_line_callback API.
			with_line_callback = function(cmd, callbacks)
				return 0
			end,
		},
		button = function(mods, btn, fn)
			return {}
		end,
	}
end

local _gears_mod
_gears_mod = {
	debug = { print_warning = function(msg) end },
	table = {
		join = function(...)
			return {}
		end,
	},
	_created = {}, -- all timer instances, appended on each gears.timer() call
	timer = function(opts)
		local t = {
			_opts = opts,
			again_count = 0,
			stopped = false,
			start = function(self) end,
			stop = function(self)
				self.stopped = true
			end,
			again = function(self)
				self.again_count = self.again_count + 1
			end,
			-- test-only: manually trigger the timer callback.
			-- No-ops if stop() has been called, matching real AwesomeWM semantics.
			fire = function(self)
				if self.stopped then
					return
				end
				if self._opts and self._opts.callback then
					self._opts.callback()
				end
			end,
		}
		_gears_mod._created[#_gears_mod._created + 1] = t
		return t
	end,
}
package.preload["gears"] = function()
	return _gears_mod
end

local _naughty_mod
_naughty_mod = {
	notify = function(opts)
		return { id = 1 }
	end,
	connect_signal = function(name, cb) end,
	notification_closed_reason = { dismissed_by_command = "dismissed_by_command" },
	config = { notify_callback = nil },
}
-- Shared factory used by the base mock and by spec overrides.
_naughty_mod.make_notification = function(opts)
	local n = { opts = opts, ignore = false, _private = { is_destroyed = false } }
	n.destroy = function(self)
		self._private.is_destroyed = true
	end
	n.connect_signal = function(self, name, cb) end
	n.reset_timeout = function(self) end
	return n
end
_naughty_mod.notification = _naughty_mod.make_notification
package.preload["naughty"] = function()
	return _naughty_mod
end

package.preload["menubar.utils"] = function()
	return {
		lookup_icon = function(name)
			return nil
		end,
	}
end

package.preload["menubar.menu_gen"] = function()
	return {
		all_menu_dirs = {},
	}
end

package.preload["beautiful.xresources"] = function()
	return {
		apply_dpi = function(value)
			return value
		end,
	}
end

package.preload["wibox.hierarchy"] = function()
	return {
		new = function(context, widget, width, height, redraw_cb, layout_cb, obj)
			return {
				draw = function(self, ctx, cr) end,
				update = function(self, ...) end,
			}
		end,
	}
end

package.preload["wibox.widget.base"] = function()
	return {
		make_widget = function(orig, name, args)
			local w = { _private = {} }
			w.emit_signal = function(self, sig) end
			w.connect_signal = function(self, sig, cb) end
			w.buttons = function(self, btns) end
			return w
		end,
		fit_widget = function(parent, context, widget, width, height)
			if widget and widget.fit then
				return widget:fit(context, width, height)
			end
			return 0, 0
		end,
		place_widget_at = function(widget, x, y, width, height)
			return { _widget = widget, _x = x, _y = y, _width = width, _height = height }
		end,
	}
end
