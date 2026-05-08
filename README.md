# continuity

An event-driven and performance oriented library to power your AwesomeWM
configuration.

Includes system monitoring, media integration, audio and backlight control,
client switching, and async CLI tool wrappers. Modules use a declarative
configuration setup and provide lifecycle subscription callbacks to keep
consumers up to date.

This is a backend library that provides an event driven interface for building
your own UIs. Check out the docs for each module for some examples.

## Contents

- [Principles](#principles)
- [Compatibility](#compatibility)
- [Installation](#installation)
- [Conventions](#conventions)
- [Brass Tacks](#brass-tacks)
- [sysinfo](#sysinfo)
  - [bat](#bat--battery)
  - [cpu](#cpu--cpu)
  - [mem](#mem--memory)
  - [net](#net--network)
  - [temp](#temp--temperature)
- [media](#media)
- [audio](#audio)
- [backlight](#backlight)
- [alttab](#alttab)
- [tools](#tools)
  - [find](#find)
  - [grep](#grep)
- [Contributing](#contributing)
- [Notes](#notes)

## Principles

- **Event Driven**: Asynchronous, push-based updates, no polling for
  consumers. This carries all the way down to the underlying CLI commands
  wherever possible.
- **Performance Oriented**: Built to be fast and efficient, minimizing
  interruptions to the glib loop and focused lifecycle callbacks allowing
  targeted updates.
- **Consistent**: Modules share a uniform interface across their categories;
  streamed data (sysinfo), control oriented (audio), and transient resources
  (media).
- **Pluggable**: Every module can be given a target backend at `setup` time.
  Want to use a different backend than is provided? Implement the backend
  and provide it to the module, or open a PR to add it to the library.
- **Non-Prescriptive**: No pre-defined widgets or UI. Built to drive your UI
  with a consistent, intuitive, and a functionally pure interface.

## Compatibility

This library **is built for**:
- AwesomeWM 4.3 and later (git master).
- Lua 5.3 and LuaJIT 2.1.

This library **should** work with:
- Lua 5.1+.

This library does **not** support:
- AwesomeWM 4.2 and earlier, but your mileage may vary.

The unit test matrix is lua5.3 and luajit2.1. My personal runtime is luajit2.1
and awesome git master.

If you encounter any issues with lua5.1+/luajit2.1 and awesome 4.3+, please
open an issue. There is currently no plan to support environments outside of
that matrix.

## Installation

**Via LuaRocks:**

```bash
luarocks install continuity
```

Then add the LuaRocks loader at the top of your `rc.lua`:

```lua
require("luarocks.loader")
```

> Optional: Install [lua-json](https://github.com/neoxic/lua-json) C extension.
> to enable faster parsing where applicable (currently in Pulse audio backend).
>
> ```sh
> luarocks install lua-json
> ```

**Via git:**

```bash
git clone https://github.com/quincyjo/continuity.git
ln -s continuity/lua/continuity ~/.config/awesome/continuity
```

## Conventions

**Streamed modules** (`bat`, `cpu`, `mem`, `net`, `temp`) provide a uniform interface:

```lua
module.setup(opts)              -- call once in rc.lua; opts.backend overrides default
local unsub = module:subscribe( -- push-based updates; fires immediately if state is known
  function(state) ... end
)
unsub()                         -- stop receiving updates
module.state                    -- last-known state (may be nil)
module.stop()                   -- tear down backend and clear subscribers
```

**Control modules** (`audio`, `backlight`) provide a uniform interface:

```lua
audio.Volume.state                      -- last-known state (may be placeholder values)
audio.Volume:on_ready(                  -- fires exactly once when state is first known or immediately.
  function(state) ... end
)
local unsub1 = audio.Volume:subscribe(  -- push-based updates; only fires when state changes
  function(state) ... end
)
local unsub2 = audio.Volume:on_control( -- fires on every control call, regardless of state change
  function(state) ... end
)
unsub1()                                -- stop receiving updates
unsub2()
audio.Volume:adjust_perc(-5)            -- relative
audio.Volume:set_perc(50)               -- absolute
audio.Volume:toggle_mute()
```

**Transient resources** (`media.sources`, `audio.inputs`) provide a uniform interface:

```lua
media.sources.all()                     -- snapshot of all sources
media.sources.on_added(                 -- fires when a new source is added
    function(source) ... end
)
media.sources.on_updated(               -- fires when a source is updated
    function(source) ... end
)
media.sources.on_removed(               -- fires when a source is removed
    function(id) ... end
)
```

## Brass Tacks

In reality, what modules are truly event based all the way down? For the ones
that are not, how are they still "performance-oriented"?

- **100% Event Driven**: Push-based throughout the entire stack.
  - ✅ Audio: Both backends via `amixer sevents` or `pactl subscribe`.
  - ✅ Media: Both backends via `dbus-monitor` and/or `nc`.
- **Mix**: Mix of event driven and polling.
  - 〽️ bat: `udevadm monitor`, but has a 30s optional (but default)
    poll for better out-of-the-box functionality on systems that may
    not emit events regularly or for certain changes in state.
- **Polling by Definition**: Inherently polling vis a vis sampling.
  - ⌛ net: `ip monitor` to detect device changes, polls stats.
  - ⌛ cpu: By definition.
  - ⌛ mem: By definition.
  - ⌛ temp: By definition.
- **Polling and Feels Bad**: It makes me sad.
  - ❌ backlight: Polls to detect out of band changes, but is cheap.
    Changes via the control API are still immediately observed by
    consumers.

**How polling is optimized when it is done:**

This ultimately comes down to minimizing how often lua code is doing anything,
and more generally, how often the glib loop has to invoke the lua engine.

- Polling processes use a long-lived single `awful.spawn` via a shell
  `while true sleep` loop.
  - This avoids extra `gears.timer` and `awful.spawn` overhead and runs
    completely outside of the glib loop with zero lua handoffs to manage.
  - This uses the kernal to remove the process from the CPU scheduling pool
    during downtime, which is as optimized as it gets.
- Use of a `grep` pipe to filter lines of `stdout` that are not actionable.
  - Not only is `grep` much faster than lua matching, but...
  - Every line of `stdout` (and `stderr`) that a `spawn` emits requires a lua
    handoff. By filtering down to only lines that are acted on, no-op handoffs
    are eliminated. This optimization is done universally, not just in polling
    processes.

---

## sysinfo

The `sysinfo` module provides system-level information, such as battery status,
CPU usage, and network rates. Subscribers receive updates regularly via push-based
callbacks, and new subscribers are notified immediately if the state is already
known.

### bat — Battery

Monitors battery charge, status, and power draw across all batteries via `udevadm`.
Maintains an EMA-smoothed power average for time-remaining estimates.

```lua
local bat = require("continuity.sysinfo.bat")
bat.setup()
bat:subscribe(function(state)
    -- state.perc, state.status ("Charging"|"Discharging")
    -- state.power_now (watts)
    -- state.ac_online, state.batteries (per-battery breakdown)
    -- EMA smoothed:
    state.power_average
    state.time_remaining  -- nil unless discharging
    state.time_until_full -- nil unless charging
end)
```

[Full documentation](docs/sysinfo/bat.md)

---

### cpu — CPU

Reads `/proc/stat` on a timer and reports aggregate and per-core usage.

```lua
local cpu = require("continuity.sysinfo.cpu")
cpu.setup()
cpu:subscribe(function(state)
    -- state.usage  (aggregate %)
    -- state.cores[n].usage, .user, .system, .idle, .iowait, .steal
end)
```

[Full documentation](docs/sysinfo/cpu.md)

---

### mem — Memory

Parses `/proc/meminfo` and reports RAM and swap usage.

```lua
local mem = require("continuity.sysinfo.mem")
mem.setup()
mem:subscribe(function(state)
    -- state.total, state.used, state.free (MiB)
    -- state.perc  (used / total * 100)
    -- state.swap_total, state.swap_used, state.swap_free (MiB)
end)
```

[Full documentation](docs/sysinfo/mem.md)

---

### net — Network

Tracks per-interface TX/RX rates, link state, and WiFi signal strength.

```lua
local net = require("continuity.sysinfo.net")
net.setup()
net:subscribe(function(state)
    -- state.tx_rate, state.rx_rate  (aggregate bytes/s)
    -- state.devices["eth0"].tx_rate, .rx_rate, .state, .carrier, .wifi, .signal
end)
```

[Full documentation](docs/sysinfo/net.md)

---

### temp — Temperature

Reads thermal zone temperatures from sysfs.

```lua
local temp = require("continuity.sysinfo.temp")
temp.setup()
temp:subscribe(function(state)
    -- state.avg                  (mean °C across all zones)
    -- state.zones["/sys/..."]    (°C per zone path)
end)
```

[Full documentation](docs/sysinfo/temp.md)

---

## media

Aggregates playback state from one or more backends (MPD, MPRIS) into
individual observable and controllable playback sources. Provides configurable
notifications, remote art resolution, and playback control.

While the default configuration will work for the majority of cases out of the
box, this module is by the far the most complex and supports a wide range of
customization. Refer to the [full documentation](docs/media.md) for more
information.

```lua
local media  = require("continuity.media")
local mpd    = require("continuity.media.backends.mpd")
local mpris  = require("continuity.media.backends.mpris")

media.setup({
    -- backends = { mpris(), mpd { host = "localhost", port = 6600 } }, -- Configure backends. Default is MPRIS only.
    -- notifications = false  -- disable OSD notifications
    -- notifications = { ... }  -- configure and provide a custom notification handler.
})

-- Each returns an unsub function if used in a temporary context, such as a popup or notification.
media.sources.on_added(function(source) ... end)
-- Updates *should* only be fired when something has changed, but exact behaviour depends
-- on the specific backend and upstream application.
media.sources.on_updated(function(source)
    -- source.state.title, .artist, .album, .art_path
    -- source.playback.play_pause(), .next(), .previous(), .stop()
end)
media.sources.on_removed(function(source_id) ... end)

media.play_pause() -- play/pause most-recent source
media.next()       -- skip forward
media.previous()   -- skip backward
```

[Full documentation](docs/media.md)

---

## audio

Tracks volume and mute state for the default output (sink) and input (source)
devices via push-based event subscription. Out-of-band changes (hardware keys,
other applications) are detected immediately via `pactl subscribe` or
`amixer sevents`. The PulseAudio/PipeWire backend is the default; an ALSA
backend is also provided.

Two pre-created handles, `Audio.Volume` (sink) and `Audio.Capture` (source), are
available after `setup`. Subscribers receive a full `AudioState` on each change,
including port type (speaker, headphones, headset, …) and connection type (analog,
bluetooth, …) when the backend can derive them.

In addition to the default handles, all sinks and sources (devices) as well as
sink-inputs (applications) are available via `audio.sinks`, `audio.sources`, and
`audio.inputs`, respectively, allowing device selection, individual device
control, and stream control and piping. See the [full documentation](docs/audio.md)
for more information.

```lua
local audio = require("continuity.audio")
audio.setup()

local volume  = audio.Volume   -- default sink
local capture = audio.Capture  -- default source

-- Current readable state. May be (0, false) if not yet known, i.e., before
-- the first backend event has been received.
local current_level, current_muted = volume.state.level, volume.state.muted

-- Alternatively, seed initial state with on_ready:
-- Fires exactly once when state is first known, or immediately if already known.
-- Any on_ready hooks are guaranteed to run before any subscribe hooks registered
-- during the same execution cycle.
volume:on_ready(function(state)
    -- Concrete known values.
    current_level, current_muted = state.level, state.muted
end)

-- Fires whenever a material change is observed (out-of-band or from a control call).
volume:subscribe(function(state)
    require("naughty").notify {
        title   = "Volume",
        message = state.muted and "Muted" or string.format("%d%%", state.level),
    }
end)

-- Fires on every control call, regardless of whether the value changed.
-- Use this for immediate UI feedback (e.g. a transient popup).
volume:on_control(function(state)
    show_volume_popup(state)
end)

-- Subscribers are informed immediately:
volume:adjust_perc(5)    -- +5% (also unmutes on PulseAudio backend)
volume:adjust_perc(-5)   -- -5%
volume:set_perc(50)      -- absolute
volume:toggle_mute()

-- Switch to the ALSA backend:
audio.setup({ backend = require("continuity.audio.backends.alsa")() })
```

[Full documentation](docs/audio.md)

---

## backlight

Controls and monitors display (and keyboard) brightness via sysfs, acpilight, or
xbacklight. A `primary_display` handle is pre-created and wired to the first
discovered display device. `on_control` fires on every control call for transient
UI feedback; `subscribe` fires only on out-of-band changes.

```lua
local backlight = require("continuity.backlight")
backlight.setup({
    -- backend = require("continuity.backlight.backends.acpilight")(), -- default: sysfs
})

-- Current readable state. May be 0 until first discovery poll completes.
local current = backlight.primary_display.state.brightness

-- Fires once when state is first known or immediately if already known.
backlight.primary_display:on_ready(function(state)
    current = state.brightness
end)

-- Fires on every change (e.g. control API, hardware key, another application).
backlight.primary_display:subscribe(function(state)
    print("brightness changed:", state.brightness)
end)

-- Fires on every control call, even when value is unchanged.
-- Use this for transient UI such as a popup.
backlight.primary_display:on_control(function(state)
    show_brightness_popup(state.brightness)
end)

backlight.primary_display:adjust_perc(10)   -- +10%
backlight.primary_display:adjust_perc(-10)  -- -10%
backlight.primary_display:set_perc(75)      -- absolute

-- Step-based control (sysfs and acpilight backends):
backlight.primary_display:adjust(2)         -- +2 raw steps
backlight.primary_display:adjust(-2)        -- -2 raw steps
backlight.primary_display:set(10)           -- absolute raw step
```

[Full documentation](docs/backlight.md)

---

## alttab

A keyboard-driven client switcher that maintains a focus-ordered stack and hands
off to a `keygrabber` during an active switch session. The UI is provided by the
caller via an `AlttabUI` callback table; a notification-based fallback is used if
none is supplied.

All keybinds require `held_key` (default "Mod1") to be held. Releasing the held key
focuses the selected client's screen, switches to that client's tag, and focuses
and raises the client. Using the `pull_key` also closes the session.

- `select_key` to select next client
- `mod_key + select_key` to select previous client
- `pull_key` close the session and moves the selected client to the current
  screen and current primary tag
- `mod_key + pull_key` close the session and moves the selected client to the current
  screen and appends the current primary tag without removing other tags.
- `1,2,...9` moves the selected client to the corresponding tag
- `mod_key + 1,2,...9` Toggles the corresponding tag on the selected client
- `escape` close the session without doing anything

```lua
local alttab = require("continuity.alttab")

alttab.setup({
    ui = my_ui,          -- AlttabUI implementation (optional)
    held_key  = "Mod1",  -- key held while switcher is open (default: "Mod1" eg alt)
    select_key = "Tab",  -- key to cycle through clients     (default: "Tab")
	mod_key = "Shift",   -- key to modify actions, eg index -1 (default "Shift")
	pull_key = "Space",  -- key to pull selected client to current screen and tag (default: "Space")
	number_shift_mappings = { ... }, -- If you don't use QWERTY, tell the keygrabber what the shift values for numbers keys are, 1-9.
})

-- Bind in rc.lua globalkeys:
awful.key({ "Mod1" },         "Tab", function() alttab.switch(1)  end)
awful.key({ "Mod1", "Shift"}, "Tab", function() alttab.switch(-1) end)
```

[Full documentation](docs/alttab.md)

---

## tools

Async wrappers around system CLI tools. Backend is selected at load time from
whatever is available on `PATH` (prefers the faster/richer option).

### find

Wraps `fd` (preferred) or `find`. Accepts a pattern string or an options table.

```lua
local find = require("continuity.tools.find")

-- Collect all results then call cb once:
find("config", function(results, exit_code)
    for _, path in ipairs(results) do ... end
end)

-- Stream results in batches as they arrive, batched per glib loop:
find.stream({ pattern = "continuity", type = "file", extension = "lua", path = "~/.config" }, function(batch, exit_code)
    -- Batch is nil once the stream is closed.
    if batch then
        for _, path in ipairs(batch) do ... end
    end
end)
```

[Full documentation](docs/tools/find.md)

---

### grep

Wraps `rg` (preferred) or `grep`. Results are structured `{ filepath, line_number, text }`.

```lua
local grep = require("continuity.tools.grep")

grep({ "setup", "~/.config/awesome" }, function(results, exit_code)
    for _, r in ipairs(results) do
        print(string.format("%s:%d: %s", r.filepath, r.line_number, r.text))
    end
end)

-- Streaming variant:
grep.stream({ pattern = "todo", path = "~", case_insensitive = true }, function(batch, exit_code)
    -- Batch is nil once the stream is closed.
    if batch then
        for _, path in ipairs(batch) do ... end
    end
end)
```

[Full documentation](docs/tools/grep.md)

---

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for development setup, branching
conventions, and the local verification checklist.

## Notes

When reloading awesome, you will see Awesome warning pairs like this:

```
2026-04-23 16:23:28 W: awesome: sysinfo.bat.udevadm: Shutting down process group 1224241. A following unknown child exited with signal 15 may occur and can be ignored.
2026-04-23 16:23:28 W: awesome: sysinfo.temp.sysfs: Shutting down process group 1224246. A following unknown child exited with signal 15 may occur and can be ignored.
2026-04-23 16:23:28 W: awesome: sysinfo.cpu.procstat: Shutting down process group 1224249. A following unknown child exited with signal 15 may occur and can be ignored.
2026-04-23 16:23:28 W: awesome: sysinfo.mem.procmeminfo: Shutting down process group 1224253. A following unknown child exited with signal 15 may occur and can be ignored.
2026-04-23 16:23:28 W: awesome: sysinfo.net.ipmonitor: Shutting down process group 1224390. A following unknown child exited with signal 15 may occur and can be ignored.
2026-04-23 16:23:28 W: awesome: backlight.acpilight: Shutting down process group 1224259. A following unknown child exited with signal 15 may occur and can be ignored.
2026-04-23 16:23:28 W: awesome: media.mpris.monitor: Shutting down process group 1224338. A following unknown child exited with signal 15 may occur and can be ignored.
2026-04-23 16:23:28 W: awesome: media.mpris.lifecycle: Shutting down process group 1224339. A following unknown child exited with signal 15 may occur and can be ignored.
2026-04-23 16:23:28 W: awesome: spawn_child_exited:388: Unknown child 1224241 exited with signal 15
2026-04-23 16:23:28 W: awesome: spawn_child_exited:388: Unknown child 1224246 exited with signal 15
2026-04-23 16:23:28 W: awesome: spawn_child_exited:388: Unknown child 1224249 exited with signal 15
2026-04-23 16:23:28 W: awesome: spawn_child_exited:388: Unknown child 1224253 exited with signal 15
2026-04-23 16:23:28 W: awesome: spawn_child_exited:388: Unknown child 1224259 exited with signal 15
2026-04-23 16:23:28 W: awesome: spawn_child_exited:388: Unknown child 1224338 exited with signal 15
2026-04-23 16:23:28 W: awesome: spawn_child_exited:388: Unknown child 1224339 exited with signal 15
2026-04-23 16:23:28 W: awesome: spawn_child_exited:388: Unknown child 1224390 exited with signal 15
```

This is expected, and can be ignored. Many of the backends use long-lived
processes instead of a `gears.timer`. When Awesome reloads, the process groups
are killed, and if this happens after the reload transfers all subprocesses to
the new Awesome instance, the child exits will be reported as
`Unknown child ... exited with signal 15`. This is confirmation that the
process properly cleaned itself up, and it is not an error.

> **Note**: These will not log when existing Awesome, only when reloading.
