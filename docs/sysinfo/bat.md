# sysinfo.bat — Battery

The `bat` module provides a singleton battery object that can be subscribed to
for changes in battery state. The provided backend listens to `udevadm` events
and reports battery status changes. It also polls on a regular interval to
support hardware that does not emit events on regular power changes.

## Setup

The module should be initialized somewhere in your `rc.lua`. This initializes the
module to start monitoring data and allows configuration as desired. Any
subscriptions registered before setup will not receive data until the module is
initialized.

```lua
require("continuity.sysinfo.bat").setup()
```

Below is a full configuration with all defaults.

```lua
require("continuity.sysinfo.bat").setup {
    backend = require("continuity.sysinfo.bat.backends.udevadm") {
        -- Or false to disable polling. Depending on hardware, udevadm events
        -- may or may not be emitted for all changes such as energy now.
        poll = 30,
    },
    power_alpha = 0.1 -- EMA weight for rolling power average.
}
```

## Wibox Widget

Sample wibox style widget that displays battery status and time remaining.

```lua
local bat = require("continuity.sysinfo.bat")

---@param seconds integer
---@return string
local function format_time(seconds)
	local minutes = math.floor(seconds / 60)
	local hours = math.floor(minutes / 60)
	if hours >= 3 then
		return string.format("%d hr", hours)
	end
	if hours == 0 then
		return string.format("%d min", minutes)
	end
	return string.format("%d:%02d", hours, minutes % 60)
end

local battery_widget = wibox.widget({
	text = "🔋 …", -- This will be seen only briefly on initial startup.
	widget = wibox.widget.textbox,
})
bat:subscribe(function(state)
	if state.ac_online then
		local markup = "🔌 AC"
		if state.status == bat.BatteryStatus.Charging and not state.charge_controlled then
			markup = string.format("%s (%s)", markup, format_time(bat.time_until_full() or 0))
		end
		battery_widget:set_markup(markup)
	else
		battery_widget:set_markup(
			string.format(
			    "%s %d%% (%s)",
			    perc > 30 and "🔋" or "🪫",
			    state.perc,
			    format_time(bat.time_remaining() or 0)
			)
		)
	end
end)
```

## Battery Notifications

Battery notifications for low, critical, and full charge.

```lua
-- Battery level notifications.
do
	local bat = require("continuity.sysinfo.bat")

	---@type BatteryStatus|nil
	local last_status
	local low_notified = false
	local critical_notified = false
	local full_notified = false
	local control_notified = false
    local critical_notification
	bat:subscribe(function(state)
		if state.status ~= last_status then
			last_status = state.status
			low_notified, critical_notified, full_notified, control_notified = false, false, false, false
		end
		if state.status == bat.BatteryStatus.Discharging then
			if state.perc <= 15 and not low_notified then
				low_notified = true
				naughty.notify({
					title = "Battery Low",
					text = "Plug in the cable!",
					timeout = 15,
					screen = mouse.screen,
				})
			elseif state.perc <= 5 and not critical_notified then
				critical_notified = true
				critical_notification = naughty.notify({
					title = "Battery Critical",
					text = "Shutdown imminent",
					screen = mouse.screen,
					preset = naughty.config.presets.critical,
				})
			end
		elseif state.status == bat.BatteryStatus.Charging then
			if critical_notification then
				critical_notification:destroy()
				critical_notification = nil
			end
			if state.perc >= 99 and not full_notified then
				full_notified = true
				naughty.notify({
					title = "Battery Full",
					text = "You can unplug the cable",
					screen = mouse.screen,
				})
			elseif state.charge_controlled and not control_notified then
                control_notified = true
				naughty.notify({
					title = "Charge Controlled",
					text = "Battery now being charge controlled",
					screen = mouse.screen,
				})
			end
		end
	end)
end
```
