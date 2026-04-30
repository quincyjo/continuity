-- Coalescer proxy factory.
-- Produces an intercepting SourceRegistrar that merges multiple configured
-- backend sources into a single unified MediaSource per configured id.
-- All capability routing and backend priority-switching state is self-contained.

---@class MediaSourceConfig
---@field id        string    -- unified source ID exposed to consumers
---@field name?     string    -- display name; falls back to first backend's name
---@field app_name? string    -- app identity for notification suppression; falls back to first backend's app_name
---@field backends  string[]  -- backend source IDs that feed this unified source

---@class Coalescer
---@field make_registrar fun(inner: SourceRegistrar): SourceRegistrar

local coalescer = {}

---@param source_configs MediaSourceConfig[]
---@return Coalescer
function coalescer.new(source_configs)
	local reverse_map = {} -- backend_id -> unified_id (first-config-wins)
	local config_name = {} -- unified_id -> configured display name
	local config_app_name = {} -- unified_id -> configured app name
	local source_config = {} -- unified_id -> MediaSourceConfig

	for _, cfg in ipairs(source_configs) do
		config_name[cfg.id] = cfg.name
		config_app_name[cfg.id] = cfg.app_name
		source_config[cfg.id] = cfg
		for _, backend_id in ipairs(cfg.backends) do
			if not reverse_map[backend_id] then
				reverse_map[backend_id] = cfg.id
			end
		end
	end

	return {
		---@param inner SourceRegistrar
		---@return SourceRegistrar
		make_registrar = function(inner)
			---@type table<string, table<string, boolean>>
			local active = {} -- unified_id -> { backend_id = true }
			---@type table<string, SourceCapabilities>
			local source_capabilities = {} -- backend_id -> SourceCapabilities
			---@type table<string, string>
			local position_owner = {} -- unified_id -> backend_id currently subscribed
			---@type table<string, function>
			local position_stop = {} -- unified_id -> stop_fn
			---@type table<string, function>
			local position_cb = {} -- unified_id -> cb retained for re-routing
			---@type table<string, string>
			local playback_owner = {} -- unified_id -> backend_id

			local function update_position_owner(unified_id)
				local cfg = source_config[unified_id]
				if not cfg then
					return
				end
				local active_set = active[unified_id]
				for _, raw_id in ipairs(cfg.backends) do
					if active_set and active_set[raw_id] then
						local c = source_capabilities[raw_id]
						if c and c.position and c.position.subscribe then
							position_owner[unified_id] = raw_id
							return
						end
					end
				end
				position_owner[unified_id] = nil
			end

			local function update_playback_owner(unified_id)
				local cfg = source_config[unified_id]
				if not cfg then
					return
				end
				local active_set = active[unified_id]
				for _, raw_id in ipairs(cfg.backends) do
					if active_set and active_set[raw_id] then
						local c = source_capabilities[raw_id]
						if c and c.playback then
							playback_owner[unified_id] = raw_id
							return
						end
					end
				end
				playback_owner[unified_id] = nil
			end

			local function make_merged_position(unified_id)
				return {
					subscribe = function(_, cb)
						local owner = position_owner[unified_id]
						position_cb[unified_id] = cb
						if owner then
							position_stop[unified_id] = source_capabilities[owner].position.subscribe(owner, cb)
						end
						return function()
							position_cb[unified_id] = nil
							if position_stop[unified_id] then
								position_stop[unified_id]()
								position_stop[unified_id] = nil
							end
						end
					end,

					get = function(_, cb)
						local owner = position_owner[unified_id]
						if owner then
							source_capabilities[owner].position.get(owner, cb)
						else
							cb(nil)
						end
					end,
				}
			end

			local function make_merged_playback(unified_id)
				local function dispatch(action, ...)
					local owner = playback_owner[unified_id]
					if owner and source_capabilities[owner] and source_capabilities[owner].playback then
						source_capabilities[owner].playback[action](owner, ...)
					end
				end
				return {
					play = function(_)
						dispatch("play")
					end,
					pause = function(_)
						dispatch("pause")
					end,
					play_pause = function(_)
						dispatch("play_pause")
					end,
					stop = function(_)
						dispatch("stop")
					end,
					next = function(_)
						dispatch("next")
					end,
					previous = function(_)
						dispatch("previous")
					end,
					seek = function(_, s)
						dispatch("seek", s)
					end,
					set_position = function(_, s)
						dispatch("set_position", s)
					end,
				}
			end

			local function sync_playback_flags(unified_id)
				local owner = playback_owner[unified_id]
				if owner then
					local flags = source_capabilities[owner] and source_capabilities[owner].flags
					if flags then
						inner.update(unified_id, {}, flags)
					end
				else
					inner.update(unified_id, {}, { can_control = false })
				end
			end

			local registrar = {}

			function registrar.add(backend_id, name, state, capabilities, app_name)
				if capabilities then
					source_capabilities[backend_id] = capabilities
				end

				local unified_id = reverse_map[backend_id]
				if not unified_id then
					return inner.add(backend_id, name, state, capabilities, app_name)
				end

				if active[unified_id] == nil then
					-- First add: inner.add receives initial flags
					local display_name = config_name[unified_id] or name
					local unified_app_name = config_app_name[unified_id] or app_name
					active[unified_id] = {}
					inner.add(unified_id, display_name, state, {
						position = make_merged_position(unified_id),
						playback = make_merged_playback(unified_id),
						flags = capabilities and capabilities.flags or nil,
					}, unified_app_name)
					active[unified_id][backend_id] = true
					update_playback_owner(unified_id)
				else
					-- Subsequent add: sync flags if ownership changes
					inner.update(unified_id, state)
					active[unified_id][backend_id] = true
					local old_pb_owner = playback_owner[unified_id]
					update_playback_owner(unified_id)
					if playback_owner[unified_id] ~= old_pb_owner then
						sync_playback_flags(unified_id)
					end
				end

				-- Re-route position if new backend outranks current owner
				local old_pos_owner = position_owner[unified_id]
				update_position_owner(unified_id)
				local new_pos_owner = position_owner[unified_id]
				if position_cb[unified_id] and new_pos_owner ~= old_pos_owner then
					if position_stop[unified_id] then
						position_stop[unified_id]()
						position_stop[unified_id] = nil
					end
					if new_pos_owner then
						position_stop[unified_id] = source_capabilities[new_pos_owner].position.subscribe(
							new_pos_owner,
							position_cb[unified_id]
						)
					end
				end
			end

			function registrar.update(backend_id, partial_state, flags)
				local unified_id = reverse_map[backend_id]
				if not unified_id then
					return inner.update(backend_id, partial_state, flags)
				end
				if active[unified_id] == nil or not active[unified_id][backend_id] then
					return
				end
				local forwarded_flags = playback_owner[unified_id] == backend_id and flags or nil
				inner.update(unified_id, partial_state, forwarded_flags)
			end

			function registrar.remove(backend_id)
				local unified_id = reverse_map[backend_id]
				if not unified_id then
					source_capabilities[backend_id] = nil
					return inner.remove(backend_id)
				end
				if active[unified_id] == nil or not active[unified_id][backend_id] then
					return
				end

				active[unified_id][backend_id] = nil
				source_capabilities[backend_id] = nil
				local old_pb_owner = playback_owner[unified_id]
				update_playback_owner(unified_id)

				-- Re-route position if removed backend was the owner
				local old_pos_owner = position_owner[unified_id]
				update_position_owner(unified_id)
				local new_pos_owner = position_owner[unified_id]
				if position_cb[unified_id] and new_pos_owner ~= old_pos_owner then
					if position_stop[unified_id] then
						position_stop[unified_id]()
						position_stop[unified_id] = nil
					end
					if new_pos_owner then
						position_stop[unified_id] = source_capabilities[new_pos_owner].position.subscribe(
							new_pos_owner,
							position_cb[unified_id]
						)
					end
				end

				if next(active[unified_id]) == nil then
					-- Last backend: send can_control=false before inner.remove
					sync_playback_flags(unified_id)
					if position_stop[unified_id] then
						position_stop[unified_id]()
					end
					active[unified_id] = nil
					position_cb[unified_id] = nil
					position_owner[unified_id] = nil
					position_stop[unified_id] = nil
					playback_owner[unified_id] = nil
					inner.remove(unified_id)
				elseif playback_owner[unified_id] ~= old_pb_owner then
					-- Ownership changed: sync new owner's flags
					sync_playback_flags(unified_id)
				end
			end

			function registrar.add_dbus_sender(backend_id, unique_name)
				local unified_id = reverse_map[backend_id]
				inner.add_dbus_sender(unified_id or backend_id, unique_name)
			end

			return registrar
		end,
	}
end

return coalescer
