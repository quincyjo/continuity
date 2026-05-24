local Monitor = require("continuity.monitor")

---@class CpuCoreState
---@field usage   number  Percentage (0-100)
---@field user    number  Percentage in user space
---@field system  number  Percentage in kernel space
---@field idle    number  Percentage idle
---@field iowait  number  Percentage waiting on I/O
---@field steal   number  Percentage stolen (relevant in VMs)

---@class CpuState
---@field usage   number          Overall usage percentage across all cores
---@field user    number          Percentage in user space
---@field system  number          Percentage in kernel space
---@field idle    number          Percentage idle
---@field iowait  number          Percentage waiting on I/O
---@field steal   number          Percentage stolen (relevant in VMs)
---@field cores   CpuCoreState[]  Per-core breakdown, index 1 = core 0

---@class CpuBackend : MonitorBackend<CpuState>

---@class CpuOptions : MonitorOptions<CpuState>
---@field backend? CpuBackend  The backend to provide CPU monitoring, defaults to procstat backend.

---@class CpuMonitor : Monitor<CpuState, CpuOptions>
local cpu = Monitor({
	name = "cpu",
	configure = function(_, opts)
		opts = opts or {}
		return opts.backend or require("continuity.sysinfo.cpu.backends.procstat")()
	end,
})

return cpu
