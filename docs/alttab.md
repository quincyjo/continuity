# alttab

## Keybindings

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

## Setup

This sets up client signals for `focus`, `manage`, and `unmanage` and any
signal hooks requested by the provided alttab UI.

Setup alttab module with default settings:

```lua
require("continuity.alttab").setup()
```

Below are the default options.

```lua
require("continuity.alttab").setup {
    ui = beautiful.alttab, -- AlttabUI implementation (optional)
    held_key = "Mod1",     -- key held while switcher is open (default: "Mod1" eg alt)
    select_key = "Tab",    -- key to cycle through clients     (default: "Tab")
    pull_key = "Space",    -- key to pull selected client to current screen and tag (default: "Space")
    mod_key = "Shift",     -- key to modify actions, eg index -1 (default "Shift")
    number_shift_mappings = { "!", "@", "#", "$", "%", "^", "&", "*", "(", ")" }, -- If you don't use QWERTY, tell the keygrabber what the shift values for numbers keys are, 1-9.
}
```

Since the alttab session uses a keygrabber to listen for key events, the bare
keys values via `number_shift_mappings` are needed when `mod_key` is `Shift`.
Provided keys are attempted to be normalized, `"Space"` becomes `" "` and
`"#10"` becomes `"1"`.

## UI

A custom alttab UI can be provided via the `ui` option. If none is provided, a
notification-based fallback is used.

```lua
---@class AlttabUI
---@field show             fun(clients: AwesomeClient[], index: integer)  Build and display the switcher popup.
---@field update           fun(index: integer)                            Move the highlight to a new index without rebuilding.
---@field hide             fun()                                          Tear down and hide the switcher popup.
---@field on_init?         fun(api: AlttabAPI)    Called after setup() with a reference to the public API.
---@field on_unfocus?      fun(c: AwesomeClient)  Called when a client loses focus. Good for caching content while visible.
---@field on_minimized?    fun(c: AwesomeClient)  Called when a client becomes minimized.
---@field on_untagged?     fun(c: AwesomeClient)  Called when a client is removed from a tag.
---@field on_unmanage?     fun(c: AwesomeClient)  Called when a client is removed. Useful for cache cleanup.
---@field on_tag_selected? fun(t: AwesomeTag)     Called when a client is removed. Useful for cache cleanup.

---@class AlttabAPI
---@field select        fun(index: integer)   Move the highlight to the given index without committing.
---@field close_session fun(commit?: boolean) End the session, committing (true/nil) or cancelling (false).
```

### Example UI

Below is an example UI that shows a preview of the selected client's content
and a list of all clients with mouse support.

Note that the client image capture behaviour may be compositor dependent.

```lua
local dpi = require("beautiful.xresources").apply_dpi

do
    local LIST_WIDTH = dpi(260)
    local PREVIEW_WIDTH = dpi(480)
    local PREVIEW_HEIGHT = dpi(270)
    local ITEM_HEIGHT = dpi(40)
    local ICON_SIZE = dpi(24)
    local MINI_ICON_SIZE = dpi(64)
    local PADDING = dpi(0)

    local BG_COLOR = "#252121"
    local SELECTED_BG_COLOR = "#464442"
    local SELECTED_FG_COLOR = "#89b4fa"
    local FG_COLOR = "#cdd6f4"

    ---@type table<AwesomeClient, ImageSurface>  Cached ImageSurfaces keyed by client.
    local preview_cache = {}
    ---@type AlttabAPI|nil
    local api = nil
    ---@type table<integer, AwesomeWidget>  Background containers for each list item.
    local item_bgs = {}
    ---@type AwesomeWidget|nil  Right-panel background container.
    local preview_bg = nil
    ---@type table|nil
    local popup = nil
    ---@type AwesomeClient[]|nil
    local current_clients = nil
    ---@type integer|nil
    local current_index = nil

    --- Capture a client's current content into the cache and return the image.
    --- Returns nil if the content is unavailable.
    ---@param c AwesomeClient
    ---@return ImageSurface|nil
    local function capture(c)
        if c.minimized or c.hidden then
            return nil
        end
        ---@diagnostic disable-next-line: param-type-mismatch
        local ok, surf = pcall(gears.surface, c.content)
        if not ok or not surf then
            return nil
        end
        local geom = c:geometry()
        if geom.width <= 0 or geom.height <= 0 then
            return nil
        end
        local img = cairo.ImageSurface.create(cairo.Format.ARGB32, geom.width, geom.height)
        local cr = cairo.Context.create(img)
        cr:set_source_surface(surf, 0, 0)
        cr:paint()
        preview_cache[c] = img
        return img
    end

    ---@param c AwesomeClient
    ---@param index integer
    ---@param selected boolean
    ---@return AwesomeWidget
    local function make_item(c, index, selected)
        local item = wibox.widget({
            {
                {
                    {
                        image = c.icon,
                        resize = true,
                        forced_width = ICON_SIZE,
                        forced_height = ICON_SIZE,
                        widget = wibox.widget.imagebox,
                    },
                    {
                        text = c.name or "?",
                        forced_width = LIST_WIDTH - ICON_SIZE - dpi(24),
                        ellipsize = "end",
                        widget = wibox.widget.textbox,
                    },
                    spacing = dpi(8),
                    layout = wibox.layout.fixed.horizontal,
                },
                margins = dpi(8),
                widget = wibox.container.margin,
            },
            bg = selected and SELECTED_BG_COLOR or "#00000000",
            fg = selected and SELECTED_FG_COLOR or FG_COLOR,
            forced_height = ITEM_HEIGHT,
            widget = wibox.container.background,
        })

        item:connect_signal("mouse::enter", function()
            if api then
                api.select(index)
            end
        end)
        -- :buttons may not work correctly in popups.
        item:connect_signal("button::press", function(_, _, _, button)
            if not api then
                return
            end
            if button == 1 then
                api.close_session(true)
            elseif button == 3 then
                api.close_session(false)
            end
        end)

        return item
    end

	---@param c AwesomeClient
	local function set_preview(c)
		---@type ImageSurface|nil
		local img = not c:isvisible() and preview_cache[c] or c:isvisible() and capture(c) or nil
		preview_bg.widget = {
			img and {
				image = img,
				resize = true,
				widget = wibox.widget.imagebox,
			} or {
				image = c.icon,
				resize = true,
				forced_width = MINI_ICON_SIZE,
				forced_height = MINI_ICON_SIZE,
				widget = wibox.widget.imagebox,
			},
			halign = "center",
			valign = "center",
			forced_width = PREVIEW_WIDTH,
			forced_height = PREVIEW_HEIGHT,
			widget = wibox.container.place,
		}
	end

    ---@param clients AwesomeClient[]
    ---@param index integer
    local function build_popup(clients, index)
        current_clients = clients
        current_index = index
        item_bgs = {}

        local list = { layout = wibox.layout.fixed.vertical }
        for i, c in ipairs(clients) do
            local item = make_item(c, i, i == index)
            item_bgs[i] = item
            list[i] = item
        end

        preview_bg = wibox.widget({
            forced_width = PREVIEW_WIDTH,
            forced_height = PREVIEW_HEIGHT,
            bg = "#11111b",
            widget = wibox.container.background,
        })
        set_preview(clients[index])

        popup = awful.popup({
            widget = {
                {
                    {
                        list,
                        strategy = "exact",
                        width = LIST_WIDTH,
                        widget = wibox.container.constraint,
                    },
                    preview_bg,
                    spacing = PADDING,
                    layout = wibox.layout.fixed.horizontal,
                },
                margins = PADDING,
                widget = wibox.container.margin,
            },
            bg = BG_COLOR,
            border_width = dpi(2),
            border_color = theme.popup_border_color,
            placement = awful.placement.centered,
            ontop = true,
            visible = true,
        })
    end

    ---@type AlttabUI
    theme.alttab = {
        show = build_popup,
        update = function(index)
            if not current_clients then
                return
            end
            if item_bgs[current_index] then
                item_bgs[current_index].bg = "00000000"
                item_bgs[current_index].fg = FG_COLOR
            end
            current_index = index
            if item_bgs[index] then
                item_bgs[index].bg = SELECTED_BG_COLOR
                item_bgs[index].fg = SELECTED_FG_COLOR
            end
            set_preview(current_clients[index])
        end,
        hide = function()
            if popup then
                popup.visible = false
                popup = nil
            end
            item_bgs = {}
            preview_bg = nil
            current_clients = nil
            current_index = nil
        end,
        on_init = function(a)
            api = a
        end,
        on_unfocus = capture,
        on_untagged = capture,
        on_unmanage = function(c)
            preview_cache[c] = nil
        end,
    }
end
```
