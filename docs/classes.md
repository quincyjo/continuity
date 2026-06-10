# Classes

Continuity provides a number of high level classes that provide event driven
APIs. All subscription functions return unsub functions that can be called to
stop receiving updates. Weak subscriptions are also available.

## Subscribable

Subscribable is the base class for stateful, observable values. It tracks the
current state and notifies registered callbacks whenever the state changes.

| Method | Description |
|---|---|
| `subscribe(cb, opts?)` | Register a callback; returns an unsub function. |
| `weak_subscribe(cb, opts?)` | Same as `subscribe`, but the callback is held weakly and may be collected. |
| `state` | The current state value. Always non-nil on a plain `Subscribable`; only `Monitor` and `ReadyAware` may have a `nil` state. |
| `map(fn)` | Return a new `Subscribable` whose state is `fn` applied to each update. |

`opts.debounce` (seconds) coalesces rapid state changes: the callback fires once after the
handle stops changing for the given duration.

```lua
local handle = require("continuity.audio").Volume

-- Subscribe to changes.
local unsub = handle:subscribe(function(state)
    print(state.level, state.muted)
end)

-- Read the current state at any time.
print(handle.state.level)

-- Stop receiving updates.
unsub()
```

### map

`map` returns a new `Subscribable` whose state is the result of applying a
function to each update from the original. The mapped subscribable forwards
subscriptions to the original, so it inherits the original's subscription
behaviour; EG, a map of a `Monitor` will replay the current state on
subscribe, for example.

```lua
local audio = require("continuity.audio")

-- Derive a subscribable that tracks only the volume level.
local level = audio.Volume:map(function(state)
    return state.level
end)

level:subscribe(function(lvl)
    print("Volume:", lvl)
end)
```

### Monitor

Monitor is a subclass of Subscribable that handles data streamed from a
backend. Unlike plain `Subscribable`, `subscribe` fires once immediately with
the current state if it is already available, so callers never miss an
initial value.

| Method | Description |
|---|---|
| `setup(opts?)` | Start the backend. Call once in `rc.lua`. |
| `stop()` | Stop the backend and reset state. |
| `subscribe(cb, opts?)` | Register a callback; replays current state immediately if available. |
| `weak_subscribe(cb, opts?)` | Same as `subscribe` with a weak reference to the callback. |
| `state` | The most recent state pushed by the backend. `nil` before the first update: one of two `Subscribable` subclasses where `nil` state is possible. |

```lua
local bat = require("continuity.sysinfo.bat")
bat.setup()

-- Fires immediately with the current battery state, then on every update.
bat:subscribe(function(state)
    print(state.percentage, state.status)
end)
```

### ReadyAware

ReadyAware is a subclass of Subscribable for handles that are instantiated
before their data is available such as `audio.Volume`, a utility handle
created before the backend has reported the device's state. ReadyAware instances
are change-oriented: `subscribe` only fires when state changes after the
handle is ready, not on the initial population. Use `on_ready` to receive the
first state.

| Method | Description |
|---|---|
| `on_ready(cb)` | Fires once when the handle becomes ready. If already ready, fires immediately. |
| `subscribe(cb, opts?)` | Register a callback for subsequent state changes. Returns an unsub function. |
| `weak_subscribe(cb, opts?)` | Same as `subscribe` with a weak reference to the callback. |
| `state` | The current state. `nil` before the handle is ready: one of two `Subscribable` subclasses where `nil` state is possible. |

```lua
local audio = require("continuity.audio")

-- The device handle exists but may not have state yet.
audio.Volume:on_ready(function(state)
    print("Device ready:", state.name)
end)

-- Only fires on subsequent changes, not on the initial state.
audio.Volume:subscribe(function(state)
    print("Device updated:", state.name)
end)
```

### History

History is a subclass of Subscribable that collects the history of another
Subscribable in a fixed-capacity ring buffer. The newest entry is always
`history.state`; iterating with `iter()` yields entries oldest-to-newest.

| Method | Description |
|---|---|
| `History(source, capacity)` | Create a new History watching `source` with the given capacity. |
| `iter()` | Return an iterator over buffered entries, oldest first. |
| `count` | Number of entries currently buffered. |
| `capacity` | Maximum number of entries to retain. |
| `reset()` | Clear the buffer. |
| `stop()` | Detach from the source. |
| `start()` | Reattach to the source (no-op if already attached). |

```lua
local History = require("continuity.history")
local bat     = require("continuity.sysinfo.bat")
bat.setup()

-- Keep the last 10 battery readings.
local history = History(bat, 10)

-- Subscribable: fires on each new entry.
history:subscribe(function(entry)
    print("New entry:", entry.percentage)
end)

-- Iterate over all buffered entries oldest to newest.
for entry in history:iter() do
    print(entry.percentage, entry.status)
end
```

## Observable

An Observable represents a mutable collection of individually subscribable
items. It fires events when items are added or removed from the
collection as well as when they are updated.

| Method | Description |
|---|---|
| `on_added(cb)` | Register a callback fired when an item is added. Returns an unsub function. |
| `on_updated(cb)` | Register a callback fired when an item is updated. Returns an unsub function. |
| `on_removed(cb)` | Register a callback fired with the item's `id` when it is removed. Returns an unsub function. |
| `weak_on_added(cb)` | Weak variant of `on_added`. |
| `weak_on_updated(cb)` | Weak variant of `on_updated`. |
| `weak_on_removed(cb)` | Weak variant of `on_removed`. |
| `all()` | Return a snapshot array of all current items. |
| `get(id)` | Return the item with the given `id`, or `nil`. |

```lua
local audio = require("continuity.audio")

-- Enumerate existing inputs, then track additions and removals.
for _, input in ipairs(audio.inputs:all()) do
    print("Input:", input.state.name)
end

audio.inputs:on_added(function(input)
    print("Added:", input.state.name)
end)

audio.inputs:on_removed(function(id)
    print("Removed:", id)
end)
```

### Transformations

Observables support functional transformations that return a new Observable
derived from the original. The derived observable stays in sync automatically.

| Method | Description |
|---|---|
| `map(fn)` | Map each item through `fn`, returning a new Observable of the results. Plain tables `{ id, state }` are automatically wrapped with `Subscribable` and `Removable`. |
| `flatmap(fn)` | Map each item to a list via `fn` and flatten into a new Observable. Plain tables `{ id, state }` are automatically wrapped with `Subscribable` and `Removable`. |
| `filter(predicate)` | Return a new Observable containing only items for which `predicate` returns true. |
| `group_by(fn)` | Return an Observable of `Group` handles keyed by `fn(item)`. |
| `unique(fn, strategy?)` | Deduplicate items by `fn(item)`; `strategy` controls which duplicate wins (`"first"`, `"last"`, `"recent"`). |

**`unique` strategies:** when multiple items share the same key, the strategy
controls which one is the representative:

| Strategy | Description |
|---|---|
| `"first"` (default) | The first item added for a key is the representative. New arrivals with the same key are tracked but do not update the output until the current representative is removed. |
| `"last"` | The most recently added item for a key is the representative. Adding a new item with the same key immediately updates the output to the newcomer. |
| `"recent"` | Like `"last"`, but updates to any item in the group also promote that item to representative and fire an update. |

`map` and `flatmap` check whether the returned value already implements `Removable`. If it does not, they automatically apply the `Subscribable + Removable` mixin, so mapper functions can return plain tables and get a fully functional Observable item without any manual setup.

```lua
local media = require("continuity.media")

-- Only sources that are actively playing.
local playing = media.sources:filter(function(source)
    return source.state.status == "playing"
end)

playing:on_added(function(source)
    print("Now playing:", source.state.title)
end)
```

### Removable

Removable is a mixin that items inside an Observable expose. It allows
subscribing to the event that fires when that specific item is removed from
its collection, without needing to filter `Observable:on_removed` by id.

| Method | Description |
|---|---|
| `on_removed(cb)` | Fires once when this item is removed. Returns an unsub function. |
| `weak_on_removed(cb)` | Same as `on_removed` with a weak reference to the callback. |

```lua
audio.inputs:on_added(function(input)
    print("Input added")
    -- Fires once when this specific input disappears.
    input:on_removed(function()
        print("Input removed")
    end)
end)
```

## Controllable

Controllable is a mixin that handles expose to drive transient displays such as
OSD notifications. Where `subscribe` fires whenever state changes for any
reason, `on_control` fires only when a control action was taken, such as after
`set_perc`, `toggle_mute`, or `set_port` on an audio handle. A volume OSD
that should appear only when the user actively changes the volume can use
`on_control` instead of `subscribe`.

| Method | Description |
|---|---|
| `on_control(cb, opts?)` | Register a callback fired after a control action on this handle. Returns an unsub function. |
| `weak_on_control(cb, opts?)` | Same as `on_control` with a weak reference to the callback. |

`opts.debounce` (seconds) coalesces rapid control actions: the callback fires once after the
given duration with no further actions. Useful for rate-limiting OSD redraws when controls
are invoked in quick succession.

```lua
local naughty = require("naughty")
local audio = require("continuity.audio")

-- Show an OSD whenever the user adjusts the volume, not on every state change.
audio.Volume:on_control(function(state)
    naughty.notification({
        message = string.format("Volume: %d%%", state.level),
    })
end)
```

## Scope

Scope is a utility class for grouping subscriptions and AwesomeWM signal
connections so they can be disposed together. A Scope is callable: calling it
with an unsub function registers that function for cleanup. Scope holds strong
references to all registered unsub functions, but auto-disposes via `__gc`
(or `newproxy`) when the Scope itself is garbage collected.

| Method | Description |
|---|---|
| `Scope()` | Create a new Scope. |
| `scope(unsub)` | Register an unsub function for cleanup on dispose. |
| `connect_signal(source, signal, cb)` | Connect an AwesomeWM signal and register the disconnection for cleanup. |
| `weak_connect_signal(source, signal, cb)` | Same as `connect_signal` using a weak signal connection. |
| `dispose()` | Fire all registered unsub functions and clear the scope. |

```lua
local Scope = require("continuity.util.scope")
local audio = require("continuity.audio")

local scope = Scope()

-- Register subscriptions through the scope.
scope(audio.Volume:subscribe(function(state)
    print("Volume:", state.level)
end))

scope(audio.inputs:on_added(function(input)
    print("Input added:", input.state.name)
end))

-- Clean up all subscriptions at once.
scope:dispose()
```

Because Scope auto-disposes when collected, subscriptions can be tied to the
lifetime of an AwesomeWM object by storing the Scope on that object. When the
object is collected the Scope is collected with it, cleaning up all
subscriptions automatically with no explicit `dispose` call required.

```lua
local function make_volume_popup()
    local widget = wibox.widget.textbox()
    local scope  = Scope()
    local popup  = awful.popup { widget = widget, ... }

    scope(audio.Volume:subscribe(function(state)
        popup.widget:set_markup(tostring(state.level))
    end))

    -- Anchor the scope to the popup so it lives exactly as long as the popup.
    -- Without this, scope would be eligible for collection immediately after
    -- make_volume_popup returns, disposing the subscriptions too early.
    popup._scope = scope

    return popup
end
```

## Weak Subscriptions

Every `weak_subscribe`, `weak_on_added`, `weak_on_removed`, etc. works the same
way: the callback is stored as a key in a weak table (`__mode = "k"`), so it
can be collected if nothing else holds a reference to it. The returned unsub
function captures the callback in its closure, creating its own strong
reference.

This means a weak subscription stays alive as long as **either** the unsub
function or the callback itself is strongly held. Only when both are released
can the callback be collected and the subscription silently dropped.

```lua
local cb = function(state) print(state.level) end

-- Both of these keep the subscription alive:
local unsub = audio.Volume:weak_subscribe(cb)  -- unsub holds cb via closure
cb = nil        -- dropping cb; unsub still holds it
unsub = nil     -- now both are gone; subscription is eligible for collection
```

This differs from AwesomeWM's `weak_connect_signal`, which also auto-disconnects
when the callback is collected but does not return an unsub function, explicit
cleanup requires calling `disconnect_signal` by name. Continuity always returns
an unsub, so explicit and automatic cleanup coexist naturally.

The idiomatic pattern is to store the unsub on the owning object. Because the
unsub holds the callback strongly, the subscription stays alive as long as the
object does. When the object is collected the unsub is released, the callback
becomes unreachable, and the weak subscription is silently dropped, no
explicit teardown required. Storing the unsub also enables an idempotent
`stop`/`start` lifecycle when needed:

```lua
function MyInstance.new()
    return {
        start = function(self)
            if self._unsub then return end
            -- self._unsub holds the callback strongly via closure,
            -- keeping the subscription alive as long as self is alive.
            -- Use Scope to bundle multiple subscriptions the same way.
            self._unsub = audio.Volume:weak_subscribe(function(state) ... end)
        end,
        stop = function(self)
            if not self._unsub then return end
            self._unsub()
            self._unsub = nil
        end,
    }
end
```

When no explicit start/stop is needed, storing the unsub directly allows
anonymous callbacks, something `weak_connect_signal` cannot do since it
requires a strong reference to the callback to be kept alive.

```lua
-- Continuity: anonymous callback, subscription lifetime tied to the object.
local instance = {
    _unsub = audio.Volume:weak_subscribe(function(state) ... end)
}
```

The equivalent AwesomeWM pattern requires keeping a strong reference to the
callback to prevent it from being garbage collected:

```lua
-- Also works in Continuity:
local cb = function(state) ... end
audio.Volume:weak_subscribe("property::state", cb)
local instance = {
    _cb = cb
}
```
