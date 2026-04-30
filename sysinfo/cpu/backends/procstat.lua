local Process = require("continuity.util.process")

---@class UprocOptions
---@field interval integer Interval for checking proc state, default is 2.

local procstat = {}

---@param line string
---@return string|nil, table|nil
function procstat._parse_stat_line(line)
	local name, rest = line:match("^(cpu%d*) +(.*)")
	if not name then
		return nil, nil
	end
	local f = {}
	for n in rest:gmatch("%d+") do
		f[#f + 1] = tonumber(n)
	end
	return name,
		{
			user = f[1] or 0,
			nice = f[2] or 0,
			system = f[3] or 0,
			idle = f[4] or 0,
			iowait = f[5] or 0,
			irq = f[6] or 0,
			softirq = f[7] or 0,
			steal = f[8] or 0,
		}
end

---@param a table  previous snapshot fields
---@param b table  current snapshot fields
---@return number usage, number user, number system, number idle, number iowait, number steal
function procstat._compute_usage(a, b)
	local prev_idle = a.idle + a.iowait
	local curr_idle = b.idle + b.iowait
	local prev_tot = a.user + a.nice + a.system + a.idle + a.iowait + a.irq + a.softirq + a.steal
	local curr_tot = b.user + b.nice + b.system + b.idle + b.iowait + b.irq + b.softirq + b.steal
	local dt = curr_tot - prev_tot
	if dt == 0 then
		return 0, 0, 0, 100, 0, 0
	end
	local di = curr_idle - prev_idle
	local pct = function(delta)
		return math.max(0, (delta / dt) * 100)
	end
	return math.max(0, math.min(100, ((dt - di) / dt) * 100)),
		pct(b.user - a.user),
		pct(b.system - a.system),
		pct(di),
		pct(b.iowait - a.iowait),
		pct(b.steal - a.steal)
end

local ZERO_FIELDS = { user = 0, nice = 0, system = 0, idle = 0, iowait = 0, irq = 0, softirq = 0, steal = 0 }

---@param  opts? UprocOptions
---@return CpuBackend
local function create(opts)
	opts = opts or {}
	local interval = opts.interval or 2
	local on_update = nil
	local prev = { cpu = ZERO_FIELDS }
	local buf = {}

	local proc = Process({
		name = "sysinfo.cpu.procstat",
		cmd = { "grep '^cpu' /proc/stat", "echo '---'" },
		interval = interval,
		stdout = function(line)
			if line ~= "---" then
				buf[#buf + 1] = line
				return
			end
			local snap = {}
			for _, l in ipairs(buf) do
				local name, fields = procstat._parse_stat_line(l)
				if name then
					snap[name] = fields
				end
			end
			buf = {}
			if not snap.cpu then
				prev = snap
				return
			end
			local u, us, sys, id, iow, st = procstat._compute_usage(prev.cpu, snap.cpu)
			local cores = {}
			local i = 0
			while snap["cpu" .. i] and prev["cpu" .. i] do
				local cu, cus, csys, cid, ciow, cst = procstat._compute_usage(prev["cpu" .. i], snap["cpu" .. i])
				cores[i + 1] = { usage = cu, user = cus, system = csys, idle = cid, iowait = ciow, steal = cst }
				i = i + 1
			end
			prev = snap
			if on_update then
				on_update({
					usage = u,
					user = us,
					system = sys,
					idle = id,
					iowait = iow,
					steal = st,
					cores = cores,
				})
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
			prev = { cpu = ZERO_FIELDS }
		end,
	}
end

return setmetatable(procstat, {
	__call = function(_, opts)
		return create(opts)
	end,
})
