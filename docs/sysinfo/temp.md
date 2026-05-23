# sysinfo.temp — Temperature

The `temp` module provides a singleton thermal monitor that pushes state to
subscribers at a regular interval. Two backends are available:

- **sysfs** (default) — reads from `/sys/class/thermal/` (thermal framework,
  present on all modern Linux systems including ARM)
- **hwmon** — reads from `/sys/class/hwmon/` (hardware monitoring subsystem,
  richer labels and thresholds on x86 Intel/AMD/NVMe/GPU)

## Setup

```lua
require("continuity.sysinfo.temp").setup()
```

Full configuration with both backends shown:

```lua
-- Default: thermal sysfs backend
require("continuity.sysinfo.temp").setup {
    backend = require("continuity.sysinfo.temp.backends.sysfs") {
        interval = 5,       -- polling interval in seconds
        cpu_device = nil,   -- override CPU zone by thermal zone type, e.g. "cpu-thermal"
        exclude = nil,      -- Lua patterns matched against zone type, e.g. { "^iwlwifi" }
    },
}

-- hwmon backend (recommended on Intel/AMD x86)
require("continuity.sysinfo.temp").setup {
    backend = require("continuity.sysinfo.temp.backends.hwmon") {
        interval = 5,       -- polling interval in seconds
        cpu_device = nil,   -- override CPU device by hwmon name, e.g. "coretemp"
        exclude = nil,      -- Lua patterns matched against device name, e.g. { "system76_acpi" }
    },
}
```

## State

Each subscriber receives a `TempState` table on every update.
All temperature values are in degrees Celsius.

```lua
---@class TempSensor
---@field label  string   Sensor label (temp*_label from hwmon, or zone type from thermal)
---@field temp   number   Degrees Celsius
---@field crit?  number   Shutdown threshold; nil if unavailable
---@field max?   number   High-water mark; nil if unavailable

---@class TempDevice : TempSensor
---@field name    string       hwmon device name or thermal zone type
---@field sensors TempSensor[] Sub-sensors (hwmon temp2..N); empty for thermal backend

---@class TempState
---@field devices TempDevice[] All devices reported by the backend
---@field cpu?    TempDevice   CPU device; nil if not identifiable
```

`cpu` is selected automatically by matching well-known package-sensor labels
(`"Package id 0"` for Intel coretemp, `"Tdie"`/`"Tctl"` for AMD k10temp,
`"x86_pkg_temp"` or `"cpu-thermal"` on the thermal backend). Pass
`cpu_device` in the backend options to override this on unusual hardware.

Threshold fields (`crit`, `max`) are nil when the backend cannot provide them
or when the raw value is a known sentinel (e.g. the 0xFFFF Kelvin NVMe
unset-threshold value, or disabled thermal trip points).

## Wibox Widgets

### Simple CPU temperature widget

```lua
local temp = require("continuity.sysinfo.temp")

local temp_widget = wibox.widget({
    text = "CPU …",
    widget = wibox.widget.textbox,
})

temp:subscribe(function(state)
    if not state.cpu then
        return
    end
    temp_widget.text = string.format("%.0f°C", state.cpu.temp)
end)
```

### CPU temperature with colorization against crit threshold

```lua
temp:subscribe(function(state)
    if not state.cpu then
        return
    end
    local t = state.cpu.temp
    local crit = state.cpu.crit
    local color = "#ffffff"
    if crit and t >= crit * 0.9 then
        color = "#ff4444"
    elseif crit and t >= crit * 0.75 then
        color = "#ffaa00"
    end
    temp_widget.markup = string.format('<span color="%s">%.0f°C</span>', color, t)
end)
```

### All devices widget

```lua
temp:subscribe(function(state)
    local parts = {}
    for _, device in ipairs(state.devices) do
        parts[#parts + 1] = string.format("%s: %.0f°C", device.name, device.temp)
    end
    temp_widget.text = table.concat(parts, "  ")
end)
```

## Synchronous Access

`temp.state` holds the most recent `TempState`, or `nil` before the first update.

```lua
local state = require("continuity.sysinfo.temp").state
if state and state.cpu then
    print(string.format("CPU: %.1f°C", state.cpu.temp))
end
```
