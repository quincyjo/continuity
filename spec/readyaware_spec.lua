local ReadyAware = require("continuity.class.readyaware")

local function make()
	return ReadyAware({})
end

describe("ReadyAware", function()
	it("is not ready before first push", function()
		local m = make()
		assert.is_false(m._ready)
	end)

	it("on_ready fires on first push", function()
		local m = make()
		local received = {}
		m:on_ready(function(s)
			received[#received + 1] = s
		end)
		m:push({ value = 1 })
		assert.equals(1, #received)
		assert.equals(1, received[1].value)
	end)

	it("on_ready does not fire again on subsequent pushes", function()
		local m = make()
		local count = 0
		m:on_ready(function()
			count = count + 1
		end)
		m:push({ value = 1 })
		m:push({ value = 2 })
		assert.equals(1, count)
	end)

	it("subscribe does not fire on first push (initialization)", function()
		local m = make()
		local received = {}
		m:subscribe(function(s)
			received[#received + 1] = s
		end)
		m:push({ value = 1 })
		assert.equals(0, #received)
	end)

	it("subscribe fires on subsequent pushes", function()
		local m = make()
		m:push({ value = 1 })
		local received = {}
		m:subscribe(function(s)
			received[#received + 1] = s
		end)
		m:push({ value = 2 })
		assert.equals(1, #received)
		assert.equals(2, received[1].value)
	end)

	it("subscribe does not replay state on registration", function()
		local m = make()
		m:push({ value = 1 })
		local fired = false
		m:subscribe(function()
			fired = true
		end)
		assert.is_false(fired)
	end)

	it("subscribe returns an unsubscribe function that stops future notifications", function()
		local m = make()
		m:push({ value = 1 })
		local received = {}
		local unsub = m:subscribe(function(s)
			received[#received + 1] = s
		end)
		unsub()
		m:push({ value = 2 })
		assert.equals(0, #received)
	end)

	it("on_ready replays immediately if already initialized", function()
		local m = make()
		m:push({ value = 1 })
		local received = {}
		m:on_ready(function(s)
			received[#received + 1] = s
		end)
		assert.equals(1, #received)
		assert.equals(1, received[1].value)
	end)

	it("push sets state", function()
		local m = make()
		m:push({ value = 42 })
		assert.equals(42, m.state.value)
	end)

	describe("weak_subscribe", function()
		it("does not fire on first push", function()
			local m = make()
			local fired = false
			local cb = function()
				fired = true
			end
			m:weak_subscribe(cb)
			m:push({ value = 1 })
			assert.is_false(fired)
		end)

		it("fires on subsequent pushes while callback is held", function()
			local m = make()
			m:push({ value = 1 })
			local received = {}
			local cb = function(s)
				received[#received + 1] = s
			end
			m:weak_subscribe(cb)
			m:push({ value = 2 })
			assert.equals(1, #received)
			assert.equals(2, received[1].value)
		end)

		it("returns an unsubscribe function that stops callbacks", function()
			local m = make()
			m:push({ value = 1 })
			local count = 0
			local cb = function()
				count = count + 1
			end
			local unsub = m:weak_subscribe(cb)
			m:push({ value = 2 })
			unsub()
			m:push({ value = 3 })
			assert.equals(1, count)
		end)

		it("does not fire after the callback reference is released and GC is forced", function()
			local m = make()
			m:push({ value = 1 })
			local fired = false
			local cb = function()
				fired = true
			end
			m:weak_subscribe(cb)
			cb = nil -- luacheck: ignore
			collectgarbage("collect")
			m:push({ value = 2 })
			assert.is_false(fired)
		end)
	end)

	it("on_ready and subscribe are both notified across their respective events", function()
		local m = make()
		local ready_log, sub_log = {}, {}
		m:on_ready(function(s)
			ready_log[#ready_log + 1] = s.value
		end)
		m:subscribe(function(s)
			sub_log[#sub_log + 1] = s.value
		end)
		m:push({ value = 10 })
		m:push({ value = 20 })
		m:push({ value = 30 })
		assert.same({ 10 }, ready_log)
		assert.same({ 20, 30 }, sub_log)
	end)
end)
