# sysinfo.temp — Temperature

The `temp` module provides a singleton thermal monitor that pushes state to
subscribers at a regular interval. The default backend reads temperature values
from `/sys/devices/virtual/thermal/thermal_zone*/temp` and exposes both
per-zone readings and an arithmetic mean across all zones.

## Setup

The module should be initialized somewhere in your `rc.lua`. This starts the
backend and allows configuration as desired. Any subscriptions registered before
setup will not receive data until the module is initialized.

```lua
require("continuity.sysinfo.temp").setup()
```

Below is a full configuration with all defaults.

```lua
require("continuity.sysinfo.temp").setup {
    backend = require("continuity.sysinfo.temp.backends.sysfs") {
        interval = 5, -- Polling interval in seconds.
    },
}
```

## State

Each subscriber receives a `TempState` table on every update. All values are
in degrees Celsius.

```lua
---@class TempState
---@field zones  table<string, number>  Per-zone temperature, keyed by sysfs path
---@field avg    number                 Arithmetic mean across all zones
```

The `zones` table is keyed by the parent sysfs directory path, for example
`"/sys/devices/virtual/thermal/thermal_zone0"`.

## Wibox Widget

A sample wibox widget showing the average temperature across all thermal zones.

```lua
local temp = require("continuity.sysinfo.temp")

local temp_widget = wibox.widget({
    text = "TEMP …",
    widget = wibox.widget.textbox,
})

temp:subscribe(function(state)
    temp_widget.text = string.format("%.0f°C", state.avg)
end)
```

For a display showing all zones:

```lua
temp:subscribe(function(state)
    local parts = {}
    for zone, val in pairs(state.zones) do
        local name = zone:match("thermal_zone%d+$") or zone
        parts[#parts + 1] = string.format("%s: %.0f°C", name, val)
    end
    table.sort(parts)
    temp_widget.text = table.concat(parts, "  ")
end)
```

## Synchronous Access

`temp.state()` returns the most recent `TempState`, or `nil` if no update has
been received yet.

```lua
local state = require("continuity.sysinfo.temp").state()
if state then
    print(string.format("avg: %.1f°C", state.avg))
end
```
