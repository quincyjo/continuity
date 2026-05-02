# backlight

The backlight module monitors and controls display and keyboard brightness via a
pluggable backend. Control methods deliver results directly via a callback,
keeping `on_control` and `subscribe` semantically separate.

Three backends are provided:

| Backend | Mechanism | Step control |
|---|---|---|
| `sysfs` (default) | `/sys/class/backlight/` | Yes |
| `acpilight` | `xbacklight -ctrl` (multi-device) | Yes |
| `xbacklight` | `xbacklight` (single device) | No |

## Setup

Call `setup` once in `rc.lua`. It starts the backend and begins device discovery.

```lua
local backlight = require("continuity.backlight")
backlight.setup()
```

To use a specific backend:

```lua
backlight.setup({
    backend = require("continuity.backlight.backends.acpilight") {
        time = 100,
        fps = 30,
    },
})
```

## Handles

### `backlight.primary_display`

A pre-created handle wired to the first display device discovered. Available
immediately after `require` — before `setup` is called. Use `on_ready` if you
need to read state before the first discovery poll completes.

### `backlight.devices`

Lifecycle table for all discovered devices (displays and keyboards). See
[Device Lifecycle](#device-lifecycle).

## Handle Fields

| Field | Type | Description |
|---|---|---|
| `id` | `string?` | Device id, e.g. `"intel_backlight"`. `nil` until wired. |
| `kind` | `BacklightKind` | `"display"` or `"keyboard"` |
| `state` | `BacklightState` | Current mutable state — see below |
| `steps` | `integer?` | Total step count; `nil` for backends without step control |

### `BacklightState` fields

| Field | Type | Description |
|---|---|---|
| `brightness` | `number` | Current brightness 0–100 |
| `raw` | `integer?` | Raw brightness value; `nil` for backends without raw values |

```lua
local b = backlight.primary_display.state.brightness
```

## Handle Callbacks

All callbacks receive a `BacklightState` (`{ brightness, raw }`).

### `on_ready`

Fires once when the device's first state is known, or immediately if already
initialized. Use this to seed UI state on startup.

```lua
backlight.primary_display:on_ready(function(state)
    print("initial:", state.brightness, state.raw)
end)
```

### `subscribe`

Fires when a material change is observed, regardless of whether the change
originated from the module or another application. Does not fire on initial
discovery or changes that result in no change, e.g. brightness is at 100% and
`adjust(1)` is called.

```lua
local unsub = backlight.primary_display:subscribe(function(state)
    print("brightness changed:", state.brightness)
end)
unsub()  -- stop receiving updates
```

### `on_control`

Fires on every control call (`set_perc`, `adjust_perc`, `set`, `adjust`)
regardless of whether the resulting value changed. Use this for transient UI —
a brightness popup that should appear on every keypress even when already at
maximum.

```lua
backlight.primary_display:on_control(function(state)
    show_brightness_popup(state.brightness)
end)
```

Returns an unsubscribe function.

`subscribe` and `on_control` serve different roles: `subscribe` is for persistent
state observers (widgets), `on_control` is for ephemeral feedback (popups).

## Control Methods

All control methods are asynchronous and fire `on_control` callbacks on success.

```lua
local d = backlight.primary_display

d:set_perc(75)      -- set brightness to 75%
d:adjust_perc(10)   -- increase by 10%
d:adjust_perc(-10)  -- decrease by 10%

-- Step-based control (sysfs and acpilight backends only):
d:set(10)           -- set to raw step 10
d:adjust(2)         -- increase by 2 raw steps
d:adjust(-2)        -- decrease by 2 raw steps
```

`set` and `adjust` are no-ops if the backend does not support step control.

## Device Lifecycle

`backlight.devices` mirrors the `media.sources` and `audio.inputs` lifecycle
table pattern.

```lua
local unsub = backlight.devices.on_added(function(handle)
    print("device added:", handle.id, handle.kind)
end)
unsub()

backlight.devices.on_removed(function(id)
    print("device removed:", id)
end)

-- All currently known handles (displays and keyboards):
local all = backlight.devices.all()

-- Filter by kind if needed:
for _, h in ipairs(backlight.devices.all()) do
    if h.kind == "display" then
        print(h.id, h.state.brightness)
    end
end
```

## Wibox Widget

A minimal textbox widget showing current brightness.

```lua
local backlight = require("continuity.backlight")
local wibox     = require("wibox")

local brightness_widget = wibox.widget({
    text   = "🔆 …",
    widget = wibox.widget.textbox,
})

local function on_update(state)
    brightness_widget:set_markup(string.format("🔆 %3d%%", state.brightness))
end

backlight.primary_display:on_ready(on_update)
backlight.primary_display:subscribe(on_update)
```

## Permissions

All three backends ultimately write to `/sys/class/backlight/*/brightness`. If
the file is not writable by your user, control calls will silently do nothing —
the sysfs backend logs a warning in this case, but acpilight and xbacklight may
not.

**Verify the backend works from the CLI before debugging the module.** If the
CLI command fails, the module will too.

### sysfs

```sh
# Read current brightness
cat /sys/class/backlight/intel_backlight/brightness

# Write (replace intel_backlight with your device name)
echo 100 | sudo tee /sys/class/backlight/intel_backlight/brightness
```

If the write requires `sudo`, add your user to the `video` group:

```sh
sudo usermod -aG video $USER
```

Then log out and back in. Alternatively, add a udev rule to set the group and
permissions on the brightness file:

```
# /etc/udev/rules.d/90-backlight.rules
ACTION=="add", SUBSYSTEM=="backlight", RUN+="/bin/chgrp video /sys/class/backlight/%k/brightness"
ACTION=="add", SUBSYSTEM=="backlight", RUN+="/bin/chmod g+w /sys/class/backlight/%k/brightness"
```

### acpilight

acpilight uses `xbacklight -ctrl` and inherits the same sysfs permission
requirement. Verify with:

```sh
xbacklight -get -ctrl intel_backlight
xbacklight -set 50 -ctrl intel_backlight
```

### xbacklight

xbacklight uses the RandR backlight property. Verify with:

```sh
xbacklight -get
xbacklight -set 50
```

If `xbacklight -get` returns nothing or errors, your display driver may not
expose a backlight property over RandR. In that case, use the sysfs or
acpilight backend instead.

## Keybindings

```lua
local backlight = require("continuity.backlight")
local awful     = require("awful")

awful.keyboard.append_global_keybindings({
    awful.key({}, "XF86MonBrightnessUp",   function() backlight.primary_display:adjust_perc(10)  end),
    awful.key({}, "XF86MonBrightnessDown", function() backlight.primary_display:adjust_perc(-10) end),
})
```
