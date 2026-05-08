# sysinfo.net — Network

The `net` module provides a singleton network monitor that pushes state to
subscribers when interface state changes or on a regular polling interval. The
default backend monitors link events via `ip monitor link` and polls `/proc/net/dev`
and `/proc/net/wireless` for per-interface byte counters and wifi signal to compute
transfer rates.

## Setup

The module should be initialized somewhere in your `rc.lua`. This starts the
backend and allows configuration as desired. Any subscriptions registered before
setup will not receive data until the module is initialized.

```lua
require("continuity.sysinfo.net").setup()
```

Below is a full configuration with all defaults.

```lua
require("continuity.sysinfo.net").setup {
    backend = require("continuity.sysinfo.net.backends.ipmonitor") {
        interval = 2, -- Polling interval in seconds for byte counters.
    },
}
```

## State

Each subscriber receives a `NetState` table on every update.

```lua
---@class NetState
---@field devices  table<string, NetDeviceState>  Per-interface state, keyed by name
---@field tx_rate  number                         Total bytes per second transmitted
---@field rx_rate  number                         Total bytes per second received

---@class NetDeviceState
---@field state    string     "up" or "down"
---@field carrier  boolean    Physical link present
---@field tx_rate  number     Bytes per second since last sample
---@field rx_rate  number     Bytes per second since last sample
---@field tx_bytes integer    Cumulative bytes transmitted
---@field rx_bytes integer    Cumulative bytes received
---@field wifi     boolean    True if the interface is a wireless device
---@field signal   number|nil Signal strength in dBm; nil if not wifi or no carrier
```

## Wibox Widget

A sample wibox widget showing the combined transfer rate across all interfaces.

```lua
local net = require("continuity.sysinfo.net")

local function fmt_rate(bytes_per_sec)
    if bytes_per_sec >= 1024 * 1024 then
        return string.format("%.1f MB/s", bytes_per_sec / (1024 * 1024))
    elseif bytes_per_sec >= 1024 then
        return string.format("%.0f KB/s", bytes_per_sec / 1024)
    else
        return string.format("%d B/s", bytes_per_sec)
    end
end

local net_widget = wibox.widget({
    text = "NET …",
    widget = wibox.widget.textbox,
})

net:subscribe(function(state)
    net_widget.text = string.format("↑ %s  ↓ %s",
        fmt_rate(state.tx_rate), fmt_rate(state.rx_rate))
end)
```

For per-interface detail, including wifi signal strength:

```lua
net:subscribe(function(state)
    for name, dev in pairs(state.devices) do
        if dev.state == "up" and dev.carrier then
            if dev.wifi and dev.signal then
                print(string.format("%s: signal %d dBm  ↑ %s  ↓ %s",
                    name, dev.signal, fmt_rate(dev.tx_rate), fmt_rate(dev.rx_rate)))
            else
                print(string.format("%s: ↑ %s  ↓ %s",
                    name, fmt_rate(dev.tx_rate), fmt_rate(dev.rx_rate)))
            end
        end
    end
end)
```

## Synchronous Access

`net.state` holds the most recent `NetState`, or `nil` if no update has
been received yet.

```lua
local state = require("continuity.sysinfo.net").state
if state then
    print("TX:", state.tx_rate, "RX:", state.rx_rate)
end
```
