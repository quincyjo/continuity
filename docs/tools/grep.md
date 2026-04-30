# tools.grep

The `grep` module is an async wrapper around `rg` or `grep`. The best available
backend is selected automatically from `PATH` at load time, preferring `rg`.

Results are structured `GrepResult` tables rather than raw lines, and file
paths are interned to reduce allocations when many results share a path.

## Usage

The module is callable directly. Pass options and a callback; the callback
receives the full result list once the process exits.

```lua
local grep = require("continuity.tools.grep")

grep({ pattern = "TODO", path = "." }, function(results, exit_code)
    for _, result in ipairs(results) do
        print(result.filepath, result.line_number, result.text)
    end
end)
```

Positional shorthand: `grep({ "pattern", "path" }, cb)` is equivalent to
`grep({ pattern = "pattern", path = "path" }, cb)`.

### Options

```lua
---@class GrepOpts
---@field pattern           string
---@field path              string
---@field fixed_string?     boolean  Match literally, not as a regex.
---@field case_insensitive? boolean
---@field include?          string   Glob for files to include (e.g. "*.lua").
---@field exclude?          string   Glob for files to exclude.
---@field type?             string   File type filter (rg type names, e.g. "lua").
---@field max_depth?        integer  Maximum directory depth. rg only; ignored by grep backend.
```

### Result Type

```lua
---@class GrepResult
---@field filepath    string
---@field line_number integer
---@field text        string
```

### Streaming

`grep.stream(opts, cb)` delivers results incrementally as they arrive. The
callback is called with a batch of `GrepResult` tables as they become available,
and a final call with `nil, exit_code` when the process exits.

```lua
grep.stream({ pattern = "error", path = "/var/log" }, function(batch, exit_code)
    if batch then
        for _, result in ipairs(batch) do
            print(result.filepath .. ":" .. result.line_number .. ": " .. result.text)
        end
    else
        print("done, exit:", exit_code)
    end
end)
```
