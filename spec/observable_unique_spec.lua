require("spec.support.awesome_mocks")

local Observable = require("continuity.observable")

local function make_observable()
	local obs = Observable()
	return obs,
		function(item)
			obs.on_added_cbs:fire(item)
		end,
		function(item)
			obs.on_updated_cbs:fire(item)
		end,
		function(id)
			obs.on_removed_cbs:fire(id)
		end
end

describe("Observable", function()
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
