# Changelog

## v0.2.1

### Changes

**Backlight:** `backlight.devices` gains `on_updated`

Backlight `devices` no fully complies with the `Observable` contract with the
addition of `on_updated`.

**Audio:** Simplified Pulse default sink/source change detection

A new `DeviceHandle:patch(id, partial)` API merges partial field updates,
fires subscribers and `on_updated` if changed, and returns the updated state
and meta by reference. The Pulse backend now handles server events with
`get-default-X` instead of a list, and `set_default` performs an optimistic
handle patch before the confirmation callback arrives, working around
inconsistent `pactl` subscribe event emission for default changes.

**Shared generic type hierarchy**

A new `lua/continuity/types.lua` module defines the primary API contracts as
generic EmmyLua types: `Subscribable<T>`, `Monitor<T>`, `ReadyAware<T>`,
`Controllable<T>`, and `Observable<T>`. Annotations across Audio, Backlight,
Media, and Sysinfo modules have been updated to reference these types.

### Bug Fixes

- **Audio:** `Audio.Volume` / `Audio.Capture` now immediately dispatch
  `on_ready` when subscribed after initialization rather causing an error.
- **Audio:** Pre built handles `Volume` and `Capture` now correctly bind to
  the current default sink/source represented by `audio.sinks` and
  `audio.sources`. Control actions and updates to the current default now
  correctly trigger subscriptions on both handles.
- **Audio:** control actions now fires `on_updated` callbacks consistently
  alongside subscribe callbacks for control actions as well as external
  poll/subscribe events.
- **Audio:** Pulse default sink/source change detection now works regardless
  of whether sink/source change events are emitted for the effected devices.

### Breaking Changes

*(none)*

## v0.2.0

### Changes

**Audio: Full sink and source enumeration (Pulse)**

`audio.sinks` and `audio.sources` are now pre-instantiated lifecycle
collections, mirroring the existing `audio.inputs` API. The Pulse backend
enumerates all sinks and sources at startup and dispatches add/update/remove
events as devices appear and disappear. ALSA registers its pseudo-devices to
satisfy the same contract.

New API surface:
- `audio.sinks` / `audio.sources`: `DeviceCollection` with the same lifecycle
  callbacks as `audio.inputs`
- `AudioHandle.name`: the backend identifier string (e.g. `alsa_output.pci-...`)
- `AudioHandle.description`: human-readable label from pactl
- `AudioHandle.state.is_default`: whether the device is the current system
  default
- `AudioHandle:set_default()`: promote the device to default sink or source
- `SinkInputHandle:move_to(sink_id)`: route a sink input to a different sink
- `SinkInputHandle.app_icon`: resolved at discovery time; consumers do not
  need to handle async icon lookup
- `audio.Volume.id` / `audio.Capture.id` now reflect the real numeric pactl
  index of the current default device rather than the `@DEFAULT_SINK@` /
  `@DEFAULT_SOURCE@` sentinel strings

**MPRIS: Streaming delta updates**

The MPRIS backend now streams `PropertiesChanged` D-Bus signals directly via
`dbus-monitor` instead of issuing a full `GetAll` poll on each event. Only
changed properties are dispatched; the registry applies partial updates. This
correctly handles players (e.g. Chromium) that omit the track ID field by
treating it as an empty string, and media notifications are now dismissed when
a source transitions to the inactive state.

**Media `source:subscribe` debounce option**

`source:subscribe` accepts a `debounce` option (milliseconds) to coalesce
rapid-fire updates before delivering them to the callback.

**Battery: Computed time fields in `BatState`**

`time_remaining` and `time_until_full` are now first-class fields on
`BatState`, calculated at update time alongside the other state fields. The
previous top-level accessor functions remain available and delegate to state.

### Performance

**MPRIS: dbus-monitor filter narrowed to MPRIS Player signals**

The `dbus-monitor` process for the MPRIS backend now filters to MPRIS Player
interface signals only. Previously the monitor received all session bus traffic
and discarded unrelated messages in Lua. Narrowing at the D-Bus level
eliminates that overhead entirely, only `org.mpris.MediaPlayer2.Player`
`PropertiesChanged` signals reach the handler.

**Net: Process-based `/proc` polling**

The `ipmonitor` backend replaces its `gears.timer` + `easy_async` polling loop
with a single `Process` running in interval mode against `/proc/net/dev` and
`/proc/net/wireless`. Callbacks per device dropped by approximately 80%, one
line per device per tick instead of one line per field.

**Audio: Optional C-extension JSON parsing**

The Pulse backend selects a JSON parser at load time. When the `lua-json` C
extension is present it is used for pactl output; otherwise the pure-Lua
fallback is used. A new `continuity.util.json` module encapsulates the
selection and exposes `is_c_extension` for introspection. See the README for
the optional `lua-json` installation step.

### Bug Fixes

*(none)*

### Breaking Changes

*(none)*
