local Monitor = require("continuity.class.monitor")

---@class MemState
---@field total      integer  Mebibytes total
---@field used       integer  Mebibytes used (total - free - buffers - cached - sreclaimable)
---@field free       integer  Mebibytes free
---@field buffers    integer  Mebibytes in kernel buffers
---@field cached     integer  Mebibytes in page cache
---@field perc       number   Used divided by total times 100
---@field swap_total integer  Mebibytes swap total
---@field swap_used  integer  Mebibytes swap used
---@field swap_free  integer  Mebibytes swap free

---@class MemBackend : MonitorBackend<MemState>

---@class MemOptions : MonitorOptions<MemState>
---@field backend? MemBackend  The backend to provide memory monitoring, defaults to procmeminfo backend.

---@class MemMonitor : Monitor<MemState, MemOptions>
local mem = Monitor({
	name = "mem",
	configure = function(_, opts)
		opts = opts or {}
		return opts.backend or require("continuity.sysinfo.mem.backends.procmeminfo")()
	end,
})

return mem
