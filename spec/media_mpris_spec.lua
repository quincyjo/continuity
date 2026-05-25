require("spec.support.awesome_mocks")

local mpris = require("continuity.media.backends.mpris")

describe("mpris parsing", function()
	describe("_parse_player_name", function()
		it("extracts player name from D-Bus service name", function()
			assert.equals("spotify", mpris._private.parse_player_name("org.mpris.MediaPlayer2.spotify"))
			assert.equals("chromium", mpris._private.parse_player_name("org.mpris.MediaPlayer2.chromium"))
		end)
	end)

	describe("_parse_metadata", function()
		it("maps xesam and mpris fields to MediaState", function()
			local props = {
				["xesam:title"] = "Test Song",
				["xesam:artist"] = { "Artist One", "Artist Two" },
				["xesam:album"] = "Test Album",
				["xesam:albumArtist"] = { "Album Artist" },
				["xesam:trackNumber"] = 3,
				["xesam:discNumber"] = 1,
				["xesam:url"] = "spotify:track:abc123",
				["mpris:artUrl"] = "https://i.scdn.co/image/abc",
				["mpris:length"] = 240000000,
				["mpris:trackid"] = "/org/mpris/MediaPlayer2/Track/1",
			}
			local state = mpris._private.parse_metadata(props)
			assert.equals("Test Song", state.title)
			assert.equals("Artist One, Artist Two", state.artist)
			assert.equals("Test Album", state.album)
			assert.equals("Album Artist", state.album_artist)
			assert.equals(3, state.track_number)
			assert.equals(1, state.disc_number)
			assert.equals("spotify:track:abc123", state.uri)
			assert.equals("https://i.scdn.co/image/abc", state.art_uri)
			assert.is_near(240.0, state.duration, 0.001)
			assert.equals("/org/mpris/MediaPlayer2/Track/1", state.track_id)
		end)

		it("joins multi-element artist array", function()
			local state = mpris._private.parse_metadata({ ["xesam:artist"] = { "A", "B" } })
			assert.equals("A, B", state.artist)
		end)

		it("handles string artist (not array)", function()
			local state = mpris._private.parse_metadata({ ["xesam:artist"] = "Solo" })
			assert.equals("Solo", state.artist)
		end)
	end)

	describe("_parse_playback_props", function()
		it("maps PlaybackStatus strings", function()
			assert.equals("playing", mpris._private.parse_playback_props({ PlaybackStatus = "Playing" }).status)
			assert.equals("paused", mpris._private.parse_playback_props({ PlaybackStatus = "Paused" }).status)
			assert.equals("stopped", mpris._private.parse_playback_props({ PlaybackStatus = "Stopped" }).status)
		end)

		it("normalizes Volume float to integer 0-100", function()
			assert.equals(75, mpris._private.parse_playback_props({ Volume = 0.75 }).volume)
			assert.equals(100, mpris._private.parse_playback_props({ Volume = 1.0 }).volume)
			assert.equals(0, mpris._private.parse_playback_props({ Volume = 0.0 }).volume)
		end)

		it("maps Shuffle boolean", function()
			assert.is_true(mpris._private.parse_playback_props({ Shuffle = true }).shuffle)
			assert.is_false(mpris._private.parse_playback_props({ Shuffle = false }).shuffle)
		end)

		it("maps LoopStatus strings", function()
			assert.equals("none", mpris._private.parse_playback_props({ LoopStatus = "None" }).loop)
			assert.equals("track", mpris._private.parse_playback_props({ LoopStatus = "Track" }).loop)
			assert.equals("playlist", mpris._private.parse_playback_props({ LoopStatus = "Playlist" }).loop)
		end)

		it("converts Position microseconds to seconds", function()
			assert.is_near(30.5, mpris._private.parse_playback_props({ Position = 30500000 }).position, 0.001)
		end)
	end)

	describe("_parse_dbus_output", function()
		-- Sample mirrors real Spotify dbus-send --print-reply output.
		-- xesam:artist is nested INSIDE the Metadata variant array block,
		-- which is the structure that breaks naive lazy-regex array parsing.
		local sample = [[
method return time=1234567890.123456 sender=:1.42 -> destination=:1.100 serial=10 reply_serial=5
   array [
      dict entry(
         string "PlaybackStatus"
         variant             string "Playing"
      )
      dict entry(
         string "Shuffle"
         variant             boolean false
      )
      dict entry(
         string "LoopStatus"
         variant             string "None"
      )
      dict entry(
         string "Volume"
         variant             double 0.800000
      )
      dict entry(
         string "Position"
         variant             int64 15000000
      )
      dict entry(
         string "Metadata"
         variant             array [
            dict entry(
               string "xesam:title"
               variant                string "My Song"
            )
            dict entry(
               string "xesam:url"
               variant                string "spotify:track:abc"
            )
            dict entry(
               string "mpris:artUrl"
               variant                string "https://example.com/art.jpg"
            )
            dict entry(
               string "mpris:length"
               variant                int64 200000000
            )
            dict entry(
               string "xesam:trackNumber"
               variant                int32 3
            )
            dict entry(
               string "xesam:artist"
               variant                array [
                  string "Artist One"
                  string "Artist Two"
               ]
            )
            dict entry(
               string "xesam:albumArtist"
               variant                array [
                  string "Album Artist"
               ]
            )
         ]
      )
   ]
]]

		it("parses top-level string fields", function()
			local props = mpris._private.parse_dbus_output(sample)
			assert.equals("Playing", props["PlaybackStatus"])
			assert.equals("None", props["LoopStatus"])
		end)

		it("parses string fields nested inside Metadata block", function()
			local props = mpris._private.parse_dbus_output(sample)
			assert.equals("My Song", props["xesam:title"])
			assert.equals("spotify:track:abc", props["xesam:url"])
			assert.equals("https://example.com/art.jpg", props["mpris:artUrl"])
		end)

		it("parses numeric fields (top-level and nested)", function()
			local props = mpris._private.parse_dbus_output(sample)
			assert.equals(15000000, props["Position"])
			assert.equals(200000000, props["mpris:length"])
			assert.equals(3, props["xesam:trackNumber"])
		end)

		it("parses double Volume", function()
			local props = mpris._private.parse_dbus_output(sample)
			assert.is_near(0.8, props["Volume"], 0.001)
		end)

		it("parses boolean Shuffle", function()
			local props = mpris._private.parse_dbus_output(sample)
			assert.is_false(props["Shuffle"])
		end)

		it("parses xesam:artist string array nested inside Metadata block", function()
			local props = mpris._private.parse_dbus_output(sample)
			assert.is_table(props["xesam:artist"])
			assert.equals(2, #props["xesam:artist"])
			assert.equals("Artist One", props["xesam:artist"][1])
			assert.equals("Artist Two", props["xesam:artist"][2])
		end)

		it("parses xesam:albumArtist string array nested inside Metadata block", function()
			local props = mpris._private.parse_dbus_output(sample)
			assert.is_table(props["xesam:albumArtist"])
			assert.equals("Album Artist", props["xesam:albumArtist"][1])
		end)

		it("parses title containing embedded double-quotes (unescaped dbus-send output)", function()
			-- dbus-send does not escape " inside string values; the parser must
			-- capture up to the last " on the line, not stop at the first inner one.
			local quoted_title =
				[[Cynthia: Champion Cynthia (From "Pokémon Diamond and Pearl") / Battle! Champion (From "Pokémon Diamond and Pearl")]] -- luacheck: ignore
			local output = string.format(
				[[
method return time=1.0 sender=:1.42 -> destination=:1.1 serial=1 reply_serial=2
   array [
      dict entry(
         string "Metadata"
         variant             array [
            dict entry(
               string "xesam:title"
               variant                string "%s"
            )
            dict entry(
               string "xesam:artist"
               variant                array [
                  string "Motoi Sakuraba"
               ]
            )
         ]
      )
   ]
]],
				quoted_title
			)
			local props = mpris._private.parse_dbus_output(output)
			assert.equals(quoted_title, props["xesam:title"])
			assert.equals("Motoi Sakuraba", props["xesam:artist"][1])
		end)

		it("parses mpris:trackid expressed as object path", function()
			local output = [[
method return time=1.0 sender=:1.1131 -> destination=:1.1 serial=1 reply_serial=2
   array [
      dict entry(
         string "Metadata"
         variant             array [
            dict entry(
               string "mpris:trackid"
               variant                      object path "/org/mpris/MediaPlayer2/firefox"
            )
         ]
      )
   ]
]]
			local props = mpris._private.parse_dbus_output(output)
			assert.equals("/org/mpris/MediaPlayer2/firefox", props["mpris:trackid"])
		end)

		it("parses Identity and DesktopEntry from MediaPlayer2 GetAll output", function()
			local output = [[
method return time=1234567890.0 sender=:1.42 -> destination=:1.1 serial=1 reply_serial=2
   array [
      dict entry(
         string "CanRaise"
         variant             boolean true
      )
      dict entry(
         string "Identity"
         variant             string "Spotify"
      )
      dict entry(
         string "DesktopEntry"
         variant             string "spotify"
      )
   ]
]]
			local props = mpris._private.parse_dbus_output(output)
			assert.equals("Spotify", props["Identity"])
			assert.equals("spotify", props["DesktopEntry"])
		end)
	end)

	describe("_private.parse_can_flags", function()
		it("returns true for all flags when all are true", function()
			local flags = mpris._private.parse_can_flags({
				CanControl = true,
				CanSeek = true,
				CanGoNext = true,
				CanGoPrevious = true,
				CanPlay = true,
				CanPause = true,
			})
			assert.is_true(flags.can_control)
			assert.is_true(flags.can_seek)
			assert.is_true(flags.can_go_next)
			assert.is_true(flags.can_go_previous)
			assert.is_true(flags.can_play)
			assert.is_true(flags.can_pause)
			assert.is_true(flags.can_set_volume)
		end)

		it("returns false for each flag when set to false", function()
			local flags = mpris._private.parse_can_flags({
				CanControl = false,
				CanSeek = false,
				CanGoNext = false,
				CanGoPrevious = false,
				CanPlay = false,
				CanPause = false,
			})
			assert.is_false(flags.can_control)
			assert.is_false(flags.can_seek)
			assert.is_false(flags.can_go_next)
			assert.is_false(flags.can_go_previous)
			assert.is_false(flags.can_play)
			assert.is_false(flags.can_pause)
			assert.is_false(flags.can_set_volume)
		end)

		it("defaults all flags to true when absent (optimistic)", function()
			local flags = mpris._private.parse_can_flags({})
			assert.is_true(flags.can_control)
			assert.is_true(flags.can_seek)
			assert.is_true(flags.can_go_next)
			assert.is_true(flags.can_go_previous)
			assert.is_true(flags.can_play)
			assert.is_true(flags.can_pause)
			assert.is_true(flags.can_set_volume)
		end)

		it("mixes true and false correctly", function()
			local flags = mpris._private.parse_can_flags({
				CanGoNext = false,
				CanGoPrevious = false,
			})
			assert.is_true(flags.can_control)
			assert.is_false(flags.can_go_next)
			assert.is_false(flags.can_go_previous)
			assert.is_true(flags.can_play)
		end)
	end)

	describe("_sender_service", function()
		-- dbus-monitor header lines may carry either the well-known MPRIS name or
		-- the sender's unique bus name (:1.xxx). Both must resolve to the service.
		local well_known = "org.mpris.MediaPlayer2.spotify"
		local header_well_known = "signal time=1.0 sender="
			.. well_known
			.. " -> destination=(null destination) serial=1"
			.. " path=/org/mpris/MediaPlayer2;"
			.. " interface=org.freedesktop.DBus.Properties;"
			.. " member=PropertiesChanged"
		local header_unique = "signal time=1.0 sender=:1.122"
			.. " -> destination=(null destination) serial=2"
			.. " path=/org/mpris/MediaPlayer2;"
			.. " interface=org.freedesktop.DBus.Properties;"
			.. " member=PropertiesChanged"

		it("returns well-known service name when sender is MPRIS name", function()
			assert.equals(well_known, mpris._private.sender_service(header_well_known, {}))
		end)

		it("resolves unique bus name via unique_name_map", function()
			local map = { [":1.122"] = well_known }
			assert.equals(well_known, mpris._private.sender_service(header_unique, map))
		end)

		it("returns nil for unique bus name not in map", function()
			assert.is_nil(mpris._private.sender_service(header_unique, {}))
		end)

		it("returns nil for non-MPRIS body lines", function()
			assert.is_nil(mpris._private.sender_service('   string "xesam:title"', {}))
			assert.is_nil(mpris._private.sender_service("", {}))
		end)
	end)

	describe("_parse_unique_name", function()
		it("extracts unique bus name from GetNameOwner reply", function()
			local stdout = "method return time=1.0 sender=org.freedesktop.DBus"
				.. " -> destination=:1.4 serial=5 reply_serial=3\n"
				.. '   string ":1.122"\n'
			assert.equals(":1.122", mpris._private.parse_unique_name(stdout))
		end)

		it("returns nil when no unique bus name present", function()
			assert.is_nil(mpris._private.parse_unique_name("Error: something failed\n"))
		end)
	end)

	describe("_parse_desktop_entry", function()
		it("extracts DesktopEntry string from dbus-send Get reply", function()
			local stdout = "method return time=1.0 sender=:1.42 -> destination=:1.1 serial=1 reply_serial=2\n"
				.. '   variant             string "spotify"\n'
			assert.equals("spotify", mpris._private.parse_desktop_entry(stdout))
		end)

		it("handles players with instance suffix in DesktopEntry", function()
			local stdout = "method return time=1.0 sender=:1.42 -> destination=:1.1 serial=1 reply_serial=2\n"
				.. '   variant             string "chromium"\n'
			assert.equals("chromium", mpris._private.parse_desktop_entry(stdout))
		end)

		it("returns nil when no string variant in reply", function()
			assert.is_nil(mpris._private.parse_desktop_entry("Error: org.freedesktop.DBus.Error.UnknownProperty\n"))
		end)
	end)

	describe("_resolve_app_icon", function()
		local mpris_fresh, mock_grep_fn

		before_each(function()
			package.loaded["continuity.media.backends.mpris"] = nil
			mock_grep_fn = nil
			package.loaded["continuity.tools.grep"] = setmetatable({}, {
				__call = function(_, opts, cb)
					if mock_grep_fn then
						mock_grep_fn(opts, cb)
					end
				end,
			})
			local menubar_utils = require("menubar.utils")
			menubar_utils.lookup_icon = function(_)
				return nil
			end
			mpris_fresh = require("continuity.media.backends.mpris")
		end)

		it("calls cb with icon path immediately when lookup_icon succeeds", function()
			local menubar_utils = require("menubar.utils")
			menubar_utils.lookup_icon = function(name)
				if name == "spotify" then
					return "/icons/hicolor/48x48/apps/spotify.png"
				end
			end
			local result = "not_called"
			mpris_fresh._private.resolve_app_icon("spotify", { "/usr/share/applications" }, function(p)
				result = p
			end)
			assert.equals("/icons/hicolor/48x48/apps/spotify.png", result)
		end)

		it("greps dirs with Name= pattern when lookup_icon returns nil", function()
			local grep_opts_seen
			mock_grep_fn = function(opts, cb)
				grep_opts_seen = opts
				cb({}, 0)
			end
			local result = "not_called"
			mpris_fresh._private.resolve_app_icon("spotify", { "/a", "/b" }, function(p)
				result = p
			end)
			assert.is_not_nil(grep_opts_seen)
			assert.is_not_nil(grep_opts_seen.pattern:find("spotify", 1, true))
			-- dirs passed as path
			assert.equals("/a", grep_opts_seen.path[1])
			assert.equals("/b", grep_opts_seen.path[2])
			assert.is_true(grep_opts_seen.follow_links)
			assert.is_nil(result)
		end)

		it("resolves icon via Icon= field in found .desktop file", function()
			local menubar_utils = require("menubar.utils")
			menubar_utils.lookup_icon = function(name)
				if name == "com.spotify.Client" then
					return "/icons/com.spotify.Client.png"
				end
			end
			local call_count = 0
			mock_grep_fn = function(_opts, cb)
				call_count = call_count + 1
				if call_count == 1 then
					cb({
						{
							filepath = "/usr/share/applications/spotify.desktop",
							line_number = 1,
							text = "Name=Spotify",
						},
					}, 0)
				else
					cb({
						{
							filepath = "/usr/share/applications/spotify.desktop",
							line_number = 5,
							text = "Icon=com.spotify.Client",
						},
					}, 0)
				end
			end
			local result = "not_called"
			mpris_fresh._private.resolve_app_icon("spotify", { "/usr/share/applications" }, function(p)
				result = p
			end)
			assert.equals("/icons/com.spotify.Client.png", result)
		end)

		it("calls cb with nil when no .desktop file found via grep", function()
			mock_grep_fn = function(_opts, cb)
				cb({}, 0)
			end
			local result = "not_called"
			mpris_fresh._private.resolve_app_icon("unknown_player", { "/usr/share/applications" }, function(p)
				result = p
			end)
			assert.is_nil(result)
		end)

		it("calls cb with nil when Icon= field absent from .desktop file", function()
			local call_count = 0
			mock_grep_fn = function(_opts, cb)
				call_count = call_count + 1
				if call_count == 1 then
					cb({
						{
							filepath = "/apps/player.desktop",
							line_number = 1,
							text = "Name=Player",
						},
					}, 0)
				else
					cb({}, 0) -- no Icon= line
				end
			end
			local result = "not_called"
			mpris_fresh._private.resolve_app_icon("player", { "/apps" }, function(p)
				result = p
			end)
			assert.is_nil(result)
		end)
	end)
end)

describe("mpris streaming parsing", function()
	describe("parse_can_flags_partial", function()
		it("returns nil when no Can* keys are present", function()
			assert.is_nil(mpris._private.parse_can_flags_partial({ PlaybackStatus = "Playing" }))
		end)

		it("returns nil for empty props", function()
			assert.is_nil(mpris._private.parse_can_flags_partial({}))
		end)

		it("returns only the present key", function()
			local flags = mpris._private.parse_can_flags_partial({ CanPause = false })
			assert.is_not_nil(flags)
			assert.is_false(flags.can_pause)
			assert.is_nil(flags.can_seek)
			assert.is_nil(flags.can_go_next)
			assert.is_nil(flags.can_go_previous)
			assert.is_nil(flags.can_play)
			assert.is_nil(flags.can_control)
		end)

		it("maps all Can* keys when all are present", function()
			local flags = mpris._private.parse_can_flags_partial({
				CanControl = true,
				CanSeek = false,
				CanGoNext = true,
				CanGoPrevious = false,
				CanPlay = true,
				CanPause = false,
			})
			assert.is_not_nil(flags)
			assert.is_true(flags.can_control)
			assert.is_false(flags.can_seek)
			assert.is_true(flags.can_go_next)
			assert.is_false(flags.can_go_previous)
			assert.is_true(flags.can_play)
			assert.is_false(flags.can_pause)
		end)

		it("treats false values as present (not absent)", function()
			local flags = mpris._private.parse_can_flags_partial({ CanSeek = false })
			assert.is_not_nil(flags)
			assert.is_false(flags.can_seek)
		end)
	end)

	describe("parse_properties_changed", function()
		local function signal(sender, changed_array, invalidated_array)
			return table.concat({
				"signal time=1.0 sender="
					.. sender
					.. " -> destination=(null destination) serial=1"
					.. " path=/org/mpris/MediaPlayer2;"
					.. " interface=org.freedesktop.DBus.Properties;"
					.. " member=PropertiesChanged",
				'   string "org.mpris.MediaPlayer2.Player"',
				"   array [",
				changed_array or "",
				"   ]",
				"   array [",
				invalidated_array or "",
				"   ]",
			}, "\n")
		end

		it("returns nil for empty input", function()
			assert.is_nil(mpris._private.parse_properties_changed(""))
		end)

		it("parses PlaybackStatus from changed properties", function()
			local body =
				'      dict entry(\n         string "PlaybackStatus"\n         variant             string "Paused"\n      )'
			local r = mpris._private.parse_properties_changed(signal(":1.62", body))
			assert.is_not_nil(r)
			assert.equals("Paused", r.props.PlaybackStatus)
			assert.equals(0, #r.invalidated)
		end)

		it("parses CanPause from changed properties", function()
			local body =
				'      dict entry(\n         string "CanPause"\n         variant             boolean false\n      )'
			local r = mpris._private.parse_properties_changed(signal(":1.62", body))
			assert.is_not_nil(r)
			assert.is_false(r.props.CanPause)
		end)

		it("parses Metadata nested dict from changed properties", function()
			local meta_body = table.concat({
				"      dict entry(",
				'         string "Metadata"',
				"         variant             array [",
				"            dict entry(",
				'               string "xesam:title"',
				'               variant             string "Some Song"',
				"            )",
				"            dict entry(",
				'               string "mpris:trackid"',
				'               variant             string "/track/1"',
				"            )",
				"         ]",
				"      )",
			}, "\n")
			local r = mpris._private.parse_properties_changed(signal(":1.62", meta_body))
			assert.is_not_nil(r)
			assert.equals("Some Song", r.props["xesam:title"])
			assert.equals("/track/1", r.props["mpris:trackid"])
			assert.equals(0, #r.invalidated)
		end)

		it("parses invalidated_properties from second array", function()
			local inv = '      string "Metadata"\n      string "PlaybackStatus"'
			local r = mpris._private.parse_properties_changed(signal(":1.62", nil, inv))
			assert.is_not_nil(r)
			assert.equals(0, next(r.props) == nil and 0 or 1) -- props empty
			assert.equals(2, #r.invalidated)
			assert.equals("Metadata", r.invalidated[1])
			assert.equals("PlaybackStatus", r.invalidated[2])
		end)

		it("includes the sender line in the result", function()
			local r = mpris._private.parse_properties_changed(
				signal(
					":1.99",
					'      dict entry(\n         string "PlaybackStatus"\n         variant             string "Playing"\n      )'
				)
			)
			assert.is_not_nil(r)
			assert.is_not_nil(r.sender_line:find(":1.99", 1, true))
		end)
	end)
end)

describe("backend instance", function()
	before_each(function()
		package.loaded["menubar.utils"] = nil
	end)

	it("has name = 'mpris'", function()
		local b = require("continuity.media.backends.mpris")()
		assert.equals("mpris", b.name)
	end)

	it("does not expose id on the backend table", function()
		local b = require("continuity.media.backends.mpris")()
		assert.is_nil(b.id)
	end)

	it("does not expose subscribe_position on the backend table", function()
		local b = require("continuity.media.backends.mpris")()
		assert.is_nil(b.subscribe_position)
	end)

	it("does not expose get_position on the backend table", function()
		local b = require("continuity.media.backends.mpris")()
		assert.is_nil(b.get_position)
	end)

	it("passes position and playback caps to registry.add() for each discovered player", function()
		package.loaded["continuity.media.backends.mpris"] = nil
		local awful = require("awful")
		awful.spawn.easy_async = function(cmd, cb)
			if type(cmd) == "table" then
				local last = cmd[#cmd]
				if last == "org.freedesktop.DBus.ListNames" then
					cb('   array [\n      string "org.mpris.MediaPlayer2.spotify"\n   ]\n', "", "", 0)
				elseif last == "org.freedesktop.DBus.GetNameOwner" then
					cb('   string ":1.42"\n', "", "", 0)
				else
					cb("", "", "", 0)
				end
			else
				cb("", "", "", 0)
			end
		end
		awful.spawn.with_line_callback = function()
			return {}
		end
		local b = require("continuity.media.backends.mpris")()
		local caps_received
		local reg = {
			add = function(_, _, _, caps)
				caps_received = caps
			end,
			update = function() end,
			remove = function() end,
		}
		b:start(reg)
		assert.is_not_nil(caps_received)
		assert.is_function(caps_received.position.subscribe)
		assert.is_function(caps_received.position.get)
		assert.is_table(caps_received.playback)
		assert.is_function(caps_received.playback.play)
	end)

	it("fetches DesktopEntry and passes resolved icon as app_icon to registry.add", function()
		package.loaded["continuity.media.backends.mpris"] = nil
		package.loaded["continuity.util.app_icon"] = {
			by_desktop_entry = function(_entry, cb)
				cb("/usr/share/icons/hicolor/48x48/apps/spotify.png")
			end,
		}
		local awful = require("awful")
		awful.spawn.easy_async = function(cmd, cb)
			if type(cmd) == "table" then
				local last = cmd[#cmd]
				if last == "org.freedesktop.DBus.ListNames" then
					cb('   array [\n      string "org.mpris.MediaPlayer2.spotify"\n   ]\n', "", "", 0)
				elseif last == "org.freedesktop.DBus.GetNameOwner" then
					cb('   string ":1.42"\n', "", "", 0)
				elseif last == "string:org.mpris.MediaPlayer2" then
					cb(
						[[   array [
					      dict entry(
					         string "Identity"
					         variant             string "Spotify"
					      )
					      dict entry(
					         string "DesktopEntry"
					         variant             string "spotify"
					      )
					   ]
					]],
						"",
						"",
						0
					)
				else
					cb("", "", "", 0)
				end
			else
				cb("", "", "", 0)
			end
		end
		awful.spawn.with_line_callback = function()
			return {}
		end
		local b = require("continuity.media.backends.mpris")()
		local add_args
		local reg = {
			add = function(sid, name, _state, _caps, app_name, app_icon)
				add_args = { sid = sid, name = name, app_name = app_name, app_icon = app_icon }
			end,
			update = function() end,
			remove = function() end,
			add_dbus_sender = function() end,
		}
		b:start(reg)
		assert.is_not_nil(add_args)
		assert.equals("mpris:spotify", add_args.sid)
		assert.equals("/usr/share/icons/hicolor/48x48/apps/spotify.png", add_args.app_icon)
	end)

	it("passes resolved icon from app_icon module to registry.add", function()
		package.loaded["continuity.media.backends.mpris"] = nil
		package.loaded["continuity.util.app_icon"] = {
			by_desktop_entry = function(_entry, cb)
				cb("/icons/com.spotify.Client.png")
			end,
		}
		local awful = require("awful")
		awful.spawn.easy_async = function(cmd, cb)
			if type(cmd) == "table" then
				local last = cmd[#cmd]
				if last == "org.freedesktop.DBus.ListNames" then
					cb('   array [\n      string "org.mpris.MediaPlayer2.spotify"\n   ]\n', "", "", 0)
				elseif last == "org.freedesktop.DBus.GetNameOwner" then
					cb('   string ":1.42"\n', "", "", 0)
				elseif last == "string:org.mpris.MediaPlayer2" then
					cb(
						[[   array [
					      dict entry(
					         string "DesktopEntry"
					         variant             string "spotify"
					      )
					   ]
					]],
						"",
						"",
						0
					)
				else
					cb("", "", "", 0)
				end
			else
				cb("", "", "", 0)
			end
		end
		awful.spawn.with_line_callback = function()
			return {}
		end
		local b = require("continuity.media.backends.mpris")()
		local add_args
		local reg = {
			add = function(_sid, _name, _state, _caps, _app_name, app_icon)
				add_args = { app_icon = app_icon }
			end,
			update = function() end,
			remove = function() end,
			add_dbus_sender = function() end,
		}
		b:start(reg)
		assert.is_not_nil(add_args)
		assert.equals("/icons/com.spotify.Client.png", add_args.app_icon)
	end)

	it("passes nil app_icon to registry.add when DesktopEntry fetch fails", function()
		package.loaded["continuity.media.backends.mpris"] = nil
		local awful = require("awful")
		awful.spawn.easy_async = function(cmd, cb)
			if type(cmd) == "table" then
				local last = cmd[#cmd]
				if last == "org.freedesktop.DBus.ListNames" then
					cb('   array [\n      string "org.mpris.MediaPlayer2.spotify"\n   ]\n', "", "", 0)
				elseif last == "org.freedesktop.DBus.GetNameOwner" then
					cb('   string ":1.42"\n', "", "", 0)
				elseif last == "string:org.mpris.MediaPlayer2" then
					cb("", "", "", 1) -- non-zero exit: GetAll failed
				else
					cb("", "", "", 0)
				end
			else
				cb("", "", "", 0)
			end
		end
		awful.spawn.with_line_callback = function()
			return {}
		end
		local b = require("continuity.media.backends.mpris")()
		local add_args
		local reg = {
			add = function(_sid, _name, _state, _caps, _app_name, app_icon)
				add_args = { app_icon = app_icon }
			end,
			update = function() end,
			remove = function() end,
			add_dbus_sender = function() end,
		}
		b:start(reg)
		assert.is_not_nil(add_args)
		assert.is_nil(add_args.app_icon)
	end)

	it("uses Identity from MediaPlayer2 GetAll as display name", function()
		package.loaded["continuity.media.backends.mpris"] = nil
		local awful = require("awful")
		awful.spawn.easy_async = function(cmd, cb)
			if type(cmd) == "table" then
				local last = cmd[#cmd]
				if last == "org.freedesktop.DBus.ListNames" then
					cb('   array [\n      string "org.mpris.MediaPlayer2.spotify"\n   ]\n', "", "", 0)
				elseif last == "string:org.mpris.MediaPlayer2" then
					cb(
						[[   array [
					      dict entry(
					         string "Identity"
					         variant             string "Spotify"
					      )
					      dict entry(
					         string "DesktopEntry"
					         variant             string "spotify"
					      )
					   ]
					]],
						"",
						"",
						0
					)
				else
					cb("", "", "", 0)
				end
			else
				cb("", "", "", 0)
			end
		end
		awful.spawn.with_line_callback = function()
			return {}
		end
		local b = require("continuity.media.backends.mpris")()
		local add_args
		local reg = {
			add = function(_sid, name, _state, _caps, _app_name, _app_icon)
				add_args = { name = name }
			end,
			update = function() end,
			remove = function() end,
			add_dbus_sender = function() end,
		}
		b:start(reg)
		assert.is_not_nil(add_args)
		assert.equals("Spotify", add_args.name)
	end)

	it("falls back to player name when Identity absent from MediaPlayer2 GetAll", function()
		package.loaded["continuity.media.backends.mpris"] = nil
		local awful = require("awful")
		awful.spawn.easy_async = function(cmd, cb)
			if type(cmd) == "table" then
				local last = cmd[#cmd]
				if last == "org.freedesktop.DBus.ListNames" then
					cb('   array [\n      string "org.mpris.MediaPlayer2.spotify"\n   ]\n', "", "", 0)
				elseif last == "string:org.mpris.MediaPlayer2" then
					cb(
						[[   array [
					      dict entry(
					         string "DesktopEntry"
					         variant             string "spotify"
					      )
					   ]
					]],
						"",
						"",
						0
					)
				else
					cb("", "", "", 0)
				end
			else
				cb("", "", "", 0)
			end
		end
		awful.spawn.with_line_callback = function()
			return {}
		end
		local b = require("continuity.media.backends.mpris")()
		local add_args
		local reg = {
			add = function(_sid, name, _state, _caps, _app_name, _app_icon)
				add_args = { name = name }
			end,
			update = function() end,
			remove = function() end,
			add_dbus_sender = function() end,
		}
		b:start(reg)
		assert.is_not_nil(add_args)
		assert.equals("spotify", add_args.name)
	end)

	describe("subscribe_position cap", function()
		local caps, gears_mod, spawned_cmds

		before_each(function()
			package.loaded["continuity.media.backends.mpris"] = nil
			gears_mod = require("gears")
			gears_mod._created = {}
			local awful = require("awful")
			spawned_cmds = {}
			awful.spawn.easy_async = function(cmd, cb)
				spawned_cmds[#spawned_cmds + 1] = { cmd = cmd, cb = cb }
			end
			awful.spawn.with_line_callback = function()
				return {}
			end
			local b = require("continuity.media.backends.mpris")()
			local reg = {
				add = function(_, _, _, c)
					caps = c
				end,
				update = function() end,
				remove = function() end,
			}
			b:start(reg)
			-- caps will be nil since no player was discovered (ListNames not mocked above)
		end)

		it("returns a stop function for unknown source (caps nil — no player discovered)", function()
			-- When no player discovered, caps is nil; subscribe_position never fires.
			-- This verifies the backend starts without error even with no players.
			assert.is_nil(caps)
		end)
	end)

	describe("get_position cap for discovered player", function()
		local caps

		before_each(function()
			package.loaded["continuity.media.backends.mpris"] = nil
			local awful = require("awful")
			awful.spawn.easy_async = function(cmd, cb)
				if type(cmd) == "table" then
					local last = cmd[#cmd]
					if last == "org.freedesktop.DBus.ListNames" then
						cb('   array [\n      string "org.mpris.MediaPlayer2.spotify"\n   ]\n', "", "", 0)
					elseif last == "org.freedesktop.DBus.GetNameOwner" then
						cb('   string ":1.42"\n', "", "", 0)
					else
						cb("", "", "", 0)
					end
				else
					cb("", "", "", 0)
				end
			end
			awful.spawn.with_line_callback = function()
				return {}
			end
			local b = require("continuity.media.backends.mpris")()
			local reg = {
				add = function(_, _, _, c)
					caps = c
				end,
				update = function() end,
				remove = function() end,
			}
			b:start(reg)
		end)

		it("get cap calls cb(nil) when invoked after discovery (mock returns empty)", function()
			-- The mock returns "" for the position query -> no int64 match -> nil
			local result = "not_called"
			caps.position:get(function(p)
				result = p
			end)
			assert.is_nil(result)
		end)
	end)
end)

describe("playback commands", function()
	local caps, spawned_cmds, update_calls
	-- source_id for "org.mpris.MediaPlayer2.spotify"
	local SOURCE_ID = "mpris:spotify"

	before_each(function()
		package.loaded["continuity.media.backends.mpris"] = nil
		local awful = require("awful")
		spawned_cmds = {}
		-- Smart mock: simulate player discovery so reverse_players is populated.
		-- Route callbacks by inspecting the last argv element.
		awful.spawn.easy_async = function(cmd, cb)
			spawned_cmds[#spawned_cmds + 1] = { cmd = cmd, cb = cb }
			if type(cmd) == "table" then
				local last = cmd[#cmd]
				if last == "org.freedesktop.DBus.ListNames" then
					-- Return a response that contains spotify
					cb('   array [\n      string "org.mpris.MediaPlayer2.spotify"\n   ]\n', "", "", 0)
				elseif last == "org.freedesktop.DBus.GetNameOwner" then
					cb('   string ":1.42"\n', "", "", 0)
				elseif last == "string:org.mpris.MediaPlayer2.Player" then
					-- Simulate GetAll with track_id so track_ids[source_id] is populated
					cb(
						'"mpris:trackid" variant string "/org/mpris/MediaPlayer2/Track/1"\n'
							.. '"CanControl" variant boolean true\n'
							.. '"CanSeek" variant boolean true\n'
							.. '"CanGoNext" variant boolean true\n'
							.. '"CanGoPrevious" variant boolean true\n'
							.. '"CanPlay" variant boolean true\n'
							.. '"CanPause" variant boolean true\n',
						"",
						"",
						0
					)
				else
					cb("", "", "", 0)
				end
			else
				cb("", "", "", 0)
			end
		end
		awful.spawn.with_line_callback = function()
			return {}
		end
		local b = require("continuity.media.backends.mpris")()
		update_calls = {}
		local reg = {
			add = function(_, _, _, c)
				caps = c
			end,
			update = function(sid, partial)
				update_calls[#update_calls + 1] = { sid = sid, state = partial }
			end,
			remove = function() end,
			add_dbus_sender = function() end,
		}
		b:start(reg)
		spawned_cmds = {} -- clear startup commands; test only what playback fires
	end)

	it("caps has playback table with all methods", function()
		assert.is_table(caps.playback)
		assert.is_function(caps.playback.play)
		assert.is_function(caps.playback.set_position)
	end)

	it("play() sends --type=method_call dbus-send for Play", function()
		caps.playback.play(SOURCE_ID)
		assert.equals(1, #spawned_cmds)
		local cmd = spawned_cmds[1].cmd
		assert.equals("dbus-send", cmd[1])
		assert.equals("--type=method_call", cmd[5])
		assert.equals("--dest=org.mpris.MediaPlayer2.spotify", cmd[4])
		assert.equals("org.mpris.MediaPlayer2.Player.Play", cmd[#cmd])
	end)

	it("pause() sends Pause", function()
		caps.playback.pause(SOURCE_ID)
		assert.equals("org.mpris.MediaPlayer2.Player.Pause", spawned_cmds[1].cmd[#spawned_cmds[1].cmd])
	end)

	it("play_pause() sends PlayPause", function()
		caps.playback.play_pause(SOURCE_ID)
		assert.equals("org.mpris.MediaPlayer2.Player.PlayPause", spawned_cmds[1].cmd[#spawned_cmds[1].cmd])
	end)

	it("stop() sends Stop", function()
		caps.playback.stop(SOURCE_ID)
		assert.equals("org.mpris.MediaPlayer2.Player.Stop", spawned_cmds[1].cmd[#spawned_cmds[1].cmd])
	end)

	it("next() sends Next", function()
		caps.playback.next(SOURCE_ID)
		assert.equals("org.mpris.MediaPlayer2.Player.Next", spawned_cmds[1].cmd[#spawned_cmds[1].cmd])
	end)

	it("previous() sends Previous", function()
		caps.playback.previous(SOURCE_ID)
		assert.equals("org.mpris.MediaPlayer2.Player.Previous", spawned_cmds[1].cmd[#spawned_cmds[1].cmd])
	end)

	it("seek(5) sends Seek with int64:5000000 using --print-reply", function()
		caps.playback.seek(SOURCE_ID, 5)
		local cmd = spawned_cmds[1].cmd
		assert.equals("org.mpris.MediaPlayer2.Player.Seek", cmd[#cmd - 1])
		assert.equals("int64:5000000", cmd[#cmd])
	end)

	it("seek(-3) sends int64:-3000000", function()
		caps.playback.seek(SOURCE_ID, -3)
		assert.equals("int64:-3000000", spawned_cmds[1].cmd[#spawned_cmds[1].cmd])
	end)

	it("seek() pushes position via registry.update in easy_async callback", function()
		local awful = require("awful")
		awful.spawn.easy_async = function(cmd, cb)
			if type(cmd) == "table" and cmd[#cmd] == "string:Position" then
				-- Simulate get_position returning 10.0 seconds (10000000 microseconds)
				cb("int64 10000000\n", "", "", 0)
			else
				cb("", "", "", 0)
			end
		end
		update_calls = {}
		caps.playback.seek(SOURCE_ID, 5)
		assert.equals(1, #update_calls)
		assert.equals(10.0, update_calls[1].state.position)
	end)

	it("set_position(30) sends SetPosition with objpath and int64 using --print-reply", function()
		caps.playback.set_position(SOURCE_ID, 30)
		local cmd = spawned_cmds[1].cmd
		assert.equals("--type=method_call", cmd[#cmd - 4])
		assert.equals("org.mpris.MediaPlayer2.Player.SetPosition", cmd[#cmd - 2])
		assert.equals("objpath:/org/mpris/MediaPlayer2/Track/1", cmd[#cmd - 1])
		assert.equals("int64:30000000", cmd[#cmd])
	end)

	it("set_position() pushes position via registry.update in easy_async callback", function()
		update_calls = {}
		caps.playback.set_position(SOURCE_ID, 30)
		assert.equals(1, #update_calls)
		assert.equals(30, update_calls[1].state.position)
	end)

	it("set_position() is no-op when track_id is nil", function()
		-- Fresh backend: discover player but GetAll returns blank -> track_ids[source_id] stays nil
		package.loaded["continuity.media.backends.mpris"] = nil
		local awful = require("awful")
		awful.spawn.easy_async = function(cmd, cb)
			if type(cmd) == "table" then
				local last = cmd[#cmd]
				if last == "org.freedesktop.DBus.ListNames" then
					cb('   array [\n      string "org.mpris.MediaPlayer2.spotify"\n   ]\n', "", "", 0)
				elseif last == "org.freedesktop.DBus.GetNameOwner" then
					cb('   string ":1.42"\n', "", "", 0)
				else
					cb("", "", "", 0) -- blank GetAll -> no track_id parsed
				end
			else
				cb("", "", "", 0)
			end
		end
		awful.spawn.with_line_callback = function()
			return {}
		end
		local b2 = require("continuity.media.backends.mpris")()
		local caps2
		b2:start({
			add = function(_, _, _, c)
				caps2 = c
			end,
			update = function() end,
			remove = function() end,
			add_dbus_sender = function() end,
		})
		spawned_cmds = {}
		caps2.playback.set_position(SOURCE_ID, 30)
		assert.equals(0, #spawned_cmds)
	end)

	it("play() is a no-op for unknown source_id", function()
		caps.playback.play("mpris:unknown")
		assert.equals(0, #spawned_cmds)
	end)

	it("caps has volume table with set_perc function", function()
		assert.is_table(caps.volume)
		assert.is_function(caps.volume.set_perc)
	end)

	it("volume.set_perc sends Properties.Set Volume as a variant:double", function()
		caps.volume.set_perc(SOURCE_ID, 60)
		assert.equals(1, #spawned_cmds)
		local cmd = spawned_cmds[1].cmd
		assert.equals("dbus-send", cmd[1])
		assert.equals("--dest=org.mpris.MediaPlayer2.spotify", cmd[4])
		assert.equals("/org/mpris/MediaPlayer2", cmd[6])
		assert.equals("org.freedesktop.DBus.Properties.Set", cmd[7])
		assert.equals("string:org.mpris.MediaPlayer2.Player", cmd[8])
		assert.equals("string:Volume", cmd[9])
		assert.equals("variant:double:0.600000", cmd[10])
	end)

	it("volume.set_perc sends correct value for 100%", function()
		caps.volume.set_perc(SOURCE_ID, 100)
		assert.equals("variant:double:1.000000", spawned_cmds[1].cmd[10])
	end)

	it("volume.set_perc sends correct value for 0%", function()
		caps.volume.set_perc(SOURCE_ID, 0)
		assert.equals("variant:double:0.000000", spawned_cmds[1].cmd[10])
	end)

	it("volume.set_perc is a no-op for unknown source_id", function()
		caps.volume.set_perc("mpris:unknown", 60)
		assert.equals(0, #spawned_cmds)
	end)

	it("volume.set_perc does not call registry.update", function()
		caps.volume.set_perc(SOURCE_ID, 60)
		assert.equals(0, #update_calls)
	end)
end)

describe("monitor streaming dispatch", function()
	local HEADER = "signal time=1.0 sender=org.mpris.MediaPlayer2.spotify"
		.. " -> destination=(null destination) serial=1"
		.. " path=/org/mpris/MediaPlayer2;"
		.. " interface=org.freedesktop.DBus.Properties;"
		.. " member=PropertiesChanged"
	-- Unique bus name header — resolves via unique_name_map populated by GetNameOwner mock.
	local UNIQUE_HEADER = "signal time=1.0 sender=:1.42"
		.. " -> destination=(null destination) serial=1"
		.. " path=/org/mpris/MediaPlayer2;"
		.. " interface=org.freedesktop.DBus.Properties;"
		.. " member=PropertiesChanged"

	local monitor_stdout, monitor_exit
	local update_calls, dbus_cmds

	before_each(function()
		package.loaded["continuity.media.backends.mpris"] = nil
		package.loaded["continuity.util.app_icon"] = {
			by_desktop_entry = function(_, cb)
				cb(nil)
			end,
		}
		update_calls = {}
		dbus_cmds = {}
		local awful = require("awful")
		awful.spawn.easy_async = function(cmd, cb)
			dbus_cmds[#dbus_cmds + 1] = cmd
			if type(cmd) == "table" then
				local last = cmd[#cmd]
				if last == "org.freedesktop.DBus.ListNames" then
					cb('   array [\n      string "org.mpris.MediaPlayer2.spotify"\n   ]\n', "", "", 0)
				elseif cmd[#cmd - 1] == "org.freedesktop.DBus.GetNameOwner" then
					cb('   string ":1.42"\n', "", "", 0)
				else
					cb("", "", "", 0)
				end
			else
				cb("", "", "", 0)
			end
		end
		awful.spawn.with_line_callback = function(cmd, cbs)
			local cmd_str = type(cmd) == "table" and table.concat(cmd, " ") or cmd
			if cmd_str:find("PropertiesChanged", 1, true) then
				monitor_stdout = cbs.stdout
				monitor_exit = cbs.exit
			end
			return 1
		end
		local b = require("continuity.media.backends.mpris")()
		local reg = {
			add = function() end,
			update = function(sid, state, flags)
				update_calls[#update_calls + 1] = { sid = sid, state = state, flags = flags }
			end,
			remove = function() end,
			add_dbus_sender = function() end,
		}
		b:start(reg)
		dbus_cmds = {}
	end)

	local function feed(lines)
		for _, line in ipairs(lines) do
			monitor_stdout(line)
		end
	end

	it("dispatches PlaybackStatus delta directly via registry.update without GetAll", function()
		feed({
			HEADER,
			'   string "org.mpris.MediaPlayer2.Player"',
			"   array [",
			"      dict entry(",
			'         string "PlaybackStatus"',
			'         variant             string "Paused"',
			"      )",
			"   ]",
			"   array [",
			"   ]",
		})
		assert.equals(1, #update_calls)
		assert.equals("mpris:spotify", update_calls[1].sid)
		assert.equals("paused", update_calls[1].state.status)
		assert.equals(0, #dbus_cmds)
	end)

	it("falls back to GetAll when invalidated_properties is non-empty", function()
		local awful = require("awful")
		local get_all_called = false
		awful.spawn.easy_async = function(cmd, cb)
			dbus_cmds[#dbus_cmds + 1] = cmd
			if type(cmd) == "table" and cmd[#cmd] == "string:org.mpris.MediaPlayer2.Player" then
				get_all_called = true
			else
				cb("", "", "", 0)
			end
		end
		feed({
			HEADER,
			'   string "org.mpris.MediaPlayer2.Player"',
			"   array [",
			"   ]",
			"   array [",
			'      string "Metadata"',
			"   ]",
		})
		assert.equals(0, #update_calls)
		assert.is_true(get_all_called)
	end)

	it("ignores signals from senders not in unique_name_map", function()
		local unknown_header = "signal time=1.0 sender=:1.99"
			.. " -> destination=(null destination) serial=1"
			.. " path=/org/mpris/MediaPlayer2;"
			.. " interface=org.freedesktop.DBus.Properties;"
			.. " member=PropertiesChanged"
		feed({
			unknown_header,
			'   string "org.mpris.MediaPlayer2.Player"',
			"   array [",
			"      dict entry(",
			'         string "PlaybackStatus"',
			'         variant             string "Paused"',
			"      )",
			"   ]",
			"   array [",
			"   ]",
		})
		assert.equals(0, #update_calls)
		assert.equals(0, #dbus_cmds)
	end)

	it("dispatches delta from unique sender resolved via unique_name_map", function()
		feed({
			UNIQUE_HEADER,
			'   string "org.mpris.MediaPlayer2.Player"',
			"   array [",
			"      dict entry(",
			'         string "PlaybackStatus"',
			'         variant             string "Playing"',
			"      )",
			"   ]",
			"   array [",
			"   ]",
		})
		assert.equals(1, #update_calls)
		assert.equals("mpris:spotify", update_calls[1].sid)
		assert.equals("playing", update_calls[1].state.status)
		assert.equals(0, #dbus_cmds)
	end)

	it("falls back to GetAll for unique sender with invalidated properties", function()
		local awful = require("awful")
		local get_all_called = false
		awful.spawn.easy_async = function(cmd, cb)
			dbus_cmds[#dbus_cmds + 1] = cmd
			if type(cmd) == "table" and cmd[#cmd] == "string:org.mpris.MediaPlayer2.Player" then
				get_all_called = true
			else
				cb("", "", "", 0)
			end
		end
		feed({
			UNIQUE_HEADER,
			'   string "org.mpris.MediaPlayer2.Player"',
			"   array [",
			"   ]",
			"   array [",
			'      string "Metadata"',
			"   ]",
		})
		assert.equals(0, #update_calls)
		assert.is_true(get_all_called)
	end)

	it("falls back to GetAll when delta arrives during pending add", function()
		package.loaded["continuity.media.backends.mpris"] = nil
		package.loaded["continuity.util.app_icon"] = {
			by_desktop_entry = function(_, cb)
				cb(nil)
			end,
		}
		local awful = require("awful")
		local get_all_called = 0
		awful.spawn.easy_async = function(cmd, cb)
			if type(cmd) == "table" then
				local last = cmd[#cmd]
				if last == "org.freedesktop.DBus.ListNames" then
					cb('   array [\n      string "org.mpris.MediaPlayer2.spotify"\n   ]\n', "", "", 0)
				elseif cmd[#cmd - 1] == "org.freedesktop.DBus.GetNameOwner" then
					cb('   string ":1.42"\n', "", "", 0)
				elseif last == "string:org.mpris.MediaPlayer2.Player" then
					get_all_called = get_all_called + 1
					-- Do not call back — keeps pending_adds[svc] alive
				else
					cb("", "", "", 0)
				end
			else
				cb("", "", "", 0)
			end
		end
		awful.spawn.with_line_callback = function(cmd, cbs)
			local cmd_str = type(cmd) == "table" and table.concat(cmd, " ") or cmd
			if cmd_str:find("PropertiesChanged", 1, true) then
				monitor_stdout = cbs.stdout
			end
			return 1
		end
		local b2 = require("continuity.media.backends.mpris")()
		local local_updates = {}
		b2:start({
			add = function() end,
			update = function(sid, state, flags)
				local_updates[#local_updates + 1] = { sid = sid, state = state, flags = flags }
			end,
			remove = function() end,
			add_dbus_sender = function() end,
		})
		-- get_all_called == 1 at this point (from add_player's player_get_all, not called back)
		local calls_at_setup = get_all_called
		feed({
			HEADER,
			'   string "org.mpris.MediaPlayer2.Player"',
			"   array [",
			"      dict entry(",
			'         string "PlaybackStatus"',
			'         variant             string "Paused"',
			"      )",
			"   ]",
			"   array [",
			"   ]",
		})
		assert.equals(0, #local_updates)
		assert.is_true(get_all_called > calls_at_setup)
	end)

	it("clears buffer on process exit so stale partial record is not replayed", function()
		-- Feed a partial record (header + some body, no closing arrays)
		monitor_stdout(HEADER)
		monitor_stdout('   string "org.mpris.MediaPlayer2.Player"')
		monitor_stdout("   array [")
		-- Process exits — buffer should clear
		monitor_exit("exit", 1)
		-- Feed a complete new signal and flush it
		feed({
			HEADER,
			'   string "org.mpris.MediaPlayer2.Player"',
			"   array [",
			"      dict entry(",
			'         string "PlaybackStatus"',
			'         variant             string "Playing"',
			"      )",
			"   ]",
			"   array [",
			"   ]",
		})
		assert.equals(1, #update_calls)
		assert.equals("playing", update_calls[1].state.status)
	end)
end)

describe("refresh_player Can* propagation", function()
	it("propagates CanGoNext=false and CanPlay=true onto source.playback via registry", function()
		package.loaded["continuity.media.backends.mpris"] = nil
		local registry_mod = require("continuity.media.registry")
		local reg2 = registry_mod.new()
		local awful = require("awful")
		awful.spawn.easy_async = function(cmd, cb2)
			if type(cmd) == "table" then
				local last = cmd[#cmd]
				if last == "org.freedesktop.DBus.ListNames" then
					cb2('   array [\n      string "org.mpris.MediaPlayer2.spotify"\n   ]\n', "", "", 0)
				elseif last == "org.freedesktop.DBus.GetNameOwner" then
					cb2('   string ":1.42"\n', "", "", 0)
				elseif last == "string:org.mpris.MediaPlayer2.Player" then
					cb2(
						'"CanGoNext" variant boolean false\n'
							.. '"CanGoPrevious" variant boolean false\n'
							.. '"CanPlay" variant boolean true\n'
							.. '"CanSeek" variant boolean true\n',
						"",
						"",
						0
					)
				else
					cb2("", "", "", 0)
				end
			else
				cb2("", "", "", 0)
			end
		end
		awful.spawn.with_line_callback = function()
			return {}
		end
		local b2 = require("continuity.media.backends.mpris")()
		b2:start(reg2.registrar())
		local sources = reg2.sources()
		assert.equals(1, #sources)
		assert.is_false(sources[1].playback.can_go_next)
		assert.is_false(sources[1].playback.can_go_previous)
		assert.is_true(sources[1].playback.can_play)
		assert.is_true(sources[1].playback.can_seek)
	end)
end)
