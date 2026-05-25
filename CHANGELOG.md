# Changelog

## v0.3.0

### Changes

**Media: Volume control**

Media sources now expose a `Playback.volume` field typed as `AudioControls`,
enabling volume control directly from the media module. Both the MPD and MPRIS
backends implement the control.

**Audio: Device port enumeration (Pulse)**

`AudioHandle.state.ports` now lists all ports for a sink or source as
`AudioPort` values (name, description, availability). A new
`AudioHandle:set_port(port)` method switches the active port by name or
`AudioPort` reference. ALSA stubs the field as an empty list.

**Observable: `map`, `flatmap`, `filter`, `group_by`, and `unique`
transformations**

Five transformation methods are now available on `Observable`:

- `map`: 1:1 id-tracked transform; re-keys (remove + add) when the mapper
  returns a different id on update.
- `flatmap`: 1:N transform with full diff on update (add new, update
  intersecting, remove dropped ids).
- `filter`: predicate pass-through that preserves source-item subscriber
  state.
- `group_by`: partitions items into keyed groups.
- `unique`: deduplicates items by a key function. Provides three strategies:
  `First` (default), `Last`, and `Recent`.

`Obsevable` now has `get(id): T|nil` API.

**Sysinfo: Temperature module rework**

`TempState` is replaced by a richer `TempDevice` / `TempSensor` model:

- `TempState.cpu` is the `TempDevice` for the auto-discovered CPU device.
- Sysfs backend reads device type labels and trip points from
  `/sys/class/thermal`.
- New `hwmon` backend reads per-chip sensors from `/sys/class/hwmon`; each
  `hwmonN` entry with `tempN_*` files becomes a device, with additional
  temperature files mapped as sensors.
- `setup()` accepts `cpu_device` (override discovery) and `exclude` (device
  blocklist).
- Default backend is now `hwmon`.

**Audio: Sink input**

`SinkInputHandle` now carries `role` (stream role), `binary` (application
executable name) metadata, and `corked` (paused/inactive flag) state.

**Lazy dot-notation exports**

The top-level `continuity` module and each sub-namespace (`continuity.sysinfo`,
`continuity.audio`, `continuity.media`, `continuity.tools`, etc.) now expose
lazy-require proxies so `continuity.sysinfo.bat` resolves without explicit
`require` calls. EmmyLua class types are registered at each namespace level for
IDE support.

**Shared metaclass extensions**

`Observable`, `Subscribable`, `Removable`, `Controllable`, `Monitor`, and
`ReadyAware` are now standalone metaclass extensions with their own `init`
lifecycle and a push-based internal API. Modules that mix multiple behaviours
compose them via `util.extend`. All collection and handle types across Audio,
Backlight, and Media have been migrated.

**Improved Lua-LS annotations**

Monitor classes use inline class definitions; stale `Awesome*` type aliases
removed; `@type` annotations on return positions dropped (ignored by lua-ls).

**Media art storage path**

Album art is now cached under `/tmp/awesome-media-art` instead of
`~/.cache/awesome/media-art`, avoiding stale-cache issues across reboots.

### Bug Fixes

- **Audio:** Fixed a race condition in the Pulse backend where a new device
  arriving as the auto-default could bleed its `state` state into the
  previous default. Default assignment is now deferred to the server-change
  event and always derived from the last server-reported default.
- **Audio:** Pre-instantiated default handles (`audio.Volume`, `audio.Capture`)
  now correctly fully share subscription events with the current default device
  via `audio.sinks` and `audio.sources` collections respectively.

### Breaking Changes

- **Observable:** Collection API methods (`on_added`, `on_updated`,
  `on_removed`, `all`) now use colon notation. Callers using dot notation must be
  updated.
- **Sysinfo/Temp:** `TempState` has a completely new structure. All consumers
  must be updated to the `TempDevice` / `TempSensor` model.
  - `state.avg` -> `state.cpu and state.cpu.temp`.
  - `state.zones` iteration -> `state.devices` reading `name` and `temp`.
- **Dependency:** `lua-json` is replaced by `lua-cjson`. If you are using the
  optional JSON dependency, install `lua-cjson` to maintain JSON support.

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
