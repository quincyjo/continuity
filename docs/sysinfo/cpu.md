# sysinfo.cpu — CPU

The `cpu` module provides a singleton CPU usage monitor that pushes state to
subscribers at a regular interval. The default backend reads `/proc/stat` to
compute per-core and aggregate usage deltas.

## Setup

The module should be initialized somewhere in your `rc.lua`. This starts the
backend and allows configuration as desired. Any subscriptions registered before
setup will not receive data until the module is initialized.

```lua
require("continuity.sysinfo.cpu").setup()
```

Below is a full configuration with all defaults.

```lua
require("continuity.sysinfo.cpu").setup {
    backend = require("continuity.sysinfo.cpu.backends.procstat") {
        interval = 2, -- Polling interval in seconds.
    },
}
```

## State

Each subscriber receives a `CpuState` table on every update.

```lua
---@class CpuState
---@field usage   number          Overall usage percentage across all cores (0–100)
---@field user    number          Percentage in user space
---@field system  number          Percentage in kernel space
---@field idle    number          Percentage idle
---@field iowait  number          Percentage waiting on I/O
---@field steal   number          Percentage stolen (relevant in VMs)
---@field cores   CpuCoreState[]  Per-core breakdown, index 1 = core 0

---@class CpuCoreState
---@field usage   number  Per-core usage percentage (0–100)
---@field user    number  Percentage in user space
---@field system  number  Percentage in kernel space
---@field idle    number  Percentage idle
---@field iowait  number  Percentage waiting on I/O
---@field steal   number  Percentage stolen
```

## Wibox Widget

A sample wibox widget showing overall CPU usage and a per-core breakdown.

```lua
local cpu = require("continuity.sysinfo.cpu")

local cpu_widget = wibox.widget({
    text = "CPU …",
    widget = wibox.widget.textbox,
})

cpu:subscribe(function(state)
    cpu_widget:set_markup(string.format("CPU %.0f%%", state.usage))
end)
```

For a per-core display:

```lua
cpu:subscribe(function(state)
    local parts = {}
    for i, core in ipairs(state.cores) do
        parts[i] = string.format("%.0f%%", core.usage)
    end
    cpu_widget:set_markup("CPU " .. table.concat(parts, " "))
end)
```

## Synchronous Access

`cpu.state()` returns the most recent `CpuState`, or `nil` if no update has
been received yet.

```lua
local state = require("continuity.sysinfo.cpu").state()
if state then
    print("CPU usage:", state.usage)
end
```
