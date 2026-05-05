local AsyncQueue = require("continuity.util.async_queue")

describe("AsyncQueue construction", function()
	it("AsyncQueue() returns a queue with submit and flush", function()
		local q = AsyncQueue()
		assert.is_table(q)
		assert.is_function(q.submit)
		assert.is_function(q.flush)
	end)

	it("AsyncQueue.new() returns a queue with submit and flush", function()
		local q = AsyncQueue.new()
		assert.is_table(q)
		assert.is_function(q.submit)
		assert.is_function(q.flush)
	end)
end)

describe("AsyncQueue submit", function()
	it("returns an item with done=false and a complete function", function()
		local q = AsyncQueue()
		local item = q:submit()
		assert.is_table(item)
		assert.is_false(item.done)
		assert.is_function(item.complete)
	end)

	it("each submit returns a distinct item", function()
		local q = AsyncQueue()
		local a = q:submit()
		local b = q:submit()
		assert.not_equal(a, b)
	end)
end)

describe("AsyncQueue single item", function()
	it("effect is called when item is completed with ok=true", function()
		local q = AsyncQueue()
		local called = false
		local item = q:submit()
		item:complete(true, function()
			called = true
		end)
		assert.is_true(called)
	end)

	it("effect is called even when ok=false", function()
		local q = AsyncQueue()
		local called = false
		local item = q:submit()
		item:complete(false, function()
			called = true
		end)
		assert.is_true(called)
	end)

	it("ok is stored on the item after complete", function()
		local q = AsyncQueue()
		local item = q:submit()
		item:complete(false)
		assert.is_false(item.ok)
	end)

	it("done is set to true after complete", function()
		local q = AsyncQueue()
		local item = q:submit()
		item:complete(true)
		assert.is_true(item.done)
	end)

	it("complete with no effect does not error", function()
		local q = AsyncQueue()
		local item = q:submit()
		assert.has_no_error(function()
			item:complete(true)
		end)
	end)
end)

describe("AsyncQueue linearization", function()
	it("effects fire in submission order when completed in order", function()
		local q = AsyncQueue()
		local order = {}
		local a = q:submit()
		local b = q:submit()
		a:complete(true, function()
			order[#order + 1] = "a"
		end)
		b:complete(true, function()
			order[#order + 1] = "b"
		end)
		assert.same({ "a", "b" }, order)
	end)

	it("second item effect is held when second completes before first", function()
		local q = AsyncQueue()
		local order = {}
		q:submit()
		local b = q:submit()
		b:complete(true, function()
			order[#order + 1] = "b"
		end)
		assert.same({}, order)
	end)

	it("held effect fires in order after first item completes", function()
		local q = AsyncQueue()
		local order = {}
		local a = q:submit()
		local b = q:submit()
		b:complete(true, function()
			order[#order + 1] = "b"
		end)
		a:complete(true, function()
			order[#order + 1] = "a"
		end)
		assert.same({ "a", "b" }, order)
	end)

	it("three items: effects fire in order when middle completes last", function()
		local q = AsyncQueue()
		local order = {}
		local a = q:submit()
		local b = q:submit()
		local c = q:submit()
		a:complete(true, function()
			order[#order + 1] = "a"
		end)
		c:complete(true, function()
			order[#order + 1] = "c"
		end)
		b:complete(true, function()
			order[#order + 1] = "b"
		end)
		assert.same({ "a", "b", "c" }, order)
	end)

	it("item with no effect does not block subsequent items", function()
		local q = AsyncQueue()
		local order = {}
		local a = q:submit()
		local b = q:submit()
		a:complete(true)
		b:complete(true, function()
			order[#order + 1] = "b"
		end)
		assert.same({ "b" }, order)
	end)
end)

describe("AsyncQueue flush", function()
	it("flush on an empty queue is a no-op", function()
		local q = AsyncQueue()
		assert.has_no_error(function()
			q:flush()
		end)
	end)

	it("completed items are removed so a subsequent submit drains immediately", function()
		local q = AsyncQueue()
		local a = q:submit()
		local b = q:submit()
		a:complete(true)
		b:complete(true)
		local order = {}
		local c = q:submit()
		c:complete(true, function()
			order[#order + 1] = "c"
		end)
		assert.same({ "c" }, order)
	end)
end)
