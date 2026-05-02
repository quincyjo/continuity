# sysinfo.mem — Memory

The `mem` module provides a singleton memory usage monitor that pushes state to
subscribers at a regular interval. The default backend reads `/proc/meminfo` to
report total, used, free, buffered, cached, and swap memory.

## Setup

The module should be initialized somewhere in your `rc.lua`. This starts the
backend and allows configuration as desired. Any subscriptions registered before
setup will not receive data until the module is initialized.

```lua
require("continuity.sysinfo.mem").setup()
```

Below is a full configuration with all defaults.

```lua
require("continuity.sysinfo.mem").setup {
    backend = require("continuity.sysinfo.mem.backends.procmeminfo") {
        interval = 5, -- Polling interval in seconds.
    },
}
```

## State

Each subscriber receives a `MemState` table on every update. All byte values
are in mebibytes (MiB).

```lua
---@class MemState
---@field total      integer  Total physical memory
---@field used       integer  Used memory (total − MemAvailable)
---@field free       integer  Unused memory (MemFree)
---@field buffers    integer  Kernel I/O buffers
---@field cached     integer  Page cache
---@field perc       number   used / total × 100
---@field swap_total integer  Total swap space
---@field swap_used  integer  Used swap space
---@field swap_free  integer  Free swap space
```

## Wibox Widget

A sample wibox widget showing memory usage as a percentage.

```lua
local mem = require("continuity.sysinfo.mem")

local mem_widget = wibox.widget({
    text = "RAM …",
    widget = wibox.widget.textbox,
})

mem:subscribe(function(state)
    mem_widget.text = string.format("RAM %.0f%%  %d/%d MiB",
        state.perc, state.used, state.total)
end)
```

## Synchronous Access

`mem.state` holds the most recent `MemState`, or `nil` if no update has
been received yet.

```lua
local state = require("continuity.sysinfo.mem").state
if state then
    print(string.format("%.0f%% of %d MiB used", state.perc, state.total))
end
```
