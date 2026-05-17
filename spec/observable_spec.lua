require("spec.support.awesome_mocks")

local Observable = require("continuity.observable")
local Subscribable = require("continuity.subscribable")
local Removable = require("continuity.removable")
local extend = require("continuity.util.extend")

-- Builds a controllable Observable for testing. Returns the Observable plus three
-- fire functions: add(item), update(item), remove(id).
local function make_observable()
	local function fire(cbs, ...)
		for _, cb in ipairs(cbs) do
			cb(...)
		end
	end

	local obs = Observable()

	return obs,
		function(item)
			fire(obs.on_added_cbs, item)
		end,
		function(item)
			fire(obs.on_updated_cbs, item)
		end,
		function(id)
			fire(obs.on_removed_cbs, id)
		end
end

-- Creates a minimal item compatible with the internal API (Subscribable + Removable).
local Item = extend(Subscribable, Removable)
local function make_item(id)
	return setmetatable(Item.init({ id = id, state = nil }), Item.MT)
end

describe("Observable", function()
	describe("internal API", function()
		local obs

		before_each(function()
			obs = Observable()
		end)

		describe("add", function()
			it("returns true on first add", function()
				local item = make_item("a")
				assert.is_true(obs:add(item))
			end)

			it("returns false when id already exists", function()
				local item = make_item("a")
				obs:add(item)
				assert.is_false(obs:add(item))
			end)

			it("item is accessible via get after add", function()
				local item = make_item("a")
				obs:add(item)
				assert.equals(item, obs:get("a"))
			end)

			it("fires on_added with the item", function()
				local item = make_item("a")
				local fired
				obs:on_added(function(h)
					fired = h
				end)
				obs:add(item)
				assert.equals(item, fired)
			end)

			it("does not fire on_added for a duplicate", function()
				local item = make_item("a")
				obs:add(item)
				local count = 0
				obs:on_added(function()
					count = count + 1
				end)
				obs:add(item)
				assert.equals(0, count)
			end)
		end)

		describe("update", function()
			it("returns false when id not found", function()
				assert.is_false(obs:update("missing", {}))
			end)

			it("calls push on the item with new state", function()
				local item = make_item("a")
				obs:add(item)
				obs:update("a", { level = 75 })
				assert.equals(75, item.state.level)
			end)

			it("fires on_updated with the item", function()
				local item = make_item("a")
				obs:add(item)
				local fired
				obs:on_updated(function(h)
					fired = h
				end)
				obs:update("a", { level = 50 })
				assert.equals(item, fired)
			end)
		end)

		describe("remove", function()
			it("returns nil when id not found", function()
				assert.is_nil(obs:remove("missing"))
			end)

			it("returns the item on success", function()
				local item = make_item("a")
				obs:add(item)
				assert.equals(item, obs:remove("a"))
			end)

			it("item is no longer accessible via get after remove", function()
				local item = make_item("a")
				obs:add(item)
				obs:remove("a")
				assert.is_nil(obs:get("a"))
			end)

			it("fires item _removed_cbs before clearing them", function()
				local item = make_item("a")
				obs:add(item)
				local received
				item:on_removed(function(id)
					received = id
				end)
				obs:remove("a")
				assert.equals("a", received)
			end)

			it("clears item _removed_cbs after firing", function()
				local item = make_item("a")
				obs:add(item)
				item:on_removed(function() end)
				obs:remove("a")
				assert.equals(0, #item._removed_cbs)
			end)

			it("clears item _subs after removal", function()
				local item = make_item("a")
				obs:add(item)
				item:subscribe(function() end)
				obs:remove("a")
				assert.equals(0, #item._subs)
			end)

			it("fires on_removed with the id", function()
				local item = make_item("a")
				obs:add(item)
				local received
				obs:on_removed(function(id)
					received = id
				end)
				obs:remove("a")
				assert.equals("a", received)
			end)

			it("item _removed_cbs fire before observable on_removed", function()
				local item = make_item("a")
				obs:add(item)
				local order = {}
				item:on_removed(function()
					order[#order + 1] = "item"
				end)
				obs:on_removed(function()
					order[#order + 1] = "obs"
				end)
				obs:remove("a")
				assert.same({ "item", "obs" }, order)
			end)
		end)

		describe("all", function()
			it("returns empty table when no items", function()
				assert.equals(0, #obs:all())
			end)

			it("returns all added items", function()
				obs:add(make_item("a"))
				obs:add(make_item("b"))
				assert.equals(2, #obs:all())
			end)

			it("does not include removed items", function()
				obs:add(make_item("a"))
				obs:add(make_item("b"))
				obs:remove("a")
				assert.equals(1, #obs:all())
			end)
		end)

		describe("get", function()
			it("returns nil for unknown id", function()
				assert.is_nil(obs:get("nope"))
			end)

			it("returns the item for a known id", function()
				local item = make_item("a")
				obs:add(item)
				assert.equals(item, obs:get("a"))
			end)
		end)

		describe("on_added / on_updated / on_removed unsub", function()
			it("on_added unsub stops callbacks", function()
				local count = 0
				local unsub = obs:on_added(function()
					count = count + 1
				end)
				obs:add(make_item("a"))
				unsub()
				obs:add(make_item("b"))
				assert.equals(1, count)
			end)

			it("on_updated unsub stops callbacks", function()
				obs:add(make_item("a"))
				local count = 0
				local unsub = obs:on_updated(function()
					count = count + 1
				end)
				obs:update("a", {})
				unsub()
				obs:update("a", {})
				assert.equals(1, count)
			end)

			it("on_removed unsub stops callbacks", function()
				obs:add(make_item("a"))
				obs:add(make_item("b"))
				local count = 0
				local unsub = obs:on_removed(function()
					count = count + 1
				end)
				obs:remove("a")
				unsub()
				obs:remove("b")
				assert.equals(1, count)
			end)
		end)
	end)
	describe("group_by", function()
		local obs, add, update, remove

		before_each(function()
			obs, add, update, remove = make_observable()
		end)

		describe("on_added", function()
			it("fires when the first item for a key is added", function()
				local grouped = obs:group_by(function(item)
					return item.kind
				end)
				local fired
				grouped:on_added(function(group)
					fired = group
				end)

				add({ id = "a", kind = "sink" })

				assert.is_not_nil(fired)
			end)

			it("fires with correct group id and entries", function()
				local grouped = obs:group_by(function(item)
					return item.kind
				end)
				local fired
				grouped:on_added(function(group)
					fired = group
				end)

				add({ id = "a", kind = "sink" })

				assert.equals("sink", fired.id)
				assert.equals(1, #fired.entries)
				assert.equals("a", fired.entries[1].id)
			end)

			it("fires separately for each new key", function()
				local grouped = obs:group_by(function(item)
					return item.kind
				end)
				local fired = {}
				grouped:on_added(function(group)
					fired[#fired + 1] = group.id
				end)

				add({ id = "a", kind = "sink" })
				add({ id = "b", kind = "source" })

				assert.equals(2, #fired)
			end)

			it("does not fire when a second item is added to an existing group", function()
				local grouped = obs:group_by(function(item)
					return item.kind
				end)
				local count = 0
				grouped:on_added(function()
					count = count + 1
				end)

				add({ id = "a", kind = "sink" })
				add({ id = "b", kind = "sink" })

				assert.equals(1, count)
			end)
		end)

		describe("on_updated", function()
			it("fires when a second item is added to an existing group", function()
				local grouped = obs:group_by(function(item)
					return item.kind
				end)
				local fired
				grouped:on_updated(function(group)
					fired = group
				end)

				add({ id = "a", kind = "sink" })
				add({ id = "b", kind = "sink" })

				assert.is_not_nil(fired)
				assert.equals("sink", fired.id)
				assert.equals(2, #fired.entries)
			end)

			it("does not fire when the first item for a key is added", function()
				local grouped = obs:group_by(function(item)
					return item.kind
				end)
				local called = false
				grouped:on_updated(function()
					called = true
				end)

				add({ id = "a", kind = "sink" })

				assert.is_false(called)
			end)

			it("fires when an item is removed from a group that still has other items", function()
				local grouped = obs:group_by(function(item)
					return item.kind
				end)
				add({ id = "a", kind = "sink" })
				add({ id = "b", kind = "sink" })

				local fired
				grouped:on_updated(function(group)
					fired = group
				end)

				remove("a")

				assert.is_not_nil(fired)
				assert.equals("sink", fired.id)
				assert.equals(1, #fired.entries)
			end)

			it("fires for old group when an item moves to a different key", function()
				local grouped = obs:group_by(function(item)
					return item.kind
				end)
				local item_a = { id = "a", kind = "sink" }
				local item_b = { id = "b", kind = "sink" }
				add(item_a)
				add(item_b)

				local fired_ids = {}
				grouped:on_updated(function(group)
					fired_ids[#fired_ids + 1] = group.id
				end)
				grouped:on_added(function(group)
					fired_ids[#fired_ids + 1] = group.id
				end)

				item_a.kind = "source"
				update(item_a)

				-- "sink" group still has item_b → on_updated("sink")
				-- "source" is a new group → on_added("source")
				assert.is_true(#fired_ids >= 1)
				local found_sink = false
				for _, id in ipairs(fired_ids) do
					if id == "sink" then
						found_sink = true
					end
				end
				assert.is_true(found_sink)
			end)

			it("fires on_added for new key when an item moves", function()
				local grouped = obs:group_by(function(item)
					return item.kind
				end)
				local item_a = { id = "a", kind = "sink" }
				local item_b = { id = "b", kind = "sink" }
				add(item_a)
				add(item_b)

				local added_key
				grouped:on_added(function(group)
					added_key = group.id
				end)

				item_a.kind = "source"
				update(item_a)

				assert.equals("source", added_key)
			end)
		end)

		describe("on_removed", function()
			it("fires with the group key when the last item is removed", function()
				local grouped = obs:group_by(function(item)
					return item.kind
				end)
				add({ id = "a", kind = "sink" })

				local removed_key
				grouped:on_removed(function(key)
					removed_key = key
				end)

				remove("a")

				assert.equals("sink", removed_key)
			end)

			it("does not fire when group still has items after removal", function()
				local grouped = obs:group_by(function(item)
					return item.kind
				end)
				add({ id = "a", kind = "sink" })
				add({ id = "b", kind = "sink" })

				local called = false
				grouped:on_removed(function()
					called = true
				end)

				remove("a")

				assert.is_false(called)
			end)

			it("fires on_removed for old key when the last item moves to a different key", function()
				local grouped = obs:group_by(function(item)
					return item.kind
				end)
				local item_a = { id = "a", kind = "sink" }
				add(item_a)

				local removed_key
				grouped:on_removed(function(key)
					removed_key = key
				end)

				item_a.kind = "source"
				update(item_a)

				assert.equals("sink", removed_key)
			end)
		end)

		describe("all()", function()
			it("returns empty table when no items have been added", function()
				local grouped = obs:group_by(function(item)
					return item.kind
				end)
				assert.equals(0, #grouped:all())
			end)

			it("returns one group per distinct key", function()
				local grouped = obs:group_by(function(item)
					return item.kind
				end)
				add({ id = "a", kind = "sink" })
				add({ id = "b", kind = "sink" })
				add({ id = "c", kind = "source" })

				assert.equals(2, #grouped:all())
			end)

			it("each group contains the correct entries", function()
				local grouped = obs:group_by(function(item)
					return item.kind
				end)
				add({ id = "a", kind = "sink" })
				add({ id = "b", kind = "sink" })

				local groups = grouped:all()
				local sink_group
				for _, g in ipairs(groups) do
					if g.id == "sink" then
						sink_group = g
					end
				end
				assert.is_not_nil(sink_group)
				assert.equals(2, #sink_group.entries)
			end)
		end)

		describe("get()", function()
			it("returns the group for a known key", function()
				local grouped = obs:group_by(function(item)
					return item.kind
				end)
				add({ id = "a", kind = "sink" })

				local group = grouped:get("sink")
				assert.is_not_nil(group)
				assert.equals("sink", group.id)
			end)

			it("returns nil for an unknown key", function()
				local grouped = obs:group_by(function(item)
					return item.kind
				end)
				assert.is_nil(grouped:get("does_not_exist"))
			end)

			it("returned group reflects subsequent additions", function()
				local grouped = obs:group_by(function(item)
					return item.kind
				end)
				add({ id = "a", kind = "sink" })
				local group = grouped:get("sink")
				add({ id = "b", kind = "sink" })

				assert.equals(2, #group.entries)
			end)
		end)

		describe("group:subscribe", function()
			it("fires when a second item is added to the group", function()
				local grouped = obs:group_by(function(item)
					return item.kind
				end)
				add({ id = "a", kind = "sink" })
				local group = grouped:get("sink")

				local fired
				group:subscribe(function(g)
					fired = g
				end)

				add({ id = "b", kind = "sink" })

				assert.is_not_nil(fired)
				assert.equals(2, #fired)
			end)

			it("fires when an item is removed from the group but the group survives", function()
				local grouped = obs:group_by(function(item)
					return item.kind
				end)
				add({ id = "a", kind = "sink" })
				add({ id = "b", kind = "sink" })
				local group = grouped:get("sink")

				local fired
				group:subscribe(function(g)
					fired = g
				end)

				remove("a")

				assert.is_not_nil(fired)
				assert.equals(1, #fired)
			end)

			it("does not fire when the first item is added (group just created)", function()
				local grouped = obs:group_by(function(item)
					return item.kind
				end)

				local called = false
				grouped:on_added(function(group)
					group:subscribe(function()
						called = true
					end)
				end)

				add({ id = "a", kind = "sink" })

				assert.is_false(called)
			end)

			it("supports multiple independent subscribers on the same group", function()
				local grouped = obs:group_by(function(item)
					return item.kind
				end)
				add({ id = "a", kind = "sink" })
				local group = grouped:get("sink")

				local count_a, count_b = 0, 0
				group:subscribe(function()
					count_a = count_a + 1
				end)
				group:subscribe(function()
					count_b = count_b + 1
				end)

				add({ id = "b", kind = "sink" })

				assert.equals(1, count_a)
				assert.equals(1, count_b)
			end)

			it("unsubscribing stops further callbacks", function()
				local grouped = obs:group_by(function(item)
					return item.kind
				end)
				add({ id = "a", kind = "sink" })
				local group = grouped:get("sink")

				local count = 0
				local unsub = group:subscribe(function()
					count = count + 1
				end)

				add({ id = "b", kind = "sink" })
				unsub()
				add({ id = "c", kind = "sink" })

				assert.equals(1, count)
			end)
		end)

		describe("unsubscribe", function()
			it("on_added unsub stops further callbacks", function()
				local grouped = obs:group_by(function(item)
					return item.kind
				end)
				local count = 0
				local unsub = grouped:on_added(function()
					count = count + 1
				end)

				add({ id = "a", kind = "sink" })
				unsub()
				add({ id = "b", kind = "source" })

				assert.equals(1, count)
			end)

			it("on_updated unsub stops further callbacks", function()
				local grouped = obs:group_by(function(item)
					return item.kind
				end)
				add({ id = "a", kind = "sink" })

				local count = 0
				local unsub = grouped:on_updated(function()
					count = count + 1
				end)

				add({ id = "b", kind = "sink" })
				unsub()
				add({ id = "c", kind = "sink" })

				assert.equals(1, count)
			end)

			it("on_removed unsub stops further callbacks", function()
				local grouped = obs:group_by(function(item)
					return item.kind
				end)
				add({ id = "a", kind = "sink" })
				add({ id = "b", kind = "source" })

				local count = 0
				local unsub = grouped:on_removed(function()
					count = count + 1
				end)

				remove("a")
				unsub()
				remove("b")

				assert.equals(1, count)
			end)
		end)
	end)

	describe("unique", function()
		local obs, add, update, remove

		before_each(function()
			obs, add, update, remove = make_observable()
		end)

		describe("First strategy (default)", function()
			it("on_added fires with the first item added for a key", function()
				local unique = obs:unique(function(item)
					return item.name
				end)
				local fired
				unique:on_added(function(item)
					fired = item
				end)

				add({ id = "a1", name = "alpha" })

				assert.is_not_nil(fired)
				assert.equals("a1", fired.id)
			end)

			it("no event when a second item is added for the same key", function()
				local unique = obs:unique(function(item)
					return item.name
				end)
				local added_count, updated_count = 0, 0
				unique:on_added(function()
					added_count = added_count + 1
				end)
				unique:on_updated(function()
					updated_count = updated_count + 1
				end)

				add({ id = "a1", name = "alpha" })
				add({ id = "a2", name = "alpha" })

				assert.equals(1, added_count)
				assert.equals(0, updated_count)
			end)

			it("on_removed fires when the only item for a key is removed", function()
				local unique = obs:unique(function(item)
					return item.name
				end)
				add({ id = "a1", name = "alpha" })

				local removed_key
				unique:on_removed(function(key)
					removed_key = key
				end)

				remove("a1")

				assert.equals("alpha", removed_key)
			end)

			it("on_updated fires with the second item when the first is removed", function()
				local unique = obs:unique(function(item)
					return item.name
				end)
				add({ id = "a1", name = "alpha" })
				add({ id = "a2", name = "alpha" })

				local fired
				unique:on_updated(function(item)
					fired = item
				end)

				remove("a1")

				assert.is_not_nil(fired)
				assert.equals("a2", fired.id)
			end)

			it("no event when a non-first item is removed", function()
				local unique = obs:unique(function(item)
					return item.name
				end)
				add({ id = "a1", name = "alpha" })
				add({ id = "a2", name = "alpha" })

				local called = false
				unique:on_updated(function()
					called = true
				end)
				unique:on_removed(function()
					called = true
				end)

				remove("a2")

				assert.is_false(called)
			end)
		end)

		describe("Last strategy", function()
			it("on_added fires with the first item added for a key", function()
				local unique = obs:unique(function(item)
					return item.name
				end, Observable.UniqueStrategy.Last)
				local fired
				unique:on_added(function(item)
					fired = item
				end)

				add({ id = "a1", name = "alpha" })

				assert.equals("a1", fired.id)
			end)

			it("on_updated fires with the new item when a second item is added", function()
				local unique = obs:unique(function(item)
					return item.name
				end, Observable.UniqueStrategy.Last)
				add({ id = "a1", name = "alpha" })

				local fired
				unique:on_updated(function(item)
					fired = item
				end)

				add({ id = "a2", name = "alpha" })

				assert.is_not_nil(fired)
				assert.equals("a2", fired.id)
			end)

			it("on_removed fires when the only item is removed", function()
				local unique = obs:unique(function(item)
					return item.name
				end, Observable.UniqueStrategy.Last)
				add({ id = "a1", name = "alpha" })

				local removed_key
				unique:on_removed(function(key)
					removed_key = key
				end)

				remove("a1")

				assert.equals("alpha", removed_key)
			end)

			it("on_updated fires with the previous item when the last-added item is removed", function()
				local unique = obs:unique(function(item)
					return item.name
				end, Observable.UniqueStrategy.Last)
				add({ id = "a1", name = "alpha" })
				add({ id = "a2", name = "alpha" })

				local fired
				unique:on_updated(function(item)
					fired = item
				end)

				remove("a2")

				assert.is_not_nil(fired)
				assert.equals("a1", fired.id)
			end)

			it("no event when a non-last item is removed", function()
				local unique = obs:unique(function(item)
					return item.name
				end, Observable.UniqueStrategy.Last)
				add({ id = "a1", name = "alpha" })
				add({ id = "a2", name = "alpha" })

				local called = false
				unique:on_updated(function()
					called = true
				end)
				unique:on_removed(function()
					called = true
				end)

				remove("a1")

				assert.is_false(called)
			end)
		end)

		describe("Recent strategy", function()
			it("on_added fires with the first item added for a key", function()
				local unique = obs:unique(function(item)
					return item.name
				end, Observable.UniqueStrategy.Recent)
				local fired
				unique:on_added(function(item)
					fired = item
				end)

				add({ id = "a1", name = "alpha" })

				assert.equals("a1", fired.id)
			end)

			it("on_updated fires with the new item when a second item is added", function()
				local unique = obs:unique(function(item)
					return item.name
				end, Observable.UniqueStrategy.Recent)
				add({ id = "a1", name = "alpha" })

				local fired
				unique:on_updated(function(item)
					fired = item
				end)

				add({ id = "a2", name = "alpha" })

				assert.is_not_nil(fired)
				assert.equals("a2", fired.id)
			end)

			it("on_updated fires when the shown item is updated", function()
				local item_a1 = { id = "a1", name = "alpha" }
				local unique = obs:unique(function(item)
					return item.name
				end, Observable.UniqueStrategy.Recent)
				add(item_a1)

				local fired
				unique:on_updated(function(item)
					fired = item
				end)

				update(item_a1)

				assert.is_not_nil(fired)
				assert.equals("a1", fired.id)
			end)

			it("on_updated fires and promotes item when a non-shown item is updated", function()
				local item_a1 = { id = "a1", name = "alpha" }
				local item_a2 = { id = "a2", name = "alpha" }
				local unique = obs:unique(function(item)
					return item.name
				end, Observable.UniqueStrategy.Recent)
				add(item_a1)
				add(item_a2) -- a2 is now shown (most recently added)

				local fired
				unique:on_updated(function(item)
					fired = item
				end)

				update(item_a1) -- a1 becomes most recent

				assert.is_not_nil(fired)
				assert.equals("a1", fired.id)
			end)

			it("on_removed fires when the only item is removed", function()
				local unique = obs:unique(function(item)
					return item.name
				end, Observable.UniqueStrategy.Recent)
				add({ id = "a1", name = "alpha" })

				local removed_key
				unique:on_removed(function(key)
					removed_key = key
				end)

				remove("a1")

				assert.equals("alpha", removed_key)
			end)
		end)

		describe("all()", function()
			it("returns empty table when no items have been added", function()
				local unique = obs:unique(function(item)
					return item.name
				end)
				assert.equals(0, #unique:all())
			end)

			it("returns one item per distinct key (First strategy)", function()
				local unique = obs:unique(function(item)
					return item.name
				end)
				add({ id = "a1", name = "alpha" })
				add({ id = "a2", name = "alpha" })
				add({ id = "b1", name = "beta" })

				assert.equals(2, #unique:all())
			end)

			it("returns the first item for each key (First strategy)", function()
				local unique = obs:unique(function(item)
					return item.name
				end)
				add({ id = "a1", name = "alpha" })
				add({ id = "a2", name = "alpha" })

				local result = unique:all()
				assert.equals(1, #result)
				assert.equals("a1", result[1].id)
			end)

			it("returns the last item for each key (Last strategy)", function()
				local unique = obs:unique(function(item)
					return item.name
				end, Observable.UniqueStrategy.Last)
				add({ id = "a1", name = "alpha" })
				add({ id = "a2", name = "alpha" })

				local result = unique:all()
				assert.equals(1, #result)
				assert.equals("a2", result[1].id)
			end)

			it("returns the most recently updated item for each key (Recent strategy)", function()
				local item_a1 = { id = "a1", name = "alpha" }
				local item_a2 = { id = "a2", name = "alpha" }
				local unique = obs:unique(function(item)
					return item.name
				end, Observable.UniqueStrategy.Recent)
				add(item_a1)
				add(item_a2)
				update(item_a1) -- a1 is now most recent

				local result = unique:all()
				assert.equals(1, #result)
				assert.equals("a1", result[1].id)
			end)
		end)

		describe("get()", function()
			it("returns the representative item for a known id (First strategy)", function()
				local unique = obs:unique(function(item)
					return item.name
				end)
				add({ id = "a1", name = "alpha" })
				add({ id = "a2", name = "alpha" })

				assert.equals("a1", unique:get("a1").id)
			end)

			it("returns the representative even when queried via a non-shown item id (First strategy)", function()
				local unique = obs:unique(function(item)
					return item.name
				end)
				add({ id = "a1", name = "alpha" })
				add({ id = "a2", name = "alpha" })

				assert.equals("a1", unique:get("a2").id)
			end)

			it("returns the last-added item for a known id (Last strategy)", function()
				local unique = obs:unique(function(item)
					return item.name
				end, Observable.UniqueStrategy.Last)
				add({ id = "a1", name = "alpha" })
				add({ id = "a2", name = "alpha" })

				assert.equals("a2", unique:get("a1").id)
			end)

			it("returns nil for an unknown id", function()
				local unique = obs:unique(function(item)
					return item.name
				end)
				assert.is_nil(unique:get("does_not_exist"))
			end)
		end)

		describe("on_updated fires for the shown item when it is updated", function()
			it("fires when the First-shown item is updated", function()
				local item_a1 = { id = "a1", name = "alpha" }
				local unique = obs:unique(function(item)
					return item.name
				end)
				add(item_a1)

				local fired
				unique:on_updated(function(item)
					fired = item
				end)

				update(item_a1)

				assert.is_not_nil(fired)
				assert.equals("a1", fired.id)
			end)

			it("does not fire when a non-First item is updated (First strategy)", function()
				local item_a2 = { id = "a2", name = "alpha" }
				local unique = obs:unique(function(item)
					return item.name
				end)
				add({ id = "a1", name = "alpha" })
				add(item_a2)

				local called = false
				unique:on_updated(function()
					called = true
				end)

				update(item_a2)

				assert.is_false(called)
			end)

			it("fires when the Last-shown item is updated", function()
				local item_a2 = { id = "a2", name = "alpha" }
				local unique = obs:unique(function(item)
					return item.name
				end, Observable.UniqueStrategy.Last)
				add({ id = "a1", name = "alpha" })
				add(item_a2)

				local fired
				unique:on_updated(function(item)
					fired = item
				end)

				update(item_a2)

				assert.is_not_nil(fired)
				assert.equals("a2", fired.id)
			end)

			it("does not fire when a non-Last item is updated (Last strategy)", function()
				local item_a1 = { id = "a1", name = "alpha" }
				local unique = obs:unique(function(item)
					return item.name
				end, Observable.UniqueStrategy.Last)
				add(item_a1)
				add({ id = "a2", name = "alpha" })

				local called = false
				unique:on_updated(function()
					called = true
				end)

				update(item_a1)

				assert.is_false(called)
			end)
		end)

		describe("key changes", function()
			it("on_removed fires for old key and on_added fires for new key when item moves", function()
				local item_a = { id = "a1", name = "alpha" }
				local unique = obs:unique(function(item)
					return item.name
				end)
				add(item_a)

				local removed_key, added_item
				unique:on_removed(function(key)
					removed_key = key
				end)
				unique:on_added(function(item)
					added_item = item
				end)

				item_a.name = "beta"
				update(item_a)

				assert.equals("alpha", removed_key)
				assert.equals("a1", added_item.id)
			end)
		end)

		describe("unsubscribe", function()
			it("on_added unsub stops further callbacks", function()
				local unique = obs:unique(function(item)
					return item.name
				end)
				local count = 0
				local unsub = unique:on_added(function()
					count = count + 1
				end)

				add({ id = "a1", name = "alpha" })
				unsub()
				add({ id = "b1", name = "beta" })

				assert.equals(1, count)
			end)

			it("on_updated unsub stops further callbacks", function()
				local unique = obs:unique(function(item)
					return item.name
				end, Observable.UniqueStrategy.Last)
				add({ id = "a1", name = "alpha" })

				local count = 0
				local unsub = unique:on_updated(function()
					count = count + 1
				end)

				add({ id = "a2", name = "alpha" })
				unsub()
				add({ id = "a3", name = "alpha" })

				assert.equals(1, count)
			end)

			it("on_removed unsub stops further callbacks", function()
				local unique = obs:unique(function(item)
					return item.name
				end)
				add({ id = "a1", name = "alpha" })
				add({ id = "b1", name = "beta" })

				local count = 0
				local unsub = unique:on_removed(function()
					count = count + 1
				end)

				remove("a1")
				unsub()
				remove("b1")

				assert.equals(1, count)
			end)
		end)
	end)
end)
