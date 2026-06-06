# audio

The audio module provides lifecycle observation and control for audio devices,
both sinks (output) and sources (input). Sink inputs (individual applications)
are supported when using the PulseAudio backend.

Change detection is push-based, a long-lived subscription process
(`pactl subscribe` or `amixer sevents`) delivers events immediately rather
than polling on a timer.

Two pre-created handles are exposed as module-level fields: `Audio.Volume` for
the default sink and `Audio.Capture` for the default source.

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

`Audio.Volume` and `Audio.Capture` are available immediately immediately with
`require`. Callbacks registered before `setup` will be fired once the
backend delivers its first event.

```lua
local audio   = require("continuity.audio")
local volume  = audio.Volume   -- default sink
local capture = audio.Capture  -- default source
```

### Reading State

The handle exposes a `state` table. See [Device Handle](#device-handle) for all
fields. With the PulseAudio backend, `port`, `port_type`, `ports`, and
`connection` are also populated when the device reports them.

```lua
print(volume.state.level, volume.state.muted)
-- port_type: "speaker"|"headphones"|"headset"|"hdmi"|nil
-- connection: "analog"|"bluetooth"|"hdmi"|"usb"|nil
print(volume.state.port_type, volume.state.connection)
-- ports: list of available ports with name, description, type, priority, availability
for _, port in ipairs(volume.state.ports or {}) do
    print(port.name, port.availability)  -- e.g. "analog-output-headphones", "not available"
end
```

Because the first backend event is asynchronous, `level` and `muted` are `0` /
`false` until the first event arrives. Use `on_ready` to seed initial state.

```lua
volume:on_ready(function(state)
    -- Called once with the first known state, then never again.
    print("initial:", state.level, state.muted)
end)
```

### Subscribing to Changes

`subscribe` fires only when at least one state field has changed (`level`,
`muted`, `port`, `port_type`, `ports`, or `connection`). Backend events that
repeat the same state do not trigger subscribers.

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

> **Note**: When using the PulseAudio backend, fields that are normally
> immutable (such as `audio.Volume.description`) will change when the default
> device changes. Because of this, `subscribe` behaviour is different from
> sources or sinks exposed via `audio.sinks` and `audio.sources` and may fire
> when with the same state if the default device is changed and the state
> matches the previous device. Consumers should update display of these fields
> when `subscribe` fires. See [Wibox widget](#wibox-widget)

### Control Feedback with `on_control`

`on_control` fires on every control call (`adjust_perc`, `set_perc`,
`toggle_mute`) regardless of whether the resulting value changed. Use this for
immediate transient UI, such as a volume popup that should appear on every
keypress even when the level is already at 100%.

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

### Switching Ports (PulseAudio)

When a device has multiple ports (e.g. speakers and headphones on a built-in
audio chip), `set_port` switches the active port by name. The state update is
optimistic — `state.port` and `state.port_type` are patched immediately on
success and `on_control` fires before the next pactl event arrives.

```lua
audio.sinks:on_added(function(handle)
    -- Inspect available ports.
    for _, port in ipairs(handle.state.ports or {}) do
        print(port.name, port.description, port.availability)
    end

    -- Switch to the first available port, passing the port object directly.
    for _, port in ipairs(handle.state.ports or {}) do
        if port.availability ~= "not available" then
            handle:set_port(port)
            break
        end
    end
end)
```

## Handle Types

### Device Handle

`Audio.Volume`, `Audio.Capture`, and every handle returned by `audio.sinks` and
`audio.sources` share the same shape:

| Field | Type | Description | Backends |
|---|---|---|---|
| `id` | `string` | Numeric device index (as string, e.g. `"57"`) | all |
| `name` | `string?` | Internal device name (e.g. `"alsa_output.pci-..."`) | all<sup>1</sup> |
| `description` | `string?` | Human-readable label (e.g. `"Built-in Audio Analog Stereo"`) | all<sup>1</sup> |
| `state.level` | `integer` | Volume 0–100 | all |
| `state.muted` | `boolean` | Mute state | all |
| `state.is_default` | `boolean` | Whether this is the current default device | all |
| `state.port` | `string?` | Raw active port name | PulseAudio |
| `state.port_type` | `string?` | `"speaker"`, `"headphones"`, `"headset"`, `"hdmi"`, `"mic"`, `"headset-mic"` | PulseAudio |
| `state.connection` | `string?` | `"analog"`, `"bluetooth"`, `"hdmi"`, `"usb"` | PulseAudio |


> <sup>1</sup> For ALSA, `name` and `description` are the same as `id`.

### Sink Input Handle

Handles returned by `audio.inputs` expose:

| Field | Type | Description |
|---|---|---|
| `id` | `string` | Sink input index (as string) |
| `app_name` | `string?` | Application name, if reported by the backend |
| `icon_name` | `string?` | Icon name, if reported by the backend |
| `role` | `string?` | Media role (e.g. `"music"`, `"notification"`, `"video"`) |
| `binary` | `string?` | Process binary name (e.g. `"spotify"`, `"Discord"`) |
| `state.level` | `integer` | Volume 0–100 |
| `state.muted` | `boolean` | Mute state |
| `state.corked` | `boolean` | Whether the stream is corked (explicitly paused by the application) |
| `state.name` | `string?` | Stream name |
| `state.sink` | `integer?` | Sink index this input is routed to |

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

A widget showing the volume and description. Note that `description` is re-read
from the handle when subscribe fires. This is only necessary when using the
Pulse backend **and** working with `audio.Volume` or `audio.Capture`
directly, not `audio.sinks` or `audio.sources`.

```lua
local volume_widget = wibox.widget {
    text = "..."
    widget = wibox.widget.textbox,
}
audio.Volume:on_ready(function(state)
    volume_widget.text = string.format(
        "%s %3d%%",
        audio.Volume.description or "Volume",
        state.level
    )
end)
audio.Volume:subscribe(function(state)
    volume_widget.text = string.format(
        "%s %3d%%",
        audio.Volume.description or "Volume",
        state.level
    )
end)
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

## Sinks

`audio.sinks` enumerates all detected output devices and tracks their lifecycle.

> **Note:** While ALSA does provide sink enumeration, there will only ever be
> the `Master` channel.

### Lifecycle

```lua
local audio = require("continuity.audio")

audio.sinks:on_added(function(handle)
    print("sink added:", handle.id, handle.description)
end)

audio.sinks:on_updated(function(handle)
    print("sink updated:", handle.id, "default:", handle.state.is_default)
end)

audio.sinks:on_removed(function(id)
    print("sink removed:", id)
end)

local sinks = audio.sinks:all()
for _, handle in ipairs(sinks) do
    print(handle.id, handle.description, handle.state.is_default)
end
```

All three registration functions return an unsubscribe function. See
[Device Handle](#device-handle) for fields.

### Per-Handle Subscriptions and Control

Individual sink handles expose the same subscription API as `Audio.Volume`:

```lua
audio.sinks:on_added(function(handle)
    handle:subscribe(function(state)
        print("sink", handle.id, "level:", state.level, "default:", state.is_default)
    end)
end)
```

### Changing the Default Sink

```lua
audio.sinks:on_added(function(handle)
    -- Make this sink the default output.
    handle:set_default()
end)
```

## Sources

`audio.sources` enumerates all detected input devices and tracks their
lifecycle.

> **Note:** While ALSA does provide source enumeration, there will only ever be
> the `Capture` channel.

### Lifecycle

```lua
local audio = require("continuity.audio")

audio.sources:on_added(function(handle)
    print("source added:", handle.id, handle.description)
end)

audio.sources:on_updated(function(handle)
    print("source updated:", handle.id, "default:", handle.state.is_default)
end)

audio.sources:on_removed(function(id)
    print("source removed:", id)
end)

local sources = audio.sources:all()
for _, handle in ipairs(sources) do
    print(handle.id, handle.description, handle.state.is_default)
end
```

All three registration functions return an unsubscribe function. See
[Device Handle](#device-handle) for fields.

### Per-Handle Subscriptions and Control

Individual source handles expose the same subscription API as `Audio.Capture`:

```lua
audio.sources:on_added(function(handle)
    handle:subscribe(function(state)
        print("source", handle.id, "level:", state.level, "default:", state.is_default)
    end)
end)
```

### Changing the Default Source

```lua
audio.sources:on_added(function(handle)
    handle:set_default()
end)
```

## Inputs

`audio.inputs` provides a collection API for sink inputs; individual application
streams routed to any sink (e.g. a browser, a music player).

> **Note:** Sink inputs are only available when the PulseAudio/PipeWire backend
> is in use. The ALSA backend does not support sink input enumeration;
> `audio.inputs:all()` will always return an empty array with that backend.

### Lifecycle

```lua
local audio = require("continuity.audio")

audio.inputs:on_added(function(handle)
    print("input added:", handle.id, handle.app_name)
end)

audio.inputs:on_updated(function(handle)
    print("input updated:", handle.id, handle.state.level)
end)

audio.inputs:on_removed(function(id)
    print("input removed:", id)
end)

-- Snapshot of all currently active inputs.
local inputs = audio.inputs:all()
for _, handle in ipairs(inputs) do
    print(handle.id, handle.state.level, handle.state.muted)
end
```

All three registration functions return an unsubscribe function. See
[Sink Input Handle](#sink-input-handle) for fields.

### Per-Handle Subscriptions and Control

Individual input handles expose the same subscription and control API as the
module-level handles except with `move_to` instead of `set_default`:

```lua
audio.inputs:on_added(function(handle)
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

    -- Route this stream to a different output device.
    local target = audio.sinks:all()[1]
    if target then
        handle:move_to(target)
    end
end)
```
