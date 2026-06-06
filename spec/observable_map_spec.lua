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
	describe("map", function()
		local obs, add, update, remove

		before_each(function()
			obs, add, update, remove = make_observable()
		end)

		describe("on_added", function()
			it("fires with the mapped item", function()
				local mapped = obs:map(function(item)
					return make_item(item.id .. "_out", item.state)
				end)
				local fired
				mapped:on_added(function(item)
					fired = item
				end)

				add(make_item("a", 1))

				assert.is_not_nil(fired)
				assert.equals("a_out", fired.id)
			end)

			it("wraps plain table output with Subscribable and Removable", function()
				local mapped = obs:map(function(item)
					return { id = item.id .. "_out", state = item.state }
				end)
				local fired
				mapped:on_added(function(item)
					fired = item
				end)

				add(make_item("a", 1))

				assert.is_not_nil(fired)
				assert.is_function(fired.subscribe)
				assert.is_function(fired.on_removed)
			end)

			it("fires separately for each added source item", function()
				local mapped = obs:map(function(item)
					return make_item(item.id .. "_out", item.state)
				end)
				local count = 0
				mapped:on_added(function()
					count = count + 1
				end)

				add(make_item("a", 1))
				add(make_item("b", 2))

				assert.equals(2, count)
			end)
		end)

		describe("on_updated", function()
			it("fires with updated state when output id is unchanged", function()
				local mapped = obs:map(function(item)
					return make_item(item.id .. "_out", item.state)
				end)
				add(make_item("a", 1))

				local fired
				mapped:on_updated(function(item)
					fired = item
				end)

				update(make_item("a", 2))

				assert.is_not_nil(fired)
				assert.equals("a_out", fired.id)
			end)

			it("fires on_removed then on_added when output id changes (re-key)", function()
				local item_a = make_item("a", "sink")
				local mapped = obs:map(function(item)
					return make_item(item.state, item.id)
				end)
				add(item_a)

				local removed_id, added_id
				mapped:on_removed(function(id)
					removed_id = id
				end)
				mapped:on_added(function(item)
					added_id = item.id
				end)

				update(make_item("a", "source"))

				assert.equals("sink", removed_id)
				assert.equals("source", added_id)
			end)

			it("does not fire on_updated when output id changes", function()
				local mapped = obs:map(function(item)
					return make_item(item.state, item.id)
				end)
				add(make_item("a", "sink"))

				local called = false
				mapped:on_updated(function()
					called = true
				end)

				update(make_item("a", "source"))

				assert.is_false(called)
			end)
		end)

		describe("on_removed", function()
			it("fires with the output id when source item is removed", function()
				local mapped = obs:map(function(item)
					return make_item(item.id .. "_out", item.state)
				end)
				add(make_item("a", 1))

				local removed_id
				mapped:on_removed(function(id)
					removed_id = id
				end)

				remove("a")

				assert.equals("a_out", removed_id)
			end)

			it("does not fire with the source id", function()
				local mapped = obs:map(function(item)
					return make_item(item.id .. "_out", item.state)
				end)
				add(make_item("a", 1))

				local removed_id
				mapped:on_removed(function(id)
					removed_id = id
				end)

				remove("a")

				assert.not_equals("a", removed_id)
			end)
		end)
	end)
end)
