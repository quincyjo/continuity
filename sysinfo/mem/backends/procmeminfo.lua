local Process = require("continuity.util.process")

---@class ProcMemInfoOptions
---@field interval? integer Integer for memory polling, default is 5.

local procmeminfo = {}

local MiB = function(kb)
	return math.floor(kb / 1024 + 0.5)
end

---@param lines string[]
---@return MemState
function procmeminfo._parse_meminfo_lines(lines)
	local raw = {}
	for _, line in ipairs(lines) do
		local k, v = line:match("^(%a+):%s+(%d+)")
		if k then
			raw[k] = tonumber(v)
		end
	end
	local total = MiB(raw.MemTotal or 0)
	local avail = MiB(raw.MemAvailable or 0)
	local free = MiB(raw.MemFree or 0)
	local buf = MiB(raw.Buffers or 0)
	local cache = MiB(raw.Cached or 0)
	local stot = MiB(raw.SwapTotal or 0)
	local sfree = MiB(raw.SwapFree or 0)
	local used = total - avail
	return {
		total = total,
		used = used,
		free = free,
		buffers = buf,
		cached = cache,
		perc = total > 0 and used / total * 100 or 0,
		swap_total = stot,
		swap_used = stot - sfree,
		swap_free = sfree,
	}
end

---@param opts? ProcMemInfoOptions
---@return MemBackend
local function create(opts)
	opts = opts or {}
	local interval = opts.interval or 5
	local on_update = nil
	local buf = {}

	local proc = Process({
		name = "sysinfo.mem.procmeminfo",
		cmd = { "cat /proc/meminfo", "echo '---'" },
		interval = interval,
		stdout = function(line)
			if line ~= "---" then
				buf[#buf + 1] = line
				return
			end
			local state = procmeminfo._parse_meminfo_lines(buf)
			buf = {}
			if on_update then
				on_update(state)
			end
		end,
		exit = function()
			buf = {}
		end,
	})

	return {
		start = function(_, cb)
			on_update = cb
			proc:start()
		end,
		stop = function(_)
			proc:stop()
			on_update = nil
		end,
	}
end

return setmetatable(procmeminfo, {
	__call = function(_, opts)
		return create(opts)
	end,
})
