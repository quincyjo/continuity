require("spec.support.awesome_mocks")

local Observable = require("continuity.observable")
local Subscribable = require("continuity.subscribable")
local Removable = require("continuity.removable")
local extend = require("continuity.util.extend")

local Item = extend(Subscribable, Removable)
local function make_item(id, state)
	return setmetatable(Item.init({ id = id, state = state }), Item.MT)
end

local function make_observable()
	local obs = Observable()
	return obs,
		function(item)
			obs.on_added_cbs:fire(item)
			obs.weak_on_added_cbs:fire(item)
		end,
		function(item)
			obs.on_updated_cbs:fire(item)
			obs.weak_on_updated_cbs:fire(item)
		end,
		function(id)
			obs.on_removed_cbs:fire(id)
			obs.weak_on_removed_cbs:fire(id)
		end
end

describe("Observable", function()
	describe("filter", function()
		local obs, add, update, remove

		before_each(function()
			obs, add, update, remove = make_observable()
		end)

		describe("on_added", function()
			it("fires for items passing the predicate", function()
				local filtered = obs:filter(function(item)
					return item.state == "sink"
				end)
				local fired
				filtered:on_added(function(item)
					fired = item
				end)

				add(make_item("a", "sink"))

				assert.is_not_nil(fired)
				assert.equals("a", fired.id)
			end)

			it("does not fire for items failing the predicate", function()
				local filtered = obs:filter(function(item)
					return item.state == "sink"
				end)
				local called = false
				filtered:on_added(function()
					called = true
				end)

				add(make_item("a", "source"))

				assert.is_false(called)
			end)
		end)

		describe("on_updated", function()
			it("fires when a passing item is updated and still passes", function()
				local filtered = obs:filter(function(item)
					return item.state == "sink"
				end)
				add(make_item("a", "sink"))

				local fired
				filtered:on_updated(function(item)
					fired = item
				end)

				update(make_item("a", "sink"))

				assert.is_not_nil(fired)
			end)

			it("does not fire on_updated when a failing item is updated", function()
				local filtered = obs:filter(function(item)
					return item.state == "sink"
				end)
				add(make_item("a", "source"))

				local called = false
				filtered:on_updated(function()
					called = true
				end)

				update(make_item("a", "source"))

				assert.is_false(called)
			end)
		end)

		describe("predicate transitions", function()
			it("fires on_removed when a passing item transitions to failing", function()
				local filtered = obs:filter(function(item)
					return item.state == "sink"
				end)
				add(make_item("a", "sink"))

				local removed_id
				filtered:on_removed(function(id)
					removed_id = id
				end)

				update(make_item("a", "source"))

				assert.equals("a", removed_id)
			end)

			it("fires on_added when a failing item transitions to passing", function()
				local filtered = obs:filter(function(item)
					return item.state == "sink"
				end)
				add(make_item("a", "source"))

				local added_id
				filtered:on_added(function(item)
					added_id = item.id
				end)

				update(make_item("a", "sink"))

				assert.equals("a", added_id)
			end)
		end)

		describe("on_removed", function()
			it("fires when a passing item is removed from source", function()
				local filtered = obs:filter(function(item)
					return item.state == "sink"
				end)
				add(make_item("a", "sink"))

				local removed_id
				filtered:on_removed(function(id)
					removed_id = id
				end)

				remove("a")

				assert.equals("a", removed_id)
			end)

			it("does not fire when a failing item is removed from source", function()
				local filtered = obs:filter(function(item)
					return item.state == "sink"
				end)
				add(make_item("a", "source"))

				local called = false
				filtered:on_removed(function()
					called = true
				end)

				remove("a")

				assert.is_false(called)
			end)
		end)

		describe("auto-disconnect on GC", function()
			it("stops forwarding on_added events when transformation is dropped and GC'd", function()
				local fired = false
				do
					local t = obs:filter(function()
						return true
					end)
					t:on_added(function()
						fired = true
					end)
					t = nil -- luacheck: ignore
				end
				collectgarbage("collect")
				add(make_item("a"))
				assert.is_false(fired)
			end)
		end)

		describe("source item lifecycle", function()
			it("does not clear source item _subs when filter removes it from view", function()
				obs:filter(function(item)
					return item.state == "sink"
				end)
				local item_a = make_item("a", "sink")
				add(item_a)

				local sub_fired = false
				item_a:subscribe(function()
					sub_fired = true
				end)

				update(make_item("a", "source"))

				item_a:push("anything")
				assert.is_true(sub_fired)
			end)

			it("does not clear source item _removed_cbs when filter removes it from view", function()
				obs:filter(function(item)
					return item.state == "sink"
				end)
				local item_a = make_item("a", "sink")
				add(item_a)

				local fired = false
				item_a:on_removed(function()
					fired = true
				end)

				update(make_item("a", "source"))

				item_a._removed_cbs:fire("a")
				assert.is_true(fired)
			end)
		end)
	end)
end)
