-- spec/history_spec.lua
-- No awesome_mocks needed — History has no WM API dependency.

local Subscribable = require("continuity.class.subscribable")

local function make_subscribable(initial_state)
	return Subscribable({ state = initial_state })
end

local function monitor_like_source(initial_state)
	local cbs = {}
	local src
	src = {
		state = initial_state,
		weak_subscribe = function(_, cb)
			cbs[#cbs + 1] = cb
			if src.state ~= nil then
				cb(src.state)
			end
			return function()
				for i = #cbs, 1, -1 do
					if cbs[i] == cb then
						table.remove(cbs, i)
					end
				end
			end
		end,
		push = function(v)
			src.state = v
			for _, cb in ipairs(cbs) do
				cb(v)
			end
		end,
	}
	return src
end

local function collect(h)
	local result = {}
	for v in h:iter() do
		result[#result + 1] = v
	end
	return result
end

describe("History", function()
	local History

	before_each(function()
		package.loaded["continuity.history"] = nil
		History = require("continuity.history")
	end)

	describe("construction", function()
		it("count is 0 and state is nil with no initial source state", function()
			local src = make_subscribable()
			local h = History(src, 10)
			assert.equals(0, h.count)
			assert.is_nil(h.state)
		end)

		it("capacity is stored", function()
			local src = make_subscribable()
			local h = History(src, 42)
			assert.equals(42, h.capacity)
		end)

		it("Monitor-like source seeds entry #1 via subscribe replay", function()
			local src = monitor_like_source(99)
			local h = History(src, 10)
			assert.equals(1, h.count)
			assert.equals(99, h.state)
			assert.same({ 99 }, collect(h))
		end)

		it("plain source with state does not seed", function()
			local src = make_subscribable(99)
			local h = History(src, 10)
			assert.equals(0, h.count)
			assert.is_nil(h.state)
		end)
	end)

	describe("push / ring buffer", function()
		it("count increments on push", function()
			local src = make_subscribable()
			local h = History(src, 10)
			src:push(1)
			src:push(2)
			assert.equals(2, h.count)
		end)

		it("state reflects the most recent entry", function()
			local src = make_subscribable()
			local h = History(src, 10)
			src:push("a")
			src:push("b")
			assert.equals("b", h.state)
		end)

		it("count stays at capacity when full", function()
			local src = make_subscribable()
			local h = History(src, 5)
			for i = 1, 10 do
				src:push(i)
			end
			assert.equals(5, h.count)
		end)

		it("oldest entries are evicted when capacity exceeded", function()
			local src = make_subscribable()
			local h = History(src, 5)
			for i = 1, 10 do
				src:push(i)
			end
			assert.same({ 6, 7, 8, 9, 10 }, collect(h))
		end)

		it("capacity=1 always holds exactly the last entry", function()
			local src = make_subscribable()
			local h = History(src, 1)
			src:push("x")
			src:push("y")
			src:push("z")
			assert.equals(1, h.count)
			assert.same({ "z" }, collect(h))
		end)
	end)

	describe("iter", function()
		it("empty buffer yields nothing", function()
			local src = make_subscribable()
			local h = History(src, 10)
			assert.same({}, collect(h))
		end)

		it("yields entries oldest to newest", function()
			local src = make_subscribable()
			local h = History(src, 10)
			src:push(1)
			src:push(2)
			src:push(3)
			assert.same({ 1, 2, 3 }, collect(h))
		end)

		it("iter is a snapshot: push during iteration does not corrupt", function()
			local src = make_subscribable()
			local h = History(src, 5)
			src:push(1)
			src:push(2)
			src:push(3)
			local result = {}
			for v in h:iter() do
				result[#result + 1] = v
				src:push(99)
			end
			assert.same({ 1, 2, 3 }, result)
		end)

		it("15 pushes on capacity=10 yields entries 6..15 in order", function()
			local src = make_subscribable()
			local h = History(src, 10)
			for i = 1, 15 do
				src:push(i)
			end
			assert.equals(10, h.count)
			assert.same({ 6, 7, 8, 9, 10, 11, 12, 13, 14, 15 }, collect(h))
		end)
	end)

	describe("subscribe", function()
		it("does not replay existing entries", function()
			local src = make_subscribable()
			local h = History(src, 10)
			src:push(1)
			src:push(2)
			local calls = 0
			h:subscribe(function()
				calls = calls + 1
			end)
			assert.equals(0, calls)
		end)

		it("receives future pushes", function()
			local src = make_subscribable()
			local h = History(src, 10)
			local received = {}
			h:subscribe(function(v)
				received[#received + 1] = v
			end)
			src:push(10)
			src:push(20)
			assert.same({ 10, 20 }, received)
		end)

		it("returns an unsubscribe function", function()
			local src = make_subscribable()
			local h = History(src, 10)
			local unsub = h:subscribe(function() end)
			assert.is_function(unsub)
		end)

		it("unsubscribe stops delivery", function()
			local src = make_subscribable()
			local h = History(src, 10)
			local calls = 0
			local unsub = h:subscribe(function()
				calls = calls + 1
			end)
			src:push(1)
			unsub()
			src:push(2)
			assert.equals(1, calls)
		end)
	end)

	describe("stop / start / reset", function()
		it("stop: no new entries arrive after stop", function()
			local src = make_subscribable()
			local h = History(src, 10)
			src:push(1)
			src:push(2)
			h:stop()
			src:push(3)
			assert.equals(2, h.count)
		end)

		it("stop: buffer and state are preserved", function()
			local src = make_subscribable()
			local h = History(src, 10)
			src:push(42)
			h:stop()
			assert.equals(42, h.state)
			assert.equals(1, h.count)
		end)

		it("stop is idempotent", function()
			local src = make_subscribable()
			local h = History(src, 10)
			h:stop()
			h:stop()
			assert.equals(0, h.count)
		end)

		it("start: entries resume after stop+start", function()
			local src = make_subscribable()
			local h = History(src, 10)
			src:push(1)
			h:stop()
			src:push(2)
			h:start()
			src:push(3)
			assert.equals(2, h.count)
			assert.same({ 1, 3 }, collect(h))
		end)

		it("start is idempotent when already running", function()
			local src = make_subscribable()
			local h = History(src, 10)
			h:start()
			src:push(1)
			assert.equals(1, h.count)
		end)

		it("reset: clears buffer and count", function()
			local src = make_subscribable()
			local h = History(src, 10)
			src:push(1)
			src:push(2)
			h:reset()
			assert.equals(0, h.count)
			assert.is_nil(h.state)
			assert.same({}, collect(h))
		end)

		it("reset: subscription stays active", function()
			local src = make_subscribable()
			local h = History(src, 10)
			src:push(1)
			h:reset()
			src:push(2)
			assert.equals(1, h.count)
			assert.equals(2, h.state)
		end)

		it("stop -> reset -> start lifecycle", function()
			local src = make_subscribable()
			local h = History(src, 10)
			src:push(1)
			src:push(2)
			src:push(3)
			src:push(4)
			src:push(5)
			assert.equals(5, h.count)

			h:stop()
			src:push(99)
			assert.equals(5, h.count)

			h:reset()
			assert.equals(0, h.count)
			assert.is_nil(h.state)
			assert.same({}, collect(h))

			h:start()
			src:push(100)
			assert.equals(1, h.count)
			assert.equals(100, h.state)
		end)
	end)
end)
