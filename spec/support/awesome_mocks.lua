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
awesome = { kill = function(_pid, _signal) end, connect_signal = function(_name, _cb) end } -- luacheck: globals awesome

package.preload["awful"] = function()
	return {
		spawn = {
			easy_async = function(_cmd, _cb) end,
			-- Returns a fake PID integer, matching the real awful.spawn.with_line_callback API.
			with_line_callback = function(_cmd, _callbacks)
				return 0
			end,
		},
		button = function(_mods, _btn, _fn)
			return {}
		end,
	}
end

local _gears_mod
_gears_mod = {
	debug = { print_warning = function(_msg) end },
	table = {
		join = function()
			return {}
		end,
	},
	_created = {}, -- all timer instances, appended on each gears.timer() call
	timer = function(opts)
		local t = {
			_opts = opts,
			again_count = 0,
			stopped = false,
			start = function(_self) end,
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
	notify = function(_opts)
		return { id = 1 }
	end,
	connect_signal = function(_name, _cb) end,
	notification_closed_reason = {
		dismissed_by_command = "dismissed_by_command",
		dismissed_by_user = "dismissed_by_user",
		expired = "expired",
		silent = "silent",
		undefined = "undefined",
	},
	config = { notify_callback = nil },
}
-- Shared factory used by the base mock and by spec overrides.
_naughty_mod.make_notification = function(opts)
	local n = { opts = opts, ignore = false, _private = { is_destroyed = false } }
	n.destroy = function(self)
		self._private.is_destroyed = true
	end
	n.connect_signal = function(_self, _name, _cb) end
	n.reset_timeout = function(_self) end
	return n
end
_naughty_mod.notification = _naughty_mod.make_notification
package.preload["naughty"] = function()
	return _naughty_mod
end

package.preload["menubar.utils"] = function()
	return {
		lookup_icon = function(_name)
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
		new = function(_context, _widget, _width, _height, _redraw_cb, _layout_cb, _obj)
			return {
				draw = function(_self, _ctx, _cr) end,
				update = function(_self) end,
			}
		end,
	}
end

package.preload["wibox.widget.base"] = function()
	return {
		make_widget = function(_orig, _name, _args)
			local w = { _private = {} }
			w.emit_signal = function(_self, _sig) end
			w.connect_signal = function(_self, _sig, _cb) end
			w.buttons = function(_self, _btns) end
			return w
		end,
		fit_widget = function(_parent, context, widget, width, height)
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
