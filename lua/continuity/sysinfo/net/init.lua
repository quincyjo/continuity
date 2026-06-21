local Monitor = require("lua.continuity.class.monitor")

---@class NetDeviceState
---@field state    DeviceState "up" or "down"
---@field carrier  boolean     Physical link present
---@field tx_rate  number      Bytes per second since last sample
---@field rx_rate  number      Bytes per second since last sample
---@field tx_bytes integer     Cumulative bytes transmitted from sysfs
---@field rx_bytes integer     Cumulative bytes received from sysfs
---@field wifi     boolean     True if the interface is a wireless device
---@field signal   number|nil  Signal strength in dBm; nil if not wifi or no carrier

---@class NetState
---@field devices  table<string, NetDeviceState>  Keyed by interface name
---@field tx_rate  number                         Bytes per second total across all devices
---@field rx_rate  number                         Bytes per second total across all devices

---@class NetBackend : MonitorBackend<NetState>

---@class NetOptions : MonitorOptions<NetState>
---@field backend? NetBackend  The backend to provide network monitoring, defaults to ipmonitor backend.

---@class NetMonitor : Monitor<NetState, NetOptions>
local net = Monitor({
	name = "net",
	configure = function(_, opts)
		opts = opts or {}
		return opts.backend or require("continuity.sysinfo.net.backends.ipmonitor")()
	end,
})

---@enum DeviceState
net.DeviceState = {
	Up = "up",
	Down = "down",
}

return net
