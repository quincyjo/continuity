---@class Process         Represents a self managed long running process.
---                       If the process exits unexpectedly, it will be
---                       restarted automatically. An exit signal is registered
---                       with Awesome to shut down the process group.
---                       The process does not start on construction, so start()
---                       must be called to start the process.
---@field stop  fun(self) Stops the process.
---@field start fun(self) Starts the process.

---@class ProcessOpts  Construction options for a Process.
---@field name         string The name of the process, used for logging.
---@field cmd          string|string[] The cmd to run. Note that if using
---                    interval and cmd is an array, each member should be a
---                    posix statement, as they are concatenated with a
---                    semicolon. If interval is nil, then cmd is passed
---                    directly to spawn.
---@field stdout       fun(line: string) callback for stdout lines.
---@field interval?    number If set, run cmd every interval seconds. Otherwise,
---                    cmd is expected to be long running.
---@field retry_delay? number The number of seconds to wait before retrying if
---                    the process exits unexpectedly. Default is 10. Note that
---                    if the process exits with exitcode 0, it will be
---                    immediately restarted rather than waiting for the retry
---                    delay.
---@field exit?        fun(exitreason: string, exitcode: integer) Callback for
---                    when the process exits. Useful to clear a buffer or other
---                    state. Is not called if stopped via stop().

local gears = require("gears")
local awful = require("awful")

local Process = {}

local ProcessMT = {
	__index = {
		start = function(self)
			if self._private.pid then
				return
			end
			local stderr = {}
			self._private.stopped = false
			self._private.pid = awful.spawn.with_line_callback(self._private.interval and {
				"sh",
				"-c",
				string.format(
					[[
                    while true; do
                        %s
                        sleep %d
                    done
                ]],
					type(self._private.cmd) == "table" and table.concat(self._private.cmd, "; ") or self._private.cmd,
					self._private.interval
				),
			} or self._private.cmd, {
				stdout = self._private.stdout,
				stderr = function(line)
					stderr[#stderr + 1] = line
				end,
				exit = function(exitreason, exitcode)
					self._private.pid = nil
					if self._private.stopped then
						return
					end
					if self._private.exit then
						self._private.exit(exitreason, exitcode)
					end
					if exitreason == "exit" and exitcode == 0 then
						-- Immediately restart if a clean exit.
						self:start()
					else -- Otherwise, schedule a retry.
						gears.debug.print_warning(
							string.format(
								"%s exited with %s:%s. Restarting in %ds: %s",
								self.name,
								tostring(exitreason),
								tostring(exitcode),
								self._private.retry_delay,
								table.concat(stderr, "\n")
							)
						)
						gears.timer({
							timeout = self._private.retry_delay,
							autostart = true,
							single_shot = true,
							callback = function()
								self:start()
							end,
						})
					end
				end,
			})
		end,
		stop = function(self)
			self._private.stopped = true
			if self._private.pid then
				awesome.kill(-self._private.pid, 15)
				self._private.pid = nil
			end
		end,
	},
}

---@param opts ProcessOpts
---@return Process
function Process.new(opts)
	local proc = {
		name = opts.name,
		_private = {
			cmd = opts.cmd,
			stdout = opts.stdout,
			interval = opts.interval,
			retry_delay = opts.retry_delay or 10,
			exit = opts.exit,
			pid = nil,
			stopped = true,
		},
	}
	proc = setmetatable(proc, ProcessMT)
	awesome.connect_signal("exit", function(restart) -- luacheck: globals awesome
		if proc._private.pid then
			if restart then
				gears.debug.print_warning(
					string.format(
						"%s: Shutting down process group %d. A following unknown child "
							.. "exited with signal 15 may occur and can be ignored.",
						proc.name,
						proc._private.pid
					)
				)
			end
			proc:stop()
		end
	end)
	return proc
end

return setmetatable(Process, {
	__call = function(_, opts)
		return Process.new(opts)
	end,
})
