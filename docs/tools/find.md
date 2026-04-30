# tools.find

The `find` module is an async wrapper around `fd` or `find`. The best available
backend is selected automatically from `PATH` at load time, preferring `fd`.

## Usage

The module is callable directly. Pass options and a callback; the callback
receives the full result list once the process exits.

```lua
local find = require("continuity.tools.find")

-- Plain string: treated as the pattern.
find("*.lua", function(results, exit_code)
    for _, path in ipairs(results) do
        print(path)
    end
end)

-- Options table:
find({ pattern = "*.lua", path = "/home", hidden = true }, function(results, exit_code)
    ...
end)
```

### Options

```lua
---@class FindOpts
---@field pattern?   string
---@field path?      string
---@field maxdepth?  integer
---@field type?      "file"|"directory"|"symlink"|"block"|"char"|"pipe"|"socket"
---@field extension? string
---@field exec?      string
---@field hidden?    boolean
```

Positional shorthand: `find("pattern", cb)` is equivalent to
`find({ pattern = "pattern" }, cb)`.

### Streaming

`find.stream(opts, cb)` delivers results incrementally as they arrive. The
callback is called with a batch of paths as they become available, and a final
call with `nil, exit_code` when the process exits.

```lua
find.stream({ pattern = "*.log", path = "/var" }, function(batch, exit_code)
    if batch then
        for _, path in ipairs(batch) do
            print(path)
        end
    else
        print("done, exit:", exit_code)
    end
end)
```
