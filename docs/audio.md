# audio

The audio module provides volume and mute observation and control for the default
output (sink) and input (source) devices. Change detection is push-based — a
long-lived subscription process (`pactl subscribe` or `amixer sevents`) delivers
events immediately rather than polling on a timer.

Two pre-created handles are exposed as module-level fields: `Audio.Volume` for
the sink and `Audio.Capture` for the source.

## Setup

Call `setup` once in `rc.lua`. It starts the backend and begins delivering events
to all registered callbacks.

```lua
require("continuity.audio").setup()
```

The default backend is PulseAudio/PipeWire (`continuity.audio.backends.pulse`).
To use ALSA instead:

```lua
require("continuity.audio").setup({
    backend = require("continuity.audio.backends.alsa")(),
})
```

## Usage

### Handles

`Audio.Volume` and `Audio.Capture` are available immediately after `require` —
before `setup` is called. Callbacks registered before `setup` will be fired once
the backend delivers its first event.

```lua
local audio   = require("continuity.audio")
local volume  = audio.Volume   -- default sink
local capture = audio.Capture  -- default source
```

### Reading State

The handle exposes a `state` table with at minimum `level` (0–100) and `muted`
(boolean). With the PulseAudio backend, `port`, `port_type`, and `connection` are
also populated when the device reports them.

```lua
print(volume.state.level, volume.state.muted)
-- port_type: "speaker"|"headphones"|"headset"|"hdmi"|nil
-- connection: "analog"|"bluetooth"|"hdmi"|"usb"|nil
print(volume.state.port_type, volume.state.connection)
```

Because the first backend event is asynchronous, `level` and `muted` are `0` /
`false` until the first event arrives. Use `on_ready` if you need concrete values
immediately on startup.

```lua
volume:on_ready(function(state)
    -- Called once with the first known state, then never again.
    print("initial:", state.level, state.muted)
end)
```

### Subscribing to Changes

`subscribe` fires only when at least one state field has changed (`level`,
`muted`, `port`, `port_type`, or `connection`). Backend events that repeat the
same state do not trigger subscribers.

```lua
volume:subscribe(function(state)
    print("volume changed:", state.level, state.muted)
end)
```

`subscribe` returns an unsubscribe function:

```lua
local unsub = volume:subscribe(function(state) ... end)
unsub()  -- stop receiving updates
```

Or call `unsubscribe` directly with the original callback:

```lua
local function on_volume(state) ... end
volume:subscribe(on_volume)
volume:unsubscribe(on_volume)
```

### Control Feedback with `on_control`

`on_control` fires on every control call (`adjust_perc`, `set_perc`,
`toggle_mute`) regardless of whether the resulting value changed. Use this for
immediate transient UI — a volume popup that should appear on every keypress even
when the level is already at 100%.

`subscribe` is for persistent state observers; `on_control` is for ephemeral
feedback.

```lua
volume:on_control(function(state)
    show_volume_popup(state)
end)
```

`on_control` also returns an unsubscribe function.

### Controlling Volume

All control methods fire asynchronously and notify `on_control` subscribers
immediately on success.

```lua
volume:adjust_perc(5)    -- +5%; also unmutes on PulseAudio backend
volume:adjust_perc(-5)   -- -5%
volume:set_perc(50)      -- absolute value, clamped to 0–100
volume:toggle_mute()     -- toggle mute state
```

`adjust_perc` clamps the delta to keep the result in [0, 100]. If the clamped
delta is 0, `on_control` is still fired with the current state.

## State Fields

| Field | Type | Description | Backends |
|---|---|---|---|
| `level` | `integer` | Volume 0–100 | all |
| `muted` | `boolean` | Mute state | all |
| `port` | `string?` | Raw active port name | PulseAudio |
| `port_type` | `string?` | `"speaker"`, `"headphones"`, `"headset"`, `"hdmi"`, `"mic"`, `"headset-mic"` | PulseAudio |
| `connection` | `string?` | `"analog"`, `"bluetooth"`, `"hdmi"`, `"usb"` | PulseAudio |

ALSA state contains only `level` and `muted`; `port`, `port_type`, and
`connection` are `nil`.

## Wibox Widget

A minimal wibox widget with an icon that reflects port type and mute state.

```lua
local audio = require("continuity.audio")

local volume_widget = wibox.widget({
    text = "🔊 …",
    widget = wibox.widget.textbox,
})

local function glyph(state)
    if state.port_type == "headphones" or state.port_type == "headset" then
        return state.muted and "🔇" or "🎧"
    end
    return state.muted and "🔇" or (state.level == 0 and "🔈" or state.level < 50 and "🔉" or "🔊")
end

local function update(state)
    volume_widget:set_markup(string.format("%s %3d%%", glyph(state), state.level))
end

audio.Volume:on_ready(update)
audio.Volume:subscribe(update)
```

## Keybindings

```lua
local audio = require("continuity.audio")
local awful = require("awful")

awful.keyboard.append_global_keybindings({
    awful.key({}, "XF86AudioRaiseVolume", function() audio.Volume:adjust_perc(5)  end),
    awful.key({}, "XF86AudioLowerVolume", function() audio.Volume:adjust_perc(-5) end),
    awful.key({}, "XF86AudioMute",        function() audio.Volume:toggle_mute()   end),
    awful.key({}, "XF86AudioMicMute",     function() audio.Capture:toggle_mute()  end),
})
```

## Inputs

`audio.inputs` provides a collection API for sink inputs — individual application
streams routed to any sink (e.g. a browser, a music player).

> **Note:** Sink inputs are only available when the PulseAudio/PipeWire backend
> is in use. The ALSA backend does not support sink input enumeration;
> `audio.inputs.all()` will always return an empty array with that backend.

### Lifecycle

```lua
local audio = require("continuity.audio")

audio.inputs.on_added(function(handle)
    print("input added:", handle.id, handle.app_name)
end)

audio.inputs.on_updated(function(handle)
    print("input updated:", handle.id, handle.state.level)
end)

audio.inputs.on_removed(function(id)
    print("input removed:", id)
end)

-- Snapshot of all currently active inputs.
local inputs = audio.inputs.all()
for _, handle in ipairs(inputs) do
    print(handle.id, handle.state.level, handle.state.muted)
end
```

All three registration functions return an unsubscribe function.

### Input Handle Fields

| Field | Type | Description |
|---|---|---|
| `id` | `string` | Sink input index (as string) |
| `app_name` | `string?` | Application name, if reported by the backend |
| `icon_name` | `string?` | Icon name, if reported by the backend |
| `state.level` | `integer` | Volume 0–100 |
| `state.muted` | `boolean` | Mute state |
| `state.name` | `string?` | Stream name |
| `state.sink` | `integer?` | Sink index this input is routed to |

### Per-Handle Subscriptions and Control

Individual input handles expose the same subscription and control API as the
module-level handles:

```lua
audio.inputs.on_added(function(handle)
    -- Subscribe to state changes for this input.
    handle:subscribe(function(state)
        print("level:", state.level, "muted:", state.muted)
    end)

    -- Fires on every control call, regardless of change.
    handle:on_control(function(state)
        show_input_popup(state)
    end)

    -- Fires when this input is removed.
    handle:on_removed(function(id)
        print("removed:", id)
    end)

    -- Control methods.
    handle:adjust_perc(5)
    handle:set_perc(80)
    handle:toggle_mute()
end)
```
