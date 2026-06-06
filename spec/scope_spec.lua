require("spec.support.awesome_mocks")

local Scope = require("continuity.util.scope")
local Subscribable = require("continuity.subscribable")
local Removable = require("continuity.removable")
local Controllable = require("continuity.controllable")
local Observable = require("continuity.observable")
local support = require("spec.support.make_observable")
local make_item = support.make_item

-- Minimal signal source that mirrors the AwesomeWM gears.object signal API.
local function make_signal_source()
	local listeners = {}
	return {
		connect_signal = function(_, signal, cb)
			listeners[signal] = listeners[signal] or {}
			listeners[signal][cb] = true
		end,
		weak_connect_signal = function(_, signal, cb)
			listeners[signal] = listeners[signal] or {}
			listeners[signal][cb] = true
		end,
		disconnect_signal = function(_, signal, cb)
			if listeners[signal] then
				listeners[signal][cb] = nil
			end
		end,
		emit_signal = function(_, signal, ...)
			if listeners[signal] then
				for cb in pairs(listeners[signal]) do
					cb(...)
				end
			end
		end,
	}
end

-- Minimal fixtures.
local function make_subscribable()
	return Subscribable({})
end

local function make_removable()
	return Removable({})
end

local function make_controllable()
	return Controllable({})
end

local function make_observable()
	return Observable()
end

describe("Scope", function()
	describe("subscribe", function()
		it("callback fires while scope is alive", function()
			local scope = Scope()
			local src = make_subscribable()
			local count = 0
			scope:subscribe(src, function()
				count = count + 1
			end)
			src:push("x")
			assert.equals(1, count)
		end)

		it("callback stops firing after dispose", function()
			local scope = Scope()
			local src = make_subscribable()
			local count = 0
			scope:subscribe(src, function()
				count = count + 1
			end)
			src:push("x")
			scope:dispose()
			src:push("y")
			assert.equals(1, count)
		end)
	end)

	describe("weak_subscribe", function()
		it("holds the callback alive while scope is alive", function()
			local scope = Scope()
			local src = make_subscribable()
			local count = 0
			do
				local cb = function()
					count = count + 1
				end
				scope:weak_subscribe(src, cb)
				-- cb goes out of scope here, but scope holds it
			end
			collectgarbage("collect")
			src:push("x")
			assert.equals(1, count)
		end)

		it("callback stops firing after dispose", function()
			local scope = Scope()
			local src = make_subscribable()
			local count = 0
			scope:weak_subscribe(src, function()
				count = count + 1
			end)
			src:push("x")
			scope:dispose()
			src:push("y")
			assert.equals(1, count)
		end)
	end)

	describe("on_removed (Removable)", function()
		it("callback fires while scope is alive", function()
			local scope = Scope()
			local item = make_removable()
			local received
			scope:on_removed(item, function(id)
				received = id
			end)
			item._removed_cbs:fire("dev-1")
			assert.equals("dev-1", received)
		end)

		it("callback stops firing after dispose", function()
			local scope = Scope()
			local item = make_removable()
			local count = 0
			scope:on_removed(item, function()
				count = count + 1
			end)
			item._removed_cbs:fire("dev-1")
			scope:dispose()
			item._removed_cbs:fire("dev-2")
			assert.equals(1, count)
		end)
	end)

	describe("weak_on_removed (Removable)", function()
		it("holds the callback alive while scope is alive", function()
			local scope = Scope()
			local item = make_removable()
			local count = 0
			do
				local cb = function()
					count = count + 1
				end
				scope:weak_on_removed(item, cb)
			end
			collectgarbage("collect")
			item._weak_removed_cbs:fire("dev-1")
			assert.equals(1, count)
		end)
	end)

	describe("on_control (Controllable)", function()
		it("callback fires while scope is alive", function()
			local scope = Scope()
			local ctrl = make_controllable()
			local received
			scope:on_control(ctrl, function(s)
				received = s
			end)
			ctrl:control_event({ value = 1 })
			assert.equals(1, received.value)
		end)

		it("callback stops firing after dispose", function()
			local scope = Scope()
			local ctrl = make_controllable()
			local count = 0
			scope:on_control(ctrl, function()
				count = count + 1
			end)
			ctrl:control_event({})
			scope:dispose()
			ctrl:control_event({})
			assert.equals(1, count)
		end)
	end)

	describe("weak_on_control (Controllable)", function()
		it("holds the callback alive while scope is alive", function()
			local scope = Scope()
			local ctrl = make_controllable()
			local count = 0
			do
				local cb = function()
					count = count + 1
				end
				scope:weak_on_control(ctrl, cb)
			end
			collectgarbage("collect")
			ctrl:control_event({})
			assert.equals(1, count)
		end)
	end)

	describe("on_added / on_updated / on_removed (Observable)", function()
		it("on_added fires while scope is alive", function()
			local scope = Scope()
			local obs = make_observable()
			local fired
			scope:on_added(obs, function(item)
				fired = item
			end)
			local item_a = make_item("a", 1)
			obs:add(item_a)
			assert.equals(item_a, fired)
		end)

		it("on_updated fires while scope is alive", function()
			local scope = Scope()
			local obs = make_observable()
			local item_a = make_item("a", 1)
			obs:add(item_a)
			local fired
			scope:on_updated(obs, function(item)
				fired = item
			end)
			obs:update("a", 2)
			assert.equals(item_a, fired)
		end)

		it("on_removed fires while scope is alive", function()
			local scope = Scope()
			local obs = make_observable()
			local item_a = make_item("a", 1)
			obs:add(item_a)
			local received
			scope:on_removed(obs, function(id)
				received = id
			end)
			obs:remove("a")
			assert.equals("a", received)
		end)

		it("all three stop firing after dispose", function()
			local scope = Scope()
			local obs = make_observable()
			local count = 0
			local cb = function()
				count = count + 1
			end
			scope:on_added(obs, cb)
			scope:on_updated(obs, cb)
			scope:on_removed(obs, cb)

			obs:add(make_item("a", 1))
			obs:update("a", 2)
			obs:remove("a")
			assert.equals(3, count)

			scope:dispose()
			obs:add(make_item("b", 1))
			obs:update("b", 2)
			obs:remove("b")
			assert.equals(3, count)
		end)
	end)

	describe("weak_on_added / weak_on_updated / weak_on_removed (Observable)", function()
		it("weak_on_added holds callback alive", function()
			local scope = Scope()
			local obs = make_observable()
			local count = 0
			do
				local cb = function()
					count = count + 1
				end
				scope:weak_on_added(obs, cb)
			end
			collectgarbage("collect")
			obs:add(make_item("a", 1))
			assert.equals(1, count)
		end)
	end)

	describe("connect_signal", function()
		it("callback fires while scope is alive", function()
			local scope = Scope()
			local src = make_signal_source()
			local received
			scope:connect_signal(src, "my::event", function(v)
				received = v
			end)
			src:emit_signal("my::event", 42)
			assert.equals(42, received)
		end)

		it("callback stops firing after dispose", function()
			local scope = Scope()
			local src = make_signal_source()
			local count = 0
			scope:connect_signal(src, "my::event", function()
				count = count + 1
			end)
			src:emit_signal("my::event")
			scope:dispose()
			src:emit_signal("my::event")
			assert.equals(1, count)
		end)

		it("dispose calls disconnect_signal with the original callback", function()
			local scope = Scope()
			local src = make_signal_source()
			local count = 0
			local cb = function()
				count = count + 1
			end
			scope:connect_signal(src, "my::event", cb)
			src:emit_signal("my::event")
			scope:dispose()
			src:emit_signal("my::event")
			assert.equals(1, count)
		end)
	end)

	describe("weak_connect_signal", function()
		it("holds the callback alive while scope is alive", function()
			local scope = Scope()
			local src = make_signal_source()
			local count = 0
			do
				local cb = function()
					count = count + 1
				end
				scope:weak_connect_signal(src, "my::event", cb)
			end
			collectgarbage("collect")
			src:emit_signal("my::event")
			assert.equals(1, count)
		end)

		it("callback stops firing after dispose", function()
			local scope = Scope()
			local src = make_signal_source()
			local count = 0
			scope:weak_connect_signal(src, "my::event", function()
				count = count + 1
			end)
			src:emit_signal("my::event")
			scope:dispose()
			src:emit_signal("my::event")
			assert.equals(1, count)
		end)

		it("multiple signals on the same source are each disconnected on dispose", function()
			local scope = Scope()
			local src = make_signal_source()
			local count = 0
			scope:weak_connect_signal(src, "event::a", function()
				count = count + 1
			end)
			scope:weak_connect_signal(src, "event::b", function()
				count = count + 1
			end)
			src:emit_signal("event::a")
			src:emit_signal("event::b")
			assert.equals(2, count)
			scope:dispose()
			src:emit_signal("event::a")
			src:emit_signal("event::b")
			assert.equals(2, count)
		end)
	end)

	describe("dispose", function()
		it("releases multiple subscriptions across different source types", function()
			local scope = Scope()
			local src = make_subscribable()
			local ctrl = make_controllable()
			local count = 0
			scope:subscribe(src, function()
				count = count + 1
			end)
			scope:on_control(ctrl, function()
				count = count + 1
			end)
			src:push("x")
			ctrl:control_event({})
			assert.equals(2, count)

			scope:dispose()
			src:push("y")
			ctrl:control_event({})
			assert.equals(2, count)
		end)

		it("second call does not error (empty unsub table is safe to iterate)", function()
			local scope = Scope()
			local src = make_subscribable()
			scope:subscribe(src, function() end)
			scope:dispose()
			assert.has_no.errors(function()
				scope:dispose()
			end)
		end)

		it("callbacks do not fire after second dispose", function()
			local scope = Scope()
			local src = make_subscribable()
			local count = 0
			scope:subscribe(src, function()
				count = count + 1
			end)
			scope:dispose()
			scope:dispose()
			src:push("x")
			assert.equals(0, count)
		end)

		it("clears subscriptions added after a prior dispose", function()
			local scope = Scope()
			local src = make_subscribable()
			local count = 0
			scope:subscribe(src, function()
				count = count + 1
			end)
			scope:dispose()
			-- register a new subscription after dispose
			scope:subscribe(src, function()
				count = count + 1
			end)
			src:push("x")
			assert.equals(1, count)
			scope:dispose()
			src:push("y")
			assert.equals(1, count)
		end)
	end)

	describe("auto-dispose on GC", function()
		-- collectgarbage("collect") is synchronous in Lua 5.3 and LuaJIT.
		-- On LuaJIT the newproxy mechanism is used; may need two GC cycles for proxy cycle.
		it("callback does not fire after scope is dropped and GC is forced", function()
			local src = make_subscribable()
			local count = 0
			do
				local scope = Scope()
				scope:subscribe(src, function()
					count = count + 1
				end)
			end
			collectgarbage("collect")
			collectgarbage("collect")
			src:push("x")
			assert.equals(0, count)
		end)
	end)

	describe("no __call metamethod", function()
		it("Scope() constructs a new instance (not a call-to-register pattern)", function()
			local scope = Scope()
			assert.is_not_nil(scope)
			assert.is_nil(getmetatable(scope).__call)
		end)
	end)
end)
