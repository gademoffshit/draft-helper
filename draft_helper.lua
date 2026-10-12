--[[
     Ghost
     draft picks, item builds and auto buy for Umbrella (Dota 2)
     github.com/gademoffshit/draft-helper
]]

--[[
     ~ qLocalization
     ~ automatic localization wrapper for Lua menu interfaces

     ~ author: qfun (qfun_g9s)
]]

local qLocalization = (function()
	local lib = {}

	local a = function(...)
		return ...
	end

	local state = {
		lang = Menu.Find("SettingsHidden", "", "", "", "Main", "Language"),
		instances = {},
	}

	local setters = {
		ToolTip = "tooltip",
	}

	local helpers
	do
		helpers = {
			resolve = a(function(root, path)
				for key in path:gmatch("[^.]+") do
					if type(root) ~= "table" then
						return
					end

					root = root[key]
				end

				return root
			end),

			is_object = a(function(value)
				return type(value) == "table" or type(value) == "userdata"
			end),

			has_method = a(function(object, name)
				return helpers.is_object(object) and type(object[name]) == "function"
			end),

			is_menu_object = a(function(value)
				return helpers.has_method(value, "Name") and helpers.has_method(value, "Type")
			end),

			is_list = a(function(value)
				if type(value) ~= "table" or #value == 0 then
					return false
				end

				for i = 1, #value do
					if type(value[i]) ~= "string" then
						return false
					end
				end

				return true
			end),

			is_indexed_list = a(function(object)
				return helpers.has_method(object, "List") and not helpers.has_method(object, "ListEnabled")
			end),
		}
	end

	function lib.new(translations)
		local languages = {}

		for i, name in ipairs(state.lang and state.lang:List() or {}) do
			local code = name:match("%a+")

			if code and translations[code] then
				languages[i - 1] = code
			end
		end

		local localization = {
			translations = translations,
			languages = languages,
			objects = {},
		}

		local methods
		do
			methods = {
				get_language = a(function(language_index)
					if language_index == nil and state.lang then
						language_index = state.lang:Get()
					end

					return localization.languages[language_index] or "en"
				end),

				localize = a(function(path, language_index)
					if type(path) ~= "string" then
						return path
					end

					local language = methods.get_language(language_index)

					return helpers.resolve(localization.translations[language], path)
						or helpers.resolve(localization.translations.en, path)
						or path
				end),

				has = a(function(path)
					if type(path) ~= "string" then
						return false
					end

					return helpers.resolve(localization.translations.en, path) ~= nil
						or helpers.resolve(localization.translations[methods.get_language()], path) ~= nil
				end),

				localize_items = a(function(items, language_index)
					local result, localized = {}, false

					for i = 1, #items do
						local value = items[i]

						if methods.has(value) then
							result[i] = methods.localize(value, language_index)
							localized = true
						else
							result[i] = value
						end
					end

					return result, localized
				end),

				apply = a(function(object, kind, path, language_index)
					if kind == "label" then
						object:ForceLocalization(methods.localize(path, language_index))
					elseif kind == "tooltip" then
						object:ToolTip(methods.localize(path, language_index))
					elseif kind == "items" then
						local value = object:Get()

						object:Update((methods.localize_items(path, language_index)))
						object:Set(value)
					end
				end),

				track = a(function(object, kind, path, apply_now)
					local record = localization.objects[object]

					if record == nil then
						record = {}
						localization.objects[object] = record
					end

					record[kind] = path

					if apply_now then
						methods.apply(object, kind, path)
					end
				end),

				register = a(function(object, path)
					if not methods.has(path) or not helpers.has_method(object, "ForceLocalization") then
						return
					end

					methods.track(object, "label", path, true)
				end),

				update = a(function(language_index)
					for object, record in pairs(localization.objects) do
						for kind, path in pairs(record) do
							methods.apply(object, kind, path, language_index)
						end
					end
				end),

				wrap = a(function(target, bind_self)
					if not helpers.is_object(target) then
						return target
					end

					local proxy

					proxy = setmetatable({}, {
						__index = function(_, key)
							local member = target[key]

							if type(member) ~= "function" then
								return member
							end

							return function(...)
								local args = table.pack(...)

								if bind_self and args[1] == proxy then
									table.remove(args, 1)
									args.n = args.n - 1
								end

								if key == "Switch" and args.n < 2 then
									args[2] = false
									args.n = 2
								end

								local name_path, item_paths

								if setters[key] then
									if methods.has(args[1]) then
										methods.track(target, setters[key], args[1], false)

										args[1] = methods.localize(args[1])
									end
								else
									local name_index = bind_self and 1 or args.n

									if methods.has(args[name_index]) then
										name_path = args[name_index]
									end

									local items_index

									if key == "Combo" then
										items_index = 2
									elseif key == "Update" and helpers.is_indexed_list(target) then
										items_index = 1
									end

									if items_index ~= nil and helpers.is_list(args[items_index]) then
										local items, localized = methods.localize_items(args[items_index])

										if localized then
											item_paths = args[items_index]
											args[items_index] = items
										end
									end
								end

								local results

								if bind_self then
									results = table.pack(member(target, table.unpack(args, 1, args.n)))
								else
									results = table.pack(member(table.unpack(args, 1, args.n)))
								end

								for i = 1, results.n do
									local result = results[i]

									if helpers.is_menu_object(result) then
										if name_path then
											methods.register(result, name_path)
										end

										if item_paths then
											methods.track(result, "items", item_paths, false)
											item_paths = nil
										end

										results[i] = methods.wrap(result, true)
									end
								end

								if item_paths then
									methods.track(target, "items", item_paths, false)
								end

								return table.unpack(results, 1, results.n)
							end
						end,

						__newindex = function(_, key, value)
							target[key] = value
						end,
					})

					return proxy
				end),
			}
		end

		state.instances[methods] = true

		return {
			GetLanguage = methods.get_language,

			Get = methods.localize,
			Localize = methods.localize,

			Update = methods.update,
			Register = methods.register,

			Wrap = methods.wrap,

			WrapLibrary = function(library)
				return methods.wrap(library, false)
			end,
		}
	end

	if state.lang then
		state.lang:SetCallback(function(this)
			local language_index = this:Get()

			for methods in pairs(state.instances) do
				methods.update(language_index)
			end
		end, true)
	else
		Log.Write("[qLocalization] Language widget not found, using English fallback")
	end

	return lib
end)()

local Config = Config
local JSON = {}
do
	local byte, sub, find, char, format, concat, sort = string.byte, string.sub, string.find, string.char, string.format, table.concat, table.sort
	local mtype, floor, huge = math.type, math.floor, math.huge
	local unescape = { [34] = '"', [92] = "\\", [47] = "/", [98] = "\b", [102] = "\f", [110] = "\n", [114] = "\r", [116] = "\t" }
	local escape = { ['"'] = '\\"', ["\\"] = "\\\\", ["\b"] = "\\b", ["\f"] = "\\f", ["\n"] = "\\n", ["\r"] = "\\r", ["\t"] = "\\t" }

	local function fail(text, pos, what)
		error(format("JSON %s at byte %d of %d", (pos or 0) > #text and "cut off" or what, pos or 0, #text), 0)
	end

	local function utf8_char(cp)
		if cp < 0x80 then
			return char(cp)
		elseif cp < 0x800 then
			return char(0xC0 | (cp >> 6), 0x80 | (cp & 0x3F))
		elseif cp < 0x10000 then
			return char(0xE0 | (cp >> 12), 0x80 | ((cp >> 6) & 0x3F), 0x80 | (cp & 0x3F))
		end
		return char(0xF0 | (cp >> 18), 0x80 | ((cp >> 12) & 0x3F), 0x80 | ((cp >> 6) & 0x3F), 0x80 | (cp & 0x3F))
	end

	local function skip(text, pos)
		return find(text, "[^ \t\r\n]", pos) or #text + 1
	end

	local function read_string(text, pos)
		local i, parts, n = pos + 1, nil, 0
		while true do
			local a = find(text, '["\\]', i)
			if not a then
				fail(text, #text + 1, "cut off")
			end
			if byte(text, a) == 34 then
				if not parts then
					return sub(text, i, a - 1), a + 1
				end
				n = n + 1
				parts[n] = sub(text, i, a - 1)
				return concat(parts, "", 1, n), a + 1
			end
			parts = parts or {}
			n = n + 1
			parts[n] = sub(text, i, a - 1)
			local c = byte(text, a + 1)
			if c == 117 then
				local cp = tonumber(sub(text, a + 2, a + 5), 16)
				if not cp then
					fail(text, a + 6 > #text and #text + 1 or a, "bad escape")
				end
				local nxt = a + 6
				if cp >= 0xD800 and cp <= 0xDBFF and sub(text, nxt, nxt + 1) == "\\u" then
					local lo = tonumber(sub(text, nxt + 2, nxt + 5), 16)
					if lo and lo >= 0xDC00 and lo <= 0xDFFF then
						cp = 0x10000 + (cp - 0xD800) * 0x400 + (lo - 0xDC00)
						nxt = nxt + 6
					end
				end
				n = n + 1
				parts[n] = utf8_char(cp)
				i = nxt
			else
				local e = c and unescape[c]
				if not e then
					fail(text, c and a or #text + 1, "bad escape")
				end
				n = n + 1
				parts[n] = e
				i = a + 2
			end
		end
	end

	local read_value

	function read_value(text, pos)
		pos = skip(text, pos)
		local c = byte(text, pos)
		if c == 34 then
			return read_string(text, pos)
		elseif c == 123 then
			local obj = {}
			pos = skip(text, pos + 1)
			if byte(text, pos) == 125 then
				return obj, pos + 1
			end
			while true do
				if byte(text, pos) ~= 34 then
					fail(text, pos, "expected a key")
				end
				local key
				key, pos = read_string(text, pos)
				pos = skip(text, pos)
				if byte(text, pos) ~= 58 then
					fail(text, pos, "expected ':'")
				end
				local val
				val, pos = read_value(text, pos + 1)
				obj[key] = val
				pos = skip(text, pos)
				c = byte(text, pos)
				if c == 44 then
					pos = skip(text, pos + 1)
				elseif c == 125 then
					return obj, pos + 1
				else
					fail(text, pos, "expected ',' or '}'")
				end
			end
		elseif c == 91 then
			local arr, n = {}, 0
			pos = skip(text, pos + 1)
			if byte(text, pos) == 93 then
				return arr, pos + 1
			end
			while true do
				local val
				val, pos = read_value(text, pos)
				n = n + 1
				arr[n] = val
				pos = skip(text, pos)
				c = byte(text, pos)
				if c == 44 then
					pos = pos + 1
				elseif c == 93 then
					return arr, pos + 1
				else
					fail(text, pos, "expected ',' or ']'")
				end
			end
		elseif c == 45 or (c and c >= 48 and c <= 57) then
			local a, b = find(text, "^-?%d+%.?%d*[eE]?[-+]?%d*", pos)
			local num = a and tonumber(sub(text, a, b))
			if not num then
				fail(text, pos, "bad number")
			end
			return num, b + 1
		elseif c == 116 and sub(text, pos, pos + 3) == "true" then
			return true, pos + 4
		elseif c == 102 and sub(text, pos, pos + 4) == "false" then
			return false, pos + 5
		elseif c == 110 and sub(text, pos, pos + 3) == "null" then
			return nil, pos + 4
		end
		fail(text, pos, "unexpected character")
	end

	function JSON.decode(_, text)
		if type(text) ~= "string" then
			error("JSON input is " .. type(text), 0)
		end
		local value, pos = read_value(text, 1)
		pos = skip(text, pos)
		if pos <= #text then
			fail(text, pos, "trailing garbage")
		end
		return value
	end

	local function esc(c)
		return escape[c] or format("\\u%04x", byte(c))
	end

	local write

	function write(v, out, n, seen)
		local t = type(v)
		if t == "string" then
			n = n + 1
			out[n] = '"' .. v:gsub('[\0-\31"\\]', esc) .. '"'
		elseif t == "number" then
			n = n + 1
			if v ~= v then
				out[n] = "null"
			elseif v >= huge then
				out[n] = "1e+9999"
			elseif v <= -huge then
				out[n] = "-1e+9999"
			elseif mtype(v) == "integer" then
				out[n] = format("%d", v)
			else
				local s = format("%.17g", v)
				if tonumber(format("%.14g", v)) == v then
					s = format("%.14g", v)
				end
				if not find(s, "[%.eEn]") then
					s = s .. ".0"
				end
				out[n] = s
			end
		elseif t == "boolean" then
			n = n + 1
			out[n] = v and "true" or "false"
		elseif t == "table" then
			if seen[v] then
				error("JSON can't encode a table that contains itself", 0)
			end
			seen[v] = true
			local strs, nums, max, bad, other = {}, 0, 0, false, false
			for k in pairs(v) do
				local kt = type(k)
				if kt == "string" then
					strs[#strs + 1] = k
				elseif kt == "number" then
					nums = nums + 1
					if k <= 0 or k >= huge or mtype(k) ~= "integer" then
						bad = true
					elseif k > max then
						max = k
					end
				elseif kt == "boolean" then
					other = true
				else
					error("JSON can't encode a table key of type " .. kt, 0)
				end
			end
			if #strs == 0 and not bad and not other then
				n = n + 1
				out[n] = "["
				for i = 1, max do
					if i > 1 then
						n = n + 1
						out[n] = ","
					end
					if v[i] == nil then
						n = n + 1
						out[n] = "null"
					else
						n = write(v[i], out, n, seen)
					end
				end
				n = n + 1
				out[n] = "]"
			else
				local map = v
				if nums > 0 or other then
					map = {}
					for k, val in pairs(v) do
						map[type(k) == "string" and k or tostring(k)] = val
					end
					strs = {}
					for k in pairs(map) do
						strs[#strs + 1] = k
					end
				end
				sort(strs)
				n = n + 1
				out[n] = "{"
				for i, k in ipairs(strs) do
					if i > 1 then
						n = n + 1
						out[n] = ","
					end
					n = n + 1
					out[n] = '"' .. k:gsub('[\0-\31"\\]', esc) .. '":'
					local val = map[k]
					if val == nil then
						n = n + 1
						out[n] = "null"
					else
						n = write(val, out, n, seen)
					end
				end
				n = n + 1
				out[n] = "}"
			end
			seen[v] = nil
		elseif v == nil then
			n = n + 1
			out[n] = "null"
		else
			error("JSON can't encode a " .. t, 0)
		end
		return n
	end

	function JSON.encode(_, value)
		local out = {}
		local n = write(value, out, 0, {})
		return concat(out, "", 1, n)
	end
end

local localization = qLocalization.new({
	en = {
		cd_group_main = "Main",
		cd_enable = "Enable",
		cd_enable_tip = "Turns Ghost on",
		cd_key = "Open window",
		cd_key_tip = "Opens and closes the draft window",
		cd_bind_name = "Ghost",
		["Draft Helper"] = "Ghost",

		cd_mode_order = "In turns",
		cd_mode_free = "Free",
		cd_bans = "Bans",
		cd_tip_mode_t = "Draft mode",
		cd_tip_mode = "Set by the game: Captains Mode goes in turns,\nevery other mode is a free pick",
		cd_gm_ap = "All Pick",
		cd_gm_cm = "Captains Mode",
		cd_gm_rd = "Random Draft",
		cd_gm_sd = "Single Draft",
		cd_gm_ar = "All Random",
		cd_gm_rcm = "Reverse Captains Mode",
		cd_gm_cd = "Captains Draft",
		cd_gm_ad = "Ability Draft",
		cd_gm_rap = "Ranked All Pick",
		cd_gm_turbo = "Turbo",
		cd_tip_tent_t = "Ally is choosing",
		cd_tip_tent = "The game has not revealed the hero yet,\nit can still change",
		cd_tip_slot_t = "Slot",
		cd_tip_free = "Click an empty slot to fill it,\nright click clears it",
		cd_title = "Draft",
		cd_first = "First pick",
		cd_us = "We",
		cd_enemy = "Enemy",
		cd_chance = "draft win chance",
		cd_replace = "Replace",
		cd_done = "Draft complete",
		cd_done_tip = "right click on a slot clears it",
		cd_search = "Type a hero, Enter puts it in the turn",
		cd_attr_str = "STRENGTH",
		cd_attr_agi = "AGILITY",
		cd_attr_int = "INTELLECT",
		cd_attr_all = "UNIVERSAL",
		cd_t_pick = "Who to pick",
		cd_s_pick = "counters to the enemy draft, then synergy",
		cd_t_ban = "Who to ban",
		cd_s_ban = "best picks for the enemy against us",
		cd_t_epick = "Enemy pick",
		cd_s_epick = "best picks for the enemy against us",
		cd_t_eban = "Enemy ban",
		cd_s_eban = "our best picks they may take away",
		cd_on = "%s for %s",
		cd_posT1 = "Carry",
		cd_posT2 = "Mid",
		cd_posT3 = "Offlane",
		cd_posT4 = "Soft support",
		cd_posT5 = "Hard support",
		cd_tip_badge_t = "Hero position",
		cd_tip_badge = "Click to set the position by hand,\nright click returns auto",
		cd_tip_pm_auto = "Position from hero stats and lineup",
		cd_tip_pm = "Lock the hero on this position",
		cd_tip_auto_t = "Auto",
		cd_tip_auto = "The script picks the position\nthat fits our lineup",
		cd_tip_pick = "Heroes for this position.\nUnder the top ones, who fits with them",
		cd_tip_ban = "Strong heroes against us\nthat play this position",
		cd_tip_taken = "Now %s plays here,\npicking it moves him to a free position",
		cd_tip_close_t = "Close",
		cd_nav_build_t = "Build",
		cd_tip_nav_draft_t = "Draft",
		cd_tip_nav_draft = "Picks and bans for this draft",
		cd_tip_nav_build_t = "Build",
		cd_tip_nav_build = "Your hero's build for this draft",
		cd_tip_grid_t = "All heroes",
		cd_tip_grid = "Show the hero grid, typing opens it too",
		cd_side_build = "BUILD",
		cd_side_empty = "The hero's build shows here",
		cd_side_core = "Core",
		cd_side_vs = "For these heroes",
		cd_side_skills = "Skills",
		cd_side_sub = "pos %d, %d pro games",
		cd_side_pos = "pos %d",
		cd_side_open = "Full build",
		cd_slot_now = "Picking now",
		cd_slot_empty = "empty",
		cd_tip_close = "Hides the window,\nit opens again with the key from the menu",
		cd_tip_undo_t = "Undo turn",
		cd_tip_undo = "Removes the last entered hero",
		cd_tip_reset_t = "Reset draft",
		cd_tip_reset = "Clears all picks and bans",
		cd_tip_first_t = "First pick",
		cd_tip_first = "Who bans and picks first.\nIt sets the order of turns",
		cd_auto_pos = "auto",
		cd_pos1 = "carry",
		cd_pos2 = "mid",
		cd_pos3 = "offlane",
		cd_pos4 = "soft support",
		cd_pos5 = "hard support",
		cd_acc1 = "carry",
		cd_acc2 = "mid",
		cd_acc3 = "offlane",
		cd_acc4 = "soft support",
		cd_acc5 = "hard support",
		cd_vs = "vs",
		cd_with = "with",
		cd_weak = "weak vs",
		cd_bad_with = "bad with",
		cd_with_him = "with him",
		cd_pro = "pro drafts %d%%",
		cd_rate = "win rate %.1f%%",
		cd_tip_num_t = "%s from the draft",
		cd_tip_num = "How counters and synergy change the win chance.\nHero win rate %s over %s matches",
		cd_matches = "%s matches",
		cd_empty = "No fitting heroes",
		cd_ld_heroes = "Loading heroes",
		cd_ld_pro = "Loading pro matches",
		cd_ld_matches = "Loading matches",
		cd_ld_build = "Counting stats",
		cd_ld_wait = "Preparing data",
		cd_ld_count = "%s of %s",
		cd_ld_first = "The first time takes a couple of minutes, then it loads from cache",
		cd_ld_error = "No connection to OpenDota",
		cd_p_retry = "Retrying every few seconds. Check VPN or proxy",
		cd_p_wait = "The hero's build is downloading from OpenDota",
		cd_ld_slow = "OpenDota is slow to answer",
		cd_tip_err_t = "Why",
		cd_ld_retry = "retry in %d s",
		cd_ld_short = "matches %d%%",
		cd_src_short0 = "Ranked",
		cd_rk0 = "All",
		cd_rk1 = "Ancient+",
		cd_rk2 = "Divine+",
		cd_rk3 = "Divine 5+",
		cd_set_source = "Matches",
		cd_set_rank = "Rank",
		cd_set_scale = "Size",
		cd_set_tips = "Hints",
		cd_set_blur = "Background blur",
		cd_set_auto = "Open on hero pick",
		cd_tip_settings_t = "Settings",
		cd_tip_settings = "Data, window look and behavior",
		cd_s_none = "no picks yet, sorted by hero win rate",
		cd_tip_wr_t = "Win rate %s",
		cd_tip_wr = "%s matches at the chosen rank.\nCounters show up after the first picks",
		cd_set_title = "Settings",
		cd_sec_data = "DATA",
		cd_set_volume = "Volume",
		cd_set_volume_tip = "more matches, steadier numbers",
		cd_set_bg = "Background",
		cd_set_debug = "Debug log",
		cd_set_logauto = "Send match data to the author",
		cd_tip_logauto = "After every match Ghost sends the author its match record\n(draft, purchases, the build plan as it changed) and its log.\nErrors are sent too. No nick or Steam ID",
		cd_set_log = "Log for the author",
		cd_tip_log = "Sends the Ghost log, settings and errors\nto the author right now. No nick or Steam ID",
		cd_log_send = "Send",
		cd_log_sending = "Sending",
		cd_log_sent = "Log sent, thank you",
		cd_log_wait = "The log was just sent, try again in a minute",
		cd_log_saved = "Could not send now, will retry later. Log: configs\\draft_helper_log.txt",
		cd_log_fail = "Could not send the log",
		cd_set_refresh = "Update",
		cd_src_long1 = "Captains Mode",
		cd_upd_now = "updated just now",
		cd_upd_min = "updated %d min ago",
		cd_upd_hour = "updated %d h ago",
		cd_upd_day = "updated %d d ago",
		cd_upd_never = "not loaded yet",
		cd_eta_s = "about %d s left",
		cd_eta_m = "about %d min left",
		cd_eta_short_s = "about %d s",
		cd_eta_short_m = "about %d min",
		cd_ld_days = "%s over %d of %d days",
		cd_cm_now = "Now %s over %d of %d days",
		cd_cm_done = "Loaded %s over %d days",
		cd_cm_total = "about %s in the end",
		cd_cm_wait = "Loading, this takes a few minutes",
		cd_cm_why = "Few CM games, about %d a day, hero pairs lean on ranked",
		cd_cm_why0 = "Few CM games, hero pairs lean on ranked matches",
		cd_lang = "en",
		cd_upd_failed = "Update failed, trying again",
		cd_pill_get = "Version %s installs after the match",
		cd_pill_down = "Downloading %s",
		cd_pill_done = "Updated, restarting",
		cd_upd_loading = "loading",
		cd_sum_t = "Draft summary",
		cd_sum_chance = "win chance",
		cd_sum_vs = "MATCHUPS",
		cd_sum_vs_sub = "% to the win chance, ours against theirs",
		cd_sum_total = "total",
		cd_sum_hint = "click one of our heroes to see the build",
		cd_tip_cell_t = "%s against %s",
		cd_tip_cell = "%s%% to the win chance\nfrom matches at the chosen rank",
		cd_tip_sum_t = "%s against their draft",
		cd_tip_sum = "Sum over all five enemies.\nClick shows the build for this hero",
		cd_build_sub = "against their pick",
		cd_build_since = "few games this patch, data since %s",
		cd_build_pooled = "%d games here, the rest from pos. %s of this hero",
		cd_p_pooled = "%d + pos. %s",
		cd_build_synth = "%d games here, the rest built for this position from similar heroes",
		cd_p_synth = "%d + similar heroes",
		cd_tip_bpos_synth = "%d matches in this position. The rest: what this position\nusually buys, adjusted to the hero, and similar heroes here",
		cd_tip_bpos_pool = "%d matches in this position, filled up\nwith this hero's pos. %s",
		cd_build_start = "START",
		cd_build_gold = "%d of %d gold",
		cd_build_spare = "keep on hand against",
		cd_build_loading = "Loading items",
		cd_build_none = "Not enough item data for this hero",
		cd_tip_item_vs = "Against %s",
		cd_th_magic = "magic",
		cd_th_disable = "disables",
		cd_th_targeted = "single-target",
		cd_th_silence = "silences",
		cd_th_roots = "roots and disarms",
		cd_th_invis = "invisibility",
		cd_th_evasion = "evasion",
		cd_th_heal = "healing",
		cd_th_illusions = "illusions",
		cd_th_passives = "strong passives",
		cd_th_phys = "right-click",
		cd_th_burst = "right-click burst damage",
		cd_th_pierce = "through BKB",
		cd_th_escape = "escapes and dodges",
		cd_th_saves = "enemy saves",
		cd_tip_after = "Later disassemble into %s",
		cd_tip_upgrade = "Later upgrade into %s",
		cd_tip_up_from = "Upgrade of %s",
		cd_tip_stats = "In %d of %d games, win rate %d%%",
		cd_tip_lift = " (%+d%% vs usual)",
		cd_tip_dis_from = "Disassemble %s and build this",
		cd_p_up = "from %s",
		cd_set_preview = "Panel preview",
		cd_preview_show = "Show",
		cd_preview_hide = "Hide",
		cd_tip_preview = "Shows the panel with a sample build,\nyou can drag it with the mouse",
		cd_p_dis = "disassemble %s",
		cd_tip_swap = "Instead of %s",
		cd_tip_swap_why = "%s has %s",
		cd_p_all = "Build complete",
		cd_tip_skipped = "Skipped for now, it stays at the end",
		cd_set_panel = "In-game build panel",
		cd_set_window = "Draft window",
		cd_sec_view = "WINDOW AND PANEL",
		cd_set_pview = "Look",
		cd_pview0 = "Compact",
		cd_pview1 = "Card",
		cd_pview2 = "Grid",
		cd_p_queue = "NEXT UP",
		cd_p_done = "DONE",
		cd_p_rmb = "right-click an item to buy",
		cd_p_min = "%d min",
		cd_p_by = "by %d min",
		cd_p_have = "%d of %d gathered",
		cd_p_gold = "gold %d",
		cd_card_order = "BUY ORDER",
		cd_card_late = "AFTER 40 MIN",
		cd_card_next = "AFTER THE CORE",
		cd_tip_ext_swap = "Instead of %s",
		cd_card_skills = "SKILLS",
		cd_card_neutral = "NEUTRAL ITEMS",
		cd_card_enemy = "WHAT ENEMIES BUY",
		cd_card_pred = "%s in %d%% of games",
		cd_card_qbuy = "click: add to quick buy, Shift+click: only this item",
		cd_set_pshop = "Only while the shop is open",
		cd_set_padapt = "Adapt to enemy items",
		cd_set_phide = "Hide when the build is complete",
		cd_set_pdanger = "Weigh the most dangerous enemy",
		cd_set_pext = "Keep buying after the core",
		cd_tip_pdanger = "Answers to the items of the enemy with the most kills\nand damage to you weigh more (about +2 points in pro games)",
		cd_tip_pext = "When the core is done, the next items come\nfrom the same pro data, upgrades first",
		cd_danger = "Most dangerous: %s %d/%d",
		cd_danger_att = "hits with attacks",
		cd_danger_spell = "hits with spells",
		cd_danger_tip_t = "Most dangerous enemy",
		cd_danger_tip = "Enemy kills: %d%%, damage to you: %s\nAnswers to his items weigh x%.1f",
		cd_dmg_attack = "attack damage",
		cd_dmg_spell = "spell damage",
		cd_tip_ext = "After the core: %d%% of pros buy it on this hero",
		cd_talent_tier = "Talent (level %d)",
		cd_tip_room = "No free slot: sell something first",
		cd_rep = "Replace: %s → %s",
		cd_rep_tip_t = "This item lost its value",
		cd_rep_why_enemy = "%s has %s, an answer to your %s",
		cd_rep_why_team = "%s already has %s, the auras do not stack",
		cd_rep_do = "Sell %s and buy %s",
		cd_rep_why_mx = "%s in this match: %+.1f points in pro games\nmain reason: %s",
		cd_mx_foe = "%s at %s",
		cd_mx_early = "%s at %s early",
		cd_mx_ally = "%s at ally %s",
		cd_mx_lane = "lane vs %s",
		cd_mx_lane_lost = "lost lane",
		cd_mx_lane_won = "won lane",
		cd_lane_line = "Lane vs %s: %s",
		cd_lane_lost = "lost (%d)",
		cd_lane_won = "won (+%d)",
		cd_lane_even = "even (%+d)",
		cd_lane_unknown = "no fresh enemy XP",
		cd_lane_tip_t = "Your lane",
		cd_lane_tip = "Who stood near you from 1 to 10 min (pro time) and the experience gap\nat 10 min. For reference: in pro games it does not change which items win",
		cd_foe_line = "Enemies: physical %d%% · magic %d%% · HP %d",
		cd_foe_eva = " · evasion %d%% (%s)",
		cd_foe_tip_t = "Enemy defense",
		cd_foe_tip = "Average over the enemies you have seen: damage that gets through\nand max health. Shown for reference: items are picked by the enemy items",
		cd_mx = "Against these enemies: %+.1f points (%s)",
		cd_mx_stun = "heavy control on your team",
		cd_mx_short = "vs enemies %+.1f",
		cd_rep_auto = "Auto buy does it at the base when the gold is there",
		cd_set_abuy_swap = "Replace items that lost their value",
		cd_set_askill = "Level skills and talents",
		cd_set_dmgtrack = "Track damage taken (unsafe)",
		cd_tip_dmgtrack = "Receives damage events from the game server to see who hits you and how.\nNeeds Umbrella unsafe mode and a script reload. Off by default: suspected in network drops",
		cd_tip_askill = "Abilities and talents in the order pros use on this hero and position.\nOff by default: two network drops came right after a level-up order",
		cd_set_pturbo = "Turbo: faster timings",
		cd_tip_pturbo = "In Turbo items come about twice as fast:\npro minutes and thresholds are scaled by 0.45",
		cd_p_title = "Build",
		cd_p_more = "%d more",
		cd_p_enough = "enough gold",
		cd_p_instead = "instead of %s",
		cd_p_preview = "preview",
		cd_p_since = "since %s",
		cd_p_start = "Start",
		cd_build_nopos = "No build for %s",
		cd_build_nopos2 = "the hero is rarely played there, pick another position",
		cd_tip_bpos = "Build from %d matches\nin this position",
		cd_tip_bpos_none = "The hero is rarely played here,\nthere is no build",
		cd_sell = "Sell %s for %s",
		cd_bag = "Move %s to the backpack for %s",
		cd_tip_late = "Owned at the end of %d%% of games\nlonger than 40 min, %d such games",
		cd_tip_sold = "Sold in %d%% of games",
		cd_step_extra = "No slot, usually by %d min",
		cd_set_live = "In-game advice",
		cd_tip_live = "Selling, late game, neutrals,\nskills, timings and falling behind",
		cd_tip_timing = "Usually by %d min, on time %d%% wins, later %d%%",
		cd_tip_behind = "When behind: %d%% wins, usually %d%%",
		cd_state_behind = "Behind on items by %s",
		cd_state_ahead = "Ahead on items by %s",
		cd_state_short = "team",
		cd_state_tip = "Item value of your whole team %.1fk, enemies %.1fk\n(only enemy items seen). This is not your own gold.\n",
		cd_state_tip_behind = "While the team is behind, the build leans to items that win from behind",
		cd_state_tip_ahead = "While the team is ahead, the build keeps the usual pro order",
		cd_late_warn = "%s is late, others get it by %d min",
		cd_tip_swap_behind = "Wins more often when behind",
		cd_tip_swap_late = "Better when items are late",
		cd_tip_swap_react = "Pros pick it more often against this lineup",
		cd_tip_alt = "Or %s: %s",
		cd_alt_vs = "vs %s",
		cd_alt_share = "taken in %d%% of games",
		cd_tip_neutral = "Tier %d, taken in %d%% of games",
		cd_tip_neutral_alt = "If not offered: %s",
		cd_neutral_enh = "Enhancement: %s",
		cd_tip_enh = "Picked in %d%% of games",
		cd_tip_skill = "Level %d, %d%% of players",
		cd_tip_talent = "Talent at level %d, %d%% of players",
		cd_threat_warn = "Enemies have %s (%d): get %s",
		cd_threat_invis_sup = "Enemies go invisible: carry dust and sentries",
		cd_threat_invis_team = "Enemies go invisible and nobody on your team has detection: buy dust",
		cd_set_lanes = "Enemy positions and lanes",
		cd_tip_lanes = "Counters against your lane opponents weigh more,\nitems of enemy supports weigh less",
		cd_set_pick_ask = "Confirm hero pick",
		cd_tip_pick_ask = "Right click on a hero in the list picks it,\nthis asks first",
		cd_set_lang = "Language",
		cd_tip_lang = "Auto follows the Umbrella language",
		cd_lang0 = "Auto",
		cd_lang1 = "English",
		cd_lang2 = "Русский",
		cd_suggest = "Suggest",
		cd_suggest_top = "Suggest top 2",
		cd_suggested = "Suggested",
		cd_tip_suggest = "Marks the hero as suggested for your team,\nlike the game's Suggest Hero button. Click again to take it back",
		cd_tip_suggest_top = "Suggests the first two heroes of this list.\nThe game keeps two suggestions per player",
		cd_sug_sent = "Suggested to the team: %s",
		cd_sug_off = "Suggestion taken back: %s",
		cd_tip_own_start = "You started it yourself: %d%% of the price is in your parts",
		cd_skv_why = "Fits this game: vs %s pros max %s first more often (%d%%, usually %d%%)",
		cd_set_ver = "Ghost %s, updates itself between matches",
		cd_card_head_sub = "plan for this match",
		cd_card_vs = "vs",
		cd_sec_logs = "REPORTS",
		cd_tal_why = "Fits this game: %s, pros take it more often (%d%%, usually %d%%)",
		cd_why_lane = "%s in lane",
		cd_why_lineup = "this lineup",
		cd_why_ahead = "your team is ahead",
		cd_why_behind = "your team is behind",
		cd_tip_own_up = "Upgrade of your %s, pros take it in %d%% of games",
		cd_ban_t = "Hide %s",
		cd_tip_ban = "Left click: never suggest it for %s.\nRight click: for all heroes. Settings list the hidden items",
		cd_ban_one = "Hidden: %s",
		cd_ban_all = "Hidden for all heroes: %s",
		cd_ban_off = "Suggested again: %s",
		cd_sec_bans = "HIDDEN ITEMS",
		cd_bans_none = "Nothing hidden. Hover an item in a build and press the thumb to hide it",
		cd_ban_everyone = "all heroes",
		cd_tip_unban = "Click to suggest it again",
		cd_bans_clear = "Show all",
		cd_bans_hint = "Builds skip these items",
		cd_say_wait = "Wait a couple of seconds",
		cd_set_pup = "Upgrades when the build is done",
		cd_tip_pup = "When the plan runs out: upgrades of owned items\nand a swap of the weakest one if gold allows",
		cd_tip_inslot = "Upgrade in the same slot, from %s",
		cd_tip_inslot_pro = "Pros on this hero take it in %d%% of games",
		cd_tip_inslot_rule = "Few pro games run this long, chosen by the item tree",
		cd_tip_inslot_attr = "This Blink fits your main attribute",
		cd_tip_weak = "Weakest item now: %s",
		cd_tip_dps_more = "Enemies hit harder than their draft suggests: needed x%.1f more",
		cd_tip_dps_less = "Enemy right-click is weaker than their draft suggests: needed x%.1f less",
		cd_tip_buy = "Right click: buy with current gold\nShift+click: reset quick buy to this item",
		cd_buy_gold = "Not enough gold for any part of it",
		cd_buy_secret = "Secret shop only: %s",
		cd_counter_toast = "New counter: %s",
		cd_counter_vs = "%s vs %s (%s)",
		cd_sec_auto = "AUTO BUY",
		cd_set_autobuy = "Buy the build automatically",
		cd_tip_autobuy = "Buys the next item part by part,\nin the order pros buy the parts",
		cd_set_abuy_sell = "Sell what is not needed",
		cd_set_abuy_bb = "Keep gold for buyback",
		cd_set_abuy_tp = "Keep a TP scroll",
		cd_set_abuy_cour = "Send the courier",
		cd_tip_abuy_cour = "Brings stash items to you. Secret shop parts\n(Point Booster, Tiara, Ultimate Orb...) are bought by the courier there",
		cd_tip_stock = "Not in the shop yet, the next item is bought meanwhile",
		cd_tip_bless = "Upgrade of %s: the effect stays and a slot frees up",
		cd_tip_vsh_more = "Against %s pros take it %.1f times more often",
		cd_tip_vsh_less = "Against %s pros take it %.1f times less often",
		cd_tip_vsa_more = "With ally %s pros take it %.1f times more often",
		cd_tip_vsa_less = "With ally %s pros take it %.1f times less often",
		cd_tip_lm_more = "With these heroes pros take it %.1f times more often (mostly because of %s)",
		cd_tip_lm_less = "With these heroes pros take it %.1f times less often (mostly because of %s)",
		cd_tip_lm_ally = "ally %s",
		cd_attr = "+2 to all attributes",
		cd_tip_lr_more = "Enemies have %s: pros take it %.1f times more often",
		cd_tip_lr_less = "Enemies have %s: pros take it %.1f times less often",
		cd_tip_lr_ally_more = "An ally has %s: pros take it %.1f times more often",
		cd_tip_lr_ally_less = "An ally has %s: pros take it %.1f times less often",
		cd_set_solo = "Don't rely on allies",
		cd_tip_solo = "Draft: raises heroes that win back lost games on their own.\nBuild: from the start, items that win when your team\nis behind and you have the farm go higher (pro data)",
		cd_tip_solo_up = "Don't rely on allies: when the team is behind and you farm,\n+%.1f points of wins with it (pro games)",
		cd_tip_solo_down = "Don't rely on allies: when the team is behind and you farm,\n-%.1f points of wins with it (pro games)",
		cd_reason_solo = "comeback %s",
		cd_state_solo = "carrying",
		cd_state_4v5 = "4 vs 5",
		cd_tip_state_solo = "Allies are behind, the build leans to survival",
		cd_tip_state_4v5 = "An ally left, the build leans to survival",
		cd_tip_swap_solo = "You carry alone, survival matters more",
		cd_solo_bb = "Keep gold for buyback",
		cd_p_auto = "auto buy",
		cd_p_reserve = "%d kept for buyback",
		cd_tip_pub = "In public games: by %d min %d%% wins, later %d%%",
		cd_pk_t = "Pick this hero?",
		cd_pk_ok = "Pick",
		cd_pk_no = "Cancel",
		cd_pk_dont = "Don't ask again",
		cd_pk_dont2 = "turn it back on in settings",
		cd_pk_stage = "Picking works only during hero selection",
		cd_pk_have = "You already have a hero",
		cd_pk_taken = "This hero can't be picked",
		cd_pk_fail = "Couldn't pick, not your turn?",
	},
	ru = {
		cd_group_main = "Основное",
		cd_enable = "Включить",
		cd_enable_tip = "Включает Ghost",
		cd_key = "Открыть окно",
		cd_key_tip = "Открывает и закрывает окно драфта",
		cd_bind_name = "Ghost",
		["Draft Helper"] = "Ghost",

		cd_mode_order = "По очереди",
		cd_mode_free = "Свободный",
		cd_bans = "Баны",
		cd_tip_mode_t = "Режим драфта",
		cd_tip_mode = "Определяется по игре: в Captains Mode баны и пики по очереди,\nв остальных режимах выбор свободный",
		cd_gm_ap = "All Pick",
		cd_gm_cm = "Captains Mode",
		cd_gm_rd = "Random Draft",
		cd_gm_sd = "Single Draft",
		cd_gm_ar = "All Random",
		cd_gm_rcm = "Reverse Captains Mode",
		cd_gm_cd = "Captains Draft",
		cd_gm_ad = "Ability Draft",
		cd_gm_rap = "Ranked All Pick",
		cd_gm_turbo = "Турбо",
		cd_tip_tent_t = "Союзник выбирает",
		cd_tip_tent = "Игра ещё не открыла героя,\nон может поменяться",
		cd_tip_slot_t = "Слот",
		cd_tip_free = "Клик по пустому слоту выбирает его,\nправый клик очищает",
		cd_title = "Драфт",
		cd_first = "Первый пик",
		cd_us = "Мы",
		cd_enemy = "Враг",
		cd_chance = "шанс по драфту",
		cd_replace = "Замена",
		cd_done = "Драфт собран",
		cd_done_tip = "правый клик по слоту очищает его",
		cd_search = "Впиши героя, Enter ставит в текущий ход",
		cd_attr_str = "СИЛА",
		cd_attr_agi = "ЛОВКОСТЬ",
		cd_attr_int = "ИНТЕЛЛЕКТ",
		cd_attr_all = "УНИВЕРСАЛ",
		cd_t_pick = "Кого пикнуть",
		cd_s_pick = "контрпики к драфту врага, потом синергия",
		cd_t_ban = "Кого забанить",
		cd_s_ban = "лучшие пики для врага против нас",
		cd_t_epick = "Пик врага",
		cd_s_epick = "лучшие пики для врага против нас",
		cd_t_eban = "Бан врага",
		cd_s_eban = "наши лучшие пики, их могут забрать",
		cd_on = "%s на %s",
		cd_posT1 = "Керри",
		cd_posT2 = "Мид",
		cd_posT3 = "Оффлейн",
		cd_posT4 = "Четвёрка",
		cd_posT5 = "Пятёрка",
		cd_tip_badge_t = "Позиция героя",
		cd_tip_badge = "Клик меняет позицию вручную,\nправый клик возвращает авто",
		cd_tip_pm_auto = "Позиция по статистике героя и составу",
		cd_tip_pm = "Закрепить героя на этой позиции",
		cd_tip_auto_t = "Авто",
		cd_tip_auto = "Скрипт сам выберет позицию,\nкоторая подходит нашему составу",
		cd_tip_pick = "Герои на эту позицию.\nПод лучшими видно, кого взять к ним",
		cd_tip_ban = "Сильные против нас герои,\nкоторые играют на этой позиции",
		cd_tip_taken = "Сейчас здесь %s, при выборе\nон сдвинется на свободную позицию",
		cd_tip_close_t = "Закрыть",
		cd_nav_build_t = "Сборка",
		cd_tip_nav_draft_t = "Драфт",
		cd_tip_nav_draft = "Пики и баны под этот драфт",
		cd_tip_nav_build_t = "Сборка",
		cd_tip_nav_build = "Сборка твоего героя под этот драфт",
		cd_tip_grid_t = "Все герои",
		cd_tip_grid = "Показать сетку героев, она открывается и при вводе",
		cd_side_build = "Сборка",
		cd_side_empty = "Здесь будет сборка героя",
		cd_side_core = "Основа",
		cd_side_vs = "Под этих героев",
		cd_side_skills = "Навыки",
		cd_side_sub = "поз. %d, %d игр про",
		cd_side_pos = "поз. %d",
		cd_side_open = "Вся сборка",
		cd_slot_now = "Сейчас выбор",
		cd_slot_empty = "пусто",
		cd_tip_close = "Прячет окно, открыть снова\nможно клавишей из меню",
		cd_tip_undo_t = "Отменить ход",
		cd_tip_undo = "Убирает последнего вписанного героя",
		cd_tip_reset_t = "Сбросить драфт",
		cd_tip_reset = "Очищает все пики и баны",
		cd_tip_first_t = "Первый пик",
		cd_tip_first = "Кто первым банит и пикает.\nОт этого зависит порядок ходов",
		cd_auto_pos = "авто",
		cd_pos1 = "керри",
		cd_pos2 = "мид",
		cd_pos3 = "оффлейн",
		cd_pos4 = "четвёрка",
		cd_pos5 = "пятёрка",
		cd_acc1 = "керри",
		cd_acc2 = "мид",
		cd_acc3 = "оффлейн",
		cd_acc4 = "четвёрку",
		cd_acc5 = "пятёрку",
		cd_vs = "против",
		cd_with = "с",
		cd_weak = "слаб против",
		cd_bad_with = "плохо с",
		cd_with_him = "с ним",
		cd_pro = "в про-драфтах %d%%",
		cd_rate = "винрейт %.1f%%",
		cd_tip_num_t = "%s от драфта",
		cd_tip_num = "Так контрпики и синергия меняют шанс победы.\nВинрейт героя %s за %s матчей",
		cd_matches = "%s матчей",
		cd_empty = "Нет подходящих героев",
		cd_ld_heroes = "Загружаю героев",
		cd_ld_pro = "Загружаю про-матчи",
		cd_ld_matches = "Загружаю матчи",
		cd_ld_build = "Считаю статистику",
		cd_ld_wait = "Готовлю данные",
		cd_ld_count = "%s из %s",
		cd_ld_first = "В первый раз это пара минут, дальше всё из кэша",
		cd_ld_error = "Нет связи с OpenDota",
		cd_p_retry = "Повторяю каждые несколько секунд. Проверь VPN или прокси",
		cd_p_wait = "Сборка героя скачивается с OpenDota",
		cd_ld_slow = "OpenDota долго отвечает",
		cd_tip_err_t = "Причина",
		cd_ld_retry = "повтор через %d с",
		cd_ld_short = "матчи %d%%",
		cd_src_short0 = "Рейтинг",
		cd_rk0 = "Все",
		cd_rk1 = "Властелин+",
		cd_rk2 = "Божество+",
		cd_rk3 = "Божество 5+",
		cd_set_source = "Матчи",
		cd_set_rank = "Ранг",
		cd_set_scale = "Размер",
		cd_set_tips = "Подсказки",
		cd_set_blur = "Размытие фона",
		cd_set_auto = "Открывать на выборе героев",
		cd_tip_settings_t = "Настройки",
		cd_tip_settings = "Данные, внешний вид окна и поведение",
		cd_s_none = "пиков ещё нет, порядок по винрейту героев",
		cd_tip_wr_t = "Винрейт %s",
		cd_tip_wr = "%s матчей на выбранном ранге.\nКонтрпики появятся после первых пиков",
		cd_set_title = "Настройки",
		cd_sec_data = "ДАННЫЕ",
		cd_set_volume = "Объём",
		cd_set_volume_tip = "больше матчей, точнее цифры",
		cd_set_bg = "Фон",
		cd_set_debug = "Отладка в лог",
		cd_set_logauto = "Отправлять данные матчей автору",
		cd_tip_logauto = "После каждого матча Ghost отправляет автору запись матча\n(драфт, покупки, план сборки по ходу игры) и свой лог.\nОшибки тоже. Ник и Steam ID не отправляются",
		cd_set_log = "Лог для автора",
		cd_tip_log = "Отправляет автору лог Ghost, настройки\nи ошибки прямо сейчас. Ник и Steam ID не отправляются",
		cd_log_send = "Отправить",
		cd_log_sending = "Отправляется",
		cd_log_sent = "Лог отправлен, спасибо",
		cd_log_wait = "Лог только что отправлен, попробуйте через минуту",
		cd_log_saved = "Не удалось отправить сейчас, отправлю позже. Лог: configs\\draft_helper_log.txt",
		cd_log_fail = "Не удалось отправить лог",
		cd_set_refresh = "Обновить",
		cd_src_long1 = "Captains Mode",
		cd_upd_now = "обновлено только что",
		cd_upd_min = "обновлено %d мин назад",
		cd_upd_hour = "обновлено %d ч назад",
		cd_upd_day = "обновлено %d дн назад",
		cd_upd_never = "ещё не загружено",
		cd_eta_s = "осталось около %d с",
		cd_eta_m = "осталось около %d мин",
		cd_eta_short_s = "около %d с",
		cd_eta_short_m = "около %d мин",
		cd_ld_days = "%s за %d из %d дней",
		cd_cm_now = "Сейчас %s за %d из %d дней",
		cd_cm_done = "Загружено %s за %d дней",
		cd_cm_total = "в итоге около %s",
		cd_cm_wait = "Загружаю, это займёт несколько минут",
		cd_cm_why = "В CM мало игр, около %d в день, пары героев дополняются рейтинговыми",
		cd_cm_why0 = "В CM мало игр, пары героев дополняются рейтинговыми",
		cd_lang = "ru",
		cd_upd_failed = "Не удалось обновить, повторю",
		cd_pill_get = "Версия %s встанет после матча",
		cd_pill_down = "Скачиваю %s",
		cd_pill_done = "Обновлено, перезапуск",
		cd_upd_loading = "загружается",
		cd_sum_t = "Итог драфта",
		cd_sum_chance = "шанс победы",
		cd_sum_vs = "КТО КОГО",
		cd_sum_vs_sub = "% к шансу победы, наши против их",
		cd_sum_total = "итог",
		cd_sum_hint = "клик по нашему герою открывает его сборку",
		cd_tip_cell_t = "%s против %s",
		cd_tip_cell = "%s%% к шансу победы\nпо матчам выбранного ранга",
		cd_tip_sum_t = "%s против их драфта",
		cd_tip_sum = "Сумма по всем пяти врагам.\nКлик покажет сборку этого героя",
		cd_build_sub = "против их пика",
		cd_build_since = "мало игр на патче, данные с %s",
		cd_build_pooled = "здесь %d игр, остальное с поз. %s этого героя",
		cd_p_pooled = "%d + поз. %s",
		cd_build_synth = "здесь %d игр, остальное собрано под позицию по похожим героям",
		cd_p_synth = "%d + похожие герои",
		cd_tip_bpos_synth = "%d матчей на этой позиции. Остальное: что обычно берут\nна этой позиции с поправкой на героя и похожие герои здесь",
		cd_tip_bpos_pool = "%d матчей на этой позиции, дополнено\nиграми героя на поз. %s",
		cd_build_start = "СТАРТ",
		cd_build_gold = "%d из %d золота",
		cd_build_spare = "в запасе против",
		cd_build_loading = "Загружаю предметы",
		cd_build_none = "Мало данных по предметам героя",
		cd_tip_item_vs = "Против %s",
		cd_th_magic = "магия",
		cd_th_disable = "контроль",
		cd_th_targeted = "в одну цель",
		cd_th_silence = "сайленсы",
		cd_th_roots = "руты и дизарм",
		cd_th_invis = "инвиз",
		cd_th_evasion = "уклонение",
		cd_th_heal = "лечение",
		cd_th_illusions = "иллюзии",
		cd_th_passives = "сильные пассивки",
		cd_th_phys = "урон с руки",
		cd_th_burst = "берст урон с руки",
		cd_th_pierce = "сквозь BKB",
		cd_th_escape = "побег и доджи",
		cd_th_saves = "сейвы у врага",
		cd_tip_after = "Потом разобрать в %s",
		cd_tip_upgrade = "Потом собрать в %s",
		cd_tip_up_from = "Апгрейд %s",
		cd_tip_stats = "Брали в %d из %d игр, винрейт %d%%",
		cd_tip_lift = " (%+d%% к норме)",
		cd_tip_dis_from = "Разобрать %s и собрать",
		cd_p_up = "из %s",
		cd_set_preview = "Предпросмотр панели",
		cd_preview_show = "Показать",
		cd_preview_hide = "Скрыть",
		cd_tip_preview = "Показывает панель с примером сборки,\nеё можно передвинуть мышью",
		cd_p_dis = "разобрать %s",
		cd_tip_swap = "Вместо %s",
		cd_tip_swap_why = "У %s: %s",
		cd_p_all = "Сборка собрана",
		cd_tip_skipped = "Пропущен, стоит в конце очереди",
		cd_set_panel = "Панель сборки в игре",
		cd_set_window = "Окно драфта",
		cd_sec_view = "ОКНО И ПАНЕЛЬ",
		cd_set_pview = "Вид",
		cd_pview0 = "Таблетка",
		cd_pview1 = "Карточка",
		cd_pview2 = "Сетка",
		cd_p_queue = "ДАЛЬШЕ",
		cd_p_done = "ГОТОВО",
		cd_p_rmb = "ПКМ по предмету: купить",
		cd_p_min = "%d мин",
		cd_p_by = "к %d мин",
		cd_p_have = "собрано %d из %d",
		cd_p_gold = "золото %d",
		cd_card_order = "ПОРЯДОК ПОКУПКИ",
		cd_card_late = "ПОСЛЕ 40 МИН",
		cd_card_next = "ПОСЛЕ ОСНОВЫ",
		cd_tip_ext_swap = "Вместо %s",
		cd_card_skills = "НАВЫКИ",
		cd_card_neutral = "НЕЙТРАЛКИ",
		cd_card_enemy = "ЧЕГО ЖДАТЬ ОТ ВРАГОВ",
		cd_card_pred = "%s в %d%% игр",
		cd_card_qbuy = "клик: в быструю покупку, Shift+клик: только он",
		cd_set_pshop = "Только при открытом магазине",
		cd_set_padapt = "Менять по предметам врагов",
		cd_set_phide = "Прятать, когда всё собрано",
		cd_set_pdanger = "Учитывать самого опасного врага",
		cd_set_pext = "Докупать после основы",
		cd_tip_pdanger = "Ответы на предметы врага с большинством убийств\nи урона по тебе весят больше (в про-играх около +2 пунктов)",
		cd_tip_pext = "Когда основа собрана, следующие предметы берутся\nиз тех же про-данных, сначала улучшения",
		cd_danger = "Опаснее всех: %s %d/%d",
		cd_danger_att = "бьёт рукой",
		cd_danger_spell = "бьёт магией",
		cd_danger_tip_t = "Самый опасный враг",
		cd_danger_tip = "Доля убийств врагов: %d%%, урона по тебе: %s\nОтветы на его предметы весят x%.1f",
		cd_dmg_attack = "урон рукой",
		cd_dmg_spell = "урон магией",
		cd_tip_ext = "После основы: берут %d%% про на этом герое",
		cd_talent_tier = "Талант (%d уровень)",
		cd_tip_room = "Нет свободного слота: сначала продай что-то",
		cd_rep = "Замена: %s → %s",
		cd_rep_tip_t = "Предмет потерял смысл",
		cd_rep_why_enemy = "У %s есть %s, это ответ на твой %s",
		cd_rep_why_team = "У %s уже есть %s, ауры не складываются",
		cd_rep_do = "Продай %s и купи %s",
		cd_rep_why_mx = "%s в этом матче: %+.1f пункта в про-играх\nглавная причина: %s",
		cd_mx_foe = "%s у %s",
		cd_mx_early = "%s у %s рано",
		cd_mx_ally = "%s у союзника %s",
		cd_mx_lane = "линия против %s",
		cd_mx_lane_lost = "проигранная линия",
		cd_mx_lane_won = "выигранная линия",
		cd_lane_line = "Линия против %s: %s",
		cd_lane_lost = "проиграна (%d)",
		cd_lane_won = "выиграна (+%d)",
		cd_lane_even = "ровно (%+d)",
		cd_lane_unknown = "нет свежего опыта врага",
		cd_lane_tip_t = "Твоя линия",
		cd_lane_tip = "Кто стоял рядом с 1 по 10 минуту (по времени про) и разница опыта\nна 10-й. Для сведения: у про это не меняет, какие предметы выигрывают",
		cd_foe_line = "Враги: физ. урон %d%% · маг. %d%% · здоровье %d",
		cd_foe_eva = " · уклонение %d%% (%s)",
		cd_foe_tip_t = "Защита врагов",
		cd_foe_tip = "Среднее по замеченным врагам: сколько урона проходит и здоровье.\nДля сведения: предметы выбираются по предметам врагов",
		cd_mx = "Против этих врагов: %+.1f пункта (%s)",
		cd_mx_stun = "много контроля по команде",
		cd_mx_short = "против врагов %+.1f",
		cd_rep_auto = "Автопокупка сделает это на базе, когда хватит золота",
		cd_set_abuy_swap = "Заменять предметы, потерявшие смысл",
		cd_set_askill = "Прокачивать навыки и таланты",
		cd_set_dmgtrack = "Отслеживать урон по себе (unsafe)",
		cd_tip_dmgtrack = "Принимает от сервера события урона, чтобы видеть, кто и чем тебя бьёт.\nНужен unsafe-режим Umbrella и перезагрузка скриптов. Выключено: подозревается в обрывах связи",
		cd_tip_askill = "Навыки и таланты по порядку, как у про на этом герое и позиции.\nВыключено: два обрыва связи случились сразу после приказа на прокачку",
		cd_set_pturbo = "Turbo: ускоренные тайминги",
		cd_tip_pturbo = "В Turbo предметы приходят примерно вдвое быстрее:\nминуты про и пороги умножаются на 0,45",
		cd_p_title = "Сборка",
		cd_p_more = "ещё %d",
		cd_p_enough = "хватает",
		cd_p_instead = "вместо %s",
		cd_p_preview = "предпросмотр",
		cd_p_since = "данные с %s",
		cd_p_start = "Старт",
		cd_build_nopos = "Сборки на %s нет",
		cd_build_nopos2 = "на этой позиции героя почти не берут, выбери другую",
		cd_tip_bpos = "Сборка по %d матчам\nна этой позиции",
		cd_tip_bpos_none = "Здесь героя почти не берут,\nсборки нет",
		cd_sell = "Продай %s ради %s",
		cd_bag = "Убери %s в рюкзак ради %s",
		cd_tip_late = "Есть в конце %d%% игр дольше 40 мин,\nтаких игр %d",
		cd_tip_sold = "Продают в %d%% игр",
		cd_step_extra = "Без слота, обычно к %d мин",
		cd_set_live = "Советы по ходу игры",
		cd_tip_live = "Продажа, поздняя игра, нейтралки,\nнавыки, тайминги и отставание",
		cd_tip_timing = "Обычно к %d мин, вовремя %d%% побед, позже %d%%",
		cd_tip_behind = "При отставании: %d%% побед, обычно %d%%",
		cd_state_behind = "Отстаем по предметам на %s",
		cd_state_ahead = "Впереди по предметам на %s",
		cd_state_short = "команда",
		cd_state_tip = "Предметы всей твоей команды %.1fk, врагов %.1fk\n(только то, что видели у врагов). Это не твоё золото.\n",
		cd_state_tip_behind = "Пока команда отстаёт, сборка смещается к предметам, которые выигрывают из отставания",
		cd_state_tip_ahead = "Пока команда впереди, сборка идёт в обычном порядке про",
		cd_late_warn = "%s опаздывает, у других к %d мин",
		cd_tip_swap_behind = "Чаще выигрывает, когда отстаешь",
		cd_tip_swap_late = "Лучше, когда предметы опаздывают",
		cd_tip_swap_react = "Против такого состава про берут его чаще",
		cd_tip_alt = "Или %s: %s",
		cd_alt_vs = "против %s",
		cd_alt_share = "берут в %d%% игр",
		cd_tip_neutral = "Уровень %d, берут в %d%% игр",
		cd_tip_neutral_alt = "Если не выпала: %s",
		cd_neutral_enh = "Улучшение: %s",
		cd_tip_enh = "Выбирают в %d%% игр",
		cd_tip_skill = "Уровень %d, так качают %d%%",
		cd_tip_talent = "Талант на %d уровне, берут %d%%",
		cd_threat_warn = "У врагов %s (%d): нужен %s",
		cd_threat_invis_sup = "У врагов невидимость: возьми пыль и сентри",
		cd_threat_invis_team = "У врагов невидимость, а детекта нет ни у кого в команде: купи пыль",
		cd_set_lanes = "Позиции врагов и линии",
		cd_tip_lanes = "Контрпики против соперников по линии весят больше,\nпредметы вражеских саппортов меньше",
		cd_set_pick_ask = "Подтверждать выбор героя",
		cd_tip_pick_ask = "Правый клик по герою в списке выбирает его,\nэтот пункт сначала спрашивает",
		cd_set_lang = "Язык",
		cd_tip_lang = "«Авто» берёт язык из настроек Umbrella",
		cd_lang0 = "Авто",
		cd_lang1 = "English",
		cd_lang2 = "Русский",
		cd_suggest = "Предложить",
		cd_suggest_top = "Предложить топ-2",
		cd_suggested = "Предложен",
		cd_tip_suggest = "Отмечает героя как предложенного команде,\nкак кнопка «Предложить героя» в игре. Повторный клик снимает",
		cd_tip_suggest_top = "Предлагает первых двух героев списка.\nИгра держит два предложения от игрока",
		cd_sug_sent = "Предложено команде: %s",
		cd_sug_off = "Предложение снято: %s",
		cd_tip_own_start = "Ты начал его сам: в частях уже %d%% цены",
		cd_skv_why = "Под эту игру: против %s про чаще сначала максят %s (%d%%, обычно %d%%)",
		cd_set_ver = "Ghost %s, обновляется сам между матчами",
		cd_card_head_sub = "план на этот матч",
		cd_card_vs = "против",
		cd_sec_logs = "ОТЧЁТЫ",
		cd_tal_why = "Под эту игру: %s, про чаще берут этот талант (%d%%, обычно %d%%)",
		cd_why_lane = "%s на линии",
		cd_why_lineup = "этого состава",
		cd_why_ahead = "команда впереди",
		cd_why_behind = "команда отстаёт",
		cd_tip_own_up = "Улучшение твоего %s, у про в %d%% игр",
		cd_ban_t = "Скрыть %s",
		cd_tip_ban = "ЛКМ: больше не предлагать для %s.\nПКМ: для всех героев. Список скрытых в настройках",
		cd_ban_one = "Скрыт: %s",
		cd_ban_all = "Скрыт для всех героев: %s",
		cd_ban_off = "Снова в сборках: %s",
		cd_sec_bans = "СКРЫТЫЕ ПРЕДМЕТЫ",
		cd_bans_none = "Ничего не скрыто. Наведи на предмет в сборке и нажми на палец вниз",
		cd_ban_everyone = "все герои",
		cd_tip_unban = "Клик вернёт предмет в сборки",
		cd_bans_clear = "Вернуть все",
		cd_bans_hint = "Сборки обходят эти предметы",
		cd_say_wait = "Подожди пару секунд",
		cd_set_pup = "Апгрейды после сборки",
		cd_tip_pup = "Когда план закончился: апгрейды купленных\nпредметов и замена самого слабого, если хватает золота",
		cd_tip_inslot = "Апгрейд в том же слоте, из %s",
		cd_tip_inslot_pro = "Про на этом герое берут в %d%% игр",
		cd_tip_inslot_rule = "Так долго про играют редко, выбрано по дереву предметов",
		cd_tip_inslot_attr = "Этот Blink под твой основной атрибут",
		cd_tip_weak = "Самый слабый предмет сейчас: %s",
		cd_tip_dps_more = "Враги бьют с руки сильнее, чем ждали по драфту: нужен в %.1f раза чаще",
		cd_tip_dps_less = "Враги бьют с руки слабее, чем ждали по драфту: нужен в %.1f раза реже",
		cd_tip_buy = "ПКМ: купить на текущее золото\nShift+клик: оставить в быстрой покупке только его",
		cd_buy_gold = "Не хватает золота даже на компонент",
		cd_buy_secret = "Только в потайной лавке: %s",
		cd_counter_toast = "Новый ответ: %s",
		cd_counter_vs = "%s против %s (%s)",
		cd_sec_auto = "АВТОПОКУПКА",
		cd_set_autobuy = "Покупать сборку автоматически",
		cd_tip_autobuy = "Покупает следующий предмет по частям,\nв том порядке, в каком их берут про",
		cd_set_abuy_sell = "Продавать ненужное",
		cd_set_abuy_bb = "Оставлять золото на выкуп",
		cd_set_abuy_tp = "Держать свиток телепорта",
		cd_set_abuy_cour = "Отправлять курьера",
		cd_tip_abuy_cour = "Несёт тебе вещи из тайника. Детали из секретной лавки\n(Point Booster, Tiara, Ultimate Orb...) курьер покупает там",
		cd_tip_stock = "Пока нет в продаже, до этого покупается следующий предмет",
		cd_tip_bless = "Улучшение %s: эффект остаётся, освобождается слот",
		cd_tip_vsh_more = "Против %s про берут его в %.1f раза чаще",
		cd_tip_vsh_less = "Против %s про берут его в %.1f раза реже",
		cd_tip_vsa_more = "С союзником %s про берут его в %.1f раза чаще",
		cd_tip_vsa_less = "С союзником %s про берут его в %.1f раза реже",
		cd_tip_lm_more = "С этими героями про берут его в %.1f раза чаще (больше всего из-за %s)",
		cd_tip_lm_less = "С этими героями про берут его в %.1f раза реже (больше всего из-за %s)",
		cd_tip_lm_ally = "союзника %s",
		cd_attr = "+2 ко всем атрибутам",
		cd_tip_lr_more = "У врагов %s: про берут его в %.1f раза чаще",
		cd_tip_lr_less = "У врагов %s: про берут его в %.1f раза реже",
		cd_tip_lr_ally_more = "У союзника %s: про берут его в %.1f раза чаще",
		cd_tip_lr_ally_less = "У союзника %s: про берут его в %.1f раза реже",
		cd_set_solo = "Без надежды на союзников",
		cd_tip_solo = "Драфт: выше герои, которые сами вытаскивают проигранные игры.\nСборка: с начала игры выше предметы, которые выигрывают,\nкогда команда отстаёт, а фарм у тебя (по про-играм)",
		cd_tip_solo_up = "Без надежды на союзников: когда команда отстаёт, а фарм у тебя,\nс ним на %.1f пункта больше побед (про-игры)",
		cd_tip_solo_down = "Без надежды на союзников: когда команда отстаёт, а фарм у тебя,\nс ним на %.1f пункта меньше побед (про-игры)",
		cd_reason_solo = "вытаскивает %s",
		cd_state_solo = "тащишь сам",
		cd_state_4v5 = "играете вчетвером",
		cd_tip_state_solo = "Союзники отстают, сборка смещена к выживанию",
		cd_tip_state_4v5 = "Союзник вышел, сборка смещена к выживанию",
		cd_tip_swap_solo = "Тащишь сам, выживание важнее",
		cd_solo_bb = "Держи золото на выкуп",
		cd_p_auto = "автопокупка",
		cd_p_reserve = "%d на выкуп",
		cd_tip_pub = "В пабликах: к %d мин %d%% побед, позже %d%%",
		cd_pk_t = "Выбрать этого героя?",
		cd_pk_ok = "Выбрать",
		cd_pk_no = "Отмена",
		cd_pk_dont = "Больше не спрашивать",
		cd_pk_dont2 = "включить обратно можно в настройках",
		cd_pk_stage = "Выбрать можно только на стадии пиков",
		cd_pk_have = "Герой уже выбран",
		cd_pk_taken = "Этого героя сейчас нельзя взять",
		cd_pk_fail = "Не получилось выбрать, не твой ход?",
	},
})

local UI = localization.WrapLibrary(Menu)
localization.memo, localization.raw_get = {}, localization.Get
function localization.Get(key, force)
	if force ~= localization.force then
		return localization.raw_get(key, force)
	end
	local v = localization.memo[key]
	if v == nil then
		v = localization.raw_get(key, force)
		localization.memo[key] = v
	end
	return v
end
local L = function(key)
	return localization.Get(key, localization.force)
end

local ui = {}

do
	local tab = UI.Create("Scripts", "Scripts", "Draft Helper")
	tab:Icon("\u{f6e2}")

	local page = tab:Create("Settings")
	local g_main = page:Create("cd_group_main", Enum.GroupSide.Left)

	ui.enable = g_main:Switch("cd_enable", true, "\u{f011}")
	ui.enable:ToolTip("cd_enable_tip")

	ui.key = g_main:Bind("cd_key", Enum.ButtonCode.KEY_NONE, "\u{f11c}")
	ui.key:ToolTip("cd_key_tip")
	ui.key:Properties(L("cd_bind_name"), nil, true)
end

ui.enable:SetCallback(function()
	ui.key:Disabled(not ui.enable:Get())
end, true)

local cfg = {}
do
	local defaults = {
		source = 0, rank = 2, volume = 1, zoom = 100, bg = 88, blur = 1, tips = 1, auto = 1, debug = 0,
		panel = 1, pview = 0, pzoom = 100, pshop = 0, padapt = 1, phide = 0, live = 1, lanes = 1, pick_ask = 1,
		autobuy = 0, abuy_sell = 1, abuy_bb = 1, abuy_tp = 1, abuy_cour = 1, solo = 0, pdanger = 1, pext = 1, pturbo = 1, askill = 0, abuy_swap = 0, dmgtrack = 0, logauto = 1,
		lang = 0, pup = 1,
	}
	for key, value in pairs(defaults) do
		cfg[key] = Config.ReadInt("draft_helper", "set_" .. key, value)
	end
end

local function set_cfg(key, value)
	cfg[key] = value
	Config.WriteInt("draft_helper", "set_" .. key, value)
end

function localization.apply_lang()
	local want = cfg.lang == 1 and "en" or (cfg.lang == 2 and "ru" or nil)
	local force
	if want == "en" then
		force = -1
	elseif want == "ru" then
		for i = 0, 63 do
			if localization.GetLanguage(i) == "ru" then
				force = i
				break
			end
		end
	end
	localization.force, localization.umb = force, localization.GetLanguage()
	localization.memo, localization.memo_lang = {}, localization.GetLanguage(force)
	localization.Update(force)
end

localization.apply_lang()

local LOGR = { first = {}, ring = {}, head = 0, total = 0, size = 600, keep = 150, errs = {}, nerr = 0, err_at = 0, rep = 0 }

function LOGR.add(line)
	local stamp = os.date("%H:%M:%S ")
	if line == LOGR.last then
		LOGR.rep = LOGR.rep + 1
		LOGR.at[LOGR.ai] = stamp .. line .. " (x" .. LOGR.rep .. ")"
		return
	end
	LOGR.last, LOGR.rep = line, 1
	if #LOGR.first < LOGR.keep then
		LOGR.at, LOGR.ai = LOGR.first, #LOGR.first + 1
	else
		LOGR.head = LOGR.head % LOGR.size + 1
		LOGR.total = LOGR.total + 1
		LOGR.at, LOGR.ai = LOGR.ring, LOGR.head
	end
	LOGR.at[LOGR.ai] = stamp .. line
end

function LOGR.put(line)
	Log.Write("[Ghost] " .. line)
	LOGR.add(line)
end

function LOGR.err(where, msg)
	local line = where .. ": " .. tostring(msg)
	LOGR.put(line)
	LOGR.nerr = LOGR.nerr + 1
	LOGR.err_at = os.clock()
	if #LOGR.errs < 12 then
		LOGR.errs[#LOGR.errs + 1] = line
	end
	LOGR.pend = LOGR.pend or line
end

local function log(fmt, ...)
	local ok, line = pcall(string.format, fmt, ...)
	line = ok and line or tostring(fmt)
	LOGR.add(line)
	if cfg.debug == 1 then
		Log.Write("[Ghost] " .. line)
	end
end

local K = {
	VERSION = "1.3.2",
	UPDATE_URLS = {
		"https://raw.githubusercontent.com/gademoffshit/draft-helper/main/version.json",
		"https://cdn.jsdelivr.net/gh/gademoffshit/draft-helper@main/version.json",
		"https://fastly.jsdelivr.net/gh/gademoffshit/draft-helper@main/version.json",
	},
	UPDATE_EVERY = 3 * 3600,
	UPDATE_RETRY = 300,
	UPDATE_WAIT = 300,
	UPDATE_MIN_SIZE = 50000,
	UPDATE_RELOAD_DELAY = 1.2,
	SCRIPT_NAME = "draft_helper.lua",
	LOG_TOKEN_FILE = "dh_logs_token.txt",

	EXPLORER = "https://api.opendota.com/api/explorer?sql=",
	HEROES_URLS = {
		"https://raw.githubusercontent.com/odota/dotaconstants/master/build/heroes.json",
		"https://cdn.jsdelivr.net/gh/odota/dotaconstants@master/build/heroes.json",
		"https://api.opendota.com/api/heroes",
	},
	HEADERS = { ["User-Agent"] = "Umbrella/draft_helper", ["Accept"] = "application/json", ["Connection"] = "close" },
	TIMEOUT = 90,
	RETRY = 60,
	RETRY_SHORT = 5,
	SEND_RETRY = 2,
	ANSWER_WAIT = 300,
	STALE_RETRY = 600,
	GAP = 1.1,
	CONFIG = "draft_helper",
	CACHE_FILE = "draft_helper.dat",
	CACHE_MAGIC = "DHC2",
	CACHE_KEYS = 10,
	BUYS_BLOB = "b:",
	ABIL_BLOB = "abil",
	STAT_FIELDS = { "bg", "bw", "vg", "vw", "sg", "sw" },
	HEROES_TTL = 7 * 86400,
	PRO_TTL = 3 * 86400,
	MATCHES_TTL = 6 * 3600,
	PRO_MATCHES = 6000,
	CONTEST_MATCHES = 2000,

	GH_URLS = {
		"https://raw.githubusercontent.com/gademoffshit/dh-data/draft-data/",
		"https://cdn.jsdelivr.net/gh/gademoffshit/dh-data@draft-data/",
		"https://gcore.jsdelivr.net/gh/gademoffshit/dh-data@draft-data/",
		"https://fastly.jsdelivr.net/gh/gademoffshit/dh-data@draft-data/",
	},
	GH_TTL = 86400,
	MODELS = "a77f613f79",
	MODELS_SHA = "3bde9223f4f326b5a95db679476ad2b0989157e1",
	MODELS_FILE = "draft_helper_models.txt",
	MODEL_KEYS = { "SYNTH", "SKV", "TLM", "LM_CORE", "LM_SUP", "LR_CORE", "LR_SUP" },
	MODEL_URLS = {
		"https://cdn.jsdelivr.net/gh/gademoffshit/dh-data@%s/models/%s.txt",
		"https://raw.githubusercontent.com/gademoffshit/dh-data/%s/models/%s.txt",
		"https://fastly.jsdelivr.net/gh/gademoffshit/dh-data@%s/models/%s.txt",
		"https://gcore.jsdelivr.net/gh/gademoffshit/dh-data@%s/models/%s.txt",
	},
	GH_RETRY = 300,
	GH_GONE = 6 * 3600,
	LOG_URL = "https://api.github.com/repos/gademoffshit/dh-logs/issues",
	LOG_TOKEN = "",
	LOG_MAX = 60000,
	LOG_COOLDOWN = 60,
	LOG_CALM = 20,
	LOG_GAP = 1800,
	LOG_SAME = 86400,
	LOG_PART = 60000,
	LOG_RETRY_MIN = 3,
	LOG_RETRY_MAX = 120,
	LOG_STUCK = 600,
	LOG_TIMEOUT = 90,
	LOG_CHECK = 30,
	LOG_BOX = 4000000,
	LOG_BOX_FILE = "draft_helper_outbox.txt",
	LOG_ID_FILE = "draft_helper_uid.txt",
	PAGE = 140,
	PAGE_CM = 140,
	PAGE_MIN = 50,
	CM_WINDOW = 4000000,
	CM_MAX = 40000,
	CM_DAYS = 60,
	PARTIAL = 20000,
	PARTIAL_CM = 3000,
	SAVE_EVERY = 10,
	RANKS = { 0, 60, 70, 75 },
	VOLUMES = { 50000, 100000, 200000 },
	REC = 20,
	PACK = "<I8" .. ("B"):rep(12),
	CHUNK = 2500,
	ETA_WARMUP = 4,

	PRIOR_BASE = 200,
	PRIOR_PAIR = 1000,
	PRIOR_POS = 12,
	PRIOR_CM = 300,
	PRIOR_CM_PAIR = 60,
	POS_FLOOR = 0.01,
	ADV_W = 1.2,
	RARE_W = 0.03,
	COUNTER_EXTRA = 0.5,
	COUNTERED_EXTRA = 0.5,
	SYN_W = 0.5,
	FIT_MIN = 0.1,
	FIT_W = 0.025,
	BASE_W = 0.25,
	CONTEST_W = 0.05,
	MIN_GAMES = 150,
	LIST_MAX = 40,
	REASONS = 2,
	REASON_MIN = 0.3,
	ORDER_W = 0.05,
	PICK_ORDER = {
		{ 0.13, 0.20, 0.14, 0.26, 0.27 },
		{ 0.07, 0.10, 0.14, 0.33, 0.35 },
		{ 0.13, 0.12, 0.27, 0.24, 0.23 },
		{ 0.27, 0.28, 0.22, 0.12, 0.11 },
		{ 0.40, 0.29, 0.21, 0.05, 0.05 },
	},
	POS_MIN = 0.2,
	COMP_ROWS = 6,
	SUM_MIN = 0.3,

	ORDER = "BF BF BS BS BF BS BS PF PS BF BF BS PS PF PF PS PS PF BF BS BF BS PF PS",
	FREE_PICKS = 10,
	SYNC_EVERY = 0.5,
	SYNC_GAME_EVERY = 3,
	ROLES_EVERY = 4,
	BAR_EVERY = 1.5,
	SYNC_MODES = {
		[Enum.GameMode.DOTA_GAMEMODE_AP] = true,
		[Enum.GameMode.DOTA_GAMEMODE_TURBO] = true,
		[Enum.GameMode.DOTA_GAMEMODE_ALL_DRAFT] = true,
		[Enum.GameMode.DOTA_GAMEMODE_SD] = true,
		[Enum.GameMode.DOTA_GAMEMODE_RD] = true,
		[Enum.GameMode.DOTA_GAMEMODE_AR] = true,
	},
	SD_OFFER_MAX = 4,
	PANEL_DEPTH = 14,
	GRID = "HeroGrid",
	GRID_CARD = "HeroCard",
	GRID_OFF = "Unavailable",
	GRID_CARD_UP = 3,
	GRID_DEPTH = 20,
	GRID_MIN = 60,
	GRID_EVERY = 2,
	GRID_CACHE = 20,
	TEAM_DIRE = Enum.TeamNum.TEAM_DIRE,
	MATCH_STATES = {
		[Enum.GameState.DOTA_GAMERULES_STATE_HERO_SELECTION] = true,
		[Enum.GameState.DOTA_GAMERULES_STATE_STRATEGY_TIME] = true,
		[Enum.GameState.DOTA_GAMERULES_STATE_TEAM_SHOWCASE] = true,
		[Enum.GameState.DOTA_GAMERULES_STATE_PRE_GAME] = true,
		[Enum.GameState.DOTA_GAMERULES_STATE_GAME_IN_PROGRESS] = true,
	},
	LANE_BITS = { [1] = 1, [2] = 3, [4] = 2, [8] = 4, [16] = 5 },
	LANE_CLASS = {
		LaneSelection__SafeLane = 1, LaneSelection__MidLane = 2, LaneSelection__OffLane = 3, LaneSelection__Support = 4,
		LaneSelection__HardSupport = 5,
	},
	LANE_TOKEN = {
		["#DOTA_TopBar_LaneSelectionSafelane"] = 1, ["#DOTA_TopBar_LaneSelectionMidlane"] = 2,
		["#DOTA_TopBar_LaneSelectionOfflane"] = 3, ["#DOTA_TopBar_LaneSelectionSupport"] = 4,
		["#DOTA_TopBar_LaneSelectionHardSupport"] = 5,
	},
	TENTATIVE = 0.45,
	HERO_SELECTION = Enum.GameState.DOTA_GAMERULES_STATE_HERO_SELECTION,
	MODE_CM = Enum.GameMode.DOTA_GAMEMODE_CM,
	GM_KEY = {
		[Enum.GameMode.DOTA_GAMEMODE_AP] = "cd_gm_ap",
		[Enum.GameMode.DOTA_GAMEMODE_CM] = "cd_gm_cm",
		[Enum.GameMode.DOTA_GAMEMODE_RD] = "cd_gm_rd",
		[Enum.GameMode.DOTA_GAMEMODE_SD] = "cd_gm_sd",
		[Enum.GameMode.DOTA_GAMEMODE_AR] = "cd_gm_ar",
		[Enum.GameMode.DOTA_GAMEMODE_REVERSE_CM] = "cd_gm_rcm",
		[Enum.GameMode.DOTA_GAMEMODE_CD] = "cd_gm_cd",
		[Enum.GameMode.DOTA_GAMEMODE_ABILITY_DRAFT] = "cd_gm_ad",
		[Enum.GameMode.DOTA_GAMEMODE_ALL_DRAFT] = "cd_gm_rap",
		[Enum.GameMode.DOTA_GAMEMODE_TURBO] = "cd_gm_turbo",
	},
	STRATEGY = Enum.GameState.DOTA_GAMERULES_STATE_STRATEGY_TIME,

	W = 960,
	WIN_H = 544,
	RAIL_W = 52,
	HEAD_H = 46,
	ARENA_H = 118,
	ARENA_ORDER_H = 104,
	SIDE_PREV = 296,
	CARD_W = 66,
	CARD_PIC = 37,
	GAUGE_R = 24,
	BAN_SW = 38,
	BAN_SH = 21,
	STRIP_STEP = 30,
	BOARD_W = 212,
	SIDE_W = 268,
	TOP_H = 54,
	SLOT_ROW = 34,
	PAD = 16,
	HEAD_H = 44,
	MAIN_H = 500,
	TL_W = 186,
	TL_HEAD = 30,
	TL_GAP = 18,
	TL_STEP = 14.5,
	TL_SAME = 3,
	PICK_W = 50,
	PICK_H = 28,
	BAN_W = 36,
	BAN_H = 20,
	GRID_W = 330,
	SEARCH_H = 32,
	CELL_H = 21,
	CELL_GAP = 3,
	CELL_CROP_Y = 0.35,
	COL_GAP = 6,
	BTN = 27,
	SET_ROW = 28,
	ROW = 46,
	ROW_COMP = 62,
	RADIUS = 10,
	SCROLL = 44,
	FADE = 0.15,
	CLICK_GUARD = 0.3,
	HUD_SHARE = 0.17,
	CLICK_ORDERS = {
		[Enum.UnitOrder.DOTA_UNIT_ORDER_MOVE_TO_POSITION] = true,
		[Enum.UnitOrder.DOTA_UNIT_ORDER_MOVE_TO_TARGET] = true,
		[Enum.UnitOrder.DOTA_UNIT_ORDER_ATTACK_MOVE] = true,
		[Enum.UnitOrder.DOTA_UNIT_ORDER_ATTACK_TARGET] = true,
		[Enum.UnitOrder.DOTA_UNIT_ORDER_CAST_POSITION] = true,
		[Enum.UnitOrder.DOTA_UNIT_ORDER_CAST_TARGET] = true,
		[Enum.UnitOrder.DOTA_UNIT_ORDER_CAST_TARGET_TREE] = true,
		[Enum.UnitOrder.DOTA_UNIT_ORDER_PICKUP_ITEM] = true,
		[Enum.UnitOrder.DOTA_UNIT_ORDER_PICKUP_RUNE] = true,
		[Enum.UnitOrder.DOTA_UNIT_ORDER_DROP_ITEM] = true,
		[Enum.UnitOrder.DOTA_UNIT_ORDER_GIVE_ITEM] = true,
	},
	FONTS = { "Inter", "Segoe UI" },
	BASE_ZOOM = 1.1,
	SLIDER_GAP = 18,
	CM_NOTE_H = 44,
	POS_ICON = { "safelane", "midlane", "offlane", "softsupport", "hardsupport" },
	POS_COLOR = { Color(240, 177, 74), Color(98, 168, 255), Color(239, 111, 94), Color(95, 208, 138), Color(181, 140, 255) },
	TIP_DELAY = 0.3,
	TIP_FADE = 0.1,
	TIP_HOLD = 0.08,
	TIP_GRACE = 0.3,
	PAGE_TIME = 0.28,
	PAGE_SLIDE = 10,
	POP = 0.22,
	MOVE = 0.18,
	STAGGER = 0.022,
	ROW_IN = 0.2,
	SLIDE = 12,
	TYPE_GAP = 0.15,
	ROUND = Enum.DrawFlags.RoundCornersAll,
	ROUND_L = Enum.DrawFlags.RoundCornersLeft,
	ROUND_BR = Enum.DrawFlags.RoundCornersBottomRight,

	MOUSE1 = Enum.ButtonCode.KEY_MOUSE1,
	MOUSE2 = Enum.ButtonCode.KEY_MOUSE2,
	WHEEL_UP = Enum.ButtonCode.KEY_MWHEELUP,
	WHEEL_DOWN = Enum.ButtonCode.KEY_MWHEELDOWN,
	BACKSPACE = Enum.ButtonCode.KEY_BACKSPACE,
	ENTER = Enum.ButtonCode.KEY_ENTER,
	PAD_ENTER = Enum.ButtonCode.KEY_PAD_ENTER,
	ESCAPE = Enum.ButtonCode.KEY_ESCAPE,
	KEY_DOWN = Enum.EKeyEvent.EKeyEvent_KEY_DOWN,
	KEY_UP = Enum.EKeyEvent.EKeyEvent_KEY_UP,
	SCROLL_UP = Enum.EKeyEvent.EKeyEvent_SCROLL_UP,
	SCROLL_DOWN = Enum.EKeyEvent.EKeyEvent_SCROLL_DOWN,

	ITEMS_URLS = {
		"https://raw.githubusercontent.com/odota/dotaconstants/master/build/items.json",
		"https://cdn.jsdelivr.net/gh/odota/dotaconstants@master/build/items.json",
		"https://api.opendota.com/api/constants/items",
	},
	ITEMS_TTL = 7 * 86400,
	ITEMS_VER = 2,
	PUB_URL = "https://api.opendota.com/api/scenarios/itemTimings?item=%s&hero_id=%d",
	PUB_TTL = 3 * 86400,
	PUB_MIN_COST = 1400,
	PUB_SIDE_MIN = 30,
	PUB_MAX_ITEMS = 10,
	PUB_KEEP = 600,
	PUB_RETRY = 600,
	BUYS_SQL = "with prk as (select patch, row_number() over (order by min(match_id) desc) k from match_patch group by "
		.. "patch), p0 as (select pm.match_id, pm.player_slot<128 r, pm.purchase_log, ((pm.player_slot<128) = "
		.. "m.radiant_win) won, m.duration dur, m.radiant_gold_adv adv, m.leagueid lg, pm.neutral_item_history nh, "
		.. "pm.ability_upgrades_arr au, "
		.. "array[pm.item_0,pm.item_1,pm.item_2,pm.item_3,pm.item_4,pm.item_5,pm.backpack_0,pm.backpack_1,pm.backpack_2] "
		.. "fin from player_matches pm join matches m using(match_id) where pm.hero_id=%d and pm.purchase_log is "
		.. "not null and pm.leaver_status = 0 and m.duration >= 900 order by pm.match_id desc limit %d), p1 as "
		.. "(select p0.*, prk.k, case lt.tier when 'premium' then 3 when 'professional' then 2 else 1 end w0 from "
		.. "p0 join match_patch mp using(match_id) join prk using(patch) left join leagues lt on lt.leagueid = "
		.. "p0.lg where prk.k <= %d), tm as (select pm.match_id, pm.hero_id, coalesce(pm.lane_role,4) l, "
		.. "pm.gold_per_min gp from player_matches pm join p1 on p1.match_id=pm.match_id and "
		.. "(pm.player_slot<128)=p1.r where pm.gold_per_min is not null), c as (select *, row_number() over "
		.. "(partition by match_id, l order by gp desc) lr from tm), d as (select *, case when l in (1,2,3) and "
		.. "lr=1 then l end core from c), e as (select *, row_number() over (partition by match_id, (core is null) "
		.. "order by gp desc) sr from d), q0 as (select e.match_id, coalesce(core, case when sr=1 then 4 else 5 "
		.. "end) pos, p1.k from e join p1 using(match_id) where hero_id=%d), cum as (select pos, k, sum(count(*)) "
		.. "over (partition by pos order by k) cg from q0 group by pos, k), lim as (select pos, coalesce(min(k) "
		.. "filter (where cg >= %d), max(k)) kmax from cum group by pos), q1 as (select q0.match_id, q0.pos, "
		.. "row_number() over (partition by q0.pos order by q0.match_id desc) rn from q0 join lim using(pos) where "
		.. "q0.k <= lim.kmax), q as (select q1.match_id, q1.pos, p1.w0::float8 * count(*) over (partition by "
		.. "q1.pos) / sum(p1.w0) over (partition by q1.pos) wt from q1 join p1 using(match_id) where q1.rn <= %d), "
		.. "p as (select p1.* from p1 join q using(match_id)), x as (select p.match_id, q.pos, q.wt, p.won, "
		.. "v->>'key' i, (v->>'time')::int t, coalesce((case when p.r then 1 else -1 end) * "
		.. "p.adv[least(coalesce(array_length(p.adv, 1), 1), greatest(1, (v->>'time')::int / 60 + 1))], 0) ga from "
		.. "p join q using(match_id), unnest(p.purchase_log) v), f as (select match_id, pos, wt, won, i, min(t) t, "
		.. "sum(case when t<=0 then 1 else 0 end) s, (array_agg(ga order by t))[1] ga from x group by 1,2,3,4,5), "
		.. "kk as (select distinct p.match_id, q.pos, q.wt, p.dur, unnest(p.fin) it from p join q using(match_id)), "
		.. "g as (select q.pos, sum(q.wt) g, sum(case when p.won then q.wt else 0 end) gw, sum(case when p.dur >= "
		.. "2400 then q.wt else 0 end) g40, sum(case when p.dur >= 2400 and p.won then q.wt else 0 end) gw40 from q "
		.. "join p using(match_id) group by q.pos), bm as (select q.pos, mm.m, sum(case when (case when p.r then 1 "
		.. "else -1 end) * p.adv[mm.m + 1] <= -2000 then q.wt else 0 end) nb, sum(case when (case when p.r then 1 "
		.. "else -1 end) * p.adv[mm.m + 1] <= -2000 and p.won then q.wt else 0 end) wb from q join p "
		.. "using(match_id) cross join unnest(array[5,10,15,20,25,30,35,40,45,50]) mm(m) where array_length(p.adv, "
		.. "1) > mm.m group by q.pos, mm.m), a as (select f.pos p, i, sum(f.wt) n, sum(case when won then f.wt else "
		.. "0 end) w, percentile_cont(0.5) within group (order by t)::int t, sum(s * f.wt) s, sum(case when s>0 "
		.. "then f.wt else 0 end) m, sum(f.wt / (1 + exp(-(array[0.6,0.59,0.384,0.294,0.277,0.264,0.233,0.193,0.173,"
		.. "0.147,0.119,0.105,0.088])[least(13, greatest(1, round(f.t / 300.0)::int + 1))] * f.ga / 1000.0))) x "
		.. "from f join g using(pos) group by f.pos, i having sum(f.wt) >= greatest(2, "
		.. "max(g.g) * 0.03)), b as (select a.p, a.i, sum(f.wt) filter (where f.t <= a.t) ne, sum(f.wt) filter "
		.. "(where f.t <= a.t and f.won) we, sum(f.wt) filter (where f.ga <= -2000) nb, sum(f.wt) filter (where "
		.. "f.ga <= -2000 and f.won) wb from a join f on f.pos = a.p and f.i = a.i group by 1, 2), fk as (select "
		.. "kk.pos, kk.it, sum(kk.wt) n from kk join items on items.id = kk.it where items.cost >= 2000 and "
		.. "items.recipe = 0 group by 1, 2), fp as (select fk.* from fk join g using(pos) where fk.n >= g.g * "
		.. "0.08), kp as (select k1.pos, k1.it i1, k2.it i2, sum(k1.wt) nab from kk k1 join kk k2 on k2.match_id = "
		.. "k1.match_id and k2.pos = k1.pos and k1.it < k2.it group by 1, 2, 3), nn as (select p.match_id, q.pos, "
		.. "q.wt, p.won, least(v.k, 5) tr, v.x->>'item_neutral' ni, v.x->>'item_neutral_enhancement' ne from p join "
		.. "q using(match_id), unnest(p.nh) with ordinality v(x, k)), sk as (select q.pos, q.wt, p.won, v.k lv, v.x "
		.. "ab from p join q using(match_id), unnest(p.au) with ordinality v(x, k) where v.k <= 20) select a.p, "
		.. "a.i, round(a.n) n, round(a.w) w, a.t, round(a.s) s, round(a.m) m, null::float8 g, null::float8 gw, "
		.. "round(b.ne) ne, round(b.we) we, round(b.nb) nb, round(b.wb) wb, round(a.x::numeric, 1) x from a join b "
		.. "on b.p = a.p and b.i = a.i union all select kk.pos, '#' || it, round(sum(kk.wt)), null, null, null, "
		.. "null, null, null, null, null, null, null, null from kk join g using(pos) where it > 0 group by kk.pos, "
		.. "it having sum(kk.wt) >= greatest(2, max(g.g) * 0.03) union all select kk.pos, '%%' || it, "
		.. "round(sum(kk.wt)), null, null, null, null, round(max(g.g40)), round(max(g.gw40)), null, null, null, null, "
		.. "null from kk join g using(pos) where it > 0 and kk.dur >= 2400 group by kk.pos, it having sum(kk.wt) >= "
		.. "greatest(2, max(g.g40) * 0.05) union all select bm.pos, '!b' || bm.m, round(bm.nb), round(bm.wb), null, "
		.. "null, null, null, null, null, null, null, null, null from bm where bm.nb > 0 union all select a.pos, "
		.. "'&' || a.it || '.' || b.it, 1, null, null, null, null, null, null, null, null, null, null, null from fp a "
		.. "join fp b on b.pos = a.pos and a.it < b.it join g on g.pos = a.pos left join kp on kp.pos = a.pos and "
		.. "kp.i1 = a.it and kp.i2 = b.it where a.n * b.n >= 5 * g.g and coalesce(kp.nab, 0) * g.g < 0.4 * a.n * b.n "
		.. "union all select nn.pos, '^' || nn.tr || '.' || nn.ni, round(sum(nn.wt)), round(sum(case when nn.won "
		.. "then nn.wt else 0 end)), null, null, null, null, null, null, null, null, null, null from nn join g "
		.. "using(pos) where nn.ni is not null and g.g >= 30 group by nn.pos, nn.tr, nn.ni having sum(nn.wt) >= "
		.. "greatest(2, max(g.g) * 0.05) union all select z.pos, '~' || z.ne, round(sum(z.wt)), round(sum(case when "
		.. "z.won then z.wt else 0 end)), null, null, null, null, null, null, null, null, null, null from (select "
		.. "distinct match_id, pos, wt, won, ne from nn where ne is not null and tr = 1) z join g using(pos) where "
		.. "g.g >= 30 group by z.pos, z.ne having sum(z.wt) >= greatest(2, max(g.g) * 0.04) union all select "
		.. "sk.pos, '*' || sk.lv || '.' || sk.ab, round(sum(sk.wt)), round(sum(case when sk.won then sk.wt else 0 "
		.. "end)), null, null, null, null, null, null, null, null, null, null from sk join g using(pos) where g.g >= "
		.. "30 group by sk.pos, sk.lv, sk.ab having sum(sk.wt) >= greatest(2, max(g.g) * 0.08) union all select "
		.. "lim.pos, '@' || prk.patch, lim.kmax, null, null, null, null, round(max(g.g)), round(max(g.gw)), null, "
		.. "null, null, null, null from lim join prk on prk.k = lim.kmax join g using(pos) group by lim.pos, "
		.. "prk.patch, lim.kmax",
	BUYS_VER = 13,
	BUYS_OLD = 12,
	ABIL_URLS = {
		"https://raw.githubusercontent.com/odota/dotaconstants/master/build/ability_ids.json",
		"https://cdn.jsdelivr.net/gh/odota/dotaconstants@master/build/ability_ids.json",
	},
	SKILL_LEVELS = 18,
	POINT_LEVELS = { 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 18, 20, 25, 26, 27, 28, 29, 30 },
	SKILL_SLACK = 0.5,
	TALENT_LATE = 0.5,
	TALENT_TIERS = { 10, 15, 20, 25 },
	NEUTRAL_ALTS = 2,
	SUB_KEPT = 0.6,
	BUYS_PAGE = 200,
	PATCH_MAX = 5,
	BUYS_COLS = { "p", "i", "n", "w", "t", "s", "m", "g", "gw", "ne", "we", "nb", "wb", "x" },
	WIN_MIN = 20,
	BUYS_MATCHES = 6000,
	BUYS_WANT = 80,
	BUYS_Q = 2,
	PACK_DIR = "dh_pack",
	STALE_TRY = 600,
	POOL_N = 100,
	SYNTH_N = 60,
	SYNTH = "",
	BUYS_CAP = 1500,
	LIFT_PRIOR = 30,
	LIFT_FIT_MIN = 15,
	LIFT_K = 4,
	LIFT_LO = 0.6,
	LIFT_HI = 1.4,
	BUYS_MIN = 30,
	BUYS_TTL = 3 * 86400,
	BUYS_KEEP = 30,
	LATE_GAMES_MIN = 15,
	FATE_LOG_SHARE = 0.1,
	FATE_SKIP = { aghanims_shard = true, ultimate_scepter_2 = true },
	NW_PROBE = { 60, 600 },
	SHOW_MIN = 8,
	LATE_SHARE = 0.2,
	LATE_MAX = 3,
	STEP_SHARE = 0.3,
	STEP_ITEMS = { "aghanims_shard", "moon_shard" },
	SELL_MIN = 0.25,
	SELL_GAP = 300,
	SELL_SHOW_COST = 400,
	SELL_SOFT_COST = 100,
	SELL_MAX = 2000,
	SELL_DROP = 0.6,
	DIS_MIN = 500,
	SELL_COUNTER = 0.3,
	SELL_SKIP = {
		aegis = true, cheese = true, gem = true, ward_dispenser = true, dust = true, smoke_of_deceit = true,
		refresher_shard = true, tpscroll = true,
	},
	BACKPACK = 3,
	LANE_W = 0.5,
	LANE_OPP = {
		{ [3] = true, [4] = true }, { [2] = true }, { [1] = true, [5] = true },
		{ [1] = true, [5] = true }, { [3] = true, [4] = true },
	},
	SUPPORT_ITEM_W = 0.67,
	INSTEAD = {
		butterfly = { skadi = true, satanic = true, greater_crit = true, disperser = true, abyssal_blade = true },
	},
	INSTEAD_BONUS = 0.1,
	BUY_GAP = 0.15,
	PICK_CHECK = 1.5,
	PICK_TRIES = 4,
	SAY_GAP = 1.5,
	SAY_TOP = 2,
	LOGO_PATH = "M28.2 63.9C17.0 63.0 6.0 54.5 2.5 44.1C1.4 40.6 1.1 39.1 1.1 34.6C1.1 29.1 1.9 25.3 4.2 20.2C10.3 6.3 24.5 -1.9 38.0 0.6C44.9 1.8 49.5 4.8 52.8 10.0C57.2 17.2 55.7 23.4 49.0 25.3C47.5 25.8 42.8 26.3 42.2 26.1C42.0 26.0 41.9 26.2 41.7 26.7C40.2 30.4 38.7 31.9 33.2 35.7C30.4 37.7 29.0 38.7 28.3 39.7C26.8 41.8 27.9 44.3 30.8 45.7C34.9 47.5 40.5 46.2 43.8 42.6C45.7 40.5 45.9 39.6 44.4 38.6C43.0 37.6 42.5 36.3 43.2 35.0C43.5 34.3 43.7 34.1 48.2 31.6C49.4 30.9 52.3 29.3 54.6 27.9C59.2 25.3 60.0 25.0 61.3 25.7C62.2 26.2 62.4 26.7 62.6 31.8C62.7 34.4 62.9 38.5 63.0 40.9C63.2 45.9 63.2 46.4 62.4 47.3C61.6 48.1 60.9 48.3 59.5 47.7C58.8 47.5 58.2 47.4 57.9 47.5C57.1 47.7 55.7 49.0 54.1 51.3C48.7 58.8 41.3 63.2 32.5 63.9C31.3 64.0 30.2 64.1 30.1 64.1C30.0 64.1 29.2 64.0 28.2 63.9ZM17.7 28.8C18.9 28.5 19.9 27.7 20.5 26.7C21.1 25.7 21.3 23.7 20.8 22.8C19.8 20.8 16.6 21.0 14.9 23.2C12.9 26.0 13.3 28.3 15.8 28.9C16.6 29.1 16.7 29.1 17.7 28.8ZM30.4 26.1C36.6 24.5 44.4 18.3 44.4 15.1C44.4 12.9 40.7 11.9 36.9 12.9C32.4 14.2 25.6 19.9 24.7 23.1C24.0 26.2 26.0 27.3 30.4 26.1ZM19.3 18.0C24.7 16.8 33.2 11.4 34.0 8.7C34.8 5.9 30.1 4.1 25.3 5.5C20.9 6.7 15.7 10.9 14.4 14.4C13.7 16.0 14.1 17.7 15.2 18.1C15.9 18.4 17.9 18.3 19.3 18.0Z",
	LOGO_BANDS = 12,
	SKV = "",
	TLM = "",
	SKV_MARGIN = 0.05,
	SKV_WHY = 0.15,
	BAN_FILE = "draft_helper_bans.txt",
	OWN_START = 0.5,
	OWN_LEAD = 0.15,
	BAN_MIN_W = 24,
	BAN_SKIP = { tpscroll = true, ward_dispenser = true, ward_observer = true, ward_sentry = true },
	MENU_CACHE = 0.01,
	SLOW_MS = 40,
	TW_MAX = 6000,
	REASON_DROP = { { 2, 2 }, { 1, 2 }, { 2, 1 } },
	SCALES = 16,
	COLOR_MAX = 4096,
	PERF_EVERY = 15,
	GC_MODE = "generational",
	SLOW_PART = 0.003,
	SLOW_GAP = 20,
	AUTO_EVERY = 0.4,
	PART_TIE = 30,
	AUTO_SETTLE = 1.2,
	AUTO_FAIL_SKIP = 30,
	TP_SLOT = 15,
	STASH_FIRST = 9,
	COURIER_EVERY = 5,
	COURIER_TRIES = 2,
	COURIER_BACKOFF = 60,
	SECRET = {
		demon_edge = true, eagle = true, energy_booster = true, hyperstone = true, mystic_staff = true, platemail = true,
		point_booster = true, reaver = true, relic = true, ring_of_tarrasque = true, talisman_of_evasion = true,
		ring_of_health = true, void_stone = true,
		tiara_of_selemene = true, ultimate_orb = true, vitality_booster = true,
	},
	SECRET_EVERY = 4,
	SECRET_IDLE = 20,
	SECRET_LEARN = 2,
	COURIER_SLOTS = 6,
	STASH_MAX = 4,
	STASH_SLOTS = 6,
	START_POS_WAIT = 25,
	STOCKED = {
		ward_observer = true, ward_sentry = true, blood_grenade = true, smoke_of_deceit = true, gem = true,
		infused_raindrop = true, tango = true, clarity = true, enchanted_mango = true, aghanims_shard = true,
		tome_of_knowledge = true,
	},
	BB_BASE = 200,
	BB_DIV = 12,
	BB_CORE_FROM = 1800,
	BB_SUP_FROM = 2400,
	SOLO_FROM = 720,
	SOLO_SHARE = 0.3,
	SOLO_DEATHS = 3,
	SOLO_HOLD = 60,
	SOLO_AWAY = 120,
	CONN_CONNECTED = 2,
	CONN_DISCONNECTED = 3,
	CONN_ABANDONED = 4,
	SOLO = {
		core = {
			sheepstick = 0.039, satanic = 0.039, abyssal_blade = 0.033, assault = 0.026, greater_crit = 0.023,
			dagon = 0.02, ethereal_blade = 0.02, eternal_shroud = 0.019, moon_shard = 0.018,
			aether_lens = 0.017, bloodstone = 0.017, witch_blade = 0.017, diffusal_blade = 0.016,
			monkey_king_bar = 0.015, soul_booster = 0.015, gungir = 0.014, oblivion_staff = 0.013,
			rod_of_atos = 0.013, shivas_guard = 0.013, mask_of_madness = 0.012, maelstrom = 0.01,
			wraith_band = 0.01, lesser_crit = 0.01, null_talisman = 0.008, ultimate_scepter = -0.007,
			blink = -0.008, soul_ring = -0.009, falcon_blade = -0.01, pipe = -0.011, kaya = -0.011,
			magic_wand = -0.011, lotus_orb = -0.013, yasha_and_kaya = -0.015, bfury = -0.019,
			helm_of_the_overlord = -0.021, travel_boots = -0.021, aeon_disk = -0.023,
			helm_of_the_dominator = -0.025, black_king_bar = -0.028,
		},
		sup = {
			ethereal_blade = 0.052, meteor_hammer = 0.045, travel_boots = 0.042, sheepstick = 0.038,
			octarine_core = 0.031, soul_booster = 0.028, ultimate_scepter = 0.027, lesser_crit = 0.026,
			vladmir = 0.019, aether_lens = 0.012, aghanims_shard = 0.011, force_staff = -0.01, pavise = -0.017,
			solar_crest = -0.018, gem = -0.022, heavens_halberd = -0.026, essence_distiller = -0.04,
		},
	},
	SOLO_P = 0.5,
	DANGER_KILLS_MIN = 5,
	DANGER_LEAD = 0.3,
	DANGER_LEAD_KILLS = 3,
	DANGER_BASE = 0.7,
	DANGER_K = 2.0,
	DANGER_LO = 0.8,
	DANGER_HI = 1.5,
	DANGER_DMG_W = 0.4,
	DMG_HALF = 300,
	DMG_MIN_HP = 0.5,
	DMG_LEAD_HP = 0.3,
	DMG_ATT_HI = 0.65,
	DMG_ATT_LO = 0.35,
	DMG_T = 0.3,
	DMG_PRESS_LO = 0.2,
	DMG_PRESS_SPAN = 0.3,
	HURT_WAIT = 180,
	LEADER_HARD = { evasion = true, magic = true, targeted = true },
	EXT_MIN_N = 5,
	EXT_SHARE = 0.03,
	EXT_MAX = 6,
	EXT_T_MIN = 1200,
	SOLE_T = 0.6,
	UP_FROM = 1800,
	UP_MAX = 3,
	UP_GOLD_STEP = 1000,
	WEAK_COST = 1.25,
	WEAK_COST_RICH = 1,
	BLINK_ATTR = { overwhelming_blink = "str", swift_blink = "agi", arcane_blink = "int" },
	TURBO_T = 0.45,
	REP_ANTI = 0.3,
	REP_COST_LO = 0.5,
	MX_CAP = 0.06,
	MX_W = 4,
	MX_MIN_SHARE = 0.05,
	MX_REP = 0.03,
	MX_SHOW = 0.01,
	MX_W_LO = 0.5,
	MX_W_HI = 1.5,
	STUN_HI = 5.1,
	STUN_BKB = 0.01,
	STUN_FROM = 300,
	MX_CORE = "abyssal_blade>butterfly:-2.2;abyssal_blade>devastator:1.3;abyssal_blade>refresher:-1.4;aeon_disk>assault:-2.2;"
		.. "aeon_disk>harpoon:-1.7;aeon_disk>wraith_band:-2.2;aether_lens>bloodstone:2.3;aether_lens>dust:-2.1;"
		.. "aether_lens>falcon_blade:-2.3;aether_lens>hydras_breath:1.3;aether_lens>sheepstick:2.1;"
		.. "aether_lens>specialists_array:1.5;aether_lens>swift_blink:2.8;ancient_janggo>black_king_bar:1.7;"
		.. "arcane_boots>hydras_breath:-1.1;arcane_boots>vladmir:-2.3;assault>swift_blink:2.4;"
		.. "bloodstone>sange_and_yasha:-1.9;bloodthorn>devastator:1.9;bloodthorn>lotus_orb:2.5;bloodthorn>refresher:1.8;"
		.. "bloodthorn>sange_and_yasha:-2.5;boots_of_bearing>hand_of_midas:1.8;bracer>phylactery:-1.7;"
		.. "butterfly>abyssal_blade:3.1;butterfly>hurricane_pike:-2.2;butterfly>lesser_crit:-2.1;butterfly>lotus_orb:2.1;"
		.. "butterfly>monkey_king_bar:3.2;consecrated_wraps>bloodstone:1.8;consecrated_wraps>magic_wand:-2.2;"
		.. "crimson_guard>sange_and_yasha:-2.2;crimson_guard>yasha:-2.1;crimson_guard>yasha_and_kaya:-2.2;"
		.. "dagon>hand_of_midas:2.3;desolator>ancient_janggo:1.9;desolator>bloodthorn:1.7;desolator>sheepstick:2.2;"
		.. "devastator>radiance:-2.8;devastator>sheepstick:2.1;disperser>shivas_guard:-1.9;dust>rod_of_atos:2.2;"
		.. "echo_sabre>rod_of_atos:-2;echo_sabre>sheepstick:2.2;echo_sabre>sphere:2.1;ethereal_blade>nullifier:1.6;"
		.. "falcon_blade>revenants_brooch:-1.7;gem>aghanims_shard:-1.9;gem>magic_wand:-2.3;gem>nullifier:-2.5;"
		.. "ghost>guardian_greaves:1.9;ghost>refresher:2.1;greater_crit>butterfly:2.6;guardian_greaves>armlet:3.1;"
		.. "guardian_greaves>heart:1.9;gungir>aghanims_shard:2.9;gungir>dust:-2.4;gungir>octarine_core:2;"
		.. "gungir>soul_booster:1.7;hand_of_midas>black_king_bar:2;hand_of_midas>mask_of_madness:-2.2;"
		.. "harpoon>rod_of_atos:-1.9;harpoon>sheepstick:2.3;harpoon>sphere:2.3;helm_of_the_dominator>magic_wand:-2;"
		.. "hurricane_pike>butterfly:2.4;hurricane_pike>helm_of_the_dominator:2.5;hurricane_pike>skadi:2.8;"
		.. "hydras_breath>magic_wand:-1.7;lesser_crit>butterfly:2.6;lotus_orb>consecrated_wraps:1.7;"
		.. "mage_slayer>magic_wand:-2.2;mask_of_madness>sheepstick:2.5;mekansm>armlet:2.6;mekansm>heart:2;"
		.. "monkey_king_bar>butterfly:-4.7;monkey_king_bar>dust:2.1;monkey_king_bar>shivas_guard:2.9;"
		.. "monkey_king_bar>veil_of_discord:2.6;n.chipped_vest>invis_sword:1.9;n.chipped_vest>octarine_core:-2;"
		.. "n.cloak_of_flames>pers:-2.2;n.essence_ring>phylactery:-1.6;n.essence_ring>revenants_brooch:-1.6;"
		.. "n.guardian_shell>basher:-1.6;n.guardian_shell>soul_booster:-1.7;n.kobold_cup>sange:2.2;"
		.. "n.mana_draught>bloodthorn:2.3;n.medallion_of_courage>dragon_lance:2.4;n.misericorde>abyssal_blade:2.2;"
		.. "n.pogo_stick>magic_wand:1.9;n.poor_mans_shield>hand_of_midas:1.9;n.psychic_headband>ultimate_scepter:-1.7;"
		.. "n.spellslinger>blade_mail:-2.1;n.stormcrafter>black_king_bar:-2;n.stormcrafter>maelstrom:2.2;"
		.. "n.weighted_dice>yasha:-1.6;n.whisper_of_the_dread>pers:2.2;nullifier>satanic:2.1;"
		.. "octarine_core>abyssal_blade:1.9;octarine_core>invis_sword:-2.2;octarine_core>swift_blink:2.1;"
		.. "orchid>butterfly:2.3;orchid>lotus_orb:2.7;orchid>sange_and_yasha:-2.1;orchid>swift_blink:2.1;"
		.. "pavise>desolator:-2.3;pipe>ultimate_scepter:-1.7;power_treads>desolator:-2.2;radiance>devastator:2.9;"
		.. "revenants_brooch>pers:1.9;revenants_brooch>wraith_band:-1.5;rod_of_atos>black_king_bar:1.9;"
		.. "rod_of_atos>dust:-2.6;sange>devastator:2.4;sange_and_yasha>crimson_guard:2.9;sange_and_yasha>orchid:2.2;"
		.. "satanic>abyssal_blade:2.7;sheepstick>black_king_bar:2.2;silver_edge>black_king_bar:2.1;"
		.. "silver_edge>bloodthorn:1.5;silver_edge>monkey_king_bar:-1.8;silver_edge>octarine_core:2.1;"
		.. "skadi>force_staff:-3;skadi>hurricane_pike:-2.5;skadi>pers:2.2;skadi>yasha_and_kaya:-2.2;"
		.. "solar_crest>dagon:-1.9;solar_crest>desolator:-2.3;soul_booster>abyssal_blade:2.4;"
		.. "soul_booster>black_king_bar:1.8;soul_ring>disperser:-2;soul_ring>nullifier:-3.1;sphere>dust:2.1;"
		.. "sphere>harpoon:-2;swift_blink>ghost:-2;swift_blink>shivas_guard:-2.6;swift_blink>veil_of_discord:-2.7;"
		.. "ultimate_scepter>black_king_bar:2.5;ultimate_scepter>yasha_and_kaya:-2.6;veil_of_discord>monkey_king_bar:-2.7;"
		.. "vladmir>consecrated_wraps:1.6;vladmir>veil_of_discord:2.6;yasha>crimson_guard:2.4;yasha>lotus_orb:2.4;"
		.. "yasha_and_kaya>crimson_guard:2.2;",
	MX_SUP = "aeon_disk>aghanims_shard:-3;aether_lens>black_king_bar:3;aghanims_shard>dragon_lance:-2.3;"
		.. "armlet>guardian_greaves:-4.5;armlet>mekansm:-3;bfury>lotus_orb:3.1;black_king_bar>rod_of_atos:-3.9;"
		.. "blink>soul_ring:-1.5;bloodstone>aether_lens:-3.1;bloodstone>ghost:2.4;bloodthorn>ghost:3.1;"
		.. "bloodthorn>magic_wand:3.3;butterfly>black_king_bar:2.9;cyclone>glimmer_cape:2.2;desolator>dust:2.8;"
		.. "desolator>pavise:2.8;desolator>solar_crest:3;devastator>sheepstick:2.4;echo_sabre>hand_of_midas:2.4;"
		.. "falcon_blade>aether_lens:2.5;ghost>blink:2.1;hydras_breath>aether_lens:-1.8;invis_sword>black_king_bar:3.1;"
		.. "invis_sword>dust:2.5;invis_sword>invis_sword:2.4;kaya>aghanims_shard:-2;lotus_orb>ward_sentry:2.5;"
		.. "mage_slayer>rod_of_atos:-3.2;mask_of_madness>rod_of_atos:3.3;mekansm>aeon_disk:3.1;mekansm>lotus_orb:2.7;"
		.. "mekansm>pers:2.9;monkey_king_bar>lotus_orb:2.4;monkey_king_bar>pers:2.5;n.gale_guard>cyclone:-2.5;"
		.. "n.spark_of_courage>ward_sentry:-1.8;nullifier>ward_sentry:1.9;orchid>ghost:2.8;phase_boots>soul_booster:-2;"
		.. "refresher>pers:2.7;sheepstick>lotus_orb:2.5;sheepstick>null_talisman:-2.7;sheepstick>pers:2.8;"
		.. "shivas_guard>ghost:-3.6;shivas_guard>pipe:3.2;silver_edge>black_king_bar:2.3;silver_edge>dust:3;"
		.. "skadi>essence_distiller:3.2;soul_booster>holy_locket:-2.6;specialists_array>aether_lens:-2.2;"
		.. "sphere>ghost:-2.7;swift_blink>aether_lens:-3.9;swift_blink>glimmer_cape:-2.8;travel_boots>pers:3;"
		.. "ultimate_scepter>black_king_bar:3.1;wraith_band>dust:2.6;",
	MXE_CORE = "aether_lens>invis_sword:2.7;aether_lens>kaya_and_sange:2.9;aether_lens>silver_edge:2.8;aether_lens>sphere:2.3;"
		.. "aghanims_shard>butterfly:2.9;ancient_janggo>skadi:2.6;arcane_boots>vladmir:-3.3;black_king_bar>ghost:-3.5;"
		.. "blade_mail>abyssal_blade:2.5;bloodstone>ultimate_scepter:-2.6;consecrated_wraps>harpoon:-2.1;"
		.. "consecrated_wraps>hurricane_pike:-2.9;crimson_guard>arcane_boots:-2.5;dagon>bfury:3;dagon>echo_sabre:-3.9;"
		.. "desolator>consecrated_wraps:2.4;dust>invis_sword:-3.4;echo_sabre>satanic:2.7;force_staff>heart:2.7;"
		.. "force_staff>manta:2.6;force_staff>octarine_core:3.8;force_staff>orchid:3.5;force_staff>yasha:2.6;"
		.. "ghost>pipe:2.9;glimmer_cape>assault:3;glimmer_cape>black_king_bar:3;glimmer_cape>monkey_king_bar:2.4;"
		.. "glimmer_cape>sphere:3;greater_crit>black_king_bar:2;hand_of_midas>assault:3.4;hand_of_midas>bloodthorn:2.5;"
		.. "helm_of_the_overlord>veil_of_discord:2.9;hurricane_pike>assault:2.6;hurricane_pike>cyclone:-2.7;"
		.. "hurricane_pike>ghost:-2.2;hurricane_pike>manta:3.2;hurricane_pike>orchid:4.8;hurricane_pike>yasha:2.8;"
		.. "invis_sword>dust:3.5;kaya>black_king_bar:1.9;lesser_crit>refresher:3.5;manta>bloodstone:2.6;"
		.. "manta>specialists_array:1.8;mekansm>harpoon:2.9;mjollnir>skadi:2.6;n.dormant_curio>vladmir:4.2;"
		.. "n.duelist_gloves>arcane_boots:-2.8;n.duelist_gloves>orchid:3.9;n.duelist_gloves>spirit_vessel:-3;"
		.. "n.guardian_shell>maelstrom:2.8;n.guardian_shell>mjollnir:3.2;n.kobold_cup>yasha:2.6;"
		.. "n.medallion_of_courage>octarine_core:3.7;n.misericorde>disperser:2.1;n.occult_bracelet>vladmir:2.7;"
		.. "n.seeds_of_serenity>black_king_bar:-2.8;n.spark_of_courage>pers:3.7;n.weighted_dice>black_king_bar:3.2;"
		.. "orb_of_corrosion>bfury:-3.8;orchid>ancient_janggo:-3.5;pavise>refresher:2.3;pavise>satanic:3.6;"
		.. "pers>monkey_king_bar:2.9;phylactery>kaya_and_sange:-2.7;phylactery>sange:-3.5;pipe>yasha_and_kaya:-2.8;"
		.. "sange>sheepstick:2.5;travel_boots>helm_of_the_dominator:2.8;travel_boots>octarine_core:4.2;"
		.. "ultimate_scepter>refresher:2.8;ultimate_scepter>satanic:3;ultimate_scepter>sheepstick:2.9;vladmir>ghost:3;"
		.. "witch_blade>echo_sabre:-2.9;yasha_and_kaya>vladmir:-2.5;",
	MXE_SUP = "aether_lens>dust:3.2;aghanims_shard>guardian_greaves:3.6;desolator>solar_crest:3.1;dust>glimmer_cape:-2.4;"
		.. "glimmer_cape>bracer:3.6;greater_crit>magic_wand:3.5;harpoon>ultimate_scepter:3.4;invis_sword>dust:4.2;"
		.. "invis_sword>force_staff:3.5;invis_sword>gem:3.5;invis_sword>ward_sentry:3.2;lesser_crit>gem:-3.7;"
		.. "lesser_crit>hand_of_midas:3;maelstrom>hand_of_midas:3.2;manta>gem:3.7;mjollnir>hand_of_midas:3.4;"
		.. "n.kobold_cup>power_treads:-3;n.medallion_of_courage>guardian_greaves:-3.8;n.misericorde>pers:3.7;"
		.. "oblivion_staff>invis_sword:2.8;oblivion_staff>pipe:-2.3;pavise>vladmir:3.6;pipe>dust:-3.5;vladmir>kaya:5.9;",
	MXA_CORE = "armlet>ghost:1.9;basher>basher:3.9;basher>mask_of_madness:-2;basher>silver_edge:-1.9;bfury>invis_sword:2.4;"
		.. "black_king_bar>black_king_bar:-1.7;black_king_bar>bloodstone:-3;black_king_bar>bloodthorn:-2.4;"
		.. "black_king_bar>orchid:-2.3;black_king_bar>soul_booster:-2.4;blade_mail>ancient_janggo:-2.1;"
		.. "blink>devastator:-2.2;bloodstone>echo_sabre:2.4;bloodthorn>yasha_and_kaya:3.9;"
		.. "consecrated_wraps>sange_and_yasha:1.8;crimson_guard>hand_of_midas:2.1;dagon>mask_of_madness:2;"
		.. "desolator>monkey_king_bar:2.6;devastator>monkey_king_bar:-2.1;dragon_lance>dragon_lance:-2.2;"
		.. "dragon_lance>force_staff:-2.3;dragon_lance>hurricane_pike:-2.4;essence_distiller>ghost:-2.1;"
		.. "eternal_shroud>null_talisman:1.5;ethereal_blade>butterfly:2.1;ethereal_blade>hand_of_midas:1.7;"
		.. "ethereal_blade>oblivion_staff:2.4;ethereal_blade>orchid:2.4;falcon_blade>falcon_blade:2.4;ghost>armlet:2.3;"
		.. "greater_crit>blink:2.2;greater_crit>force_staff:-2.5;greater_crit>greater_crit:-2.2;"
		.. "greater_crit>lesser_crit:-2.9;greater_crit>satanic:-2;greater_crit>wraith_band:-2.3;hand_of_midas>dagon:2;"
		.. "hand_of_midas>skadi:2.7;harpoon>heart:2.1;harpoon>wraith_band:-2.3;heavens_halberd>kaya:-2.4;"
		.. "heavens_halberd>oblivion_staff:2.1;helm_of_the_overlord>radiance:-2.2;holy_locket>witch_blade:2.3;"
		.. "hurricane_pike>blink:1.8;hurricane_pike>dragon_lance:-2.3;hurricane_pike>hurricane_pike:-2.3;"
		.. "hurricane_pike>lesser_crit:-2.7;invis_sword>sphere:-2.3;kaya_and_sange>hand_of_midas:-2.4;"
		.. "kaya_and_sange>revenants_brooch:-1.8;lesser_crit>blink:1.7;lesser_crit>greater_crit:-2.7;"
		.. "maelstrom>maelstrom:-2.5;maelstrom>ultimate_scepter:2;mage_slayer>pers:-3;mask_of_madness>basher:-2.4;"
		.. "mekansm>boots_of_bearing:-2;mjollnir>force_staff:-2.3;monkey_king_bar>desolator:2.6;monkey_king_bar>dust:-2.3;"
		.. "orb_of_corrosion>maelstrom:-2.7;orchid>helm_of_the_dominator:-2.4;phylactery>radiance:-2;"
		.. "phylactery>yasha_and_kaya:2.6;pipe>harpoon:2.5;radiance>consecrated_wraps:2.2;radiance>phylactery:-1.8;"
		.. "radiance>radiance:3.5;radiance>shivas_guard:2.3;rod_of_atos>sheepstick:2.3;sange_and_yasha>ghost:2.8;"
		.. "satanic>null_talisman:2.6;satanic>yasha:-2.5;travel_boots>kaya_and_sange:2.4;travel_boots>travel_boots:2.4;"
		.. "ultimate_scepter>helm_of_the_dominator:-2.3;ultimate_scepter>maelstrom:2.6;wraith_band>greater_crit:-2.4;"
		.. "wraith_band>guardian_greaves:2.1;wraith_band>harpoon:-2.2;yasha>ghost:2.3;yasha_and_kaya>bloodthorn:3.6;"
		.. "yasha_and_kaya>heart:2.3;",
	MXA_SUP = "ancient_janggo>ward_sentry:1.1;desolator>invis_sword:1.9;desolator>phase_boots:1.9;echo_sabre>pipe:1.7;"
		.. "essence_distiller>dust:-2.1;falcon_blade>phase_boots:-2;guardian_greaves>ward_sentry:1.4;"
		.. "heavens_halberd>cyclone:-1.7;mage_slayer>kaya:-2.1;mekansm>ward_sentry:1.4;sheepstick>rod_of_atos:2;",
	MXL_CORE = "27>bracer:4;30>blink:3.3;35>hand_of_midas:3.7;37>null_talisman:4;65>maelstrom:3.3;70>blink:4.4;"
		.. "74>maelstrom:-2.9;",
	LANE_LOST = "",
	VSH_CORE = "1>monkey_king_bar:1.66;1>skadi:0.38;2>sange:1.19;2>sange_and_yasha:1.4;2>sphere:0.5;3>lotus_orb:1.7;"
		.. "3>pers:1.44;3>sphere:1.65;4>pers:1.75;4>sphere:1.86;5>black_king_bar:0.86;5>ward_sentry:0.81;"
		.. "6>butterfly:0.54;7>aeon_disk:1.98;7>pers:0.68;7>sange:1.18;7>sange_and_yasha:1.31;8>black_king_bar:0.78;"
		.. "8>lotus_orb:1.99;8>pers:1.39;9>dust:1.3;10>monkey_king_bar:1.62;10>skadi:1.61;12>maelstrom:1.67;"
		.. "12>mjollnir:1.8;13>bloodthorn:1.44;13>oblivion_staff:1.42;13>orchid:1.95;13>pers:0.75;13>pipe:1.36;"
		.. "13>sheepstick:2.08;14>black_king_bar:0.78;15>force_staff:1.33;15>hurricane_pike:1.29;16>dust:2.1;"
		.. "16>pipe:1.79;16>ward_sentry:1.19;17>oblivion_staff:1.25;17>orchid:1.56;17>sheepstick:1.5;"
		.. "18>monkey_king_bar:0.37;20>black_king_bar:0.79;21>blade_mail:1.22;21>greater_crit:0.78;"
		.. "21>monkey_king_bar:2.54;22>dust:0.74;22>eternal_shroud:1.95;23>cyclone:1.53;25>sphere:1.45;"
		.. "26>sange_and_yasha:1.24;28>black_king_bar:0.86;28>butterfly:1.34;28>crimson_guard:1.45;28>ghost:1.61;"
		.. "28>lotus_orb:1.79;28>manta:1.26;28>pipe:0.52;28>shivas_guard:1.27;28>wraith_band:1.29;"
		.. "29>invis_sword:1.67;29>silver_edge:1.98;31>nullifier:1.47;32>dust:2.88;32>force_staff:1.67;"
		.. "32>monkey_king_bar:1.85;34>nullifier:2.65;35>black_king_bar:0.85;36>nullifier:3.08;37>dust:1.24;"
		.. "38>lotus_orb:1.57;38>pers:1.82;38>sange_and_yasha:1.25;38>sphere:2.63;39>dust:0.79;"
		.. "42>black_king_bar:0.81;44>greater_crit:0.69;44>lesser_crit:0.79;44>monkey_king_bar:3.45;"
		.. "44>silver_edge:1.56;45>dust:1.44;45>nullifier:2.67;46>assault:1.49;46>black_king_bar:0.85;"
		.. "46>butterfly:1.27;46>dust:1.48;46>ghost:1.48;46>heavens_halberd:1.97;46>manta:1.27;"
		.. "46>monkey_king_bar:0.47;46>pipe:0.65;46>shivas_guard:1.28;46>veil_of_discord:1.24;48>dust:0.76;"
		.. "48>ward_sentry:0.81;49>pers:1.24;49>sphere:1.42;52>blade_mail:1.38;52>mage_slayer:1.57;"
		.. "53>force_staff:1.32;53>hurricane_pike:1.3;54>bloodthorn:1.58;54>monkey_king_bar:1.62;"
		.. "54>oblivion_staff:1.26;54>orchid:1.51;55>nullifier:1.87;56>dust:3.29;56>gem:2.05;56>ghost:1.66;"
		.. "57>nullifier:1.97;59>invis_sword:1.54;59>silver_edge:1.7;62>dust:3.01;62>ward_sentry:1.27;63>dust:1.41;"
		.. "63>orchid:1.4;65>lotus_orb:1.5;65>pers:1.64;65>sphere:2.05;65>wraith_band:0.74;67>invis_sword:1.7;"
		.. "67>pers:1.49;67>silver_edge:1.95;67>sphere:1.75;69>lotus_orb:1.57;69>pers:2.05;69>sange_and_yasha:1.37;"
		.. "69>satanic:0.56;69>sphere:3.17;70>butterfly:1.38;70>crimson_guard:0.55;70>cyclone:2.11;"
		.. "70>force_staff:1.21;70>hurricane_pike:1.21;70>monkey_king_bar:0.29;70>nullifier:1.42;"
		.. "71>black_king_bar:0.77;71>cyclone:1.39;71>pers:1.5;71>sphere:2.67;72>crimson_guard:1.41;74>dust:2.15;"
		.. "75>cyclone:1.65;75>lotus_orb:1.89;75>manta:1.27;75>pers:1.29;77>assault:1.59;77>butterfly:1.52;"
		.. "77>crimson_guard:1.72;78>monkey_king_bar:1.94;83>dust:1.5;83>manta:1.42;84>black_king_bar:0.83;"
		.. "86>ward_sentry:0.87;88>dust:1.46;88>gem:2.24;90>lotus_orb:1.5;94>crimson_guard:1.66;"
		.. "94>diffusal_blade:2.57;94>disperser:3.17;94>heavens_halberd:1.76;94>monkey_king_bar:2.23;"
		.. "94>vanguard:1.43;95>cyclone:1.58;97>sange_and_yasha:1.24;98>nullifier:1.44;98>pipe:0.67;"
		.. "99>invis_sword:2.68;99>silver_edge:3.4;100>force_staff:1.18;101>cyclone:1.37;104>black_king_bar:0.67;"
		.. "104>pers:1.8;104>sphere:3.31;106>lotus_orb:1.58;106>manta:1.18;108>black_king_bar:1.15;"
		.. "109>crimson_guard:1.59;109>revenants_brooch:1.55;110>pipe:1.31;129>black_king_bar:1.2;"
		.. "129>force_staff:0.79;129>hurricane_pike:0.79;129>pers:0.77;131>nullifier:1.86;136>crimson_guard:1.43;"
		.. "137>lotus_orb:1.59;137>pers:1.68;137>sphere:2.06;138>black_king_bar:1.18;",
	VSH_SUP = "2>cyclone:1.58;3>lotus_orb:1.71;3>pers:1.56;4>pers:1.66;7>dust:0.86;8>dust:0.82;8>lotus_orb:1.68;"
		.. "8>pers:1.61;9>bracer:1.56;9>dust:1.38;9>essence_distiller:1.74;10>ghost:0.73;10>spirit_vessel:1.43;"
		.. "13>aghanims_shard:0.86;13>force_staff:0.75;13>glimmer_cape:1.31;13>oblivion_staff:2.22;13>orchid:2.58;"
		.. "13>sheepstick:1.84;14>dust:0.84;14>gem:0.69;14>pavise:0.8;14>solar_crest:0.79;15>force_staff:1.31;"
		.. "16>dust:1.77;16>pipe:1.79;17>force_staff:0.84;17>glimmer_cape:1.31;17>orchid:1.57;20>dust:0.78;"
		.. "20>gem:0.62;22>dust:0.81;22>pipe:1.96;28>ghost:1.7;28>glimmer_cape:0.56;28>pavise:1.36;"
		.. "28>solar_crest:1.36;29>silver_edge:1.7;32>dust:2.1;32>force_staff:1.64;32>gem:1.55;32>ghost:1.72;"
		.. "34>cyclone:1.36;35>bracer:1.28;36>pavise:0.65;36>solar_crest:0.64;36>spirit_vessel:1.69;"
		.. "36>wind_waker:1.76;38>cyclone:0.78;38>lotus_orb:1.87;38>pers:1.78;39>dust:0.86;39>ghost:0.75;"
		.. "42>dust:0.8;44>ghost:1.81;45>dust:1.3;46>dust:1.48;46>gem:1.34;46>ghost:1.82;48>bracer:1.22;"
		.. "48>dust:0.87;48>ghost:0.6;51>force_staff:1.39;52>force_staff:1.2;53>force_staff:1.26;56>dust:2.01;"
		.. "56>ghost:2.53;57>bracer:1.46;59>spirit_vessel:1.66;60>force_staff:1.43;60>ghost:1.42;62>dust:2.18;"
		.. "62>gem:1.37;62>glimmer_cape:0.62;62>lotus_orb:1.64;62>pers:1.58;63>dust:1.82;65>lotus_orb:1.87;"
		.. "65>pers:1.82;66>pavise:1.34;67>ghost:1.66;69>lotus_orb:1.68;69>pers:1.74;69>sphere:1.82;70>cyclone:1.88;"
		.. "70>ghost:1.31;71>cyclone:1.77;71>dust:1.18;71>force_staff:0.79;71>sphere:1.79;72>dust:0.87;74>dust:1.76;"
		.. "74>force_staff:1.17;75>cyclone:1.32;75>guardian_greaves:1.98;75>lotus_orb:2.13;75>mekansm:1.66;"
		.. "75>pers:1.94;77>ghost:2.24;77>helm_of_the_dominator:1.76;83>dust:1.63;83>gem:1.46;84>dust:0.86;"
		.. "84>gem:0.76;84>pavise:0.81;84>solar_crest:0.81;87>force_staff:0.79;88>dust:1.79;88>gem:1.59;"
		.. "94>diffusal_blade:2.45;94>heavens_halberd:2.27;95>cyclone:1.61;98>cyclone:1.3;99>ghost:1.3;"
		.. "99>silver_edge:1.93;99>solar_crest:1.21;100>force_staff:1.21;100>pavise:1.18;100>solar_crest:1.18;"
		.. "101>force_staff:1.22;108>force_staff:1.43;110>ancient_janggo:1.27;119>dust:0.87;120>ghost:1.54;"
		.. "120>glimmer_cape:0.76;120>pavise:1.33;120>solar_crest:1.33;129>black_king_bar:1.49;129>force_staff:0.75;"
		.. "136>ghost:1.3;137>lotus_orb:1.87;137>pers:1.8;145>dust:1.38;",
	VSA_CORE = "2>bracer:0.86;2>crimson_guard:0.58;2>pipe:0.53;2>vanguard:0.63;5>black_king_bar:0.84;5>dagon_3:1.29;"
		.. "5>dagon_4:1.32;5>dagon_5:1.33;5>greater_crit:1.17;5>helm_of_the_dominator:0.65;5>ward_sentry:0.83;"
		.. "8>falcon_blade:0.54;8>manta:0.72;8>mask_of_madness:0.72;10>butterfly:0.67;10>lesser_crit:0.81;"
		.. "10>mask_of_madness:0.66;13>dust:1.16;13>helm_of_the_dominator:1.21;13>kaya:0.81;13>oblivion_staff:0.82;"
		.. "13>orchid:0.81;13>ward_sentry:0.83;13>yasha_and_kaya:0.58;14>black_king_bar:0.82;14>pipe:0.8;"
		.. "16>helm_of_the_dominator:1.32;17>dust:1.13;17>ward_sentry:0.83;17>yasha_and_kaya:0.67;"
		.. "18>falcon_blade:0.65;18>mask_of_madness:0.68;20>black_king_bar:0.83;20>helm_of_the_dominator:0.69;"
		.. "20>soul_ring:0.87;22>black_king_bar:0.89;22>sange_and_yasha:1.14;22>ward_sentry:0.85;"
		.. "25>black_king_bar:0.87;25>ward_sentry:0.85;25>yasha_and_kaya:0.7;26>helm_of_the_dominator:0.8;"
		.. "27>helm_of_the_dominator:0.77;28>dust:0.71;28>monkey_king_bar:1.27;29>bracer:0.84;29>pipe:0.5;"
		.. "32>glimmer_cape:1.48;35>ward_sentry:0.8;36>black_king_bar:0.87;36>radiance:0.74;39>ward_sentry:0.86;"
		.. "42>black_king_bar:0.82;44>butterfly:0.58;44>falcon_blade:0.55;45>helm_of_the_dominator:1.26;"
		.. "46>butterfly:0.73;46>desolator:0.76;46>greater_crit:0.81;46>nullifier:1.27;46>satanic:0.7;"
		.. "48>falcon_blade:0.53;48>manta:0.78;48>mask_of_madness:0.78;48>mjollnir:0.77;48>sange_and_yasha:0.81;"
		.. "48>yasha_and_kaya:1.19;49>pipe:1.15;54>falcon_blade:0.63;54>radiance:0.72;54>satanic:0.64;"
		.. "55>bracer:0.78;55>pipe:0.45;60>bracer:0.86;62>dust:0.72;65>black_king_bar:1.13;65>dagon_2:0.63;"
		.. "66>black_king_bar:1.13;66>ward_sentry:1.16;69>pipe:0.67;70>butterfly:0.67;70>falcon_blade:0.56;"
		.. "70>manta:0.76;70>mask_of_madness:0.71;70>mjollnir:0.79;71>dust:0.85;72>butterfly:0.7;"
		.. "72>falcon_blade:0.73;72>greater_crit:0.78;72>lesser_crit:0.81;72>manta:0.83;72>mask_of_madness:0.7;"
		.. "72>yasha_and_kaya:1.21;73>ultimate_scepter:0.74;74>dust:0.85;74>ward_sentry:0.85;77>assault:0.64;"
		.. "81>black_king_bar:0.83;81>wraith_band:1.2;84>black_king_bar:0.88;84>helm_of_the_dominator:0.75;"
		.. "84>pipe:0.85;86>helm_of_the_dominator:0.8;86>ward_sentry:0.87;91>armlet:1.31;91>orb_of_corrosion:1.33;"
		.. "94>greater_crit:0.66;94>lesser_crit:0.77;94>mask_of_madness:0.64;94>mjollnir:0.71;94>satanic:0.65;"
		.. "95>falcon_blade:0.59;95>mask_of_madness:0.68;96>bracer:0.87;96>crimson_guard:0.55;96>pipe:0.35;"
		.. "96>vanguard:0.67;97>dust:0.85;97>pipe:0.75;99>bracer:0.87;99>dust:1.18;100>nullifier:1.21;100>pipe:1.13;"
		.. "104>black_king_bar:0.81;104>wraith_band:1.16;106>kaya:0.86;106>pipe:1.16;106>satanic:1.16;"
		.. "106>veil_of_discord:0.85;106>ward_sentry:0.86;106>yasha_and_kaya:0.71;108>pipe:0.52;"
		.. "109>greater_crit:0.74;109>invis_sword:0.77;109>lesser_crit:0.83;109>maelstrom:0.82;114>pipe:1.21;"
		.. "120>wraith_band:0.87;123>helm_of_the_dominator:1.24;128>helm_of_the_dominator:1.2;129>bracer:0.88;"
		.. "129>pipe:0.62;129>vanguard:0.69;135>bracer:0.82;135>gungir:0.72;135>pipe:0.63;",
	VSA_SUP = "1>pavise:0.76;1>solar_crest:0.75;3>essence_distiller:1.46;5>aghanims_shard:1.16;5>dragon_lance:1.38;"
		.. "5>pavise:0.74;5>solar_crest:0.77;5>ultimate_scepter:1.23;8>pavise:0.82;9>bracer:1.52;10>vladmir:0.46;"
		.. "11>vladmir:1.25;12>pavise:0.55;12>solar_crest:0.53;13>dust:1.18;13>gem:1.31;14>aether_lens:1.15;"
		.. "14>aghanims_shard:1.16;14>blade_mail:1.33;14>gem:0.76;14>pavise:0.8;14>solar_crest:0.8;"
		.. "14>ultimate_scepter:1.22;17>dust:1.16;17>gem:1.2;19>bracer:0.86;20>gem:0.64;20>pavise:0.72;"
		.. "20>solar_crest:0.73;21>bracer:1.28;22>gem:0.63;22>pavise:0.74;22>solar_crest:0.74;"
		.. "22>ultimate_scepter:1.2;23>bracer:1.28;25>pavise:0.83;25>solar_crest:0.83;27>gem:1.22;28>dust:0.8;"
		.. "30>pavise:0.69;31>gem:0.67;31>pavise:0.67;31>solar_crest:0.66;33>ancient_janggo:0.59;33>gem:1.25;"
		.. "34>gem:0.74;34>pavise:0.76;34>solar_crest:0.75;35>bracer:1.26;36>pavise:0.71;36>solar_crest:0.7;"
		.. "37>gem:0.76;37>pavise:0.71;37>solar_crest:0.71;38>gem:1.19;39>gem:0.86;42>gem:0.65;"
		.. "42>helm_of_the_dominator:1.4;42>pavise:0.64;42>solar_crest:0.65;45>bracer:0.72;48>bracer:1.19;"
		.. "48>phylactery:1.42;53>bracer:1.19;53>spirit_vessel:0.74;55>guardian_greaves:0.61;55>mekansm:0.66;"
		.. "55>pipe:0.46;59>pavise:1.22;59>solar_crest:1.25;60>bracer:0.76;62>pavise:1.23;62>solar_crest:1.23;"
		.. "64>gem:0.77;64>pavise:0.83;64>solar_crest:0.83;65>bracer:0.79;65>gem:1.3;65>pavise:1.27;"
		.. "65>solar_crest:1.26;67>pavise:0.66;67>solar_crest:0.66;70>pavise:0.79;70>solar_crest:0.79;"
		.. "71>aghanims_shard:1.16;71>blade_mail:1.49;71>dust:0.85;71>gem:0.74;71>ultimate_scepter:1.28;"
		.. "72>bracer:0.81;72>pavise:1.29;72>solar_crest:1.29;72>ultimate_scepter:0.82;72>vladmir:1.71;"
		.. "73>ultimate_scepter:0.76;74>dust:0.84;75>pavise:0.75;75>solar_crest:0.75;76>gem:0.61;76>pavise:0.76;"
		.. "76>solar_crest:0.74;79>gem:1.22;81>pavise:0.66;81>solar_crest:0.65;83>gem:0.68;84>gem:0.75;"
		.. "84>pavise:0.7;84>solar_crest:0.7;86>essence_distiller:0.6;86>gem:0.86;88>solar_crest:1.19;90>gem:1.28;"
		.. "90>spirit_vessel:0.64;94>mekansm:0.75;96>essence_distiller:1.33;96>pipe:0.5;97>bracer:0.76;"
		.. "97>vladmir:1.29;99>dust:1.16;99>gem:1.18;100>pavise:1.21;100>solar_crest:1.2;104>dust:0.81;104>gem:0.66;"
		.. "104>pavise:0.77;104>phylactery:1.39;104>solar_crest:0.78;107>essence_distiller:1.37;107>gem:1.23;"
		.. "107>spirit_vessel:0.6;108>bracer:1.29;108>pipe:0.51;109>bracer:0.81;110>gem:0.82;110>spirit_vessel:0.7;"
		.. "112>essence_distiller:1.52;119>pavise:1.15;119>solar_crest:1.15;123>gem:1.24;123>pavise:1.22;"
		.. "123>solar_crest:1.22;126>spirit_vessel:0.71;135>bracer:0.82;138>bracer:0.73;138>gem:1.25;"
		.. "138>pavise:1.26;138>solar_crest:1.25;138>ultimate_scepter:0.81;",
	VSH_LO = 0.4,
	VSH_HI = 3,
	-- lineup model (tools\matrix\lm_fit.py g8, lm_export.py): pro buy odds of an item against these enemies and
	-- with these allies, jointly over all 9 heroes, plus own hero group x enemy terms
	LM_ALPHA = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz!",
	LM_A = 0.05,
	LM_S = 0.15651907398350612,
	LM_P = 0.3,
	LM_P_LO = 0.01,
	LM_P_HI = 0.97,
	LM_LO = 0.25,
	LM_HI = 5,
	LM_TIP = 0.14,
	ATTR_BONUS = "special_bonus_attributes",
	-- reaction model (tools\matrix\lm_react.py, lr_export.py): pro buy odds of an item after enemies or allies
	-- got certain items, with heroes, own items and the item-value gap as controls; counts capped at 2
	LR_CAP = 2,
	LR_W = 0.6,
	LR_ITEMS = "abyssal_blade,aeon_disk,aether_lens,aghanims_shard,ancient_janggo,angels_demise,arcane_blink,arcane_boots,armlet,assault,basher,bfury,black_king_bar,blade_mail,blink,bloodstone,bloodthorn,boots_of_bearing,bracer,butterfly,consecrated_wraps,crellas_crozier,crimson_guard,cyclone,dagon,dagon_2,dagon_3,dagon_4,dagon_5,desolator,devastator,diffusal_blade,diffusal_blade_2,disperser,dragon_lance,dust,echo_sabre,essence_distiller,eternal_shroud,ethereal_blade,falcon_blade,force_staff,gem,ghost,glimmer_cape,greater_crit,guardian_greaves,gungir,hand_of_midas,harpoon,heart,heavens_halberd,helm_of_the_dominator,helm_of_the_overlord,holy_locket,hurricane_pike,hydras_breath,invis_sword,kaya,kaya_and_sange,lesser_crit,lotus_orb,maelstrom,mage_slayer,magic_wand,manta,mask_of_madness,mekansm,meteor_hammer,mjollnir,monkey_king_bar,moon_shard,necronomicon,necronomicon_2,necronomicon_3,null_talisman,nullifier,oblivion_staff,octarine_core,orb_of_corrosion,orchid,overwhelming_blink,pavise,pers,phase_boots,phylactery,pipe,power_treads,radiance,refresher,revenants_brooch,rod_of_atos,sange,sange_and_yasha,satanic,sheepstick,shivas_guard,silver_edge,skadi,solar_crest,soul_booster,soul_ring,specialists_array,sphere,spirit_vessel,swift_blink,tranquil_boots,travel_boots,travel_boots_2,ultimate_scepter,vanguard,veil_of_discord,vladmir,ward_sentry,wind_waker,witch_blade,wraith_band,wraith_pact,yasha,yasha_and_kaya",
	LR_CORE = "",
	LR_SUP = "",
	LM_CORE = "",
	LM_SUP = "",
	MXE_T = 1200,
	LANE_Q_LO = -333,
	LANE_Q_HI = 284,
	XP_LEVEL = { 0, 240, 640, 1160, 1760, 2440, 3200, 4000, 4900, 5900, 7000, 8200, 9500, 10900, 12400, 14000, 15700, 17500,
		19400, 21400, 23600, 26000, 28600, 31400, 34400, 38400, 43400, 49400, 56400, 63900 },
	LANE_FROM = 60,
	LANE_TO = 600,
	MXL_T = 900,
	LANE_STALE = 30,
	RESUME_T = 90,
	LANE_R = 1500,
	LANE_SHARE = 0.25,
	EVASION = { butterfly = 35, talisman_of_evasion = 15, heavens_halberd = 25, elven_tunic = 16 },
	FOE_EVERY = 5,
	INVIS_FROM = 300,
	INVIS_HERO = 0.8,
	SKILL_EVERY = 0.5,
	SKILL_WAIT = 2.0,
	TALENT_ALL = 27,
	SKILL_FAIL_SKIP = 20,
	HERO_ATT = "1:70;2:14;3:24;4:37;5:12;6:68;7:3;8:32;9:24;10:59;11:56;12:71;13:26;14:11;15:34;16:7;17:34;18:71;19:27;"
		.. "20:37;21:59;22:4;23:24;25:34;26:23;27:63;28:56;29:13;30:37;31:6;32:26;33:34;34:4;35:56;36:7;37:22;38:37;39:13;"
		.. "40:23;41:51;42:42;43:13;44:66;45:11;46:55;47:24;48:33;49:59;50:37;51:6;52:8;53:43;54:59;55:29;56:64;57:35;58:55;"
		.. "59:42;60:54;61:76;62:32;63:51;64:10;65:11;66:61;67:30;68:20;69:22;70:83;71:29;72:27;73:37;74:24;75:24;76:18;"
		.. "77:88;78:42;79:31;80:61;81:85;82:59;83:29;84:13;85:17;86:16;87:19;88:10;89:68;90:11;91:23;92:23;93:71;94:55;"
		.. "95:69;96:15;97:26;98:4;99:26;100:55;101:11;102:34;103:37;104:34;105:7;106:10;107:12;108:19;109:86;110:9;111:15;"
		.. "112:37;113:44;114:46;119:18;120:15;121:23;123:16;126:24;128:18;129:15;131:13;135:19;136:56;137:4;138:23;145:26;"
		.. "155:7",
	COMEBACK = "1:15;2:-12;3:-31;4:3;5:-14;6:-6;7:-17;8:35;9:44;10:13;11:18;12:33;13:3;14:38;15:32;16:-13;17:-12;"
		.. "18:-12;19:-11;20:-3;22:58;23:-3;25:-1;26:1;27:-34;28:-27;29:-1;30:-19;31:-34;32:-42;33:-9;34:24;35:30;36:16;"
		.. "37:-48;38:-35;39:8;40:-24;41:35;42:34;43:-25;44:23;45:-40;46:-13;47:-24;48:33;49:-9;50:-3;51:-5;52:9;53:15;"
		.. "54:21;55:2;56:26;57:-9;58:-9;59:-16;61:3;63:-5;64:-51;65:-22;66:-42;67:-35;68:-24;69:-9;70:-9;71:-20;72:-6;"
		.. "73:-6;74:55;76:-23;77:5;78:7;79:-39;80:24;81:23;82:-55;83:3;85:-30;86:-51;87:-49;88:15;89:16;90:-23;91:19;"
		.. "92:20;93:-37;94:19;95:-16;96:5;97:12;98:5;99:-13;100:-24;101:-12;102:17;103:-25;104:1;105:-17;106:-7;107:-26;"
		.. "108:-35;109:19;110:19;111:-4;112:1;113:-4;114:-3;119:-44;120:-5;121:-19;123:-74;126:-24;128:-37;129:-11;"
		.. "131:-16;135:-16;136:18;137:-5;138:27;145:-2;155:2",
	HISTORY2 = "draft_helper_history2.csv",
	REC_FILE = "draft_helper_matches.jsonl",
	REC_PARK_FILE = "draft_helper_match_open.txt",
	REC_PARK_WAIT = 900,
	REC_PRE_T = -90,
	REC_SKILL_OWN = { sand_king = "sandking" },
	REC_VER = 1,
	REC_MAX = 400,
	REC_TOP = 5,
	REC_BUILD_EVERY = 5,
	REC_ABIL_LAST = 31,
	REC_STATS = {
		"networth", "totalearned_gold", "gold_spent_on_items", "gold_spent_on_consumables", "gold_spent_on_support",
		"gold_spent_on_buybacks", "gold_lost_to_death", "lasthit_count", "deny_count", "hero_damage", "tower_Kills",
		"stuns", "healing", "creeps_stacked", "rune_pickups", "observer_wards_placed", "sentry_wards_placed",
	},
	NEUTRAL_SLOT = 16,
	TOAST = 2.5,
	COUNTER_TOAST = 8,
	GOLD_SWING_OUT = 2000,
	SOLD_TIP_MIN = 0.15,
	MAIN_LAST = 5,
	TIMING_MIN = 10,
	TIMING_GAP = 0.08,
	LATE_GRACE = 240,
	GOLD_SWING = 3000,
	WIN_B = { 0.6, 0.59, 0.384, 0.294, 0.277, 0.264, 0.233, 0.193, 0.173, 0.147, 0.119, 0.105, 0.088 },
	STATE_LOGIT = 0.62,
	STATE_EVERY = 2,
	BEHIND_W = 1.0,
	LIFT_B_CAP = 0.15,
	BEHIND_DEF = { disable = true, magic = true, burst = true },
	BEHIND_COUNTER = 1.5,
	ADJ_MIN = 0.02,
	ALT_MAX = 2,
	HISTORY_FILE = "draft_helper_history.csv",
	ALT_SHARE = 0.1,
	TEAM_ONE = {
		pipe = "pipe", guardian_greaves = "mek", mekansm = "mek", crimson_guard = "crimson", vladmir = "vlad",
		boots_of_bearing = "drum", spirit_vessel = "vessel",
	},
	TEAM_DUP_W = 1,
	ITEM_RETRY = 15,
	ITEM_FAIL_SKIP = 60,
	START_GOLD = 600,
	START_MIN = 0.35,
	STACK = {
		branches = 3, tango = 2, ward_sentry = 2, ward_observer = 2, flask = 2, clarity = 2, enchanted_mango = 2,
		blood_grenade = 2, faerie_fire = 2,
	},
	SLOTS = 6,
	SLOT_MIN_COST = 1000,
	SLOT_EXTRA = { blink = true, ghost = true },
	SLOT_SKIP = { ultimate_scepter_2 = true, ward_dispenser = true, rapier = true },
	EARLY_EXTRA = { bottle = true },
	EARLY_SHARE = 0.5,
	EARLY_T = 900,
	EARLY_MIN_COST = 300,
	EARLY_MAX = 3,
	BOOTS = {
		power_treads = true, phase_boots = true, arcane_boots = true, tranquil_boots = true, travel_boots = true,
		travel_boots_2 = true, guardian_greaves = true, boots_of_bearing = true,
	},
	ITEM_SHARE = 0.15,
	ITEM_SHARE_FULL = 0.25,
	ITEM_COUNTER_W = 0.4,
	CNT_CORE = "aeon_disk.pierce:1.87;assault.phys:1.23;black_king_bar.targeted:0.87;bloodthorn.escape:1.27;bloodthorn.evasion:1.47;butterfly.phys:1.4;crimson_guard.phys:1.48;cyclone.silence:1.54;ethereal_blade.phys:1.43;gem.invis:2.76;ghost.phys:1.72;heavens_halberd.phys:1.74;lotus_orb.silence:1.59;lotus_orb.targeted:1.41;manta.silence:1.24;monkey_king_bar.evasion:4.83;orchid.escape:1.7;rod_of_atos.escape:1.19;sange_and_yasha.silence:0.78;shivas_guard.phys:1.21;silver_edge.passives:2.78;sphere.targeted:4.03;",
	CNT_SUP = "cyclone.silence:1.25;gem.invis:1.55;ghost.phys:1.99;glimmer_cape.magic:1.57;guardian_greaves.silence:1.75;lotus_orb.silence:1.82;lotus_orb.targeted:2.04;orchid.escape:2.41;silver_edge.passives:3.94;sphere.targeted:3.85;spirit_vessel.heal:1.23;",
	CNT_LO = 0.4,
	CNT_HI = 5,
	ITEM_UPGRADE = 0.5,
	CORE_LOCK = 3,
	SIBLING_COST = 800,
	UPGRADE_MIN = 0.15,
	PRE_SHARE = 0.3,
	PRE_COST = 1500,
	PRE_GAP = 180,
	DISASSEMBLE = {
		mask_of_madness = true, echo_sabre = true, pers = true, vanguard = true, vladmir = true, sange_and_yasha = true,
		kaya_and_sange = true, yasha_and_kaya = true, radiance = true, angels_demise = true,
	},
	KEEP_MAX = 0.75,
	AFTER_SHARE = 0.2,
	AFTER_GAP = 480,
	SPARE_MIN = 0.4,
	VS_MIN = 0.2,
	VS_MAX = 3,
	ROLE_MAGIC = 0.4,
	ROLE_DISABLE = 0.5,
	ROLE_PHYS_AGI = 0.6,
	ROLE_PHYS_STR = 0.35,
	KIT_MAGIC_ONE = 0.15,
	KIT_MAGIC_DIV = 3,
	KIT_DISABLE = 0.5,
	KIT_PIERCE = 0.5,
	KIT_ALL_SPELLS = { npc_dota_hero_invoker = true },
	NO_DAMAGE = { slark_pounce = true, dark_willow_terrorize = true, witch_doctor_voodoo_restoration = true },
	MAGIC_BASE = 1.0,
	DPS_FROM = 0.7,
	DPS_FULL = 1.4,
	DPS_MAX = 5000,
	DPS_NEW = 0.4,
	DPS_HEROES = 6,
	DPS_LOG_STEP = 0.35,
	DPS_LOG_GAP = 60,
	DPS_DX_LOG = 0.25,
	PHYS_PRIOR_KEEP = 0.5,
	DPS_TIP = 0.1,
	SELF_MAX = 0.8,
	SELF_COVER = "life_stealer_rage magic .6 disable .6 silence .7 roots .7;juggernaut_blade_fury magic .4 disable .3 silence .5 roots .5;"
		.. "antimage_counterspell magic .35 targeted .8;slark_dark_pact silence .6 roots .6;"
		.. "legion_commander_press_the_attack silence .4 roots .4;abaddon_aphotic_shield silence .4 roots .4 disable .2;"
		.. "weaver_time_lapse silence .4 roots .4 disable .2;troll_warlord_battle_trance silence .4 roots .4;"
		.. "phantom_assassin_blur silence .3 roots .3;templar_assassin_refraction phys .4 burst .3 magic .3 silence .3 roots .3;"
		.. "kez_raptor_dance silence .3 roots .3 magic .2;keeper_of_the_light_chakra_magic silence .3 roots .3;"
		.. "marci_bodyguard silence .3 roots .3;pangolier_gyroshell magic .3 disable .2;omniknight_martyr magic .3;"
		.. "oracle_fates_edict magic .3;huskar_berserkers_blood magic .3;ember_spirit_flame_guard magic .3;lina_flame_cloak magic .2;"
		.. "ursa_enrage disable .3 silence .3 roots .3 phys .3;tiny_insurmountable disable .2 silence .2 roots .2;"
		.. "spirit_breaker_bulldoze disable .2;tidehunter_kraken_shell silence .3 roots .3;medusa_mana_shield phys .3 magic .3;"
		.. "bristleback_bristleback phys .3 magic .2;phantom_assassin_immaterial phys .3;"
		.. "nyx_assassin_spiked_carapace targeted .2 phys .2 burst .4;arc_warden_magnetic_field phys .3;mars_bulwark phys .3;"
		.. "shredder_reactive_armor phys .3;abaddon_borrowed_time burst .5 pierce .3;omniknight_guardian_angel burst .6 phys .5;"
		.. "windrunner_windrun burst .5 phys .5;dazzle_shallow_grave burst .5;oracle_false_promise burst .5;"
		.. "skeleton_king_reincarnation burst .4;faceless_void_time_walk burst .4;puck_phase_shift pierce .5 targeted .3;"
		.. "void_spirit_dissimilate pierce .3;storm_spirit_ball_lightning pierce .3;phantom_lancer_doppelwalk pierce .4 targeted .3;"
		.. "life_stealer_infest pierce .5 targeted .4 burst .3;brewmaster_primal_split pierce .5 targeted .3;"
		.. "riki_tricks_of_the_trade pierce .4 targeted .3 burst .3;naga_siren_mirror_image pierce .4 targeted .3;"
		.. "slark_shadow_dance pierce .3 targeted .4 burst .3;morphling_waveform pierce .3 targeted .3;"
		.. "tusk_snowball pierce .3 targeted .3;weaver_shukuchi pierce .3 targeted .3;spectre_dispersion burst .3 phys .2;"
		.. "zuus_lightning_bolt invis .3;rattletrap_rocket_flare invis .3;drow_ranger_wave_of_silence invis .3;"
		.. "slardar_amplify_damage invis .3;void_spirit_aether_remnant invis .2;ancient_apparition_ice_blast heal .7;"
		.. "necrolyte_heartstopper_aura heal .4;abaddon_withering_mist heal .3;bane_enfeeble heal .3;venomancer_poison_sting heal .2;"
		.. "doom_bringer_doom passives .4 escape .5;batrider_flaming_lasso escape .5;lion_voodoo escape .4;"
		.. "shadow_shaman_voodoo escape .4;legion_commander_duel escape .4;bane_fiends_grip escape .4;disruptor_glimpse escape .4;"
		.. "faceless_void_chronosphere escape .4;shadow_shaman_shackles escape .3;skywrath_mage_ancient_seal escape .3;"
		.. "silencer_last_word escape .3;rubick_telekinesis escape .3;enigma_black_hole escape .3;disruptor_kinetic_field escape .3;"
		.. "disruptor_static_storm escape .3;night_stalker_crippling_fear escape .3;beastmaster_primal_roar escape .3;"
		.. "gyrocopter_flak_cannon illusions .3;medusa_split_shot illusions .3;luna_moon_glaive illusions .3;"
		.. "sven_great_cleave illusions .3;kunkka_tidebringer illusions .3;ember_spirit_sleight_of_fist illusions .3",
	COUNTERS = {
		black_king_bar = { magic = 0.5, disable = 0.5, silence = 0.5, targeted = 0.5 },
		eternal_shroud = { magic = 0.8 },
		pipe = { magic = 0.3 },
		glimmer_cape = { magic = 0.2 },
		mage_slayer = { magic = 0.35 },
		sange_and_yasha = { disable = 0.25, silence = 0.25 },
		sphere = { targeted = 0.1 },
		lotus_orb = { targeted = 0.7, silence = 0.3 },
		manta = { silence = 0.4 },
		cyclone = { silence = 0.3, pierce = 0.6 },
		wind_waker = { silence = 0.3, pierce = 0.6 },
		guardian_greaves = { silence = 0.2 },
		orchid = { escape = 0.1 },
		bloodthorn = { escape = 0.1, evasion = 0.5 },
		harpoon = { escape = 0.1 },
		rod_of_atos = { escape = 0.2 },
		diffusal_blade = { escape = 0.1 },
		disperser = { escape = 0.1, saves = 0.6 },
		nullifier = { saves = 1 },
		silver_edge = { passives = 0.2 },
		monkey_king_bar = { evasion = 1 },
		shivas_guard = { illusions = 0.1, heal = 0.2, phys = 0.6 },
		skadi = { heal = 0.2 },
		spirit_vessel = { heal = 0.2 },
		ghost = { phys = 0.9 },
		crellas_crozier = { phys = 0.9, burst = 0.2, heal = 0.2 },
		ethereal_blade = { phys = 0.5 },
		solar_crest = { phys = 0.6 },
		pavise = { phys = 0.5 },
		force_staff = { phys = 0.2 },
		hurricane_pike = { phys = 0.4 },
		assault = { phys = 0.8 },
		butterfly = { phys = 0.7 },
		heavens_halberd = { phys = 0.1 },
		blade_mail = { phys = 0.3, pierce = 0.5, burst = 0.5 },
		crimson_guard = { phys = 0.5 },
		aeon_disk = { pierce = 0.4, burst = 0.1 },
		gem = { invis = 0.8 },
	},
	FIT = {
		black_king_bar = { core = true },
		eternal_shroud = { core = true },
		gem = { core = true },
		pipe = { support = true, core = { str = true } },
		glimmer_cape = { support = true },
		mage_slayer = { core = { agi = true, int = true } },
		sange_and_yasha = { core = { str = true, agi = true, all = true } },
		sphere = { core = true },
		lotus_orb = { support = true, core = { str = true, int = true } },
		manta = { core = { agi = true, all = true } },
		cyclone = { support = true, core = { int = true } },
		guardian_greaves = { support = true },
		sheepstick = { core = { int = true } },
		orchid = { core = { int = true, agi = true } },
		bloodthorn = { core = { int = true, agi = true } },
		abyssal_blade = { core = { str = true, agi = true, all = true } },
		harpoon = { core = { str = true, agi = true, all = true } },
		rod_of_atos = { support = true, core = { int = true } },
		diffusal_blade = { core = { agi = true } },
		silver_edge = { core = { str = true, agi = true, all = true } },
		monkey_king_bar = { core = { str = true, agi = true, all = true } },
		mjollnir = { core = { str = true, agi = true, all = true } },
		gungir = { core = { int = true } },
		bfury = { core = { str = true, agi = true, all = true }, melee = true },
		radiance = { core = { str = true, agi = true, all = true } },
		shivas_guard = { core = { str = true, int = true } },
		skadi = { core = { agi = true, all = true } },
		spirit_vessel = { support = true, core = { str = true } },
		ghost = { support = true },
		crellas_crozier = { support = true, core = { int = true } },
		solar_crest = { support = true },
		pavise = { support = true },
		ethereal_blade = { core = { int = true } },
		force_staff = { support = true, core = { int = true } },
		assault = { core = { str = true, agi = true, all = true } },
		butterfly = { core = { agi = true, all = true } },
		heavens_halberd = { core = { str = true } },
		blade_mail = { core = { str = true } },
		crimson_guard = { core = { str = true } },
		aeon_disk = { core = true },
		nullifier = { core = true },
	},
	MUST = {},
	MUST_MAX = 2,
	MUST_COVER = 0.5,
	PROTECT_T = 0.5,
	EW_ITEMS_T = 900,
	EXT_KEPT = 0.2,
	EXT_KEPT_N = 5,
	SELL_HOLD = 300,
	LIFT_SAFE = 1200,
	LIFT_GAP = 3,
	LIFT_TRIES = 3,
	REACT_KEEP_SHARE = 0.3,
	PHYS_MIN = 0.8,
	PHYS_ITEMS = {
		bfury = true, manta = true, butterfly = true, greater_crit = true, lesser_crit = true, desolator = true,
		monkey_king_bar = true, skadi = true, satanic = true, mjollnir = true, maelstrom = true, abyssal_blade = true,
		basher = true, disperser = true, diffusal_blade = true, silver_edge = true, bloodthorn = true, echo_sabre = true,
		harpoon = true, armlet = true, mask_of_madness = true, sange_and_yasha = true, nullifier = true, radiance = true,
	},
	REACT = {
		{ items = { "butterfly" }, threat = "evasion", counters = { "monkey_king_bar", "bloodthorn" }, phys = true, hard = 1 },
		{ items = { "dagon", "dagon_2", "dagon_3", "dagon_4", "dagon_5", "ethereal_blade" }, threat = "magic",
			counters = { "black_king_bar", "eternal_shroud", "pipe" }, hard = 2 },
		{ items = { "sheepstick", "orchid", "bloodthorn", "abyssal_blade", "nullifier" }, threat = "targeted",
			counters = { "black_king_bar", "lotus_orb" } },
		{ items = { "greater_crit", "desolator" }, threat = "phys", min = 2, counters = { "assault", "shivas_guard", "ghost" } },
		{ items = { "silver_edge", "invis_sword" }, threat = "invis", counters = { "gem" }, extra = true },
		{ items = { "ghost", "crellas_crozier", "ethereal_blade", "glimmer_cape", "cyclone", "wind_waker" }, threat = "saves",
			min = 2, counters = { "nullifier" }, rate = true, hard = 3, soft = true },
	},
	PREDICT_SHARE = 0.35,
	ROLE_MIX = 0.7,
	ROLE_FLIP_GAP = 2500,
	PREDICT_SHOW = 4,
	REACT_MAX = 2,
	REACT_RATE = 0.03,
	REACT_URGENT = { targeted = true, magic = true, evasion = true },
	RATE_MIN_GAMES = 60,
	HERO_TAGS = "abaddon heal .5;alchemist heal 1;antimage escape .8 passives .3;"
		.. "arc_warden evasion .5 illusions .5 silence .3;axe passives .4 pierce 1 targeted .5;"
		.. "bane pierce .5 targeted 1;batrider escape .3 pierce .6 targeted .9;"
		.. "beastmaster illusions .3 pierce .5 targeted .7;bloodseeker pierce .4 silence .4;"
		.. "bounty_hunter invis .8;brewmaster evasion .5;bristleback passives 1;broodmother illusions .8;"
		.. "chaos_knight illusions .8 passives .5 targeted .4;chen heal .6;clinkz burst .5 invis .8;"
		.. "crystal_maiden roots .4;dark_seer illusions .3;dark_willow escape .5 roots .4;dawnbreaker heal .8;"
		.. "dazzle heal .6;death_prophet silence .5;disruptor silence .6;doom_bringer pierce .7 targeted 1;"
		.. "dragon_knight heal .3 passives .3 targeted .3;drow_ranger passives .6 silence .5;"
		.. "earth_spirit escape .4 silence .3;ember_spirit burst .3 escape .7 roots .5;enchantress heal .6;"
		.. "enigma illusions .4 pierce .7;faceless_void escape .6 passives .5 pierce .6;"
		.. "furion escape .3 illusions .5;grimstroke targeted .4;hoodwink escape .4 evasion .4;"
		.. "huskar burst .6 heal .6 passives .8;invoker illusions .3 invis .5;"
		.. "juggernaut burst .9 heal .6 passives .4;kez escape .4 heal .4 silence .4;kunkka targeted .3;"
		.. "legion_commander burst .7 heal .3 passives .3 pierce .6 targeted 1;lich targeted .4;"
		.. "life_stealer heal .6;lina targeted .4;lion targeted .9;lone_druid illusions .5 roots .3;"
		.. "luna passives .4;lycan burst .3 heal .4 illusions .5;magnataur escape .3 pierce .8;"
		.. "marci burst .6 escape .3 silence .3;mars passives .6;medusa pierce .4;meepo illusions 1 roots .4;"
		.. "mirana escape .5 evasion .3 invis .6;monkey_king escape .5 heal .4 passives .4;morphling escape .6;"
		.. "muerta silence .4;naga_siren evasion .4 illusions 1 roots .5;"
		.. "necrolyte heal .8 passives .4 targeted .6;night_stalker silence .5;nyx_assassin escape .4 invis .8;"
		.. "obsidian_destroyer targeted .4;omniknight heal 1;oracle heal 1;pangolier escape .8;"
		.. "phantom_assassin burst .5 escape .4 evasion 1 passives 1;"
		.. "phantom_lancer escape .5 evasion .5 illusions 1 invis .3;phoenix heal .5;primal_beast pierce .5;"
		.. "puck escape 1 silence .4;pudge pierce .4 targeted .7;pugna heal .4;queenofpain escape .7;"
		.. "rattletrap pierce .3;razor targeted .4;riki burst .4 escape .3 invis 1 silence .5;"
		.. "rubick targeted .4;sand_king escape .3 invis .5;shadow_demon targeted .8;"
		.. "shadow_shaman illusions .4 targeted 1;shredder escape .5 passives .8;silencer silence 1;"
		.. "skeleton_king heal .5 passives .4;skywrath_mage silence .6;slardar passives .4;"
		.. "slark escape 1 passives .7;sniper passives .3;spectre illusions .3 passives .8;"
		.. "spirit_breaker passives .4 pierce .3;storm_spirit escape 1;sven burst .5;techies invis .6;"
		.. "templar_assassin invis .4 passives .3 silence .3;terrorblade burst .4 illusions .8;"
		.. "tidehunter passives .6;tinker escape .4 targeted .3;treant heal 1 pierce .3 roots .4;"
		.. "troll_warlord burst .6 heal .5 passives .5;tusk pierce .3;undying heal .5 illusions .3;"
		.. "ursa burst .8 passives .7;vengefulspirit targeted .3;venomancer illusions .4;"
		.. "viper passives .4 targeted .4;visage illusions .3 invis .5 passives .5;void_spirit escape .9;"
		.. "warlock heal .4 illusions .3;weaver escape .9 invis .8 passives .4;"
		.. "windrunner burst 1 escape .4 evasion .6;winter_wyvern heal .5 pierce .4 targeted .5;"
		.. "wisp escape .3 heal .8;witch_doctor heal .6",

	PANEL_EVERY = 0.5,
	PILL_QUEUE = 3,
	PN_HOLD = 0.3,
	QFLASH = 0.4,
	STRIP_COLS = 8,
	SUM_STEP_W = 56,
	PANEL_STATES = {
		[Enum.GameState.DOTA_GAMERULES_STATE_PRE_GAME] = true,
		[Enum.GameState.DOTA_GAMERULES_STATE_GAME_IN_PROGRESS] = true,
	},
	INV_LAST = 14,
	ENEMY_INV_LAST = 8,
	SWAP_MARGIN = 0.12,
	SWAPS_MAX = 2,
	SIGNAL_MIN = 700,
	COVER = 0.8,
	ENEMY_ITEMS = {
		invis_sword = { invis = 1 },
		silver_edge = { invis = 1 },
		shadow_amulet = { invis = 0.4 },
		glimmer_cape = { invis = 0.3, saves = 0.5 },
		butterfly = { evasion = 1, phys = 0.2 },
		talisman_of_evasion = { evasion = 0.4 },
		heavens_halberd = { evasion = 0.4, roots = 0.4 },
		satanic = { heal = 0.7, phys = 0.2 },
		heart = { heal = 0.6 },
		holy_locket = { heal = 0.4 },
		guardian_greaves = { heal = 0.4 },
		bloodstone = { heal = 0.4 },
		mekansm = { heal = 0.3 },
		vladmir = { heal = 0.2 },
		manta = { illusions = 0.4 },
		helm_of_the_overlord = { illusions = 0.2 },
		orchid = { silence = 0.6, targeted = 0.5 },
		bloodthorn = { silence = 0.8, targeted = 0.6, phys = 0.3 },
		sheepstick = { disable = 0.6, targeted = 0.8 },
		rod_of_atos = { roots = 0.5 },
		gungir = { roots = 0.5 },
		nullifier = { targeted = 0.4 },
		abyssal_blade = { phys = 0.4, targeted = 0.5 },
		dagon = { magic = 0.6 },
		dagon_2 = { magic = 0.6 },
		dagon_3 = { magic = 0.6 },
		dagon_4 = { magic = 0.6 },
		dagon_5 = { magic = 0.6 },
		ethereal_blade = { magic = 0.6, saves = 0.3 },
		crellas_crozier = { saves = 0.5 },
		veil_of_discord = { magic = 0.2 },
		revenants_brooch = { magic = 0.3 },
		phylactery = { magic = 0.2 },
		blink = { escape = 0.4 },
		swift_blink = { escape = 0.4 },
		arcane_blink = { escape = 0.4 },
		overwhelming_blink = { escape = 0.4 },
		ghost = { saves = 0.5 },
		cyclone = { saves = 0.4 },
		wind_waker = { saves = 0.6 },
		force_staff = { saves = 0.3 },
		hurricane_pike = { saves = 0.4 },
		aeon_disk = { saves = 0.7 },
		lotus_orb = { saves = 0.3 },
		greater_crit = { phys = 0.6 },
		lesser_crit = { phys = 0.3 },
		desolator = { phys = 0.4 },
		basher = { phys = 0.3 },
		monkey_king_bar = { phys = 0.3 },
		bfury = { phys = 0.3 },
		mjollnir = { phys = 0.3 },
		diffusal_blade = { phys = 0.2 },
		disperser = { phys = 0.2 },
	},
	ANTI = {
		monkey_king_bar = { butterfly = 0.5, talisman_of_evasion = 0.3 },
		bloodthorn = { butterfly = 0.3 },
		nullifier = { ghost = 0.5, crellas_crozier = 0.5, glimmer_cape = 0.5, cyclone = 0.2 },
		crellas_crozier = { satanic = 0.2, heart = 0.2 },
		spirit_vessel = { satanic = 0.1, heart = 0.1 },
		skadi = { satanic = 0.2, heart = 0.2 },
		shivas_guard = { satanic = 0.15 },
	},
}

K.FREE = {}
for i = 1, 10 do
	K.FREE[i] = { kind = "P", team = i <= 5 and 0 or 1, group = i <= 5 and "us" or "enemy" }
end
for i = 11, 20 do
	K.FREE[i] = { kind = "B", team = 0, group = "ban" }
end

K.HERO_ATT_MAP = {}
for id, v in K.HERO_ATT:gmatch("(%d+):(%d+)") do
	K.HERO_ATT_MAP[tonumber(id)] = tonumber(v)
end

K.MX = { core = {}, sup = {} }
do
	local covered = { core = {}, sup = {} }
	for role, fit in pairs({ core = "core", sup = "support" }) do
		for _, rule in ipairs(K.REACT) do
			if not rule.extra and (rule.min or 1) <= 1 then
				local y
				for _, c in ipairs(rule.counters) do
					if not y and (not K.FIT[c] or K.FIT[c][fit]) then
						y = c
					end
				end
				for _, x in ipairs(y and rule.items or {}) do
					covered[role][x .. ">" .. y] = true
				end
			end
		end
		for x, list in pairs(K.ANTI) do
			for y in pairs(list) do
				covered[role][x .. ">" .. y] = true
			end
		end
	end
	K.MXE, K.MXA, K.MXL, K.MX_X, K.LANE_LOST_MAP = { core = {}, sup = {} }, { core = {}, sup = {} }, { core = {} }, {}, {}
	local function parse(dest, text, skip, mark)
		for x, y, v in text:gmatch("([%w_%.]+)>([%w_]+):(%-?[%d%.]+)") do
			if not (skip and skip[x .. ">" .. y]) then
				dest[x] = dest[x] or {}
				dest[x][y] = tonumber(v) / 100
				if mark then
					K.MX_X[x] = true
				end
			end
		end
	end
	parse(K.MX.core, K.MX_CORE, covered.core, true)
	parse(K.MX.sup, K.MX_SUP, covered.sup, true)
	parse(K.MXE.core, K.MXE_CORE, covered.core, true)
	parse(K.MXE.sup, K.MXE_SUP, covered.sup, true)
	parse(K.MXA.core, K.MXA_CORE, false, false)
	parse(K.MXA.sup, K.MXA_SUP, false, false)
	parse(K.MXL.core, K.MXL_CORE, false, false)
	K.CNT = { core = {}, sup = {} }
	for role, text in pairs({ core = K.CNT_CORE, sup = K.CNT_SUP }) do
		for it, threat, v in text:gmatch("([%w_]+)%.([%w_]+):([%d%.]+)") do
			K.CNT[role][it] = K.CNT[role][it] or {}
			K.CNT[role][it][threat] = tonumber(v)
		end
	end
	K.VSH, K.VSA = { core = {}, sup = {} }, { core = {}, sup = {} }
	for _, src in ipairs({ { K.VSH, "core", K.VSH_CORE }, { K.VSH, "sup", K.VSH_SUP }, { K.VSA, "core", K.VSA_CORE },
		{ K.VSA, "sup", K.VSA_SUP } }) do
		for h, y, v in src[3]:gmatch("(%d+)>([%w_]+):([%d%.]+)") do
			local row = src[1][src[2]][tonumber(h)] or {}
			src[1][src[2]][tonumber(h)] = row
			row[y] = tonumber(v)
		end
	end
	for y, v in K.LANE_LOST:gmatch("([%w_]+):(%-?[%d%.]+)") do
		K.LANE_LOST_MAP[y] = tonumber(v) / 100
	end
end

K.STEPS = {}
for token in K.ORDER:gmatch("%S+") do
	K.STEPS[#K.STEPS + 1] = { kind = token:sub(1, 1), side = token:sub(2, 2) == "F" and 0 or 1 }
end

K.CHARS = {}
for i = 0, 25 do
	local letter = string.char(65 + i)
	local code = Enum.ButtonCode["KEY_" .. letter]
	if code then
		K.CHARS[code] = letter:lower()
	end
end
for i = 0, 9 do
	local code = Enum.ButtonCode["KEY_" .. i]
	if code then
		K.CHARS[code] = tostring(i)
	end
end
K.CHARS[Enum.ButtonCode.KEY_SPACE] = " "

K.TYPE_KEYS = { K.BACKSPACE, K.ENTER, K.PAD_ENTER, K.ESCAPE }
for code in pairs(K.CHARS) do
	K.TYPE_KEYS[#K.TYPE_KEYS + 1] = code
end

local P = {
	BG = Color(10, 16, 21, 255),
	RAIL = Color(6, 10, 14, 255),
	SIDE = Color(13, 20, 26, 255),
	TEXT = Color(236, 243, 247, 255),
	MUTED = Color(132, 149, 161, 255),
	DIM = Color(82, 99, 112, 255),
	GOOD = Color(80, 228, 150, 255),
	BAD = Color(239, 125, 111, 255),
	LINE = Color(214, 236, 255, 14),
	CELL = Color(214, 236, 255, 9),
	FIELD = Color(214, 236, 255, 14),
	CHIP_ON = Color(64, 206, 186, 40),
	HOVER = Color(214, 236, 255, 11),
	SEP = Color(214, 236, 255, 40),
	SHADE = Color(0, 0, 0, 150),
	WARN = Color(240, 198, 116, 255),
	CARD = Color(15, 23, 30, 255),
	TIP = Color(19, 29, 37, 255),
	WHITE = Color(255, 255, 255, 255),
	BAN = Color(170, 170, 170, 255),
	USED = Color(90, 90, 90, 255),
	BAR = Color(214, 236, 255, 18),
	ACC = Color(56, 214, 176, 255),
	ACC_A = Color(70, 247, 138, 255),
	ACC_B = Color(28, 140, 198, 255),
	SCRIM = Color(3, 8, 12, 160),
	POP = Color(19, 29, 37, 255),
}

local D = {
	loaded = false,
	t_start = os.clock(),
	heroes = nil,
	by_id = {},
	by_unit = {},
	by_attr = { str = {}, agi = {}, int = {}, all = {} },
	heroes_at = 0,
	pos_count = nil,
	pos_at = 0,
	contest = nil,
	contest_at = 0,
	pos_prob = {},
	sets = nil,
	loading = nil,
	busy = false,
	next_request = 0,
	error = nil,
	status = nil,
}

local draft = {
	first = 0,
	mode = 1,
	store = { [0] = {}, [1] = {} },
	history = { [0] = {}, [1] = {} },
	target = nil,
	manual = { [0] = {}, [1] = {} },
	known_pos = {},
	tentative = {},
	extra_bans = {},
	unavail = {},
	grid_at = 0,
	me = nil,
	my_role = nil,
	filter_user = false,
	sync_at = 0,
	sync_sig = nil,
	steps = {},
	edit = nil,
	match = nil,
	query = "",
	filter = 0,
	dirty = true,
	result = nil,
	slot_pos = {},
	chance = nil,
	vs_cache = {},
	summary = nil,
	summary_sig = nil,
	build_h = nil,
}

draft.steps = draft.store[1]

local W = {
	open = false,
	auto = false,
	vis = 0,
	x = nil,
	y = nil,
	w = 0,
	h = 0,
	drag = false,
	dx = 0,
	dy = 0,
	hits = {},
	swallow = {},
	click_at = -1,
	scroll_at = -1,
	grid_scroll = 0,
	list_scroll = 0,
	grid_rect = nil,
	list_rect = nil,
	images = {},
	fonts = nil,
	focus = false,
	anim = {},
	placed = {},
	typed = {},
	down = {},
	held = {},
	settings = false,
	set_gear = nil,
	gear_pop = nil,
	gear_block = nil,
	gear_anchor = {},
	preview = false,
	pos_menu = nil,
	pm_last = nil,
	badge_rect = {},
	tip_cand = nil,
	tip_id = nil,
	tip_t = 0,
	tip_last = nil,
	list_t0 = 0,
	step_t = 0,
	step_c = false,
	snap = false,
}

local store, store_save, store_load

do
	local function cheat_path(name)
		local dir = Engine.GetCheatDirectory()
		if not dir:match("[\\/]$") then
			dir = dir .. "\\"
		end
		return dir .. "configs\\" .. name
	end

	local function read_path(path)
		local f = io.open(path, "rb")
		if not f then
			return nil
		end
		local text = f:read("a")
		f:close()
		return text
	end

	local function write_path(path, text)
		local tmp = path .. ".tmp"
		local f = io.open(tmp, "wb")
		if not f then
			return false
		end
		f:write(text)
		f:close()
		os.remove(path)
		if not os.rename(tmp, path) then
			f = io.open(path, "wb")
			if f then
				f:write(text)
				f:close()
			end
			os.remove(tmp)
		end
		return true
	end

	function D.models_read()
		local ok, text = pcall(read_path, cheat_path(K.MODELS_FILE))
		return ok and text or nil
	end

	function D.models_write(text)
		pcall(write_path, cheat_path(K.MODELS_FILE), text)
	end

	local function decode(text)
		if type(text) ~= "string" or text == "" then
			return nil
		end
		local ok, data = pcall(JSON.decode, JSON, text)
		return (ok and type(data) == "table") and data or nil
	end

	store = { data = { sets = {} }, blobs = {} }

	local function evict()
		local keys = {}
		for key in pairs(store.blobs) do
			if key:sub(1, #K.BUYS_BLOB) ~= K.BUYS_BLOB and key ~= K.ABIL_BLOB then
				keys[#keys + 1] = key
			end
		end
		if #keys <= K.CACHE_KEYS then
			return
		end
		table.sort(keys, function(x, y)
			local mx, my = store.data.sets[x] or {}, store.data.sets[y] or {}
			return (tonumber(mx.used) or 0) > (tonumber(my.used) or 0)
		end)
		for i = K.CACHE_KEYS + 1, #keys do
			store.blobs[keys[i]] = nil
			store.data.sets[keys[i]] = nil
		end
	end

	function store_save()
		evict()
		local keys = {}
		for key, blob in pairs(store.blobs) do
			if #blob > 0 then
				keys[#keys + 1] = key
			end
		end
		table.sort(keys)
		store.data.blob_keys = keys
		local ok, text = pcall(JSON.encode, JSON, store.data)
		if not ok then
			return
		end
		local parts = { string.pack("<c4I4", K.CACHE_MAGIC, #text), text }
		for _, key in ipairs(keys) do
			local blob = store.blobs[key]
			parts[#parts + 1] = string.pack("<I4", #blob)
			parts[#parts + 1] = blob
		end
		write_path(cheat_path(K.CACHE_FILE), table.concat(parts))
	end

	local function store_read(blob)
		local magic = blob:sub(1, 4)
		local n = string.unpack("<I4", blob, 5)
		local data = decode(blob:sub(9, 8 + n))
		if not data then
			error("broken cache")
		end
		data.sets = type(data.sets) == "table" and data.sets or {}
		local pos = 9 + n
		local blobs = {}
		if magic == "DHC1" then
			local old_sets = data.sets
			data.sets = {}
			for source = 0, 1 do
				local len = string.unpack("<I4", blob, pos)
				local part = blob:sub(pos + 4, pos + 3 + len)
				pos = pos + 4 + len
				local meta = old_sets[tostring(source)]
				if meta and #part > 0 and meta.rank then
					local key = source .. ":" .. math.floor(tonumber(meta.rank))
					blobs[key] = part
					data.sets[key] = meta
				end
			end
		else
			for _, key in ipairs(type(data.blob_keys) == "table" and data.blob_keys or {}) do
				local len = string.unpack("<I4", blob, pos)
				local part = blob:sub(pos + 4, pos + 3 + len)
				if #part ~= len then
					error("broken cache")
				end
				blobs[key] = part
				pos = pos + 4 + len
			end
		end
		return data, blobs
	end

	function store_load()
		local blob = read_path(cheat_path(K.CACHE_FILE))
		local magic = blob and blob:sub(1, 4)
		if blob and #blob >= 8 and (magic == K.CACHE_MAGIC or magic == "DHC1") then
			local ok, data, blobs = pcall(store_read, blob)
			if ok then
				store.data, store.blobs = data, blobs
				if magic ~= K.CACHE_MAGIC then
					store_save()
				end
				return
			end
			log("cache file broken, starting fresh")
		end
	end
end

local function url_encode(s)
	return (s:gsub("[^%w%-_%.~]", function(c)
		return ("%%%02X"):format(c:byte())
	end))
end

local function compact_sql(inner, cols, order)
	local parts = {}
	for i, c in ipairs(cols) do
		parts[i] = ("coalesce((%s)::text, '')"):format(c)
	end
	return ("select coalesce(string_agg(concat_ws(',', %s), ';'%s), '') || '$' d from (%s) z")
		:format(table.concat(parts, ", "), order and (" order by " .. order) or "", inner)
end

local function compact_rows(text)
	if type(text) ~= "string" then
		return nil, "empty response"
	end
	local err = text:match('"err":"([^"]*)"')
	if err then
		return nil, err
	end
	local d = text:match('"d":"([^"]*)%$"')
	if not d then
		return nil, "answer cut off"
	end
	local rows = {}
	for rec in d:gmatch("[^;]+") do
		local f = {}
		for v in (rec .. ","):gmatch("([^,]*),") do
			f[#f + 1] = v
		end
		rows[#rows + 1] = f
	end
	return rows
end

local function logit(p)
	return math.log(p / (1 - p))
end

local function sigm(x)
	return 1 / (1 + math.exp(-x))
end

local function clamp(v, lo, hi)
	return math.max(lo, math.min(hi, v))
end

local function norm(s)
	return (s:lower():gsub("[^%w]", ""))
end

local function set_heroes(list)
	local heroes = {}
	D.by_id = {}
	D.by_unit = {}
	D.by_attr = { str = {}, agi = {}, int = {}, all = {} }
	for _, h in ipairs(list) do
		local id = math.tointeger(tonumber(h.id))
		if id and id > 0 and id < 256 and type(h.name) == "string" and type(h.localized_name) == "string" then
			local label = h.localized_name
			local initials = {}
			for word in label:gsub("'", ""):gmatch("%w+") do
				initials[#initials + 1] = word:sub(1, 1):lower()
			end
			local hero = {
				id = id,
				unit = h.name,
				name = label,
				attr = D.by_attr[h.primary_attr] and h.primary_attr or "all",
				roles = type(h.roles) == "table" and h.roles or {},
				melee = h.attack_type == "Melee",
				key = norm(label),
				short = norm(h.name:gsub("^npc_dota_hero_", "")),
				initials = table.concat(initials),
			}
			hero.words = {}
			for word in label:lower():gsub("'", ""):gmatch("%w+") do
				hero.words[#hero.words + 1] = word
			end
			heroes[#heroes + 1] = hero
			D.by_id[id] = hero
			D.by_unit[hero.unit] = hero
			table.insert(D.by_attr[hero.attr], hero)
		end
	end
	for _, group in pairs(D.by_attr) do
		table.sort(group, function(a, b)
			return a.name < b.name
		end)
	end
	D.heroes = heroes
	D.pos_prob = {}
	draft.dirty = true
end

local function set_pos(rows)
	local count = {}
	for _, row in ipairs(rows) do
		local h, pos, n = tonumber(row.h), tonumber(row.pos), tonumber(row.n)
		if h and pos and n and pos >= 1 and pos <= 5 then
			count[h] = count[h] or { 0, 0, 0, 0, 0 }
			count[h][pos] = count[h][pos] + n
		end
	end
	D.pos_count = count
	D.pos_prob = {}
	draft.dirty = true
end

local function set_contest(rows)
	local contest = {}
	for _, row in ipairs(rows) do
		local h, c, n = tonumber(row.h), tonumber(row.c), tonumber(row.n)
		if h and c and n and n > 0 then
			contest[h] = c / n
		end
	end
	D.contest = contest
	draft.dirty = true
end

local function pack_record(id, ids, win, tier)
	return string.pack(K.PACK, id, ids[1], ids[2], ids[3], ids[4], ids[5], ids[6], ids[7], ids[8], ids[9], ids[10],
		win, tier)
end

local function new_set(source)
	return {
		source = source,
		file = source == 1 and "cm" or "ranked",
		page = source == 1 and K.PAGE_CM or K.PAGE,
		recs = {},
		rank = nil,
		updated = 0,
		job = nil,
		build = nil,
		stats = nil,
		loaded = false,
		force = false,
		exhausted = false,
	}
end

D.sets = { [0] = new_set(0), [1] = new_set(1) }

local function source()
	return cfg.source == 1 and 1 or 0
end

local function load_set(S, rank)
	S.loaded = true
	S.recs, S.stats, S.build, S.job = {}, nil, nil, nil
	S.rank, S.updated, S.exhausted, S.oldest, S.stats_tried, S.gh_on, S.gh_pack, S.gh_near = rank, 0, false, nil, false, nil, nil, nil
	local key = S.source .. ":" .. rank
	local meta = store.data.sets[key]
	local blob = store.blobs[key]
	if meta and blob and #blob % K.REC == 0 then
		S.updated = tonumber(meta.updated) or 0
		S.exhausted = meta.exhausted == true
		S.oldest = tonumber(meta.oldest)
		local recs = {}
		for i = 1, #blob, K.REC do
			recs[#recs + 1] = blob:sub(i, i + K.REC - 1)
		end
		S.recs = recs
		meta.used = os.time()
	end
	draft.dirty = true
	log("cache %s rank %d: %d matches", S.file, rank, #S.recs)
end

function D.models_apply(text)
	if type(text) ~= "string" then
		return false
	end
	local ver, len, body = text:match("^models (%S+) (%d+)\n(.*)$")
	if ver ~= K.MODELS or tonumber(len) ~= #body then
		return false
	end
	local got = {}
	for name, value in body:gmatch("#([%u_]+)\n([^\n]*)") do
		got[name] = value
	end
	for _, name in ipairs(K.MODEL_KEYS) do
		if not got[name] or got[name] == "" then
			return false
		end
	end
	for _, name in ipairs(K.MODEL_KEYS) do
		K[name] = got[name]
	end
	D.models_ok = true
	return true
end

function D.models_tick()
	local now = os.clock()
	if D.models_ok or K.MODELS == "" or now < (D.models_at or 0) then
		return
	end
	if D.models_busy then
		if now - D.models_busy > K.ANSWER_WAIT then
			D.models_busy, D.models_src = nil, (D.models_src or 1) + 1
			log("models: no answer, next mirror")
		end
		return
	end
	local n = D.models_src or 1
	local url = K.MODEL_URLS[(n - 1) % #K.MODEL_URLS + 1]:format(K.MODELS_SHA, K.MODELS)
	D.models_seq = (D.models_seq or 0) + 1
	local seq = D.models_seq
	D.models_busy = now
	local sent = HTTP.Request("GET", url, { headers = K.HEADERS, timeout = K.TIMEOUT }, function(res)
		if seq ~= D.models_seq then
			return
		end
		D.models_busy = nil
		local text = type(res) == "table" and tostring(res.code) == "200" and res.response or nil
		if D.models_apply(text) then
			D.models_write(text)
			D.models_fresh = true
			log("models %s loaded: %d bytes", K.MODELS, #text)
			return
		end
		D.models_src, D.models_fails = n + 1, (D.models_fails or 0) + 1
		D.models_at = os.clock() + math.min(K.LOG_RETRY_MAX, K.LOG_RETRY_MIN * 2 ^ (D.models_fails - 1))
		log("models: %s answered http %s, %d bytes", url, tostring(type(res) == "table" and res.code), type(text) == "string" and #text or 0)
	end, "cd_models")
	if not sent then
		D.models_busy = nil
		D.models_at = now + K.SEND_RETRY
	end
end

D.models_apply(D.models_read())

local function load_cache()
	D.loaded = true
	store_load()
	local heroes = store.data.heroes
	if heroes and type(heroes.list) == "table" then
		set_heroes(heroes.list)
		D.heroes_at = tonumber(heroes.time) or 0
	end
	local pro = store.data.pro
	if type(pro) == "table" then
		if type(pro.pos) == "table" then
			set_pos(pro.pos)
			D.pos_at = tonumber(pro.pos_time) or 0
		end
		if type(pro.contest) == "table" then
			set_contest(pro.contest)
			D.contest_at = tonumber(pro.contest_time) or 0
		end
	end
	load_set(D.sets[0], K.RANKS[cfg.rank + 1] or 70)
end

local function save_matches(S)
	if not S.rank then
		return
	end
	local key = S.source .. ":" .. S.rank
	store.blobs[key] = table.concat(S.recs)
	store.data.sets[key] = { updated = S.updated, exhausted = S.exhausted, oldest = S.oldest, used = os.time() }
	store_save()
end

local function record_id(rec)
	return (string.unpack("<I8", rec))
end

local function build_chunk(b)
	local st, recs = b.st, b.recs
	local bg, bw, vg, vw, sg, sw = st.bg, st.bw, st.vg, st.vw, st.sg, st.sw
	local h = b.h
	local last = math.min(st.n, b.i + K.CHUNK)
	for i = b.i + 1, last do
		local rec = recs[i]
		h[1], h[2], h[3], h[4], h[5], h[6], h[7], h[8], h[9], h[10] = rec:byte(9, 18)
		local rad = rec:byte(19) == 1
		for j = 1, 10 do
			local a = h[j]
			bg[a] = (bg[a] or 0) + 1
			if (j <= 5) == rad then
				bw[a] = (bw[a] or 0) + 1
			end
		end
		for j = 1, 5 do
			local a = h[j]
			for l = 6, 10 do
				local c = h[l]
				local key, won
				if a < c then
					key, won = a * 256 + c, rad
				else
					key, won = c * 256 + a, not rad
				end
				vg[key] = (vg[key] or 0) + 1
				if won then
					vw[key] = (vw[key] or 0) + 1
				end
			end
		end
		for t = 0, 5, 5 do
			local won = (t == 0) == rad
			for j = 1, 4 do
				local a = h[t + j]
				for l = j + 1, 5 do
					local c = h[t + l]
					local key = a < c and a * 256 + c or c * 256 + a
					sg[key] = (sg[key] or 0) + 1
					if won then
						sw[key] = (sw[key] or 0) + 1
					end
				end
			end
		end
	end
	b.i = last
	return last >= st.n
end

local function start_build(S, recs)
	recs = recs or S.recs
	S.build = {
		recs = recs,
		i = 0,
		h = {},
		t0 = os.clock(),
		st = { bg = {}, bw = {}, vg = {}, vw = {}, sg = {}, sw = {}, n = #recs },
	}
	log("building %s stats from %d matches", S.file, #recs)
end

local function save_stats(S, st)
	if not S.rank or #S.recs == 0 then
		return
	end
	local parts = { string.pack("<I4I4", st.n, st.median or 1) }
	for _, f in ipairs(K.STAT_FIELDS) do
		local m, cnt = st[f], 0
		for _ in pairs(m) do
			cnt = cnt + 1
		end
		parts[#parts + 1] = string.pack("<I4", cnt)
		for k, v in pairs(m) do
			parts[#parts + 1] = string.pack("<I4I4", k, v)
		end
	end
	local key = "st:" .. S.source .. ":" .. S.rank
	store.blobs[key] = table.concat(parts)
	store.data.sets[key] = { used = os.time(), n = #S.recs, top = tostring(record_id(S.recs[1])) }
	store_save()
end

local function load_stats(S)
	local key = "st:" .. S.source .. ":" .. S.rank
	local meta, blob = store.data.sets[key], store.blobs[key]
	if not meta or not blob or #S.recs == 0 or tonumber(meta.n) ~= #S.recs or meta.top ~= tostring(record_id(S.recs[1])) then
		return false
	end
	local ok, st = pcall(function()
		local n, median, pos = string.unpack("<I4I4", blob)
		local out = { n = n, median = median }
		for _, f in ipairs(K.STAT_FIELDS) do
			local cnt
			cnt, pos = string.unpack("<I4", blob, pos)
			local m = {}
			for _ = 1, cnt do
				local k, v
				k, v, pos = string.unpack("<I4I4", blob, pos)
				m[k] = v
			end
			out[f] = m
		end
		return out
	end)
	if not ok or type(st) ~= "table" then
		return false
	end
	S.stats = st
	meta.used = os.time()
	draft.dirty = true
	return true
end

local function step_build(S)
	local b = S.build
	if not b then
		return
	end
	local ok, done = pcall(build_chunk, b)
	if not ok then
		LOGR.err("build", tostring(done))
		S.build = nil
		return
	end
	if done then
		S.build = nil
		local counts = {}
		for _, g in pairs(b.st.bg) do
			if g >= K.MIN_GAMES then
				counts[#counts + 1] = g
			end
		end
		table.sort(counts)
		b.st.median = counts[math.max(1, math.floor(#counts / 2))] or 1
		S.stats = b.st
		draft.dirty = true
		log("%s stats ready: %d matches in %.1f s", S.file, b.st.n, os.clock() - (b.t0 or os.clock()))
		if b.recs == S.recs then
			pcall(save_stats, S, b.st)
		end
	end
end

local function matches_sql(S, rank, above, below)
	local where = { S.source == 1 and "game_mode=2" or "lobby_type=7" }
	if rank > 0 then
		where[#where + 1] = "avg_rank_tier>=" .. rank
	end
	if above then
		where[#where + 1] = ("match_id>%d"):format(above)
	end
	if below then
		where[#where + 1] = ("match_id<%d"):format(below)
	end
	local inner = ("select match_id m, radiant_team r, dire_team d, radiant_win w, avg_rank_tier t, start_time s from public_matches where %s order by match_id desc limit %d")
		:format(table.concat(where, " and "), S.page)
	return compact_sql(inner, { "m", "array_to_string(r, '.')", "array_to_string(d, '.')", "w::int", "t", "s" }, "m desc")
end

local function parse_matches(text)
	local rows, err = compact_rows(text)
	if not rows then
		return nil, err
	end
	local count = #rows
	local out, low, oldest, high, newest = {}, nil, nil, nil, nil
	for _, f in ipairs(rows) do
		local id = math.tointeger(tonumber(f[1]))
		local r, d = f[2], f[3]
		local w = f[4] == "1" and "true" or f[4] == "0" and "false" or nil
		local t = tonumber(f[5]) or 0
		local s = tonumber(f[6])
		if id then
			low = low and math.min(low, id) or id
			high = high and math.max(high, id) or id
			if s then
				oldest = oldest and math.min(oldest, s) or s
				newest = newest and math.max(newest, s) or s
			end
			if r and d and (w == "true" or w == "false") then
				local ids, ok = {}, true
				for hero in (r .. "." .. d):gmatch("%d+") do
					local v = tonumber(hero)
					if not v or v < 1 or v > 255 then
						ok = false
					end
					ids[#ids + 1] = v
				end
				if ok and #ids == 10 then
					out[#out + 1] = pack_record(id, ids, w == "true" and 1 or 0, clamp(t, 0, 255))
				end
			end
		end
	end
	return out, count, low, oldest, high, newest
end

local function want(S)
	local target = K.VOLUMES[cfg.volume + 1] or 100000
	if S.source == 1 then
		target = math.min(target, K.CM_MAX)
	end
	return K.RANKS[cfg.rank + 1] or 70, target
end

local function pack_text(name)
	local dir = Engine.GetCheatDirectory()
	if type(dir) ~= "string" then
		return nil
	end
	if not dir:match("[\\/]$") then
		dir = dir .. "\\"
	end
	local f = io.open(dir .. "configs\\" .. K.PACK_DIR .. "\\" .. name, "rb")
	if not f then
		return nil
	end
	local text = f:read("a")
	f:close()
	local t, body = (text or ""):match("^t=(%d+)[^\n]*\n(.*)$")
	if not t or body == "" then
		return nil
	end
	return body, tonumber(t)
end

function D.pack_url(name, n)
	local list = K.GH_URLS
	return list[((n or 1) - 1) % #list + 1] .. "pack/" .. name
end

function D.pack_body(res)
	local text = type(res) == "table" and tostring(res.code) == "200" and type(res.response) == "string" and res.response or ""
	local t, q, body = text:match("^t=(%d+) ?q?=?(%d*)[^\n]*\n(.+)$")
	return body, tonumber(t), tonumber(q)
end

local function request(url, param, on_done)
	D.busy = true
	D.busy_at = os.clock()
	D.seq = (D.seq or 0) + 1
	local seq = D.seq
	local sent = HTTP.Request("GET", url, { headers = K.HEADERS, timeout = K.TIMEOUT }, function(res)
		if seq ~= D.seq then return end
		D.busy = false
		D.next_request = os.clock() + K.GAP
		local ok, err = pcall(on_done, res)
		if not ok then
			D.error = tostring(err):gsub("^.-:%d+: ", "")
			local low_err = D.error:lower()
			local short = low_err:find("timeout", 1, true) or low_err:find("cut off", 1, true) or low_err:find("json", 1, true)
				or low_err:find("connect", 1, true) or low_err:find("resolve", 1, true) or low_err:find("http 0 ", 1, true)
			D.next_request = os.clock() + (short and K.RETRY_SHORT or K.RETRY)
			if D.error ~= D.logged_error then
				D.logged_error = D.error
				LOGR.put(param .. " failed: " .. D.error)
			end
		end
	end, param)
	if not sent then
		D.busy = false
		D.error = "request was not sent"
		D.next_request = os.clock() + K.SEND_RETRY
	end
end

local function fail(what, res)
	local body = type(res.response) == "string" and res.response:match('"err":"([^"]*)"') or ""
	error(("%s: http %s %s %s"):format(what, tostring(res.code), tostring(res.error_message or ""), body))
end

local function request_heroes()
	D.status = "cd_st_heroes"
	local src = D.hero_src or 1
	local function on_heroes(res)
		D.hero_src = src % #K.HEROES_URLS + 1
		if tostring(res.code) ~= "200" then
			fail("heroes", res)
		end
		local data = JSON:decode(res.response)
		local list = {}
		for _, h in pairs(type(data) == "table" and data or {}) do
			if type(h) == "table" and tonumber(h.id) then
				list[#list + 1] = {
					id = tonumber(h.id),
					name = h.name,
					localized_name = h.localized_name,
					primary_attr = h.primary_attr,
					attack_type = h.attack_type,
					roles = h.roles,
				}
			end
		end
		table.sort(list, function(a, b)
			return a.id < b.id
		end)
		if #list < 100 then
			error("heroes: bad list")
		end
		D.hero_src = src
		set_heroes(list)
		D.heroes_at = os.time()
		D.error = nil
		store.data.heroes = { time = D.heroes_at, list = list }
		store_save()
		log("heroes loaded: %d", #D.heroes)
	end
	if not D.heroes and not D.pack_heroes then
		D.pack_heroes = true
		local text, t = pack_text("heroes.json")
		if text and pcall(on_heroes, { code = 200, response = text }) then
			D.heroes_at = t
			store.data.heroes.time = t
			log("heroes from the local pack")
			return
		end
	end
	request(K.HEROES_URLS[src], "cd_heroes", on_heroes)
end

local function explorer(sql, param, cols, on_rows)
	request(K.EXPLORER .. url_encode(compact_sql(sql, cols)), param, function(res)
		if tostring(res.code) ~= "200" then
			fail(param, res)
		end
		local list, err = compact_rows(res.response)
		if not list then
			error(param .. ": " .. tostring(err))
		end
		local rows = {}
		for i, f in ipairs(list) do
			local row = {}
			for k, name in ipairs(cols) do
				row[name] = f[k]
			end
			rows[i] = row
		end
		on_rows(rows)
		D.error = nil
	end)
end

local function save_pro(rows_pos, rows_contest)
	local pro = type(store.data.pro) == "table" and store.data.pro or {}
	if rows_pos then
		pro.pos, pro.pos_time = rows_pos, D.pos_at
	end
	if rows_contest then
		pro.contest, pro.contest_time = rows_contest, D.contest_at
	end
	store.data.pro = pro
	store_save()
end

local function request_pos()
	D.status = "cd_st_pro"
	local sql = ("with m as (select match_id from matches order by match_id desc limit %d), "
		.. "p as (select pm.match_id, pm.hero_id h, pm.player_slot<128 t, coalesce(pm.lane_role,4) l, pm.gold_per_min g "
		.. "from player_matches pm join m using(match_id) where pm.gold_per_min is not null), "
		.. "c as (select *, row_number() over (partition by match_id, t, l order by g desc) lr from p), "
		.. "d as (select *, case when l in (1,2,3) and lr=1 then l end core from c), "
		.. "e as (select *, row_number() over (partition by match_id, t, (core is null) order by g desc) sr from d) "
		.. "select h, coalesce(core, case when sr=1 then 4 else 5 end) pos, count(*) n from e group by 1,2")
		:format(K.PRO_MATCHES)
	local function on_rows(rows)
		set_pos(rows)
		D.pos_at = os.time()
		save_pro(rows, nil)
		log("positions loaded: %d rows", #rows)
	end
	if not D.pos_count and not D.pack_pos then
		local text, t = pack_text("pro_pos.json")
		if not text and not D.web_pos then
			D.web_pos = true
			request(D.pack_url("pro_pos.json", D.web_src), "cd_pos", function(res)
				local body, wt = D.pack_body(res)
				local ok, rows = pcall(JSON.decode, JSON, body or "")
				if body and ok and type(rows) == "table" and #rows > 0 and pcall(on_rows, rows) then
					D.pos_at = wt
					save_pro(rows, nil)
					log("positions from the GitHub pack (%s)", os.date("%Y-%m-%d", wt))
				else
					D.web_src = (D.web_src or 1) + 1
					log("positions: GitHub pack http %s, asking OpenDota", tostring(res.code))
				end
			end)
			return
		end
		D.pack_pos = true
		local ok, rows = pcall(JSON.decode, JSON, text or "")
		if text and ok and type(rows) == "table" and #rows > 0 and pcall(on_rows, rows) then
			D.pos_at = t
			save_pro(rows, nil)
			log("positions from the local pack")
			return
		end
	end
	explorer(sql, "cd_pos", { "h", "pos", "n" }, on_rows)
end

local function request_contest()
	D.status = "cd_st_pro"
	local sql = ("with m as (select match_id from matches where game_mode=2 order by match_id desc limit %d) "
		.. "select hero_id h, count(*) c, (select count(*) from m) n from picks_bans join m using(match_id) group by 1")
		:format(K.CONTEST_MATCHES)
	local function on_rows(rows)
		set_contest(rows)
		D.contest_at = os.time()
		save_pro(nil, rows)
		log("pro contest loaded: %d heroes", #rows)
	end
	if not D.contest and not D.pack_contest then
		local text, t = pack_text("pro_contest.json")
		if not text and not D.web_contest then
			D.web_contest = true
			request(D.pack_url("pro_contest.json", D.web_src), "cd_contest", function(res)
				local body, wt = D.pack_body(res)
				local ok, rows = pcall(JSON.decode, JSON, body or "")
				if body and ok and type(rows) == "table" and #rows > 0 and pcall(on_rows, rows) then
					D.contest_at = wt
					save_pro(nil, rows)
					log("pro contest from the GitHub pack (%s)", os.date("%Y-%m-%d", wt))
				else
					D.web_src = (D.web_src or 1) + 1
					log("pro contest: GitHub pack http %s, asking OpenDota", tostring(res.code))
				end
			end)
			return
		end
		D.pack_contest = true
		local ok, rows = pcall(JSON.decode, JSON, text or "")
		if text and ok and type(rows) == "table" and #rows > 0 and pcall(on_rows, rows) then
			D.contest_at = t
			save_pro(nil, rows)
			log("pro contest from the local pack")
			return
		end
	end
	explorer(sql, "cd_contest", { "h", "c", "n" }, on_rows)
end

local function finish_job(S)
	local job = S.job
	S.job = nil
	S.updated = os.time()
	save_matches(S)
	start_build(S)
	log("%s ready: %d (rank %d, %d new)", S.file, #S.recs, S.rank, job.added or 0)
end

local function next_window(job)
	job.cursor = job.lo + 1
	job.lo = job.cursor - K.CM_WINDOW
end

local function request_page(S)
	local job = S.job
	local rank, target = want(S)
	if rank ~= S.rank then
		S.job = nil
		return
	end
	local windowed = S.source == 1 and job.phase == "tail" and job.lo ~= nil
	local page = S.page
	local sql
	if job.phase == "head" then
		sql = matches_sql(S, rank, job.top, job.cursor)
	elseif windowed then
		sql = matches_sql(S, rank, job.lo, job.cursor)
	else
		sql = matches_sql(S, rank, nil, job.cursor)
	end
	D.status = "cd_st_matches"
	D.loading = S
	local cutoff = S.source == 1 and os.time() - K.CM_DAYS * 86400 or nil
	request(K.EXPLORER .. url_encode(sql), "cd_page", function(res)
		if S.job ~= job then
			return
		end
		local recs, count, low, oldest, high, newest
		if tostring(res.code) == "200" then
			recs, count, low, oldest, high, newest = parse_matches(res.response)
		else
			count = type(res.response) == "string" and res.response:match('"err":"([^"]*)"')
				or ("http " .. tostring(res.code) .. " " .. tostring(res.error_message or ""))
		end
		if not recs then
			local timeout = tostring(count):lower():find("timeout", 1, true) or tostring(count):find("cut off", 1, true)
			if timeout then
				S.ok = 0
				if S.page > K.PAGE_MIN then
					S.page = math.max(K.PAGE_MIN, math.floor(S.page / 2))
				elseif windowed then
					job.fails = (job.fails or 0) + 1
					if job.fails >= 2 then
						job.fails = 0
						next_window(job)
						log("%s: window skipped after timeouts", S.file)
					end
				end
			end
			error("page: " .. tostring(count))
		end
		D.error = nil
		job.fails = 0
		S.ok = (S.ok or 0) + 1
		local full = S.source == 1 and K.PAGE_CM or K.PAGE
		if S.ok >= 3 and S.page < full then
			S.ok, S.page = 0, math.min(full, S.page * 2)
		end
		job.pages = job.pages + 1
		job.added = (job.added or 0) + #recs
		if oldest then
			job.oldest = job.oldest and math.min(job.oldest, oldest) or oldest
			S.oldest = S.oldest and math.min(S.oldest, oldest) or oldest
		end
		if S.source == 1 and not job.floor and high and low and newest and oldest and newest > oldest then
			local rate = (high - low) / (newest - oldest)
			job.floor = math.floor(high - rate * K.CM_DAYS * 86400)
		end
		local too_old = (cutoff and oldest and oldest < cutoff) or (job.floor and job.cursor and job.cursor < job.floor)
		if job.phase == "head" then
			for _, rec in ipairs(recs) do
				job.newer[#job.newer + 1] = rec
			end
			job.cursor = low
			if count < page or not low or #job.newer >= target or too_old then
				local merged = job.newer
				if #merged < target then
					for _, rec in ipairs(S.recs) do
						merged[#merged + 1] = rec
						if #merged >= target then
							break
						end
					end
				end
				S.recs = merged
				job.newer = nil
				if #S.recs < target and #S.recs > 0 and not too_old and not S.exhausted then
					job.phase, job.cursor = "tail", record_id(S.recs[#S.recs])
					if S.source == 1 then
						job.lo = job.cursor - K.CM_WINDOW
					end
				else
					if too_old then
						S.exhausted = true
					end
					finish_job(S)
					return
				end
			end
		else
			for _, rec in ipairs(recs) do
				if #S.recs >= target then
					break
				end
				S.recs[#S.recs + 1] = rec
			end
			if S.source == 1 then
				if not job.lo then
					job.cursor = low
					job.lo = low and low - K.CM_WINDOW or nil
				elseif count < page or not low then
					next_window(job)
				else
					job.cursor = low
				end
				local done = too_old or #S.recs >= target or not job.cursor
				if done then
					if #S.recs < target then
						S.exhausted = true
					end
					finish_job(S)
					return
				end
			else
				job.cursor = low
				if count < page or not low or #S.recs >= target or too_old then
					if #S.recs < target then
						S.exhausted = true
					end
					finish_job(S)
					return
				end
			end
			if job.pages % K.SAVE_EVERY == 0 then
				save_matches(S)
			end
		end
		if not S.stats and not S.build then
			local pool = (S.job and S.job.newer and #S.recs == 0) and S.job.newer or S.recs
			if #pool >= (S.source == 1 and K.PARTIAL_CM or K.PARTIAL) then
				start_build(S, pool)
			end
		end
	end)
end

local function job_counts()
	local S = D.loading or D.sets[source()]
	local _, target = want(S)
	if not S.stats and not S.build then
		target = math.min(target, S.source == 1 and K.PARTIAL_CM or K.PARTIAL)
	end
	local job = S.job
	local have = #S.recs
	if job and job.newer then
		have = math.min(target, #job.newer + #S.recs)
	end
	return have, target
end

local function job_progress()
	local have, target = job_counts()
	local p = clamp(have / target, 0, 1)
	local S = D.loading
	if S and S.source == 1 and S.job and S.job.oldest and S.job.phase == "tail" then
		p = math.max(p, clamp((os.time() - S.job.oldest) / (K.CM_DAYS * 86400), 0, 1))
	end
	return p
end

local function job_days()
	local S = D.loading
	if S and S.source == 1 and S.job and S.job.oldest then
		return math.floor((os.time() - S.job.oldest) / 86400)
	end
	return nil
end

local function job_eta()
	local S = D.loading
	local job = S and S.job
	if not job or not job.t0 then
		return nil
	end
	local _, target = job_counts()
	if job.eta_target ~= target then
		job.eta_target, job.t0, job.p0 = target, os.clock(), nil
	end
	local p = job_progress()
	job.p0 = job.p0 or p
	local elapsed = os.clock() - job.t0
	if elapsed < K.ETA_WARMUP or p <= job.p0 + 0.005 then
		return nil
	end
	return elapsed * (1 - p) / (p - job.p0)
end

local function parse_gh(text)
	local st = { bg = {}, bw = {}, vg = {}, vw = {}, sg = {}, sw = {}, n = tonumber(text:match("^n (%d+)")) }
	if not st.n then
		error("github stats: bad file")
	end
	local games = { b = st.bg, v = st.vg, s = st.sg }
	local wins = { b = st.bw, v = st.vw, s = st.sw }
	for kind, key, g, w in text:gmatch("(%a) (%d+) (%d+) (%d+)") do
		local gt = games[kind]
		if gt then
			key, w = tonumber(key), tonumber(w)
			gt[key] = tonumber(g)
			if w > 0 then
				wins[kind][key] = w
			end
		end
	end
	local counts = {}
	for _, g in pairs(st.bg) do
		if g >= K.MIN_GAMES then
			counts[#counts + 1] = g
		end
	end
	table.sort(counts)
	st.median = counts[math.max(1, math.floor(#counts / 2))] or 1
	return st
end

local function own_enough(S)
	return #S.recs >= (S.source == 1 and K.PARTIAL_CM or K.PARTIAL)
end

local function nearest_stats(S, rank)
	local cands = {}
	for _, r in ipairs(K.RANKS) do
		for _, v in ipairs(S.source == 1 and { K.CM_MAX } or K.VOLUMES) do
			cands[#cands + 1] = { key = ("%d_%d_%d"):format(S.source, r, v), v = v,
				d = r == rank and 0 or (r == 0 and 1 or 2 + math.abs(r - rank)) }
		end
	end
	table.sort(cands, function(a, b)
		if a.d ~= b.d then
			return a.d < b.d
		end
		return a.v > b.v
	end)
	for _, c in ipairs(cands) do
		local text, t = store.blobs["gh:" .. c.key], nil
		local meta = store.data.sets["gh:" .. c.key]
		if text and type(meta) == "table" then
			t = tonumber(meta.time)
		else
			text, t = pack_text("stats_" .. c.key .. ".txt")
		end
		if text then
			local ok, st = pcall(parse_gh, text)
			if ok then
				return st, c.key, t or 0
			end
		end
	end
	return nil
end

local function gh_stats(S)
	local rank, target = want(S)
	if not S.loaded or S.rank ~= rank or own_enough(S) or S.build then
		S.gh_on = nil
		return false
	end
	local forced = S.force
	if forced then
		S.force, S.gh_retry = false, 0
	end
	local key = ("%d_%d_%d"):format(S.source, rank, target)
	local meta = store.data.sets["gh:" .. key]
	local fresh = type(meta) == "table" and os.time() - (tonumber(meta.time) or 0) < K.GH_TTL
	if S.gh_on ~= key then
		local blob = store.blobs["gh:" .. key]
		local ok, st = false, nil
		if blob and type(meta) == "table" then
			ok, st = pcall(parse_gh, blob)
		end
		if ok then
			S.stats, S.gh_on, S.updated = st, key, tonumber(meta.time) or 0
			meta.used = os.time()
			draft.dirty = true
			log("github stats %s from cache: %d matches", key, st.n)
		else
			S.gh_on = nil
		end
	end
	if S.gh_on ~= key and S.gh_pack ~= key then
		S.gh_pack = key
		local text, t = pack_text("stats_" .. key .. ".txt")
		local ok, st = false, nil
		if text then
			ok, st = pcall(parse_gh, text)
		end
		if ok then
			store.blobs["gh:" .. key] = text
			store.data.sets["gh:" .. key] = { time = t, used = os.time() }
			meta = store.data.sets["gh:" .. key]
			fresh = os.time() - t < K.GH_TTL
			S.stats, S.gh_on, S.updated = st, key, t
			draft.dirty = true
			log("draft stats %s from the local pack: %d matches", key, st.n)
		end
	end
	if S.gh_on ~= key and S.gh_near ~= key then
		S.gh_near = key
		local st, near, t = nearest_stats(S, rank)
		if st then
			S.stats, S.gh_on, S.updated = st, key, t
			draft.dirty = true
			log("draft stats %s not on disk, using %s: %d matches", key, near, st.n)
		end
	end
	if (S.gh_on == key and fresh and not forced) or os.clock() < (S.gh_retry or 0) then
		return false
	end
	S.gh_retry = os.clock() + K.GH_RETRY
	D.status = "cd_st_matches"
	local base = D.gh_base or 1
	request(K.GH_URLS[base] .. "stats/" .. key .. ".txt", "cd_stats", function(res)
		local code = tostring(res.code)
		if code ~= "200" or type(res.response) ~= "string" or res.response == "" then
			D.gh_base = base % #K.GH_URLS + 1
			D.gh_miss = (D.gh_miss or 0) + 1
			local all = D.gh_miss >= #K.GH_URLS
			S.gh_retry = os.clock() + (not all and K.RETRY_SHORT or code == "404" and K.GH_GONE or K.GH_RETRY)
			if all then
				D.gh_miss = 0
			end
			if D.gh_gone ~= key .. code then
				D.gh_gone = key .. code
				log("github stats %s: http %s %s from %s, using what is on disk", key, code,
					tostring(res.error_message or ""), K.GH_URLS[base])
			end
			return
		end
		D.gh_miss = 0
		local st = parse_gh(res.response)
		store.blobs["gh:" .. key] = res.response
		store.data.sets["gh:" .. key] = { time = os.time(), used = os.time() }
		store_save()
		if S.rank == rank and not own_enough(S) then
			S.stats, S.gh_on, S.updated = st, key, os.time()
			draft.dirty = true
		end
		D.error = nil
		log("github stats %s: %d matches", key, st.n)
	end)
	return true
end

local function plan_job(S)
	if S.job then
		return
	end
	local rank, target = want(S)
	if not S.loaded then
		load_set(S, rank)
	elseif S.rank ~= rank then
		if #S.recs > 0 then
			save_matches(S)
		end
		load_set(S, rank)
	end
	if S.gh_on and S.stats and not own_enough(S) and not S.force then
		return
	end
	if #S.recs > target then
		for i = #S.recs, target + 1, -1 do
			S.recs[i] = nil
		end
		save_matches(S)
		start_build(S)
	end
	local stale = os.time() - S.updated > K.MATCHES_TTL
	if S.force then
		S.exhausted = false
	end
	local hold = D.in_match and S.stats and not S.force
	if not hold and (S.force or stale or (#S.recs < target and not S.exhausted)) then
		if not S.stats and not S.build and #S.recs > 0 then
			S.stats_tried = true
			if load_stats(S) then
				log("%s stats from cache before the update: %d matches", S.file, S.stats.n)
			else
				start_build(S)
			end
		end
		local top = #S.recs > 0 and record_id(S.recs[1]) or nil
		if top then
			S.job = { phase = "head", top = top, cursor = nil, newer = {}, pages = 0 }
		else
			S.job = { phase = "tail", cursor = nil, pages = 0 }
		end
		S.job.t0 = os.clock()
		S.job.p0 = clamp(#S.recs / target, 0, 1)
		S.force = false
		log("job %s: rank %d, have %d, want %d, top %s", S.file, rank, #S.recs, target, tostring(top))
	elseif not S.stats and not S.build and #S.recs > 0 then
		S.stats_tried = true
		if not load_stats(S) then
			start_build(S)
		end
	end
end

local function any_busy()
	for _, S in pairs(D.sets) do
		if S.job or S.build then
			return true
		end
	end
	return false
end

local function data_tick()
	if not D.loaded then
		local t0 = os.clock()
		load_cache()
		log("load: cache read in %.2f s, models %s", os.clock() - t0, D.models_ok and K.MODELS or "missing")
	end
	D.models_tick()
	for _, S in pairs(D.sets) do
		if S.loaded and not S.stats and not S.build and not S.job and not S.stats_tried and #S.recs > 0 then
			S.stats_tried = true
			local t0 = os.clock()
			if load_stats(S) then
				log("%s stats from cache: %d matches in %.2f s", S.file, S.stats.n, os.clock() - t0)
			end
		end
	end
	step_build(D.sets[0])
	step_build(D.sets[1])
	if D.busy and os.clock() - (D.busy_at or 0) > K.ANSWER_WAIT then
		D.busy = false
		D.seq = (D.seq or 0) + 1
		D.error = "no answer"
		D.next_request = os.clock() + K.RETRY_SHORT
		log("stats request got no answer, retrying")
	end
	if D.busy or os.clock() < D.next_request then
		return
	end
	local now = os.time()
	D.try = D.try or {}
	local function due(k, missing, at, ttl)
		if D.in_match and not missing then
			return false
		end
		if not missing and now - (at or 0) <= ttl then
			return false
		end
		if os.clock() < (D.try[k] or 0) then
			return false
		end
		D.try[k] = os.clock() + K.STALE_RETRY
		return true
	end
	if not D.heroes then
		request_heroes()
		return
	end
	if due("h", false, D.heroes_at, K.HEROES_TTL) then
		request_heroes()
		return
	end
	if due("p", not D.pos_count, D.pos_at, K.PRO_TTL) then
		request_pos()
		return
	end
	if due("c", not D.contest, D.contest_at, K.PRO_TTL) then
		request_contest()
		return
	end
	local order = { D.sets[0] }
	if source() == 1 then
		order = (D.sets[0].stats or D.sets[0].build) and { D.sets[1], D.sets[0] } or { D.sets[0], D.sets[1] }
	end
	for _, S in ipairs(order) do
		local rank = want(S)
		if not S.loaded or S.rank ~= rank then
			if S.loaded and #S.recs > 0 then
				save_matches(S)
			end
			load_set(S, rank)
		end
		if D.in_match and S.stats then
			break
		end
		if not S.job and gh_stats(S) then
			return
		end
		plan_job(S)
		if S.job then
			request_page(S)
			return
		end
	end
	D.loading = nil
	D.status = any_busy() and "cd_st_build" or nil
end

local function refresh_data()
	D.heroes_at, D.pos_at, D.contest_at = 0, 0, 0
	D.try = {}
	for _, S in pairs(D.sets) do
		S.force = true
	end
	D.next_request, D.error = 0, nil
	log("manual refresh")
end

local U = {
	status = "idle",
	remote = nil,
	url = nil,
	checked = 0,
	error = nil,
	reload_at = nil,
	busy = false,
}

do
	local function parts(v)
		local out = {}
		for n in tostring(v or ""):gmatch("%d+") do
			out[#out + 1] = tonumber(n)
		end
		return out
	end

	local function newer(a, b)
		local x, y = parts(a), parts(b)
		for i = 1, math.max(#x, #y) do
			local p, q = x[i] or 0, y[i] or 0
			if p ~= q then
				return p > q
			end
		end
		return false
	end

	local function script_path()
		local ok, info = pcall(function()
			return debug and debug.getinfo and debug.getinfo(1, "S")
		end)
		local src = ok and type(info) == "table" and info.source or nil
		if type(src) == "string" and src:sub(1, 1) == "@" and src:lower():find("%.lua$") then
			return src:sub(2)
		end
		local dir = Engine.GetCheatDirectory()
		if not dir:match("[\\/]$") then
			dir = dir .. "\\"
		end
		return dir .. "scripts\\" .. K.SCRIPT_NAME
	end

	local function fail(msg)
		U.status, U.error, U.busy = "error", msg, false
		LOGR.put("update: " .. msg)
	end

	function U.check(i)
		if U.busy and not i then
			return
		end
		i = i or 1
		local url = K.UPDATE_URLS[i]
		if not url then
			return
		end
		U.busy, U.status, U.error = true, "checking", nil
		U.checked, U.busy_at = os.time(), os.clock()
		local function next_or_fail(msg)
			if K.UPDATE_URLS[i + 1] then
				log("update check %d: %s, trying the next source", i, msg)
				U.check(i + 1)
			else
				fail("check: " .. msg)
			end
		end
		local sent = HTTP.Request("GET", url, { headers = K.HEADERS, timeout = 60 }, function(res)
			U.busy = false
			U.checked = os.time()
			if tostring(res.code) ~= "200" then
				next_or_fail("http " .. tostring(res.code) .. " " .. tostring(res.error_message or ""))
				return
			end
			local ok, data = pcall(JSON.decode, JSON, res.response)
			local urls = ok and type(data) == "table" and type(data.urls) == "table" and data.urls or nil
			if not ok or type(data) ~= "table" or type(data.version) ~= "string" or not (urls or type(data.url) == "string") then
				next_or_fail("bad version.json")
				return
			end
			U.remote, U.urls, U.size = data.version, urls or { data.url }, tonumber(data.size)
			U.url = U.urls[1]
			U.status = newer(data.version, K.VERSION) and "available" or "latest"
			log("update check: local %s, remote %s -> %s", K.VERSION, data.version, U.status)
		end, "cd_update")
		if not sent then
			U.busy = false
			next_or_fail("request was not sent")
		end
	end

	local function write_script(text)
		local tok = LOGR.token()
		if tok ~= "" then
			text = text:gsub('LOG_TOKEN = ""', 'LOG_TOKEN = "' .. tok .. '"', 1)
		end
		local path = script_path()
		local tmp = path .. ".new"
		local f = io.open(tmp, "wb")
		if not f then
			return "no access to " .. path
		end
		f:write(text)
		f:close()
		os.remove(path)
		if not os.rename(tmp, path) then
			local g = io.open(path, "wb")
			if not g then
				return "could not replace " .. path
			end
			g:write(text)
			g:close()
			os.remove(tmp)
		end
		return nil
	end

	function U.install(i)
		if not U.urls or (not i and (U.busy or U.status ~= "available")) then
			return
		end
		i = i or 1
		local url = U.urls[i]
		if not url then
			return
		end
		U.busy, U.status, U.error, U.busy_at = true, "downloading", nil, os.clock()
		local want = U.remote
		local function next_or_fail(msg)
			if U.urls[i + 1] then
				log("update download %d: %s, trying the next source", i, msg)
				U.install(i + 1)
			else
				fail("download: " .. msg)
			end
		end
		local sent = HTTP.Request("GET", url, { headers = K.HEADERS, timeout = 90 }, function(res)
			U.busy = false
			if tostring(res.code) ~= "200" or type(res.response) ~= "string" then
				next_or_fail("http " .. tostring(res.code) .. " " .. tostring(res.error_message or ""))
				return
			end
			local text = res.response
			if #text < K.UPDATE_MIN_SIZE or (U.size and #text ~= U.size) then
				next_or_fail(("size %d, expected %s"):format(#text, tostring(U.size)))
				return
			end
			local version = text:match('VERSION = "([^"]+)"')
			if version ~= want then
				next_or_fail("version inside is " .. tostring(version) .. ", expected " .. tostring(want))
				return
			end
			if type(load) == "function" then
				local chunk, err = load(text, "=draft_helper", "t")
				if not chunk then
					next_or_fail("file does not compile: " .. tostring(err))
					return
				end
			end
			local err = write_script(text)
			if err then
				fail("write: " .. err)
				return
			end
			U.status = "done"
			U.reload_at = os.clock() + K.UPDATE_RELOAD_DELAY
			LOGR.put("updated " .. K.VERSION .. " -> " .. want .. ", reloading scripts")
		end, "cd_update_file")
		if not sent then
			U.busy = false
			next_or_fail("request was not sent")
		end
	end

	function U.idle()
		local gs = GameRules.GetGameState()
		if gs and K.MATCH_STATES[gs] then
			return false
		end
		return not Engine.IsInGame()
	end

	function U.tick()
		if U.reload_at and os.clock() >= U.reload_at then
			U.reload_at = nil
			Engine.ReloadScriptSystem()
			return
		end
		if not U.token_saved then
			U.token_saved = true
			LOGR.token()
		end
		if U.busy and os.clock() - (U.busy_at or 0) > K.UPDATE_WAIT then
			U.busy = false
			if U.status == "downloading" then
				U.status = "available"
			end
		end
		if U.busy then
			return
		end
		local wait = U.status == "error" and K.UPDATE_RETRY or K.UPDATE_EVERY
		if U.status == "error" and U.remote and U.urls and newer(U.remote, K.VERSION) and U.idle()
			and os.clock() >= (U.auto_at or 0) then
			U.status = "available"
		end
		if os.time() - U.checked > wait and U.status ~= "available" then
			U.check()
		elseif U.status == "available" and U.idle() and os.clock() >= (U.auto_at or 0) then
			U.auto_at = os.clock() + K.UPDATE_RETRY
			log("update: installing %s automatically", tostring(U.remote))
			U.install()
		end
	end
end

local M = {}

do
	local function ranked()
		return D.sets[0].stats
	end

	local function cm()
		return source() == 1 and D.sets[1].stats or nil
	end

	local function shrink(w, g, prior, weight)
		return (w + weight * prior) / (g + weight)
	end

	local function base_ranked(h)
		local st = ranked()
		return shrink(st.bw[h] or 0, st.bg[h] or 0, 0.5, K.PRIOR_BASE)
	end

	function M.base(h)
		local p = base_ranked(h)
		local c = cm()
		if c then
			p = shrink(c.bw[h] or 0, c.bg[h] or 0, p, K.PRIOR_CM)
		end
		return p
	end

	function M.rarity(h)
		local st = ranked()
		local g = st and st.bg[h] or 0
		local med = st and st.median or 1
		if g <= 0 or g >= med then
			return 0
		end
		return K.RARE_W * math.log(g / med)
	end

	function M.games(h)
		local st = ranked()
		return st and st.bg[h] or 0
	end

	function M.comeback(h)
		if not M.cb then
			M.cb = {}
			for id, v in K.COMEBACK:gmatch("(%d+):(%-?%d+)") do
				M.cb[math.tointeger(tonumber(id))] = tonumber(v) / 1000
			end
		end
		return M.cb[h] or 0
	end

	function M.shown_games(h)
		local c = cm()
		if c then
			return c.bg[h] or 0
		end
		return M.games(h)
	end

	local function pair(st, a, b, versus)
		local key = a < b and a * 256 + b or b * 256 + a
		if versus then
			local g = st.vg[key] or 0
			local w = st.vw[key] or 0
			if a > b then
				w = g - w
			end
			return w, g
		end
		return st.sw[key] or 0, st.sg[key] or 0
	end

	local function expect(a, b, versus)
		if versus then
			return sigm(logit(a) - logit(b))
		end
		return sigm(logit(a) + logit(b))
	end

	local function effect(a, b, versus)
		local e_r = expect(base_ranked(a), base_ranked(b), versus)
		local w, g = pair(ranked(), a, b, versus)
		local fx = logit(shrink(w, g, e_r, K.PRIOR_PAIR)) - logit(e_r)
		local c = cm()
		if not c then
			return fx
		end
		local e_c = expect(M.base(a), M.base(b), versus)
		local prior = sigm(logit(e_c) + fx)
		local wc, gc = pair(c, a, b, versus)
		return logit(shrink(wc, gc, prior, K.PRIOR_CM_PAIR)) - logit(e_c)
	end

	function M.adv(a, b)
		return effect(a, b, true)
	end

	function M.syn(a, b)
		return effect(a, b, false)
	end
end

function M.pos(h)
	local prob = D.pos_prob[h]
	if prob then
		return prob
	end
	local hero = D.by_id[h]
	local prior = { 0.2, 0.2, 0.2, 0.2, 0.2 }
	if hero then
		local carry, support = false, false
		for _, role in ipairs(hero.roles) do
			carry = carry or role == "Carry"
			support = support or role == "Support"
		end
		if carry and not support then
			prior = { 0.4, 0.3, 0.2, 0.05, 0.05 }
		elseif support and not carry then
			prior = { 0.02, 0.04, 0.08, 0.43, 0.43 }
		end
	end
	local count = D.pos_count and D.pos_count[h] or { 0, 0, 0, 0, 0 }
	local total = 0
	for i = 1, 5 do
		total = total + count[i]
	end
	prob = {}
	for i = 1, 5 do
		prob[i] = math.log(math.max(K.POS_FLOOR, (count[i] + K.PRIOR_POS * prior[i]) / (total + K.PRIOR_POS)))
	end
	D.pos_prob[h] = prob
	return prob
end

function M.assign(team, blocked)
	local n = #team
	if n == 0 then
		return 0, {}
	end
	local best, best_map = -math.huge, {}
	local map, used, probs = {}, {}, {}
	for i = 1, n do
		probs[i] = M.pos(team[i])
	end
	local function run(i, acc)
		if i > n then
			if acc > best then
				best = acc
				best_map = { (table.unpack or unpack)(map, 1, n) }
			end
			return
		end
		local pp = probs[i]
		for p = 1, 5 do
			if not used[p] and not (blocked and blocked[p]) then
				used[p] = true
				map[i] = p
				run(i + 1, acc + pp[p])
				used[p] = false
			end
		end
	end
	run(1, 0)
	return best, best_map
end

local I = {
	loaded = false,
	lm = {},
	lr = {},
	items = nil,
	by_name = {},
	items_at = 0,
	buys = {},
	buys_at = {},
	buys_raw = {},
	skip = {},
	busy = false,
	next_at = 0,
	error = nil,
	logged = nil,
	dirty = false,
	tags = nil,
	threat_of = {},
	builds = {},
	bpos = {},
	fate_logged = {},
	build_logged = {},
	shown_pos = {},
	labels = {},
	talent_vals = {},
	abil_metas = {},
	hero_tal = {},
	gone = {},
	pub = {},
	pub_queue = {},
	pub_queued = {},
	pub_failed = {},
	pub_at = 0,
}

do
	local function set_items(list)
		local items, by_name = {}, {}
		for _, it in ipairs(list) do
			local id = math.tointeger(tonumber(it.id))
			if id and type(it.n) == "string" then
				local parts = {}
				for part in tostring(it.p or ""):gmatch("[%w_]+") do
					parts[#parts + 1] = part
				end
				local item = {
					id = id,
					name = it.n,
					label = type(it.d) == "string" and it.d ~= "" and it.d or it.n,
					cost = tonumber(it.c) or 0,
					created = tonumber(it.m) == 1,
					consumable = it.q == "consumable",
					secret = K.SECRET[it.n] == true,
					recipe = math.tointeger(tonumber(it.r)),
					parts = parts,
				}
				items[id] = item
				by_name[item.name] = item
			end
		end
		for name, item in pairs(by_name) do
			local base, lvl = name:match("^(.-)_(%d)$")
			lvl = tonumber(lvl)
			if base and lvl and lvl >= 2 and #item.parts == 0 then
				local prev, root = by_name[lvl == 2 and base or (base .. "_" .. (lvl - 1))], by_name[base]
				if prev and root then
					item.parts = { prev.name }
					if not item.recipe and root.recipe then
						item.recipe, item.recipe_name = root.recipe, "recipe_" .. base
					end
				end
			end
		end
		I.items, I.by_name, I.builds = items, by_name, {}
	end

	local function parse_items(text)
		local starts, pos = {}, 1
		while true do
			local s, e, key = text:find('"([%w_]+)":{', pos)
			if not s then
				break
			end
			starts[#starts + 1] = { s = s, e = e, key = key }
			pos = e + 1
		end
		local list, recipes = {}, {}
		for i, st in ipairs(starts) do
			local seg = text:sub(st.e, starts[i + 1] and starts[i + 1].s - 1 or #text)
			local id = tonumber(seg:match('"id":(%d+)'))
			if st.key:find("^recipe_") then
				recipes[st.key:sub(8)] = id
			else
				if id then
					local parts = (seg:match('"components":%[([^%]]*)%]') or ""):gsub('"', "")
					list[#list + 1] = {
						id = id,
						n = st.key,
						d = seg:match('"dname":"([^"]*)"'),
						c = tonumber(seg:match('"cost":(%d+)')) or 0,
						m = seg:find('"created":true', 1, true) and 1 or 0,
						p = parts,
						q = seg:match('"qual":"([^"]*)"') or "",
					}
				end
			end
		end
		for _, it in ipairs(list) do
			it.r = recipes[it.n]
		end
		return list
	end

	function I.rows_pack(rows)
		local out, f = {}, {}
		for _, r in ipairs(rows) do
			for j, col in ipairs(K.BUYS_COLS) do
				local v = r[col]
				f[j] = v ~= nil and tostring(v) or ""
			end
			out[#out + 1] = table.concat(f, ",", 1, #K.BUYS_COLS)
		end
		return table.concat(out, ";")
	end

	function I.rows_unpack(text)
		local rows, cols, n = {}, K.BUYS_COLS, 0
		local find, sub = string.find, string.sub
		local pos, len = 1, #text
		while pos <= len do
			local e = find(text, ";", pos, true) or len + 1
			if e > pos then
				local r, j, p = {}, 0, pos
				while p <= e do
					local c = find(text, ",", p, true)
					if not c or c > e then
						c = e
					end
					j = j + 1
					local col = cols[j]
					if col and c > p then
						local v = sub(text, p, c - 1)
						r[col] = col == "i" and v or tonumber(v)
					end
					p = c + 1
				end
				n = n + 1
				rows[n] = r
			end
			pos = e + 1
		end
		return rows
	end

	local function add_nw(dst, src, k)
		dst.n = (dst.n or 0) + k * (src.n or 0)
		dst.w = (dst.w or 0) + k * (src.w or 0)
	end

	function I.synth(h, p)
		local key, text = h .. "." .. p .. ":", K.SYNTH
		local s0
		if text:sub(1, #key) == key then
			s0 = #key + 1
		else
			local a = text:find("/" .. key, 1, true)
			if not a then
				return nil
			end
			s0 = a + #key + 1
		end
		local e = text:find("/", s0, true) or (#text + 1)
		local rows, any = {}, false
		for id, sh, mn, st in text:sub(s0, e - 1):gmatch("(%d+)%.(%d+)%.(%d+)%.?(%d*)") do
			local item = I.items and I.items[math.tointeger(tonumber(id))]
			if item then
				rows[item.name] = { sh = tonumber(sh) / 100, t = tonumber(mn) * 60, st = (tonumber(st) or 0) / 100 }
				any = true
			end
		end
		return any and rows or nil
	end

	function I.pool(by, h)
		local out = {}
		for p = 1, 5 do
			local d = by[p]
			local own = d and d.g or 0
			if own >= K.POOL_N then
				out[p] = d
			else
				local same, same_g, other, other_g = {}, 0, {}, 0
				for q = 1, 5 do
					if q ~= p and by[q] then
						if (q <= 3) == (p <= 3) then
							same[#same + 1], same_g = q, same_g + by[q].g
						else
							other[#other + 1], other_g = q, other_g + by[q].g
						end
					end
				end
				local synth = h and own + same_g < K.SYNTH_N and I.synth(h, p) or nil
				local donors, total = {}, same_g
				for _, q in ipairs(same) do
					donors[#donors + 1] = q
				end
				if not synth and own + same_g < K.BUYS_MIN then
					for _, q in ipairs(other) do
						donors[#donors + 1] = q
					end
					total = same_g + other_g
				end
				if total <= 0 and not synth then
					out[p] = d
				else
					local k = total > 0 and math.min(1, (K.POOL_N - own) / total) or 0
					local m = { g = 0, gw = 0, rows = {}, fin = {}, late = {}, bm = {}, subs = {}, neut = {}, enh = {}, skill = {},
						since = d and d.since, kmax = d and d.kmax, pooled = { own = own, from = donors, synth = synth ~= nil } }
					local function rows_in(list, kk)
						for name, r in pairs(list) do
							local t = m.rows[name]
							if not t then
								t = { n = 0, w = 0, t = 0, s = 0, m = 0, tn = 0 }
								m.rows[name] = t
							end
							if r.t ~= 0 then
								t.t = (t.t * t.tn + r.t * kk * r.n) / (t.tn + kk * r.n)
								t.tn = t.tn + kk * r.n
							end
							t.n, t.w = t.n + kk * r.n, t.w + kk * r.w
							t.s, t.m = t.s + kk * (r.s or 0), t.m + kk * (r.m or 0)
							for _, fld in ipairs({ "ne", "we", "nb", "wb", "x", "ns" }) do
								if r[fld] then
									t[fld] = (t[fld] or 0) + kk * r[fld]
								end
							end
						end
					end
					local function meta_in(src, kk)
						for tier, list in pairs(src.neut) do
							m.neut[tier] = m.neut[tier] or {}
							for name, v in pairs(list) do
								m.neut[tier][name] = m.neut[tier][name] or {}
								add_nw(m.neut[tier][name], v, kk)
							end
						end
						for name, v in pairs(src.enh) do
							m.enh[name] = m.enh[name] or {}
							add_nw(m.enh[name], v, kk)
						end
						for lv, list in pairs(src.skill) do
							m.skill[lv] = m.skill[lv] or {}
							for id, v in pairs(list) do
								m.skill[lv][id] = m.skill[lv][id] or {}
								add_nw(m.skill[lv][id], v, kk)
							end
						end
					end
					local function take(src, kk)
						m.g = m.g + kk * src.g
						m.gw = m.gw + kk * src.gw
						if src.g40 then
							m.g40, m.gw40 = (m.g40 or 0) + kk * src.g40, (m.gw40 or 0) + kk * (src.gw40 or 0)
						end
						rows_in(src.rows, kk)
						for id, n in pairs(src.fin) do
							m.fin[id] = (m.fin[id] or 0) + kk * n
						end
						for id, n in pairs(src.late) do
							m.late[id] = (m.late[id] or 0) + kk * n
						end
						for mm, v in pairs(src.bm) do
							m.bm[mm] = m.bm[mm] or {}
							add_nw(m.bm[mm], v, kk)
						end
						for a, set in pairs(src.subs) do
							m.subs[a] = m.subs[a] or {}
							for b in pairs(set) do
								m.subs[a][b] = true
							end
						end
						meta_in(src, kk)
						m.since = m.since or src.since
						m.kmax = m.kmax or src.kmax
					end
					if d then
						take(d, 1)
					end
					for _, q in ipairs(donors) do
						take(by[q], k)
					end
					if synth then
						local gs = math.max(0, K.POOL_N - m.g)
						local list = {}
						for name, r in pairs(synth) do
							local nn = r.sh * gs
							nn = math.max(nn, r.st * gs)
							local real = m.rows[name]
							list[name] = { n = nn, w = nn / 2, ns = nn, t = r.t, s = r.st * gs, m = r.st * gs,
								x = (not real or real.x) and nn / 2 or nil }
						end
						rows_in(list, 1)
						m.g_real = m.g
						m.g, m.gw = m.g + gs, m.gw + gs / 2
						if next(m.skill) == nil or next(m.neut) == nil then
							local og = 0
							for _, q in ipairs(other) do
								og = og + by[q].g
							end
							for _, q in ipairs(other) do
								meta_in(by[q], og > 0 and gs / og or 0)
							end
						end
					end
					local function round(t)
						for key, v in pairs(t) do
							if type(v) == "number" and key ~= "x" then
								t[key] = math.floor(v + 0.5)
							elseif type(v) == "table" and key ~= "pooled" and key ~= "subs" then
								round(v)
							end
						end
					end
					for _, r in pairs(m.rows) do
						r.tn = nil
					end
					round(m)
					for name, r in pairs(m.rows) do
						if r.n <= 0 then
							m.rows[name] = nil
						end
					end
					m.pooled.k = k
					out[p] = m
				end
			end
		end
		return out
	end

	function I.pool_note(pl, short)
		local from = {}
		for _, q in ipairs(pl.from) do
			from[#from + 1] = tostring(q)
		end
		if pl.synth then
			return L(short and "cd_p_synth" or "cd_build_synth"):format(math.floor(pl.own + 0.5))
		end
		return L(short and "cd_p_pooled" or "cd_build_pooled"):format(math.floor(pl.own + 0.5), table.concat(from, ", "))
	end

	function I.pos_tip(h, p)
		local d = I.buys[h] and I.buys[h].pos[p]
		if not d then
			return ""
		end
		if d.pooled and d.pooled.synth then
			return L("cd_tip_bpos_synth"):format(math.floor(d.pooled.own + 0.5))
		end
		if d.pooled then
			local from = {}
			for _, q in ipairs(d.pooled.from) do
				from[#from + 1] = tostring(q)
			end
			return L("cd_tip_bpos_pool"):format(math.floor(d.pooled.own + 0.5), table.concat(from, ", "))
		end
		return L("cd_tip_bpos"):format(math.floor(d.g + 0.5))
	end

	local function set_buys(h, list)
		local by = {}
		for _, r in ipairs(list) do
			local p, name, n, g = math.tointeger(tonumber(r.p)), r.i, tonumber(r.n), tonumber(r.g) or 0
			if p and p >= 1 and p <= 5 and type(name) == "string" and n and n > 0 then
				local d = by[p]
				if not d then
					d = { g = g, gw = 0, rows = {}, fin = {}, late = {}, bm = {}, subs = {}, neut = {}, enh = {}, skill = {} }
					by[p] = d
				end
				d.g = math.max(d.g, g)
				d.gw = math.max(d.gw, tonumber(r.gw) or 0)
				local id = math.tointeger(tonumber(name:match("^#(%d+)$")))
				local late = math.tointeger(tonumber(name:match("^%%(%d+)$")))
				local bmin = math.tointeger(tonumber(name:match("^!b(%d+)$")))
				local sa, sb = name:match("^&(%d+)%.(%d+)$")
				local ntier, nname = name:match("^%^(%d+)%.([%w_]+)$")
				local enh = name:match("^~([%w_]+)$")
				local slv, sid = name:match("^%*(%d+)%.(%d+)$")
				local patch = name:match("^@(.+)$")
				local w = tonumber(r.w) or 0
				if ntier then
					ntier = math.tointeger(tonumber(ntier))
					d.neut[ntier] = d.neut[ntier] or {}
					d.neut[ntier][nname] = { n = n, w = w }
				elseif enh then
					d.enh[enh] = { n = n, w = w }
				elseif slv then
					slv, sid = math.tointeger(tonumber(slv)), math.tointeger(tonumber(sid))
					d.skill[slv] = d.skill[slv] or {}
					d.skill[slv][sid] = { n = n, w = w }
				elseif sa then
					sa, sb = math.tointeger(tonumber(sa)), math.tointeger(tonumber(sb))
					if sa and sb then
						d.subs[sa] = d.subs[sa] or {}
						d.subs[sb] = d.subs[sb] or {}
						d.subs[sa][sb], d.subs[sb][sa] = true, true
					end
				elseif patch then
					d.since, d.kmax = patch, n
				elseif id then
					d.fin[id] = n
				elseif late then
					d.late[late] = n
					d.g40, d.gw40 = g, tonumber(r.gw) or 0
				elseif bmin then
					d.bm[bmin] = { n = n, w = tonumber(r.w) or 0 }
				elseif not name:find("^[%%!#@&%^~%*]") then
					d.rows[name] = {
						n = n, w = tonumber(r.w) or 0, t = tonumber(r.t) or 0, s = tonumber(r.s) or 0, m = tonumber(r.m) or 0,
						ne = tonumber(r.ne), we = tonumber(r.we), nb = tonumber(r.nb), wb = tonumber(r.wb), x = tonumber(r.x),
					}
				end
			end
		end
		for p, d in pairs(by) do
			if d.g <= 0 then
				by[p] = nil
			end
		end
		by = I.pool(by, h)
		for _, d in pairs(by) do
			local sw, st, sy, stt, sty = 0, 0, 0, 0, 0
			local xn, xs = 0, 0
			for _, r in pairs(d.rows) do
				if r.t > 0 and r.n >= K.LIFT_FIT_MIN then
					local t, y = r.t / 60, r.w / r.n
					sw, st, sy, stt, sty = sw + r.n, st + r.n * t, sy + r.n * y, stt + r.n * t * t, sty + r.n * t * y
					if r.x then
						xn, xs = xn + r.n, xs + r.w - r.x
					end
				end
			end
			d.xoff = xn > 0 and xs / xn or nil
			local base = d.g > 0 and d.gw / d.g or 0.5
			d.icpt, d.slope = base, 0
			if sw > 0 then
				local mt, my = st / sw, sy / sw
				local var = stt / sw - mt * mt
				if var > 1 then
					d.slope = (sty / sw - mt * my) / var
					d.icpt = my - d.slope * mt
				else
					d.icpt = my
				end
			end
		end
		I.buys[h] = { pos = by }
		I.builds = {}
		I.threat_of = {}
	end

	local function set_abil(list)
		local map, n = {}, 0
		for id, name in list:gmatch("(%d+)[:\"%s]+([%w_]+)") do
			map[math.tointeger(tonumber(id))] = name
			n = n + 1
		end
		return map, n
	end

	local function load()
		I.loaded = true
		local items = store.data.items
		if type(items) == "table" and type(items.list) == "table" then
			set_items(items.list)
			I.items_at = items.ver == K.ITEMS_VER and tonumber(items.time) or 0
		end
		local abil = store.data.abil
		if type(abil) == "table" and abil.blob and type(store.blobs[K.ABIL_BLOB]) == "string" then
			I.abil, I.abil_at = set_abil(store.blobs[K.ABIL_BLOB]), tonumber(abil.time) or 0
		elseif type(abil) == "table" and type(abil.list) == "string" then
			I.abil, I.abil_at = set_abil(abil.list), tonumber(abil.time) or 0
			store.blobs[K.ABIL_BLOB] = abil.list
			store.data.abil = { time = I.abil_at, blob = true }
			I.dirty = true
		end
		if type(store.data.pub) == "table" then
			for key, e in pairs(store.data.pub) do
				if type(e) == "table" and type(e.b) == "string" then
					local list = {}
					for t, g, w in e.b:gmatch("(%d+),(%d+),(%d+)") do
						list[#list + 1] = { t = tonumber(t), g = tonumber(g), w = tonumber(w) }
					end
					I.pub[key] = { at = tonumber(e.t) or 0, b = list }
				end
			end
		end
		local buys = store.data.buys
		local lazy, moved = 0, 0
		if type(buys) == "table" then
			for key, entry in pairs(buys) do
				local h = math.tointeger(tonumber(key))
				local blob = store.blobs[K.BUYS_BLOB .. key]
				if h and type(entry) == "table" and entry.v == K.BUYS_VER and type(blob) == "string" then
					I.buys_raw[h] = blob
					I.buys_at[h] = entry.q == K.BUYS_Q and tonumber(entry.time) or 0
					lazy = lazy + 1
				elseif h and type(entry) == "table" and entry.v == K.BUYS_OLD and type(entry.rows) == "table" then
					local c = I.rows_pack(entry.rows)
					store.blobs[K.BUYS_BLOB .. key] = c
					buys[key] = { time = 0, v = K.BUYS_VER }
					I.buys_raw[h], I.buys_at[h] = c, 0
					moved, lazy = moved + 1, lazy + 1
				else
					buys[key] = nil
				end
			end
		end
		if moved > 0 then
			I.dirty = true
		end
		setmetatable(I.buys, {
			__index = function(t, h)
				local raw = I.buys_raw[h]
				if not raw then
					return nil
				end
				I.buys_raw[h] = nil
				local ok, err = pcall(set_buys, h, I.rows_unpack(raw))
				if not ok then
					log("purchases %s: cache broken: %s", tostring(h), tostring(err))
				end
				return t[h]
			end,
		})
		log("load: purchases for %d heroes kept packed (%d converted, refreshed in background)", lazy, moved)
	end

	local function fetch(url, param, on_done)
		I.busy = true
		I.busy_at, I.busy_param = os.clock(), param
		I.seq = (I.seq or 0) + 1
		local seq = I.seq
		local sent = HTTP.Request("GET", url, { headers = K.HEADERS, timeout = K.TIMEOUT }, function(res)
			if seq ~= I.seq then return end
			I.busy = false
			I.next_at = os.clock() + K.GAP
			local ok, err = pcall(on_done, res)
			if ok then
				I.error = nil
				I.cut = 0
				return
			end
			local msg = tostring(err):gsub("^.-:%d+: ", "")
			if (msg:find("JSON", 1, true) or msg:find("cut off", 1, true)) and (I.cut or 0) < 3 then
				I.cut = (I.cut or 0) + 1
				I.next_at = os.clock() + K.RETRY_SHORT
				log("%s: answer was cut off, retry %d", param, I.cut)
				return
			end
			I.cut = 0
			I.error = msg:sub(1, 200)
			I.next_at = os.clock() + K.ITEM_RETRY
			if I.error ~= I.logged then
				I.logged = I.error
				LOGR.put(param .. " failed: " .. I.error)
			end
		end, param)
		if not sent then
			I.busy = false
			I.error = "request was not sent"
			I.next_at = os.clock() + K.SEND_RETRY
		end
	end

	local function keep_buys(h, rows)
		local buys = type(store.data.buys) == "table" and store.data.buys or {}
		buys[tostring(h)] = { time = I.buys_at[h], v = K.BUYS_VER, q = K.BUYS_Q }
		store.blobs[K.BUYS_BLOB .. tostring(h)] = I.rows_pack(rows)
		local keys = {}
		for key in pairs(buys) do
			keys[#keys + 1] = key
		end
		if #keys > K.BUYS_KEEP then
			table.sort(keys, function(x, y)
				return (tonumber(buys[x].time) or 0) > (tonumber(buys[y].time) or 0)
			end)
			for n = K.BUYS_KEEP + 1, #keys do
				buys[keys[n]] = nil
				store.blobs[K.BUYS_BLOB .. keys[n]] = nil
			end
		end
		store.data.buys = buys
		I.dirty = true
	end

	function I.models_rebuild()
		I.skv, I.tlm, I.lm, I.lr = nil, nil, {}, {}
		for h in pairs(I.buys) do
			local raw = store.blobs[K.BUYS_BLOB .. tostring(h)]
			if raw then
				pcall(set_buys, h, I.rows_unpack(raw))
			end
		end
	end

	local function request_items()
		local src = I.item_src or 1
		local function on_items(res)
			I.item_src = src % #K.ITEMS_URLS + 1
			if tostring(res.code) ~= "200" or type(res.response) ~= "string" then
				error(("items: http %s %s"):format(tostring(res.code), tostring(res.error_message or "")))
			end
			if not res.response:find("}%s*$") then
				error("items: answer cut off")
			end
			local list = parse_items((res.response:gsub('"%s*:%s*', '":')))
			if #list < 100 then
				error("items: bad list")
			end
			I.item_src = src
			set_items(list)
			I.items_at = os.time()
			store.data.items = { time = I.items_at, list = list, ver = K.ITEMS_VER }
			I.dirty = true
			log("items loaded: %d", #list)
		end
		if not I.items and not I.pack_items then
			I.pack_items = true
			local text, t = pack_text("items.json")
			if text and pcall(on_items, { code = 200, response = text }) then
				I.items_at = t
				store.data.items.time = t
				log("items from the local pack")
				return
			end
		end
		fetch(K.ITEMS_URLS[src], "cd_items", on_items)
	end

	local function request_abil()
		local src = I.abil_src or 1
		local function on_abil(res)
			I.abil_src = src % #K.ABIL_URLS + 1
			I.abil_skip = os.clock() + K.ITEM_FAIL_SKIP
			if tostring(res.code) ~= "200" or type(res.response) ~= "string" then
				error(("abilities: http %s %s"):format(tostring(res.code), tostring(res.error_message or "")))
			end
			if not res.response:find("}%s*$") then
				error("abilities: answer cut off")
			end
			local map, n = set_abil(res.response)
			if n < 500 then
				error("abilities: bad list")
			end
			local parts = {}
			for id, name in pairs(map) do
				parts[#parts + 1] = id .. ":" .. name
			end
			I.abil_src = src
			I.abil, I.abil_at = map, os.time()
			I.builds = {}
			store.blobs[K.ABIL_BLOB] = table.concat(parts, ";")
			store.data.abil = { time = I.abil_at, blob = true }
			I.dirty = true
			log("abilities loaded: %d", n)
		end
		if not I.abil and not I.pack_abil then
			I.pack_abil = true
			local text, t = pack_text("ability_ids.json")
			if text and pcall(on_abil, { code = 200, response = text }) then
				I.abil_at = t
				store.data.abil.time = t
				log("abilities from the local pack")
				return
			end
		end
		fetch(K.ABIL_URLS[src], "cd_abil", on_abil)
	end

	local function pub_drop(key, failed)
		for i, job in ipairs(I.pub_queue) do
			if job.key == key then
				table.remove(I.pub_queue, i)
				break
			end
		end
		I.pub_queued[key] = nil
		if failed then
			I.pub_failed[key] = os.time()
		end
	end

	local function request_pub(h, name)
		local key = h .. ":" .. name
		fetch(K.PUB_URL:format(name, h), "cd_pub", function(res)
			if tostring(res.code) ~= "200" or type(res.response) ~= "string" then
				pub_drop(key, true)
				error(("public timings %s: http %s"):format(key, tostring(res.code)))
			end
			if not res.response:find("%]%s*$") then
				error("public timings: answer cut off")
			end
			local ok, rows = pcall(JSON.decode, JSON, res.response)
			if not ok or type(rows) ~= "table" then
				pub_drop(key, true)
				error("public timings: bad json")
			end
			pub_drop(key, false)
			local list, parts = {}, {}
			for _, row in ipairs(rows) do
				local t, g, w = tonumber(row.time), tonumber(row.games), tonumber(row.wins)
				if t and g and w and g > 0 then
					list[#list + 1] = { t = t, g = g, w = w }
				end
			end
			table.sort(list, function(a, b)
				return a.t < b.t
			end)
			for _, e in ipairs(list) do
				parts[#parts + 1] = ("%d,%d,%d"):format(e.t, e.g, e.w)
			end
			I.pub[key] = { at = os.time(), b = list }
			I.pub_at = os.clock()
			I.builds = {}
			local saved = type(store.data.pub) == "table" and store.data.pub or {}
			saved[key] = { t = os.time(), b = table.concat(parts, ";") }
			local keys = {}
			for k in pairs(saved) do
				keys[#keys + 1] = k
			end
			if #keys > K.PUB_KEEP then
				table.sort(keys, function(x, y)
					return (tonumber(saved[x].t) or 0) > (tonumber(saved[y].t) or 0)
				end)
				for n = K.PUB_KEEP + 1, #keys do
					saved[keys[n]] = nil
				end
			end
			store.data.pub = saved
			I.dirty = true
			log("public timings %s: %d buckets", key, #list)
		end)
	end

	local function request_buys(h)
		local part = I.part
		if not part or part.h ~= h then
			part = { h = h, rows = {}, off = 0 }
			I.part = part
		end
		local inner = ("select * from (%s) y order by p, i limit %d offset %d")
			:format(K.BUYS_SQL:format(h, K.BUYS_MATCHES, K.PATCH_MAX, h, K.BUYS_WANT, K.BUYS_CAP), K.BUYS_PAGE, part.off)
		local url = K.EXPLORER .. url_encode(compact_sql(inner, K.BUYS_COLS))
		fetch(url, "cd_buys", function(res)
			if tostring(res.code) ~= "200" or type(res.response) ~= "string" then
				I.skip[h] = os.clock() + K.ITEM_FAIL_SKIP
				error(("purchases %d: http %s %s"):format(h, tostring(res.code), tostring(res.error_message or "")))
			end
			local list, err = compact_rows(res.response)
			if not list then
				if err ~= "answer cut off" then
					I.skip[h] = os.clock() + K.ITEM_FAIL_SKIP
				end
				error(("purchases %d: %s"):format(h, tostring(err)))
			end
			for _, f in ipairs(list) do
				local row = {
					p = tonumber(f[1]),
					i = f[2],
					n = tonumber(f[3]) or 0,
					w = tonumber(f[4]) or 0,
					t = tonumber(f[5]) or 0,
					s = tonumber(f[6]) or 0,
					m = tonumber(f[7]) or 0,
					g = tonumber(f[8]) or 0,
					gw = tonumber(f[9]) or 0,
				}
				if type(f[2]) == "string" and f[2]:find("^%a") then
					row.ne, row.we, row.nb, row.wb = tonumber(f[10]), tonumber(f[11]), tonumber(f[12]), tonumber(f[13])
					row.x = tonumber(f[14])
				end
				part.rows[#part.rows + 1] = row
			end
			if #list >= K.BUYS_PAGE then
				part.off = part.off + K.BUYS_PAGE
				return
			end
			I.part = nil
			local rows = part.rows
			I.buys_at[h] = os.time()
			set_buys(h, rows)
			keep_buys(h, rows)
			log("purchases loaded for %d: %d rows", h, #rows)
		end)
	end

	function I.web_pack(h)
		fetch(D.pack_url(h .. ".txt", I.web_src), "cd_buys", function(res)
			local body, t, q = D.pack_body(res)
			if not body or I.buys[h] then
				I.web_src = (I.web_src or 1) + 1
				log("purchases for %d: GitHub pack http %s, asking OpenDota", h, tostring(res.code))
				return
			end
			local rows = I.rows_unpack(body)
			if #rows == 0 then
				return
			end
			I.buys_at[h] = q == K.BUYS_Q and t or 0
			set_buys(h, rows)
			keep_buys(h, rows)
			log("purchases for %d from the GitHub pack (%s): %d rows", h, os.date("%Y-%m-%d %H:%M", t), #rows)
		end)
	end

	function I.positions(h)
		local out = {}
		local all = I.buys[h]
		for p, d in pairs(all and all.pos or {}) do
			if d.g >= K.BUYS_MIN then
				out[p] = d.g
			end
		end
		return out
	end

	function I.hero(sm)
		for _, row in ipairs(sm.rows) do
			if row.h == draft.build_h then
				return row
			end
		end
		local mine = draft.mode == 1 and draft.me and draft.steps[draft.me]
		for _, row in ipairs(sm.rows) do
			if row.h == mine then
				return row
			end
		end
		return sm.rows[1]
	end

	function I.pack_read(h)
		local dir = Engine.GetCheatDirectory()
		if not dir:match("[\\/]$") then
			dir = dir .. "\\"
		end
		local f = io.open(dir .. "configs\\" .. K.PACK_DIR .. "\\" .. h .. ".txt", "rb")
		if not f then
			return nil
		end
		local text = f:read("a")
		f:close()
		local t, q, body = (text or ""):match("^t=(%d+) q=(%d+)\r?\n(.*)$")
		if not t or body == "" then
			return nil
		end
		return body, tonumber(t), tonumber(q)
	end

	function I.pack_tick(sm)
		if not I.items then
			return
		end
		local list = {}
		list[#list + 1] = I.want
		list[#list + 1] = I.want_preview
		if sm then
			for _, row in ipairs(sm.rows) do
				list[#list + 1] = row.h
			end
			for _, e in ipairs(sm.them or {}) do
				list[#list + 1] = e
			end
		end
		for _, h in ipairs(I.want_more or {}) do
			list[#list + 1] = h
		end
		I.pack_tried = I.pack_tried or {}
		for _, h in ipairs(list) do
			if h and I.buys_raw[h] then
				local _ = I.buys[h]
				return
			end
			if h and not I.buys[h] then
				if I.pack_tried[h] and not (I.pack_web or {})[h] and I.web_pack and not I.busy and os.clock() >= I.next_at then
					I.pack_web = I.pack_web or {}
					I.pack_web[h] = true
					I.web_pack(h)
					return
				end
				if not I.pack_tried[h] then
					I.pack_tried[h] = true
					local okr, body, t, q = pcall(I.pack_read, h)
					if okr and body then
						local ok, err = pcall(set_buys, h, I.rows_unpack(body))
						if ok then
							I.buys_at[h] = q == K.BUYS_Q and t or 0
							log("purchases for %d from the local pack (%s)", h, os.date("%Y-%m-%d %H:%M", t))
						else
							log("purchases for %d: local pack broken: %s", h, tostring(err))
						end
						return
					end
				end
			end
		end
	end

	function I.tick()
		if not D.loaded then
			return
		end
		if not I.loaded then
			load()
		end
		local sm = draft.summary
		I.pack_tick(sm)
		if I.busy and os.clock() - (I.busy_at or 0) > K.ANSWER_WAIT then
			I.busy = false
			I.seq = (I.seq or 0) + 1
			I.error = "no answer"
			I.next_at = os.clock() + K.RETRY_SHORT
			if I.logged ~= I.error then
				I.logged = I.error
				LOGR.put(tostring(I.busy_param or "items") .. ": no answer from OpenDota, retrying")
			end
		end
		if I.busy or os.clock() < I.next_at then
			return
		end
		if sm or I.want or I.want_preview then
			local now = os.time()
			if not I.items or (now - I.items_at > K.ITEMS_TTL and os.clock() >= (I.items_try or 0)) then
				I.items_try = os.clock() + K.STALE_TRY
				request_items()
				return
			end
			if cfg.live == 1 and (not I.abil or now - (I.abil_at or 0) > K.ITEMS_TTL) and os.clock() >= (I.abil_skip or 0) then
				request_abil()
				return
			end
			local want = {}
			want[#want + 1] = I.want
			want[#want + 1] = I.want_preview
			if sm then
				local first = I.hero(sm)
				want[#want + 1] = first and first.h
				for _, row in ipairs(sm.rows) do
					want[#want + 1] = row.h
				end
				if cfg.live == 1 then
					for _, e in ipairs(sm.them or {}) do
						want[#want + 1] = e
					end
				end
			end
			if cfg.live == 1 then
				for _, h in ipairs(I.want_more or {}) do
					want[#want + 1] = h
				end
			end
			for _, h in ipairs(want) do
				local stale = not I.buys[h] or now - (I.buys_at[h] or 0) > K.BUYS_TTL
				if stale and os.clock() >= (I.skip[h] or 0) then
					request_buys(h)
					return
				end
			end
			local job = cfg.live == 1 and I.pub_queue[1]
			if job then
				request_pub(job.h, job.name)
				return
			end
		end
		if I.dirty then
			I.dirty = false
			store_save()
		end
	end

	local function parse_tags()
		local tags = {}
		for entry in K.HERO_TAGS:gmatch("[^;]+") do
			local words = {}
			for word in entry:gmatch("%S+") do
				words[#words + 1] = word
			end
			local t = {}
			for k = 2, #words - 1, 2 do
				t[words[k]] = tonumber(words[k + 1])
			end
			tags["npc_dota_hero_" .. words[1]] = t
		end
		return tags
	end

	function I.erole(e)
		local r = I.eroles and I.eroles[e]
		if r then
			return r
		end
		local p = (draft.enemy_pos or {})[e]
		return p and (p <= 3 and "core" or "sup") or nil
	end

	function I.threats(h, role)
		role = role or I.erole(h)
		local ckey = h .. ":" .. (role or "-")
		local cached = I.threat_of[ckey]
		if cached then
			return cached
		end
		I.tags = I.tags or parse_tags()
		local hero = D.by_id[h]
		local t = {}
		if hero then
			for k, v in pairs(I.tags[hero.unit] or {}) do
				t[k] = v
			end
			local roles = {}
			for _, role in ipairs(hero.roles) do
				roles[role] = true
			end
			local kit = I.kit(h)
			if kit then
				local m = kit.magic >= 2 and kit.magic / K.KIT_MAGIC_DIV or (kit.magic == 1 and K.KIT_MAGIC_ONE or 0)
				if m > 0 then
					t.magic = (t.magic or 0) + m
				end
			elseif roles.Nuker then
				t.magic = (t.magic or 0) + K.ROLE_MAGIC
			end
			if kit and kit.disable > 0 then
				t.disable = (t.disable or 0) + kit.disable * K.KIT_DISABLE
			elseif roles.Disabler and (t.pierce or 0) < K.KIT_PIERCE then
				t.disable = (t.disable or 0) + K.ROLE_DISABLE
			end
			if roles.Carry and not roles.Support and (hero.attr == "agi" or hero.attr == "str") then
				t.phys = (t.phys or 0) + (hero.attr == "agi" and K.ROLE_PHYS_AGI or K.ROLE_PHYS_STR)
			end
			for _, p in ipairs(I.predicted(h, role)) do
				for k, v in pairs(K.ENEMY_ITEMS[p.name] or {}) do
					t[k] = (t[k] or 0) + v * p.share
				end
			end
			for k, v in pairs(t) do
				t[k] = math.min(1, v)
			end
		end
		I.threat_of[ckey] = t
		return t
	end

	local function inside(item, name, depth)
		for _, part in ipairs(item.parts) do
			if part == name then
				return true
			end
			local p = depth < 4 and I.by_name[part]
			if p and inside(p, name, depth + 1) then
				return true
			end
		end
		return false
	end

	local function related(a, b)
		return inside(a, b.name, 0) or inside(b, a.name, 0)
	end

	function I.same_line(a, b)
		return (a:gsub("_%d$", "")) == (b:gsub("_%d$", ""))
	end

	local function siblings(a, b)
		for _, x in ipairs(a.parts) do
			local part = I.by_name[x]
			if part and part.created and part.cost >= K.SIBLING_COST then
				for _, y in ipairs(b.parts) do
					if x == y then
						return true
					end
				end
			end
		end
		return false
	end

	function I.cnt_k(name, T, cover, pos)
		local row = K.CNT[(pos or 1) <= 3 and "core" or "sup"][name]
		if not row then
			return 1, nil
		end
		local k, why, vs = 1, {}, {}
		for threat, eff in pairs(row) do
			local x = math.min(1, (T[threat] or 0) * (cover and cover[threat] or 1))
			if x > 0 then
				k = k * eff ^ x
				if eff > 1 then
					why[#why + 1] = { threat = threat, x = math.log(eff) * x }
					vs[threat] = math.log(eff)
				end
			end
		end
		table.sort(why, function(a, b)
			return a.x > b.x
		end)
		return clamp(k, K.CNT_LO, K.CNT_HI), why, vs
	end

	local function vs_heroes(vs, them, per)
		local list = {}
		for _, e in ipairs(them) do
			local x = 0
			for threat, w in pairs(vs) do
				x = x + w * (per[e][threat] or 0)
			end
			if x >= K.VS_MIN then
				list[#list + 1] = { h = e, x = x }
			end
		end
		table.sort(list, function(a, b)
			return a.x > b.x
		end)
		local out = {}
		for n = 1, math.min(K.VS_MAX, #list) do
			out[n] = list[n].h
		end
		return out
	end

	local function fits_hero(name, h, pos)
		local fit, hero = K.FIT[name], D.by_id[h]
		if not fit or not hero or (fit.melee and not hero.melee) or I.banned(name, h) then
			return false
		end
		local rule = (not pos or pos <= 3) and fit.core or fit.support
		return rule == true or (type(rule) == "table" and rule[hero.attr] == true)
	end

	local function est_time(item, cands)
		local sum, n, last = 0, 0, 0
		for _, cd in pairs(cands) do
			last = math.max(last, cd.t)
			if math.abs(cd.item.cost - item.cost) <= 1000 then
				sum, n = sum + cd.t, n + 1
			end
		end
		return n > 0 and sum / n or last + 120
	end

	local function counter_cd(name, cands)
		local item = I.by_name[name]
		return cands[name] or { item = item, count = 0, share = 0, t = est_time(item, cands) }
	end

	function I.sole_answer(slots, s, T)
		for threat, w in pairs(K.COUNTERS[s.item.name] or {}) do
			if w >= K.MUST_COVER and (T and T[threat] or 0) >= K.SOLE_T then
				local other = false
				for _, o in ipairs(slots) do
					if o ~= s and ((K.COUNTERS[o.item.name] or {})[threat] or 0) >= K.MUST_COVER then
						other = true
					end
				end
				if not other then
					return threat
				end
			end
		end
		return nil
	end

	local function place(slots, cd, locked, T)
		local item = cd.item
		local idx, low
		for i, sl in ipairs(slots) do
			local guard = T and I.sole_answer(slots, sl, T)
			if not locked(sl) and not sl.must and not K.BOOTS[sl.item.name]
				and not (guard and ((K.COUNTERS[item.name] or {})[guard] or 0) < K.MUST_COVER) then
				local ok = true
				for j, o in ipairs(slots) do
					if j ~= i and (o.item == item or related(o.item, item) or (not K.BOOTS[o.item.name] and siblings(o.item, item))) then
						ok = false
					end
				end
				local v = (sl.score or sl.share or 0) + (sl.core and 10 or 0)
				if ok and (not idx or v < low) then
					idx, low = i, v
				end
			end
		end
		if not idx then
			return nil
		end
		local new = {}
		for k, v in pairs(cd) do
			new[k] = v
		end
		new.replaced, new.drop, new.core = slots[idx].item, nil, nil
		slots[idx] = new
		return new
	end

	function I.must(slots, cands, T, per, them, h, pos, locked)
		local added = {}
		for _, rule in ipairs(K.MUST) do
			local threat = rule[1]
			local strongest = 0
			for _, e in ipairs(them) do
				strongest = math.max(strongest, (per[e] or {})[threat] or 0)
			end
			local role_ok = not rule[4] or I.physical(h, pos)
			if strongest >= rule[2] and rule[3][pos or 0] and role_ok and #added < K.MUST_MAX then
				local covered = 0
				for _, s in ipairs(slots) do
					covered = math.max(covered, (K.COUNTERS[s.item.name] or {})[threat] or 0)
				end
				local best, best_v
				if covered < K.MUST_COVER then
					for name, vs in pairs(K.COUNTERS) do
						local w = vs[threat]
						if w and w >= K.MUST_COVER and I.by_name[name] and fits_hero(name, h, pos) then
							local v = w + (cands[name] and cands[name].share or 0)
							if not best or v > best_v or (v == best_v and name < best) then
								best, best_v = name, v
							end
						end
					end
				end
				local new = best and place(slots, counter_cd(best, cands), locked, T)
				if new then
					new.why = { { threat = threat, x = K.COUNTERS[best][threat] } }
					new.vs = vs_heroes({ [threat] = 1 }, them, per)
					new.must = threat
					added[#added + 1] = new
				end
			end
		end
		return added
	end

	function I.physical(h, pos)
		local all = I.buys[h]
		local data = all and pos and all.pos[pos]
		if not data or data.g <= 0 then
			return false
		end
		local sum = 0
		for name in pairs(K.PHYS_ITEMS) do
			local r = data.rows[name]
			if r then
				sum = sum + r.n / data.g
			end
		end
		return sum >= K.PHYS_MIN
	end

	function I.rate(h, pos, name)
		local all = I.buys[h]
		if not all then
			return 0
		end
		local d = pos and all.pos[pos]
		if d and d.g >= K.RATE_MIN_GAMES then
			local r = d.rows[name]
			return r and r.n / d.g or 0
		end
		local n, g = 0, 0
		for _, dd in pairs(all.pos) do
			g = g + dd.g
			local r = dd.rows[name]
			if r then
				n = n + r.n
			end
		end
		return g > 0 and n / g or 0
	end

	function I.react(slots, cands, them, seen, h, pos, locked, locked_hard, T)
		local added = {}
		I.guard_note = nil
		local phys = I.physical(h, pos)
		local function guards(sl, pick)
			for threat, w in pairs(K.COUNTERS[sl.item.name] or {}) do
				if w >= K.MUST_COVER and (T and T[threat] or 0) >= K.PROTECT_T
					and ((K.COUNTERS[pick] or {})[threat] or 0) < K.MUST_COVER then
					local other = false
					for _, o in ipairs(slots) do
						if o ~= sl and ((K.COUNTERS[o.item.name] or {})[threat] or 0) >= K.MUST_COVER then
							other = true
						end
					end
					if not other then
						return threat
					end
				end
			end
			return nil
		end
		for _, rule in ipairs(K.REACT) do
			local sources, by = {}, {}
			for _, e in ipairs(them) do
				for _, name in ipairs(rule.items) do
					if not by[e] and seen[e] and seen[e][name] then
						by[e] = true
						sources[#sources + 1] = { e = e, item = name }
					end
				end
			end
			local covered = false
			for _, sl in ipairs(slots) do
				if ((K.COUNTERS[sl.item.name] or {})[rule.threat] or 0) >= K.MUST_COVER then
					covered = true
				end
			end
			local hard = rule.hard
			if I.leader and by[I.leader] and K.LEADER_HARD[rule.threat] then
				hard = 1
			end
			local pick
			if not rule.extra and #sources >= (rule.min or 1) and not covered and (not rule.phys or phys) and #added < K.REACT_MAX then
				for _, name in ipairs(rule.counters) do
					if not pick and I.by_name[name] and fits_hero(name, h, pos) and I.buys_it(name, h, pos)
						and (not rule.rate or I.rate(h, pos, name) >= K.REACT_RATE) then
						pick = name
					end
				end
			end
			local guarded = locked
			if pick and (not hard or (rule.soft and #sources < hard)) then
				guarded = function(sl)
					if locked(sl) then
						return true
					end
					if (sl.share or 0) >= K.REACT_KEEP_SHARE then
						I.guard_note = ("%s keeps %s (share %.2f)"):format(pick, sl.item.name, sl.share)
						return true
					end
					local threat = guards(sl, pick)
					if threat then
						I.guard_note = ("%s keeps %s (%s)"):format(pick, sl.item.name, threat)
						return true
					end
					return false
				end
			end
			local new = pick and place(slots, counter_cd(pick, cands), guarded, T)
			if pick and not new and hard and #sources >= hard and locked_hard then
				new = place(slots, counter_cd(pick, cands), locked_hard, T) or place(slots, counter_cd(pick, cands), locked_hard)
			end
			if new then
				new.leader = hard ~= rule.hard or nil
				new.why = { { threat = rule.threat, x = K.COUNTERS[pick] and K.COUNTERS[pick][rule.threat] or 1 } }
				new.vs = {}
				for _, s in ipairs(sources) do
					new.vs[#new.vs + 1] = s.e
				end
				new.must, new.reason, new.sources = rule.threat, sources[1], sources
				added[#added + 1] = new
			end
		end
		return added
	end

	I.fits = fits_hero

	function I.buys_it(name, h, pos)
		return not I.banned(name, h) and (not I.buys[h] or I.rate(h, pos, name) >= K.REACT_RATE)
	end

	function I.ban_path()
		local dir = Engine.GetCheatDirectory()
		if not dir:match("[\\/]$") then
			dir = dir .. "\\"
		end
		return dir .. "configs\\" .. K.BAN_FILE
	end

	function I.ban_load()
		I.bans, I.ban_v = { [0] = {} }, (I.ban_v or 0) + 1
		local ok, f = pcall(io.open, I.ban_path(), "rb")
		if not ok or not f then
			return
		end
		local text = f:read("a") or ""
		f:close()
		for hs, name in text:gmatch("(%d+)%s+([%w_]+)") do
			local h = math.tointeger(tonumber(hs))
			if h then
				I.bans[h] = I.bans[h] or {}
				I.bans[h][name] = true
			end
		end
	end

	function I.ban_save()
		local lines = {}
		for h, set in pairs(I.bans or {}) do
			for name in pairs(set) do
				lines[#lines + 1] = ("%d %s"):format(h, name)
			end
		end
		table.sort(lines)
		local ok, f = pcall(io.open, I.ban_path(), "wb")
		if ok and f then
			f:write(table.concat(lines, "\n"))
			f:close()
		end
	end

	function I.banned(name, h)
		if not I.bans then
			I.ban_load()
		end
		return I.bans[0][name] == true or (h ~= nil and I.bans[h] ~= nil and I.bans[h][name] == true)
	end

	function I.ban_list()
		if not I.bans then
			I.ban_load()
		end
		local out = {}
		for h, set in pairs(I.bans) do
			for name in pairs(set) do
				out[#out + 1] = { h = h, name = name }
			end
		end
		table.sort(out, function(a, b)
			if a.h ~= b.h then
				return a.h < b.h
			end
			return a.name < b.name
		end)
		return out
	end

	function I.ban_toggle(name, h)
		if not I.bans then
			I.ban_load()
		end
		h = h or 0
		I.bans[h] = I.bans[h] or {}
		local on = not I.bans[h][name]
		I.bans[h][name] = on or nil
		if on and h == 0 then
			for _, set in pairs(I.bans) do
				if set ~= I.bans[0] then
					set[name] = nil
				end
			end
		end
		I.ban_v = (I.ban_v or 0) + 1
		I.builds = {}
		draft.vs_cache = {}
		I.ban_save()
		log("item %s %s for %s", name, on and "hidden" or "back", h == 0 and "all heroes" or tostring(h))
		return on
	end

	I.none, I.pred_memo = {}, {}

	function I.predicted(h, role)
		local all = I.buys[h]
		if cfg.live ~= 1 or not all then
			return I.none
		end
		role = role or I.erole(h)
		local memo = I.pred_memo[h]
		if not memo or memo.all ~= all then
			memo = { all = all }
			I.pred_memo[h] = memo
		end
		local rk = role or "any"
		if memo[rk] then
			return memo[rk]
		end
		local function pool(lo, hi)
			local g, n = 0, {}
			for p = lo, hi do
				local d = all.pos[p]
				if d then
					g = g + d.g
					for name in pairs(K.ENEMY_ITEMS) do
						local r = d.rows[name]
						if r then
							n[name] = (n[name] or 0) + r.n
						end
					end
				end
			end
			return g, n
		end
		local out = {}
		memo[rk] = out
		local ga, na = pool(1, 5)
		if ga < K.BUYS_MIN then
			return out
		end
		local gr, nr = 0, {}
		if role then
			gr, nr = pool(role == "core" and 1 or 4, role == "core" and 3 or 5)
		end
		for name in pairs(K.ENEMY_ITEMS) do
			local sh = (na[name] or 0) / ga
			if gr >= K.BUYS_MIN then
				sh = K.ROLE_MIX * (nr[name] or 0) / gr + (1 - K.ROLE_MIX) * sh
			end
			if sh >= K.PREDICT_SHARE then
				out[#out + 1] = { name = name, share = sh }
			end
		end
		table.sort(out, function(a, b)
			if a.share ~= b.share then
				return a.share > b.share
			end
			return a.name < b.name
		end)
		return out
	end

	local function item_body(cd)
		local lines = {}
		if cd.pre then
			lines[1] = L("cd_tip_up_from"):format(cd.pre.item.label)
		end
		if cd.why then
			local names = {}
			for _, e in ipairs(cd.vs) do
				names[#names + 1] = D.by_id[e] and D.by_id[e].name or "?"
			end
			if #names > 0 then
				lines[#lines + 1] = L("cd_tip_item_vs"):format(table.concat(names, ", "))
			end
			local threats = {}
			for n = 1, math.min(2, #cd.why) do
				threats[n] = L("cd_th_" .. cd.why[n].threat)
			end
			lines[#lines + 1] = table.concat(threats, ", ")
		end
		if cd.solo_v then
			lines[#lines + 1] = L(cd.solo_v > 0 and "cd_tip_solo_up" or "cd_tip_solo_down"):format(math.abs(cd.solo_v) * 100)
		end
		if cd.dk and math.abs(math.log(cd.dk)) >= K.DPS_TIP then
			lines[#lines + 1] = L(cd.dk > 1 and "cd_tip_dps_more" or "cd_tip_dps_less"):format(cd.dk > 1 and cd.dk or 1 / cd.dk)
		end
		if cd.rtop then
			local it = I.by_name[cd.rtop.x]
			local label = it and it.label or cd.rtop.x
			local more = cd.rtop.k > 1
			local key = cd.rtop.ally and (more and "cd_tip_lr_ally_more" or "cd_tip_lr_ally_less") or (more and "cd_tip_lr_more" or "cd_tip_lr_less")
			lines[#lines + 1] = L(key):format(label, more and cd.rtop.k or 1 / cd.rtop.k)
		end
		if cd.vsh and cd.vsh.lm then
			local hero = D.by_id[cd.vsh.e]
			local who = hero and hero.name or "?"
			if cd.vsh.ally then
				who = L("cd_tip_lm_ally"):format(who)
			end
			local more = cd.vsh.k > 1
			lines[#lines + 1] = L(more and "cd_tip_lm_more" or "cd_tip_lm_less"):format(more and cd.vsh.k or 1 / cd.vsh.k, who)
		elseif cd.vsh then
			local hero = D.by_id[cd.vsh.e]
			local more = cd.vsh.v > 1
			local key = cd.vsh.ally and (more and "cd_tip_vsa_more" or "cd_tip_vsa_less")
				or (more and "cd_tip_vsh_more" or "cd_tip_vsh_less")
			lines[#lines + 1] = L(key):format(hero and hero.name or "?", more and cd.vsh.v or 1 / cd.vsh.v)
		end
		if cd.after then
			lines[#lines + 1] = L(cd.after_kind == "up" and "cd_tip_upgrade" or "cd_tip_after"):format(cd.after.item.label)
		end
		if cd.fate and (cd.count or 0) >= K.SHOW_MIN and cd.fate.sold >= K.SOLD_TIP_MIN then
			lines[#lines + 1] = L("cd_tip_sold"):format(math.floor(cd.fate.sold * 100 + 0.5))
		end
		for _, alt in ipairs(cd.alts or {}) do
			local why
			if alt.vs and #alt.vs > 0 then
				local names = {}
				for _, e in ipairs(alt.vs) do
					names[#names + 1] = D.by_id[e] and D.by_id[e].name or "?"
				end
				why = L("cd_alt_vs"):format(table.concat(names, ", "))
			else
				why = L("cd_alt_share"):format(math.floor(alt.count / math.max(1, alt.g) * 100 + 0.5))
			end
			lines[#lines + 1] = L("cd_tip_alt"):format(alt.item.label, why)
		end
		if cfg.live == 1 and cd.timing then
			lines[#lines + 1] = L("cd_tip_timing"):format(I.mins(cd.timing.t),
				math.floor(cd.timing.on_wr * 100 + 0.5), math.floor(cd.timing.off_wr * 100 + 0.5))
		end
		if cfg.live == 1 and cd.h then
			local pt = I.pub_timing(cd.h, cd.item.name, cd.t)
			if pt then
				lines[#lines + 1] = L("cd_tip_pub"):format(I.mins(pt.split), math.floor(pt.on * 100 + 0.5),
					math.floor(pt.off * 100 + 0.5))
			end
		end
		if cfg.live == 1 and cd.behind then
			lines[#lines + 1] = L("cd_tip_behind"):format(math.floor(cd.behind.wr * 100 + 0.5),
				math.floor(cd.behind.base * 100 + 0.5))
		end
		if cd.wr and cd.g and cd.g > 0 and cd.count > 0 then
			local line = L("cd_tip_stats"):format(cd.count, cd.g, math.floor(cd.wr * 100 + 0.5))
			local lift = math.floor((cd.lift or 0) * 100 + 0.5)
			if lift ~= 0 then
				line = line .. L("cd_tip_lift"):format(lift)
			end
			lines[#lines + 1] = line
		end
		return table.concat(lines, "\n")
	end

	I.body, I.related, I.siblings = item_body, related, siblings

	function I.share(data, r)
		if data.gw >= K.WIN_MIN then
			return r.w / data.gw
		end
		return r.n / data.g
	end

	function I.lift(data, r)
		if data.gw < K.WIN_MIN or not data.icpt or r.n <= 0 then
			return 0
		end
		if r.x and data.xoff then
			return (r.w - r.x - r.n * data.xoff) / (r.n + K.LIFT_PRIOR)
		end
		local expect = r.t > 0 and data.icpt + data.slope * r.t / 60 or data.gw / data.g
		return (r.w / r.n - expect) * r.n / (r.n + K.LIFT_PRIOR)
	end

	function I.rank(data, r)
		local pop = r.n / data.g
		if data.gw < K.WIN_MIN then
			return pop
		end
		return pop * clamp(1 + K.LIFT_K * I.lift(data, r), K.LIFT_LO, K.LIFT_HI)
	end

	function I.contains(item, name, depth)
		depth = depth or 0
		if depth > 4 then
			return false
		end
		for _, part in ipairs(item.parts) do
			local p = I.by_name[part]
			if part == name or (p and I.contains(p, name, depth + 1)) then
				return true
			end
		end
		return false
	end

	function I.fates(data)
		if not I.items then
			return nil
		end
		if data.fate and data.fate_at == I.items_at then
			return data.fate
		end
		local out = {}
		for name, r in pairs(data.rows) do
			local item = I.by_name[name]
			local nr = r.n - (r.ns or 0)
			if item and nr > 0 and not item.consumable and not K.FATE_SKIP[name] then
				local fin = data.fin[item.id] or 0
				local up = 0
				if name == "ultimate_scepter" then
					local y = data.rows.ultimate_scepter_2
					up = y and y.n - (y.ns or 0) or 0
				else
					for yname, y in pairs(data.rows) do
						local yi = I.by_name[yname]
						if yi and yi ~= item and y.t > r.t and I.contains(yi, name) then
							up = up + y.n - (y.ns or 0)
						end
					end
				end
				local f = { kept = math.min(1, fin / nr), up = math.min(1, math.max(0, up) / nr) }
				f.sold = math.max(0, 1 - f.kept - f.up)
				if (data.g40 or 0) >= K.LATE_GAMES_MIN and fin > 0 then
					f.late_drop = clamp(1 - ((data.late[item.id] or 0) / data.g40) / (fin / (data.g_real or data.g)), 0, 1)
				end
				out[name] = f
			end
		end
		data.fate, data.fate_at = out, I.items_at
		return out
	end

	function I.log_fates(h, pos, data)
		local key = ("%d:%d:%d"):format(h, pos, I.buys_at[h] or 0)
		if cfg.debug ~= 1 or I.fate_logged[key] then
			return
		end
		I.fate_logged[key] = true
		local fates = I.fates(data)
		if not fates then
			return
		end
		local list = {}
		for name, f in pairs(fates) do
			local r = data.rows[name]
			if r.n / data.g >= K.FATE_LOG_SHARE then
				list[#list + 1] = { name = name, r = r, f = f }
			end
		end
		table.sort(list, function(a, b)
			return a.r.n > b.r.n
		end)
		log("fates %d pos %d: games %d, 40+ min %s, since %s", h, pos, data.g, tostring(data.g40), tostring(data.since))
		for _, e in ipairs(list) do
			log("fate %s n=%d t=%d kept=%.2f up=%.2f sold=%.2f late_drop=%s ne=%s we=%s nb=%s wb=%s", e.name, e.r.n, e.r.t,
				e.f.kept, e.f.up, e.f.sold, e.f.late_drop and ("%.2f"):format(e.f.late_drop) or "-", tostring(e.r.ne),
				tostring(e.r.we), tostring(e.r.nb), tostring(e.r.wb))
		end
		local mins = {}
		for m in pairs(data.bm) do
			mins[#mins + 1] = m
		end
		table.sort(mins)
		local parts = {}
		for _, m in ipairs(mins) do
			parts[#parts + 1] = ("%d:%d/%d"):format(m, data.bm[m].w, data.bm[m].n)
		end
		log("behind base %d pos %d: %s", h, pos, table.concat(parts, " "))
	end

	function I.expect(data, t)
		if t and t > 0 and data.icpt then
			return data.icpt + data.slope * t / 60
		end
		return data.g > 0 and data.gw / data.g or 0.5
	end

	function I.rank_with(data, r, lift)
		local pop = r.n / data.g
		if data.gw < K.WIN_MIN then
			return pop
		end
		return pop * clamp(1 + K.LIFT_K * lift, K.LIFT_LO, K.LIFT_HI)
	end

	function I.timing(data, r)
		local n, w = r.n - (r.ns or 0), r.w - (r.ns or 0) / 2
		if not r.ne or not r.we or r.t <= 0 or r.ne < K.TIMING_MIN or n - r.ne < K.TIMING_MIN then
			return nil
		end
		local e, prior = I.expect(data, r.t), K.LIFT_PRIOR
		local on = (r.we + prior * e) / (r.ne + prior)
		local off = (w - r.we + prior * e) / (n - r.ne + prior)
		return {
			t = r.t,
			gap = on - off,
			off_lift = off - e,
			on_wr = r.we / r.ne,
			off_wr = (w - r.we) / (n - r.ne),
		}
	end

	function I.base_b(data, t)
		local mins = {}
		for m, b in pairs(data.bm or {}) do
			if b.n >= K.SHOW_MIN then
				mins[#mins + 1] = m
			end
		end
		if #mins == 0 then
			return nil
		end
		table.sort(mins)
		local function wr(m)
			return data.bm[m].w / data.bm[m].n
		end
		local x = t / 60
		if x <= mins[1] then
			return wr(mins[1])
		end
		for i = 2, #mins do
			if x <= mins[i] then
				local a, b = mins[i - 1], mins[i]
				return wr(a) + (wr(b) - wr(a)) * (x - a) / (b - a)
			end
		end
		return wr(mins[#mins])
	end

	function I.behind(data, r)
		if not r.nb or not r.wb or r.t <= 0 or r.nb < K.SHOW_MIN then
			return nil
		end
		local base = I.base_b(data, r.t)
		if not base then
			return nil
		end
		local lift = (r.wb + K.LIFT_PRIOR * base) / (r.nb + K.LIFT_PRIOR) - base
		return { lift = clamp(lift, -K.LIFT_B_CAP, K.LIFT_B_CAP), wr = r.wb / r.nb, base = base }
	end

	function I.item_label(name)
		local key = "i:" .. name
		if I.labels[key] then
			return I.labels[key]
		end
		local item = I.by_name[name]
		if item then
			I.labels[key] = item.label
			return item.label
		end
		local ok, s = pcall(GameLocalizer.FindItem, "item_" .. name)
		if ok and type(s) == "string" and s ~= "" then
			I.labels[key] = s
			return s
		end
		return name
	end

	local function data_file(name)
		local dir = Engine.GetCheatDirectory()
		if not dir:match("[\\/]$") then
			dir = dir .. "\\"
		end
		local f = io.open(dir .. "assets\\data\\" .. name, "rb")
		local s = f and f:read("a") or false
		if f then
			f:close()
		end
		return s
	end

	function I.abil_json()
		if I.abil_text == nil then
			I.abil_text = data_file("npc_abilities.json")
		end
		return I.abil_text or nil
	end

	local function kv_block(src, name)
		local a = src and src:find('\n    "' .. name .. '": {', 1, true)
		return a and src:sub(a, src:find("\n    }", a + 1, true) or #src) or nil
	end

	-- talent bonus for one tooltip field: "{s:bonus_movespeed_slow}" reads movespeed_slow's entry for this talent
	function I.talent_value(name, key)
		local ck = name .. "|" .. (key or "")
		local v = I.talent_vals[ck]
		if v ~= nil then
			return v or nil
		end
		local src = I.abil_json()
		v = false
		local field = key and key:gsub("^bonus_", "")
		if src and field and field ~= "value" then
			local from = 1
			while not v do
				local a, b = src:find('"' .. field .. '": {', from, true)
				if not a then
					break
				end
				v = src:sub(b + 1, src:find("}", b + 1, true) or #src):match('"' .. name .. '": "([^"]+)"') or false
				from = b + 1
			end
		end
		if src and not v then
			local blk = kv_block(src, name)
			v = blk and blk:match('"value": "([^"]+)"') or src:match('"' .. name .. '"%s*:%s*"([^"]+)"') or false
		end
		if v then
			v = v:gsub("^[=+]", "")
		end
		I.talent_vals[ck] = v
		return v or nil
	end

	function I.ability_label(name)
		local key = "a:" .. name
		if I.labels[key] then
			return I.labels[key]
		end
		local ok, s = pcall(GameLocalizer.FindAbility, name)
		s = ok and type(s) == "string" and s or ""
		if s == "" or name == K.ATTR_BONUS then
			return name == K.ATTR_BONUS and L("cd_attr") or name
		end
		local talent = name:find("^special_bonus") ~= nil
		s = s:gsub("{%a:([%w_]+)}(%%?)", function(k, pct)
			local v = talent and I.talent_value(name, k) or ""
			if pct ~= "" then
				v = v:gsub("%%$", "")
			end
			return v .. pct
		end):gsub("{[^}]*}", "")
		s = s:gsub("%+%-", "-"):gsub("%-%-", "-"):gsub("\226\128\147%-", "\226\128\147"):gsub("%%[%w_]*%%", "")
		s = s:gsub("%s+", " "):match("^%s*(.-)%s*$")
		if s == "" then
			return name
		end
		I.labels[key] = s
		return s
	end

	function I.neutrals(data)
		if I.neut_pool == nil then
			I.neut_pool = false
			local text = data_file("neutral_items.json")
			if text then
				local pool = {}
				for blk in text:gmatch('"items"%s*:%s*(%b{})') do
					for name in blk:gmatch('"item_([%w_]+)"') do
						pool[name] = true
					end
				end
				if next(pool) then
					I.neut_pool = pool
				end
			end
		end
		local pool = I.neut_pool or nil
		local tiers, base = {}, data.g > 0 and data.gw / data.g or 0.5
		for t = 1, 5 do
			local list, total = {}, 0
			for name, s in pairs(data.neut[t] or {}) do
				if not pool or pool[name] then
					total = total + s.n
					local lift = (s.w / s.n - base) * s.n / (s.n + K.LIFT_PRIOR)
					list[#list + 1] = { name = name, n = s.n, score = s.n * clamp(1 + K.LIFT_K * lift, K.LIFT_LO, K.LIFT_HI) }
				end
			end
			if #list > 0 and total >= K.SHOW_MIN then
				table.sort(list, function(a, b)
					if a.score ~= b.score then
						return a.score > b.score
					end
					return a.name < b.name
				end)
				for _, e in ipairs(list) do
					e.share = e.n / total
				end
				tiers[#tiers + 1] = { tier = t, items = list }
			end
		end
		local enh, total = nil, 0
		for name, s in pairs(data.enh) do
			total = total + s.n
			if s.n >= K.SHOW_MIN and (not enh or s.n > enh.n) then
				enh = { name = name, n = s.n }
			end
		end
		if enh then
			enh.share = enh.n / total
		end
		return tiers, enh
	end

	function I.abil_meta(name)
		local m = I.abil_metas[name]
		if m ~= nil then
			return m or nil
		end
		local blk = kv_block(I.abil_json(), name)
		m = false
		if blk then
			local function num(key)
				return math.tointeger(tonumber(blk:match('\n      "' .. key .. '": "(%-?%d+)"')))
			end
			m = { ult = blk:find('"ABILITY_TYPE_ULTIMATE"', 1, true) ~= nil, max = num("MaxLevel"), req = num("RequiredLevel"),
				gap = num("LevelsBetweenUpgrades") }
		end
		I.abil_metas[name] = m
		return m or nil
	end

	local function talent_family(name)
		return not name:find("_unique_", 1, true) and name:gsub("%d+$", "") or nil
	end

	-- the hero's current talents from assets\data\npc_heroes.json: tier by slot, plus stat families
	function I.hero_talents(h)
		local t = I.hero_tal[h]
		if t ~= nil then
			return t or nil
		end
		if I.heroes_text == nil then
			I.heroes_text = data_file("npc_heroes.json")
		end
		local hero = D.by_id[h]
		local blk = hero and kv_block(I.heroes_text or nil, hero.unit)
		t = false
		if blk then
			local list = {}
			t = { tier = {}, fam = {}, cur = {}, abil = {} }
			for idx, name in blk:gmatch('\n      "Ability(%d+)": "([%w_]+)"') do
				if name:find("^special_bonus") and name ~= K.ATTR_BONUS then
					list[#list + 1] = { i = tonumber(idx), name = name }
				else
					t.abil[name] = true
				end
			end
			table.sort(list, function(a, b)
				return a.i < b.i
			end)
			if #list == 2 * #K.TALENT_TIERS then
				for n, e in ipairs(list) do
					local tier = K.TALENT_TIERS[(n + 1) // 2]
					t.tier[e.name] = tier
					local fam = talent_family(e.name)
					if fam then
						t.fam[fam] = tier
						t.cur[fam] = e.name
					end
				end
			end
		end
		I.hero_tal[h] = t
		return t or nil
	end

	function I.kit(h)
		I.kits = I.kits or {}
		local k = I.kits[h]
		if k ~= nil then
			return k or nil
		end
		local t, src, hero = I.hero_talents(h), I.abil_json(), D.by_id[h]
		k = false
		if t and src and hero then
			k = { magic = 0, disable = 0, names = {} }
			local all = K.KIT_ALL_SPELLS[hero.unit]
			for name in pairs(t.abil) do
				local blk = kv_block(src, name)
				local beh = blk and blk:match('"AbilityBehavior": "([^"]*)"') or ""
				if blk and not beh:find("PASSIVE", 1, true) and (all or not beh:find("HIDDEN", 1, true)) then
					k.names[name] = true
					if blk:match('"AbilityUnitDamageType": "([%w_]+)"') == "DAMAGE_TYPE_MAGICAL" and not K.NO_DAMAGE[name] then
						k.magic = k.magic + 1
					end
					if blk:match('"SpellDispellableType": "([%w_]+)"') == "SPELL_DISPELLABLE_YES_STRONG"
						and blk:match('"SpellImmunityType": "([%w_]+)"') ~= "SPELL_IMMUNITY_ENEMIES_YES" then
						k.disable = k.disable + 1
					end
				end
			end
		end
		I.kits[h] = k
		return k or nil
	end

	function I.self_cover(h)
		I.self_of = I.self_of or {}
		local c = I.self_of[h]
		if c then
			return c
		end
		if not I.self_tab then
			I.self_tab = {}
			for entry in K.SELF_COVER:gmatch("[^;]+") do
				local name, rest = entry:match("^(%S+)%s+(.+)$")
				if name then
					local row = {}
					for threat, v in rest:gmatch("(%a+)%s+([%d%.]+)") do
						row[threat] = tonumber(v)
					end
					I.self_tab[name] = row
				end
			end
		end
		c = { k = {}, names = {} }
		local t = I.hero_talents(h)
		for name in pairs(t and t.abil or {}) do
			local row = I.self_tab[name]
			if row then
				c.names[#c.names + 1] = name
				for threat, w in pairs(row) do
					c.k[threat] = (c.k[threat] or 1) * (1 - w)
				end
			end
		end
		for threat, f in pairs(c.k) do
			c.k[threat] = math.max(1 - K.SELF_MAX, f)
		end
		table.sort(c.names)
		I.self_of[h] = c
		return c
	end

	function I.team_threats(T, h)
		if T.magic then
			T.magic = math.max(0, T.magic - K.MAGIC_BASE)
		end
		for threat, f in pairs(I.self_cover(h).k) do
			if T[threat] then
				T[threat] = T[threat] * f
			end
		end
		return T
	end

	-- data.skill[i] counts what players took with their i-th skill point; levels 17, 19 and 21-24 give no point,
	-- so point 17 is hero level 18. Picking the most common choice per point on its own gives orders the game
	-- does not allow (one ability five times, four points in a row), so every step is checked against the rules.
	function I.skills(data, h, pos, them, lane, state)
		if not I.abil then
			return nil, nil
		end
		local function level(i)
			return K.POINT_LEVELS[i] or i
		end
		local static = h and I.hero_talents(h)
		local function static_tier(name)
			return static and (static.tier[name] or (talent_family(name) and static.fam[talent_family(name)]))
		end
		local function cur_name(name)
			local f = static and not static.tier[name] and talent_family(name)
			return f and static.cur[f] or name
		end
		-- talents from older patches that the game no longer has at all
		local src = I.abil_json()
		local function gone(name)
			if I.gone[name] == nil then
				I.gone[name] = src ~= nil and not src:find('"' .. name .. '"', 1, true)
			end
			return I.gone[name] or (static and next(static.abil) and not name:find("^special_bonus") and not static.abil[name])
		end
		local tiers = {}
		for k, from in ipairs(K.TALENT_TIERS) do
			local upto = (K.TALENT_TIERS[k + 1] or K.TALENT_ALL) - 1
			local sum = {}
			for i, opts in pairs(data.skill) do
				local lv = level(i)
				if lv >= from and lv <= upto then
					for id, s in pairs(opts) do
						local name = I.abil[id]
						if name and name ~= K.ATTR_BONUS and name:find("^special_bonus") then
							name = cur_name(name)
							if not gone(name) then
								sum[name] = (sum[name] or 0) + s.n
							end
						end
					end
				end
			end
			tiers[k] = { from = from, upto = upto, sum = sum }
		end
		-- a talent taken late (the other tier 10 talent at level 27) belongs to the tier where it shows up first
		local tier_of = {}
		for k, tr in ipairs(tiers) do
			local names = {}
			for name in pairs(tr.sum) do
				names[#names + 1] = name
			end
			for _, name in ipairs(names) do
				local before = 0
				for j = 1, k - 1 do
					before = before + (tiers[j].sum[name] or 0)
				end
				local st = static_tier(name)
				if before >= K.TALENT_LATE * tr.sum[name] or (st and st ~= tr.from) then
					tr.sum[name] = nil
				else
					tier_of[name] = tier_of[name] or tr.from
				end
			end
		end
		local talents, by_tier = {}, {}
		for _, tr in ipairs(tiers) do
			-- only talents the hero has in this patch, when his talent list is known
			local known = static and next(static.tier) ~= nil
			local best, total = nil, 0
			for name, n in pairs(tr.sum) do
				if not known or static_tier(name) then
					total = total + n
					if not best or n > tr.sum[best] or (n == tr.sum[best] and name < best) then
						best = name
					end
				end
			end
			if best and total >= K.SHOW_MIN then
				local t = { from = tr.from, upto = tr.upto, name = best, share = tr.sum[best] / total }
				talents[#talents + 1] = t
				by_tier[tr.from] = t
			end
		end
		local ult6, ult6_n
		for id, s in pairs(data.skill[6] or {}) do
			if not ult6_n or s.n > ult6_n then
				ult6, ult6_n = I.abil[id], s.n
			end
		end
		local function rules(name)
			local m = I.abil_meta(name)
			local ult = m and m.ult or (not m and name == ult6)
			local max = m and m.max and m.max > 0 and m.max or (ult and 3 or 4)
			if name == K.ATTR_BONUS then
				return max, m and m.req or 2, 0
			end
			return max, m and m.req or (ult and 6 or 1), m and m.gap or (ult and 6 or 2)
		end
		local seen, cum = {}, {}
		for i = 1, K.SKILL_LEVELS do
			local opts, total = data.skill[i] or {}, 0
			for _, s in pairs(opts) do
				total = total + s.n
			end
			for id, s in pairs(opts) do
				local name = I.abil[id]
				if name and not name:find("^special_bonus") and not gone(name) then
					seen[name] = (seen[name] or 0) + s.n
					cum[name] = cum[name] or {}
					cum[name][i] = s.n / total
				end
			end
		end
		-- average points players have put into the ability by point i
		local function by(name, i)
			local sum = 0
			for j = 1, i do
				sum = sum + (cum[name] and cum[name][j] or 0)
			end
			return sum
		end
		local seq, have, taken = {}, {}, {}
		-- legal by the ability data, or most players already have that many points in it (Meepo's ultimate at 3,
		-- Invoker's orbs), which the ability data does not describe
		local function legal(name, lv, i)
			local max, req, gap = rules(name)
			local k = (have[name] or 0) + 1
			return k <= max and (lv >= req + (k - 1) * gap or by(name, i) >= k - K.SKILL_SLACK)
		end
		for i = 1, K.SKILL_LEVELS do
			local opts = data.skill[i]
			if not opts or not next(opts) then
				break
			end
			local lv, total, cands, tal = level(i), 0, {}, {}
			for id, s in pairs(opts) do
				total = total + s.n
				local name = I.abil[id]
				if name and name ~= K.ATTR_BONUS and name:find("^special_bonus") then
					local t = tier_of[name] or static_tier(name)
					if not t then
						for _, f in ipairs(K.TALENT_TIERS) do
							if f <= lv then
								t = f
							end
						end
					end
					if t then
						tal[t] = (tal[t] or 0) + s.n
					end
				elseif name and not gone(name) then
					cands[#cands + 1] = { name = name, n = s.n, key = name }
				end
			end
			for t, n in pairs(tal) do
				cands[#cands + 1] = { tier = t, n = n, key = "~" .. t }
			end
			table.sort(cands, function(a, b)
				if a.n ~= b.n then
					return a.n > b.n
				end
				return a.key < b.key
			end)
			local pick
			for _, c in ipairs(cands) do
				local ok
				if c.tier then
					ok = not taken[c.tier] and c.tier <= lv
				else
					ok = legal(c.name, lv, i)
				end
				if ok then
					pick = c
					break
				end
			end
			if not pick then
				local best
				for name, n in pairs(seen) do
					if name ~= K.ATTR_BONUS and legal(name, lv, i) and (not best or n > seen[best] or (n == seen[best] and name < best)) then
						best = name
					end
				end
				if not best then
					break
				end
				pick = { name = best, n = 0 }
			end
			local step = { lv = lv, share = pick.n / total }
			if pick.tier then
				taken[pick.tier] = true
				step.talent, step.tier = true, pick.tier
				step.name = by_tier[pick.tier] and by_tier[pick.tier].name or nil
			else
				have[pick.name] = (have[pick.name] or 0) + 1
				step.name, step.attr = pick.name, pick.name == K.ATTR_BONUS
			end
			seq[#seq + 1] = step
		end
		if #seq > 0 and h then
			local ok, err = pcall(I.skill_adapt, seq, h, pos, them, lane, rules)
			if not ok then
				log("skills adapt: %s", tostring(err))
			end
			for _, t in ipairs(talents) do
				local name, p, why = I.talent_pick(h, pos, t.from, them, state, t.name)
				if name and (name == t.name or not static or not next(static.tier) or static_tier(name)) then
					t.name, t.why = name, why
					t.share = p or t.share
				end
			end
			for _, step in ipairs(seq) do
				if step.talent and step.tier and by_tier[step.tier] then
					step.name = by_tier[step.tier].name
				end
			end
		end
		return #seq > 0 and seq or nil, talents
	end

	function I.sk_models()
		if I.skv then
			return
		end
		I.skv, I.tlm = {}, {}
		local function nums(text)
			local out = {}
			for x in text:gmatch("[^,]+") do
				out[#out + 1] = tonumber(x) or 0
			end
			return out
		end
		for rec in K.SKV:gmatch("[^;]+") do
			local hs, ult, vars, b, feats = rec:match("^(%d+)|([^|]*)|([^|]*)|([^|]*)|(.*)$")
			local h = math.tointeger(tonumber(hs))
			if h then
				local m = { ult = ult, vars = {}, b = nums(b), w = {} }
				for v in vars:gmatch("[^,]+") do
					m.vars[#m.vars + 1] = v
				end
				for f, cs in feats:gmatch("(%w+)=(%S+)") do
					m.w[f] = nums(cs)
				end
				I.skv[h] = m
			end
		end
		for rec in K.TLM:gmatch("[^;]+") do
			local hs, ts, left, right, b, feats = rec:match("^(%d+):(%d+)|([^|]*)|([^|]*)|([^|]*)|(.*)$")
			local h, tier = math.tointeger(tonumber(hs)), math.tointeger(tonumber(ts))
			if h and tier then
				local m = { left = left, right = right, b = tonumber(b) or 0, w = {} }
				for f, c in feats:gmatch("(%w+)=(%S+)") do
					m.w[f] = tonumber(c) or 0
				end
				I.tlm[h] = I.tlm[h] or {}
				I.tlm[h][tier] = m
			end
		end
	end

	function I.skill_var(h, pos, them, lane)
		I.sk_models()
		local m = I.skv[h]
		if not m then
			return nil
		end
		local role = (pos or 1) <= 3 and "core" or "sup"
		local feats = {}
		for _, e in ipairs(them or {}) do
			feats[#feats + 1] = { f = "e" .. e, e = e }
		end
		for _, e in ipairs(lane or {}) do
			feats[#feats + 1] = { f = "l" .. e, e = e, lane = true }
		end
		local n = #m.vars
		local function logits(with)
			local z = {}
			for k = 1, n do
				z[k] = n == 2 and (k == 2 and m.b[1] or 0) or (m.b[k] or 0)
			end
			local list = { { f = role } }
			if with then
				for _, x in ipairs(feats) do
					list[#list + 1] = x
				end
			end
			for _, x in ipairs(list) do
				local c = m.w[x.f]
				if c then
					if n == 2 then
						z[2] = z[2] + c[1]
					else
						for k = 1, n do
							z[k] = z[k] + (c[k] or 0)
						end
					end
				end
			end
			local top, sum, p = -math.huge, 0, {}
			for k = 1, n do
				top = math.max(top, z[k])
			end
			for k = 1, n do
				p[k] = math.exp(z[k] - top)
				sum = sum + p[k]
			end
			for k = 1, n do
				p[k] = p[k] / sum
			end
			return p
		end
		local r = { vars = m.vars, ult = m.ult, p = logits(true), base = logits(false), feats = feats, m = m }
		local best = 1
		for k = 2, n do
			if r.p[k] > r.p[best] then
				best = k
			end
		end
		r.best = best
		return r
	end

	function I.skv_why(r, best, cur)
		local list = {}
		for _, x in ipairs(r.feats) do
			local c = r.m.w[x.f]
			if c then
				local d
				if #r.vars == 2 then
					d = (best == 2 and 1 or -1) * c[1]
				else
					d = (c[best] or 0) - (c[cur] or 0)
				end
				if d >= K.SKV_WHY then
					list[#list + 1] = { e = x.e, lane = x.lane, d = d }
				end
			end
		end
		table.sort(list, function(a, b)
			return a.d > b.d
		end)
		local names, used = {}, {}
		for _, x in ipairs(list) do
			local hero = D.by_id[x.e]
			if hero and not used[x.e] and #names < 2 then
				used[x.e] = true
				names[#names + 1] = x.lane and L("cd_why_lane"):format(hero.name) or hero.name
			end
		end
		return names
	end

	function I.skill_adapt(seq, h, pos, them, lane, rules)
		local r = I.skill_var(h, pos, them, lane)
		if not r then
			return nil
		end
		local function basic(name)
			return name and name ~= r.ult and name ~= K.ATTR_BONUS
		end
		local pts, first4, n, first_at, last_at = {}, nil, 0, {}, {}
		for i, st in ipairs(seq) do
			if not st.talent and basic(st.name) then
				first_at[st.name] = first_at[st.name] or i
				last_at[st.name] = i
				n = n + 1
				if n <= 10 then
					pts[st.name] = (pts[st.name] or 0) + 1
					if pts[st.name] == 4 and not first4 then
						first4 = st.name
					end
				end
			end
		end
		if not first4 then
			local top = 0
			for i = 1, #seq do
				local name = seq[i].name
				if not seq[i].talent and basic(name) and (pts[name] or 0) > top then
					first4, top = name, pts[name]
				end
			end
		end
		local cur
		for k, v in ipairs(r.vars) do
			if v == first4 then
				cur = k
			end
		end
		local best = r.best
		local note = ("%s: template %s, model %s %.0f%% (base %.0f%%)"):format(tostring(h), tostring(first4), r.vars[best],
			r.p[best] * 100, r.base[best] * 100)
		if not cur or best == cur or r.p[best] - r.p[cur] < K.SKV_MARGIN or not first_at[r.vars[best]] then
			I.skv_note = note .. ", kept"
			return r
		end
		local prio = { r.vars[best] }
		local others = {}
		for name in pairs(first_at) do
			if name ~= r.vars[best] then
				others[#others + 1] = name
			end
		end
		table.sort(others, function(a, b)
			if last_at[a] ~= last_at[b] then
				return last_at[a] < last_at[b]
			end
			return a < b
		end)
		for _, name in ipairs(others) do
			prio[#prio + 1] = name
		end
		local due = {}
		for name, i in pairs(first_at) do
			due[i] = name
		end
		local cnt = {}
		local function legal(name, lv)
			local max, req, gap = rules(name)
			local k = (cnt[name] or 0) + 1
			return k <= max and lv >= req + (k - 1) * gap
		end
		local names = I.skv_why(r, best, cur)
		local why = L("cd_skv_why"):format(#names > 0 and table.concat(names, ", ") or L("cd_why_lineup"),
			I.ability_label(r.vars[best]), math.floor(r.p[best] * 100 + 0.5), math.floor(r.base[best] * 100 + 0.5))
		local moved = 0
		for i, st in ipairs(seq) do
			if not st.talent and basic(st.name) then
				local pick = nil
				local d = due[i]
				if d and (cnt[d] or 0) == 0 then
					pick = d
				else
					for _, name in ipairs(prio) do
						if not pick and legal(name, st.lv) and ((cnt[name] or 0) > 0 or first_at[name] <= i) then
							pick = name
						end
					end
				end
				pick = pick or st.name
				if pick ~= st.name then
					st.name, st.why, st.share = pick, why, r.p[best]
					moved = moved + 1
				end
				cnt[pick] = (cnt[pick] or 0) + 1
			end
		end
		I.skv_note = note .. (", %d points moved"):format(moved)
		r.applied = moved > 0
		return r
	end

	function I.talent_pick(h, pos, tier, them, state, default)
		I.sk_models()
		local m = I.tlm[h] and I.tlm[h][tier]
		if not m then
			return default, nil, nil
		end
		local z = m.b + (m.w[(pos or 1) <= 3 and "core" or "sup"] or 0)
		local base = z
		local parts = {}
		for _, e in ipairs(them or {}) do
			local c = m.w["e" .. e]
			if c then
				z = z + c
				parts[#parts + 1] = { e = e, c = c }
			end
		end
		local sc = state == "ahead" and m.w.ahead or (state == "behind" and m.w.behind) or nil
		if sc then
			z = z + sc
		end
		local p = 1 / (1 + math.exp(-z))
		local pb = 1 / (1 + math.exp(-base))
		local right = p >= 0.5
		local name = right and m.right or m.left
		local sign = right and 1 or -1
		table.sort(parts, function(a, b)
			return a.c * sign > b.c * sign
		end)
		local names = {}
		for _, x in ipairs(parts) do
			local hero = D.by_id[x.e]
			if hero and x.c * sign >= K.SKV_WHY and #names < 2 then
				names[#names + 1] = hero.name
			end
		end
		if sc and sc * sign >= K.SKV_WHY then
			names[#names + 1] = L(state == "ahead" and "cd_why_ahead" or "cd_why_behind")
		end
		local pr, pbr = right and p or 1 - p, right and pb or 1 - pb
		local why = #names > 0 and pr - pbr >= K.SKV_MARGIN and L("cd_tal_why"):format(table.concat(names, ", "),
			math.floor(pr * 100 + 0.5), math.floor(pbr * 100 + 0.5)) or nil
		return name, pr, why
	end

	function I.mins(t)
		return math.floor(t * (I.tk or 1) / 60 + 0.5)
	end

	function I.pub_want(h, names)
		local n = 0
		for _, name in ipairs(names) do
			local item = I.by_name[name]
			if item and item.cost >= K.PUB_MIN_COST and n < K.PUB_MAX_ITEMS then
				n = n + 1
				local key = h .. ":" .. name
				local have, failed = I.pub[key], I.pub_failed[key]
				if not I.pub_queued[key] and not (have and os.time() - have.at < K.PUB_TTL)
					and not (failed and os.time() - failed < K.PUB_RETRY) then
					I.pub_queued[key] = true
					I.pub_queue[#I.pub_queue + 1] = { key = key, h = h, name = name }
				end
			end
		end
	end

	function I.pub_timing(h, name, t)
		local e = I.pub[h .. ":" .. name]
		if not e or #e.b == 0 or not t or t <= 0 then
			return nil
		end
		local split
		for _, b in ipairs(e.b) do
			if not split and b.t >= t then
				split = b.t
			end
		end
		split = split or e.b[#e.b].t
		local g1, w1, g2, w2 = 0, 0, 0, 0
		for _, b in ipairs(e.b) do
			if b.t <= split then
				g1, w1 = g1 + b.g, w1 + b.w
			else
				g2, w2 = g2 + b.g, w2 + b.w
			end
		end
		if g1 < K.PUB_SIDE_MIN or g2 < K.PUB_SIDE_MIN then
			return nil
		end
		return { split = split, on = w1 / g1, off = w2 / g2, gap = w1 / g1 - w2 / g2 }
	end

	function I.subst(data, a, b)
		local s = data.subs and data.subs[a.id]
		if not s or not s[b.id] then
			return false
		end
		local fates = I.fates(data)
		local fa, fb = fates and fates[a.name], fates and fates[b.name]
		return fa ~= nil and fb ~= nil and fa.kept >= K.SUB_KEPT and fb.kept >= K.SUB_KEPT
	end

	function I.late_items(data, picked, h)
		local out = {}
		if (data.g40 or 0) < K.LATE_GAMES_MIN then
			return out
		end
		for id, n in pairs(data.late) do
			local item = I.items[id]
			local r = item and data.rows[item.name]
			if r and r.n >= K.SHOW_MIN and n / data.g40 >= K.LATE_SHARE and not K.SLOT_SKIP[item.name]
				and item.created and item.cost >= K.SLOT_MIN_COST and not I.banned(item.name, h) then
				local taken = false
				for _, cd in ipairs(picked) do
					if cd.item == item or I.contains(cd.item, item.name) or (cd.after and cd.after.item == item)
						or I.subst(data, cd.item, item) then
						taken = true
					end
				end
				if not taken then
					out[#out + 1] = {
						item = item,
						t = r.t,
						n = n,
						g40 = data.g40,
						share = n / data.g40,
						score = n / data.g40 * clamp(1 + K.LIFT_K * I.lift(data, r), K.LIFT_LO, K.LIFT_HI),
					}
				end
			end
		end
		table.sort(out, function(a, b)
			if a.score ~= b.score then
				return a.score > b.score
			end
			return a.item.name < b.item.name
		end)
		for n = #out, K.LATE_MAX + 1, -1 do
			out[n] = nil
		end
		return out
	end

	function I.extras(data, picked, h)
		local out = {}
		for _, name in ipairs(K.STEP_ITEMS) do
			local r, item = data.rows[name], I.by_name[name]
			if r and item and r.n >= K.SHOW_MIN and r.n / data.g >= K.STEP_SHARE and not I.banned(name, h) then
				out[#out + 1] = {
					item = item,
					t = r.t,
					kind = "step",
					extra = true,
					body = L("cd_step_extra"):format(I.mins(r.t)),
				}
			end
		end
		local sc, bl, blessing = data.rows.ultimate_scepter, data.rows.ultimate_scepter_2, I.by_name.ultimate_scepter_2
		if sc and bl and blessing and bl.n >= K.SHOW_MIN and bl.n >= K.UPGRADE_MIN * sc.n and not I.banned("ultimate_scepter_2", h) then
			for _, cd in ipairs(picked) do
				if cd.item.name == "ultimate_scepter" then
					out[#out + 1] = {
						item = blessing,
						t = math.max(bl.t, cd.t + 1),
						base = cd.item,
						kind = "up",
						extra = true,
						body = L("cd_tip_up_from"):format(cd.item.label),
					}
				end
			end
		end
		return out
	end

	function I.ext_items(data, picked, boots, cands, late, h)
		local skip = {}
		for _, cd in ipairs(picked) do
			skip[cd.item.name] = true
			if cd.after then
				skip[cd.after.item.name] = true
			end
		end
		for _, lt in ipairs(late) do
			skip[lt.item.name] = true
		end
		local list = {}
		local fates = I.fates(data) or {}
		local function ok_n(r)
			return r and r.n >= K.EXT_MIN_N and r.n / data.g >= K.EXT_SHARE
		end
		for name, cd in pairs(cands) do
			local fate = fates[name]
			local part = fate and (cd.count or 0) >= K.EXT_KEPT_N and fate.kept < K.EXT_KEPT
			if not skip[name] and not cd.drop and ok_n(cd.r) and not part then
				local base, bad = nil, false
				for _, p in ipairs(picked) do
					if p ~= boots then
						if I.contains(p.item, name, 0) then
							bad = true
						elseif I.contains(cd.item, p.item.name, 0) then
							base = base or p.item
						elseif siblings(p.item, cd.item) or I.subst(data, p.item, cd.item) then
							bad = true
						end
					end
				end
				if not bad and (base or cd.r.t >= K.EXT_T_MIN) then
					list[#list + 1] = { item = cd.item, cd = cd, base = base, share = cd.count / data.g, score = cd.score or cd.rank }
				end
			end
		end
		if boots then
			for name in pairs(K.BOOTS) do
				local r, item = data.rows[name], I.by_name[name]
				if item and name ~= boots.item.name and not skip[name] and ok_n(r) and item.cost > boots.item.cost and not I.banned(name, h)
					and r.t >= boots.t + K.AFTER_GAP
					and not I.contains(boots.item, name, 0) then
					local up = I.contains(item, boots.item.name, 0) and boots.item or nil
					list[#list + 1] = {
						item = item, cd = { item = item, share = I.share(data, r), rank = I.rank(data, r), count = r.n, r = r },
						base = up, swap = not up and boots.item or nil, share = r.n / data.g, score = I.rank(data, r),
					}
				end
			end
		end
		table.sort(list, function(a, b)
			if (a.base ~= nil) ~= (b.base ~= nil) then
				return a.base ~= nil
			end
			if a.score ~= b.score then
				return a.score > b.score
			end
			return a.item.name < b.item.name
		end)
		local out = {}
		for _, e in ipairs(list) do
			local clash = false
			for _, x in ipairs(list) do
				if x ~= e and I.contains(x.item, e.item.name, 0) then
					clash = true
				end
			end
			for _, o in ipairs(out) do
				if related(o.item, e.item) or siblings(o.item, e.item) or (K.BOOTS[o.item.name] and K.BOOTS[e.item.name]) then
					clash = true
				end
			end
			if not clash and #out < K.EXT_MAX then
				out[#out + 1] = e
			end
		end
		return out
	end

	function I.timeline(build)
		local fates = build.fates or {}
		local core = {}
		for _, cd in ipairs(build.slots) do
			if cd.core then
				core[cd.item.name] = true
			end
		end
		local events = {}
		for _, st in ipairs(build.start) do
			for _ = 1, st.q do
				events[#events + 1] = { item = st.item, t = -90 }
			end
		end
		for _, st in ipairs(build.steps) do
			if not st.extra then
				events[#events + 1] = { item = st.item, t = st.t, step = st }
			end
		end
		for _, lt in ipairs(build.late) do
			events[#events + 1] = { item = lt.item, t = lt.t, step = lt, late = true }
		end
		table.sort(events, function(a, b)
			if a.t ~= b.t then
				return a.t < b.t
			end
			return a.item.cost < b.item.cost
		end)
		local inv, sells, at = {}, {}, {}
		local marks, mi = { 600, 1200, 1800, 2400 }, 1
		local function snapshot(t)
			while marks[mi] and t > marks[mi] do
				local names = {}
				for _, e in ipairs(inv) do
					names[#names + 1] = e.item.name
				end
				at[marks[mi] // 60] = names
				mi = mi + 1
			end
		end
		local function take(name)
			for i, e in ipairs(inv) do
				if e.item.name == name then
					table.remove(inv, i)
					return true
				end
			end
			return false
		end
		local function consume(item, depth)
			for _, part in ipairs(item.parts) do
				local p = I.by_name[part]
				if not take(part) and depth < 3 and p and p.created then
					consume(p, depth + 1)
				end
			end
		end
		for _, ev in ipairs(events) do
			snapshot(ev.t)
			local item = ev.item
			if not item.consumable and item.cost > 0 then
				consume(item, 0)
				if ev.step and ev.step.kind == "dis" and ev.step.base then
					take(ev.step.base.name)
				end
				inv[#inv + 1] = { item = item, t = ev.t }
				while #inv > K.SLOTS do
					local best, best_v
					for i, e in ipairs(inv) do
						local f = fates[e.item.name]
						local v = f and (f.sold + (f.late_drop or 0)) or 0
						local late_ok = ev.late and v >= K.SELL_DROP
						if e.item ~= item and not K.BOOTS[e.item.name] and not K.SELL_SKIP[e.item.name] and ev.t - e.t >= K.SELL_GAP
							and (late_ok or (not core[e.item.name] and e.item.cost <= K.SELL_MAX)) then
							if not best or v > best_v or (v == best_v and e.item.cost < inv[best].item.cost) then
								best, best_v = i, v
							end
						end
					end
					if not best then
						break
					end
					local victim = table.remove(inv, best).item
					local f = fates[victim.name]
					if ev.step and victim.cost >= K.SELL_SHOW_COST and not sells[ev.step] then
						sells[ev.step] = { name = victim.name, label = victim.label, bag = not f or f.sold < K.SELL_MIN }
					end
				end
			end
		end
		snapshot(math.huge)
		build.sells, build.at = sells, at
	end

	function I.log_build(h, pos, build)
		if cfg.debug ~= 1 then
			return
		end
		local late, extras, sells = {}, {}, {}
		for _, lt in ipairs(build.late or {}) do
			late[#late + 1] = ("%s %d%%"):format(lt.item.name, math.floor(lt.share * 100 + 0.5))
		end
		for _, e in ipairs(build.extras or {}) do
			extras[#extras + 1] = ("%s %ds"):format(e.item.name, math.floor(e.t))
		end
		for st, s in pairs(build.sells or {}) do
			sells[#sells + 1] = ("%s %s for %s at %ds"):format(s.bag and "bag" or "sell", s.name, st.item.name, math.floor(st.t))
		end
		table.sort(sells)
		local ext = {}
		for _, e in ipairs(build.ext or {}) do
			ext[#ext + 1] = ("%s%s %d%%"):format(e.base and (e.base.name .. ">") or (e.swap and (e.swap.name .. "/") or ""),
				e.item.name, math.floor(e.share * 100 + 0.5))
		end
		local line = ("late [%s], no slot [%s], sells [%s], after core [%s]"):format(table.concat(late, ", "),
			table.concat(extras, ", "), table.concat(sells, ", "), table.concat(ext, ", "))
		local key = h .. ":" .. pos
		if I.build_logged[key] == line then
			return
		end
		I.build_logged[key] = line
		log("build %d pos %d: %s", h, pos, line)
		if build.lineup and build.lineup ~= "" then
			log("build %d pos %d lineup: %s", h, pos, build.lineup)
		end
		for _, m in ipairs({ 10, 20, 30, 40 }) do
			if build.at and build.at[m] then
				log("build %d pos %d at %d min: %s", h, pos, m, table.concat(build.at[m], ", "))
			end
		end
		local skills, neut = {}, {}
		for _, sk in ipairs(build.skills or {}) do
			skills[#skills + 1] = sk.lv .. " " .. (sk.talent and ("talent" .. (sk.tier or "")) or sk.name)
		end
		for _, t in ipairs(build.talents or {}) do
			skills[#skills + 1] = ("[%d: %s = %s]"):format(t.from, t.name, I.ability_label(t.name))
		end
		for _, tr in ipairs(build.neutrals or {}) do
			neut[#neut + 1] = ("%d:%s"):format(tr.tier, tr.items[1].name)
		end
		log("build %d pos %d skills: %s", h, pos, table.concat(skills, ", "))
		log("build %d pos %d neutrals: %s, enhancement %s", h, pos, table.concat(neut, " "), build.enh and build.enh.name or "-")
	end

	local LM_DEC, LM_IDX, LR_ORDER

	local function lm_dec()
		if not LM_DEC then
			LM_DEC, LM_IDX = {}, {}
			for i = 1, #K.LM_ALPHA do
				local x = K.LM_S * (i - 32)
				LM_DEC[K.LM_ALPHA:byte(i)] = K.LM_A * (math.exp(x) - math.exp(-x)) / 2
				LM_IDX[K.LM_ALPHA:byte(i)] = i - 1
			end
		end
	end

	function I.lm_item(role, name)
		local M = I.lm[role]
		if not M then
			M = { grp = {}, raw = {}, rows = {} }
			local head, body = (role == "core" and K.LM_CORE or K.LM_SUP or ""):match("^(%d+)#(.*)$")
			for id = 1, #(head or "") do
				M.grp[id - 1] = head:byte(id) - 48
			end
			for item, line in (body or ""):gmatch("([%w_]+)=([^;]*)") do
				M.raw[item] = line
			end
			I.lm[role] = M
		end
		local row = M.rows[name]
		if row == nil then
			row = false
			local line = M.raw[name]
			if line and #line >= 320 then
				lm_dec()
				row = { e = {}, a = {}, x = {} }
				for id = 0, 159 do
					local b = LM_DEC[line:byte(id + 1)] or 0
					if math.abs(b) > 1e-9 then
						row.e[id] = b
					end
					b = LM_DEC[line:byte(id + 161)] or 0
					if math.abs(b) > 1e-9 then
						row.a[id] = b
					end
				end
				for n = 321, #line - 3, 4 do
					local e = (LM_IDX[line:byte(n + 1)] or 0) * 62 + (LM_IDX[line:byte(n + 2)] or 0)
					row.x[(line:byte(n) - 48) * 1000 + e] = LM_DEC[line:byte(n + 3)] or 0
				end
			end
			M.rows[name] = row
		end
		return row or nil, M
	end

	function I.lr_item(role, name)
		local M = I.lr[role]
		if not M then
			M = { raw = {}, rows = {}, set = {} }
			for item, line in ((role == "core" and K.LR_CORE or K.LR_SUP) or ""):gmatch("([%w_]+)=([^;]*)") do
				M.raw[item] = line
			end
			I.lr[role] = M
		end
		if not LR_ORDER then
			LR_ORDER = {}
			for x in (K.LR_ITEMS or ""):gmatch("[%w_]+") do
				LR_ORDER[#LR_ORDER + 1] = x
			end
		end
		local row = M.rows[name]
		if row == nil then
			row = false
			local line, n = M.raw[name], #LR_ORDER
			if line and n > 0 and #line >= 2 * n then
				lm_dec()
				row = { e = {}, a = {} }
				for j, x in ipairs(LR_ORDER) do
					local b = LM_DEC[line:byte(j)] or 0
					if math.abs(b) > 1e-9 then
						row.e[x] = b
					end
					b = LM_DEC[line:byte(n + j)] or 0
					if math.abs(b) > 1e-9 then
						row.a[x] = b
					end
				end
			end
			M.rows[name] = row
		end
		return row or nil
	end

	function I.lr_known(name)
		if not LR_ORDER then
			I.lr_item("core", "")
		end
		if not I.lr_set then
			I.lr_set = {}
			for _, x in ipairs(LR_ORDER) do
				I.lr_set[x] = true
			end
		end
		return I.lr_set[name] == true
	end

	function I.lr_counts(seen, allies)
		local out = { e = {}, a = {}, from = {} }
		local function add(t, from, name, hero, done, depth)
			if done[name] or depth > 3 then
				return
			end
			done[name] = true
			t[name] = math.min(K.LR_CAP, (t[name] or 0) + 1)
			if from and not from[name] then
				from[name] = hero
			end
			local it = I.by_name[name]
			for _, part in ipairs(it and it.parts or {}) do
				add(t, from, part, hero, done, depth + 1)
			end
		end
		for e, items in pairs(seen or {}) do
			local done = {}
			for name in pairs(items) do
				if not name:find("^n%.") then
					add(out.e, out.from, name, e, done, 0)
				end
			end
		end
		for e, items in pairs(allies or {}) do
			local done = {}
			for name in pairs(items) do
				add(out.a, nil, name, e, done, 0)
			end
		end
		return out
	end

	local function react_z(row, have)
		local z = 0
		for x, c in pairs(have.e) do
			z = z + (row.e[x] or 0) * c
		end
		for x, c in pairs(have.a) do
			z = z + (row.a[x] or 0) * c
		end
		return z
	end

	function I.react_k(name, pos, share, have)
		local role = (pos or 1) <= 3 and "core" or "sup"
		local row = have and I.lr_item(role, name)
		if not row then
			return 1, nil
		end
		have.zmean = have.zmean or {}
		if not have.zmean[role] then
			local sum, n = 0, 0
			for _, x in ipairs(LR_ORDER) do
				local r = I.lr_item(role, x)
				if r then
					sum, n = sum + react_z(r, have), n + 1
				end
			end
			have.zmean[role] = n > 0 and sum / n or 0
		end
		local parts = {}
		for x, c in pairs(have.e) do
			local b = row.e[x]
			if b then
				parts[#parts + 1] = { x = x, b = K.LR_W * b * c, e = have.from[x] }
			end
		end
		for x, c in pairs(have.a) do
			local b = row.a[x]
			if b then
				parts[#parts + 1] = { x = x, b = K.LR_W * b * c, ally = true }
			end
		end
		if #parts == 0 then
			return 1, nil
		end
		local z = K.LR_W * (react_z(row, have) - have.zmean[role])
		local p = clamp(share or K.LM_P, K.LM_P_LO, K.LM_P_HI)
		local lp = math.log(p / (1 - p))
		local k = clamp(1 / (1 + math.exp(-(lp + z))) / p, K.LM_LO, K.LM_HI)
		local top
		for _, c in ipairs(parts) do
			if c.b * z > 0 and (not top or math.abs(c.b) > math.abs(top.b) or (math.abs(c.b) == math.abs(top.b) and c.x < top.x)) then
				top = c
			end
		end
		if not top or math.abs(math.log(k)) < K.LM_TIP then
			return k, nil
		end
		top.k = k
		return k, top
	end

	function I.vsh(name, them, pos, mates, h, share)
		local role = (pos or 1) <= 3 and "core" or "sup"
		local row, M = I.lm_item(role, name)
		if row then
			local g = h and M.grp[h]
			local z, parts = 0, {}
			for _, side in ipairs({ { them, false }, { mates, true } }) do
				for _, e in ipairs(side[1] or {}) do
					local b
					if side[2] then
						b = row.a[e] or 0
					else
						b = (row.e[e] or 0) + (g and row.x[g * 1000 + e] or 0)
					end
					if b ~= 0 then
						z = z + b
						parts[#parts + 1] = { e = e, b = b, ally = side[2] }
					end
				end
			end
			if #parts == 0 then
				return 1, nil, true
			end
			local p = clamp(share or K.LM_P, K.LM_P_LO, K.LM_P_HI)
			local lp = math.log(p / (1 - p))
			local k = clamp(1 / (1 + math.exp(-(lp + z))) / p, K.LM_LO, K.LM_HI)
			local top
			for _, c in ipairs(parts) do
				if c.b * z > 0 and (not top or math.abs(c.b) > math.abs(top.b)) then
					top = c
				end
			end
			if not top or math.abs(math.log(k)) < K.LM_TIP then
				return k, nil, true
			end
			top.v = 1 / (1 + math.exp(-(lp + top.b))) / p
			top.k, top.lm = k, true
			return k, top, true
		end
		local k, top = 1, nil
		for _, side in ipairs({ { K.VSH[role], them, false }, { K.VSA[role], mates, true } }) do
			for _, e in ipairs(side[2] or {}) do
				local v = side[1][e] and side[1][e][name]
				if v then
					k = k * v
					if not top or math.abs(math.log(v)) > math.abs(math.log(top.v)) then
						top = { e = e, v = v, ally = side[3] }
					end
				end
			end
		end
		if not top then
			return 1, nil
		end
		k = clamp(k, K.VSH_LO, K.VSH_HI)
		top.k = k
		return k, top
	end

	function I.collect(data, them, pos, mates, h)
		local cands, boots = {}, nil
		for name, r in pairs(data.rows) do
			local item = I.by_name[name]
			if item and not I.banned(name, h) then
				local share = I.share(data, r)
				local k, vsh, lm = I.vsh(name, them, pos, mates, h, share)
				local cd = {
					item = item,
					count = r.n,
					t = r.t,
					share = share,
					rank = I.rank(data, r) * k,
					vsh = vsh,
					vk = k,
					lm = lm,
					lift = I.lift(data, r),
					wr = r.w / r.n,
					g = data.g,
					r = r,
					timing = I.timing(data, r),
					behind = I.behind(data, r),
				}
				if K.BOOTS[name] then
					if not boots or cd.rank > boots.rank then
						boots = cd
					end
				elseif not K.SLOT_SKIP[name] and (K.SLOT_EXTRA[name] or (item.created and item.cost >= K.SLOT_MIN_COST)) then
					cands[name] = cd
				end
			end
		end
		for _, cd in pairs(cands) do
			for _, part in ipairs(cd.item.parts) do
				local p = cands[part]
				if p and p ~= cd and cd.count >= K.ITEM_UPGRADE * p.count and not I.same_line(cd.item.name, part) then
					p.drop = true
				end
			end
		end
		return cands, boots
	end

	function I.pre(cd, data)
		local best
		for _, part in ipairs(cd.item.parts) do
			local r = data.rows[part]
			local p = I.by_name[part]
			if r and p and r.n / data.g >= K.PRE_SHARE and r.t < cd.t - K.PRE_GAP
				and ((p.created and p.cost >= K.PRE_COST) or (part == "boots" and K.BOOTS[cd.item.name]))
				and (not best or p.cost > best.item.cost) then
				best = { item = p, t = r.t }
			end
		end
		return best
	end

	function I.upgrade(cd, cands, taken)
		local best
		for _, y in pairs(cands) do
			local contains, used = false, false
			for _, part in ipairs(y.item.parts) do
				if part == cd.item.name then
					contains = true
				end
			end
			for _, p in ipairs(taken) do
				if p.item == y.item then
					used = true
				end
			end
			if contains and not used and y.t > cd.t and y.count >= K.UPGRADE_MIN * cd.count
				and (not best or y.count > best.count) then
				best = y
			end
		end
		return best
	end

	function I.after(cd, cands, taken, data)
		local item = cd.item
		if not K.DISASSEMBLE[item.name] or (data.fin[item.id] or 0) >= K.KEEP_MAX * cd.count then
			return nil
		end
		local best
		for _, y in pairs(cands) do
			if y.share >= K.AFTER_SHARE and y.t >= cd.t + K.AFTER_GAP and not related(item, y.item) then
				local shared, used = false, false
				for _, a in ipairs(item.parts) do
					for _, b in ipairs(y.item.parts) do
						if a == b then
							shared = true
						end
					end
				end
				for _, p in ipairs(taken) do
					if p.item == y.item then
						used = true
					end
				end
				if shared and not used and (not best or y.share > best.share) then
					best = y
				end
			end
		end
		return best
	end

	local function start_items(data, h)
		local sorted = {}
		for name, r in pairs(data.rows) do
			local item = I.by_name[name]
			if item and r.m > 0 and r.m >= K.START_MIN * data.g and not I.banned(name, h) then
				sorted[#sorted + 1] = { item = item, r = r }
			end
		end
		table.sort(sorted, function(a, b)
			if a.r.m ~= b.r.m then
				return a.r.m > b.r.m
			end
			return a.item.name < b.item.name
		end)
		local out, gold = {}, 0
		for _, st in ipairs(sorted) do
			local q = clamp(math.floor(st.r.s / st.r.m + 0.5), 1, K.STACK[st.item.name] or 1)
			while q > 0 and gold + q * st.item.cost > K.START_GOLD do
				q = q - 1
			end
			if q > 0 then
				out[#out + 1] = { item = st.item, q = q }
				gold = gold + q * st.item.cost
			end
		end
		return out, gold
	end

	function I.early(data, picked, start, h)
		local skip = {}
		for _, st in ipairs(start) do
			skip[st.item.name] = true
		end
		for _, cd in ipairs(picked) do
			skip[cd.item.name] = true
		end
		local list = {}
		for name, r in pairs(data.rows) do
			local item = I.by_name[name]
			if item and not skip[name] and not K.BOOTS[name] and r.t > 0 and r.t <= K.EARLY_T and not I.banned(name, h)
				and r.n / data.g >= K.EARLY_SHARE
				and (K.EARLY_EXTRA[name] or (item.created and item.cost >= K.EARLY_MIN_COST and item.cost < K.SLOT_MIN_COST)) then
				list[#list + 1] = { item = item, t = r.t, share = r.n / data.g }
			end
		end
		table.sort(list, function(a, b)
			if a.share ~= b.share then
				return a.share > b.share
			end
			return a.item.name < b.item.name
		end)
		for n = #list, K.EARLY_MAX + 1, -1 do
			list[n] = nil
		end
		for _, e in ipairs(list) do
			for _, cd in ipairs(picked) do
				for _, part in ipairs(cd.item.parts) do
					if not e.up and cd.t > e.t and part == e.item.name then
						e.up = cd.item
					end
				end
			end
			e.body = e.up and L("cd_tip_upgrade"):format(e.up.label) or ""
		end
		return list
	end

	function I.build(h, pos, them, mates, quiet)
		local all = I.buys[h]
		if not all or not I.items then
			return nil
		end
		local data = pos and all.pos[pos]
		local dpos = pos
		if not data or data.g < K.BUYS_MIN then
			return { none = true, pos = pos, slots = {}, start = {}, gold = 0 }
		end
		local st, sm = {}, {}
		for i, e in ipairs(them) do
			st[i] = e
		end
		for i, e in ipairs(mates or {}) do
			sm[i] = e
		end
		table.sort(st)
		table.sort(sm)
		them, mates = st, sm
		local epos, erole = {}, {}
		for j, e in ipairs(them) do
			epos[j] = (draft.enemy_pos or {})[e] or 0
			erole[j] = (I.erole(e) or "-"):sub(1, 1)
		end
		local sf = I.state_for and I.state_for.h == h and I.state_for or nil
		local key = ("%d:%d:%s:%s:%s:%d:%d:%d:%s:%s:%d:%s"):format(h, pos or 0, table.concat(them, ","), table.concat(epos, ","),
			table.concat(mates or {}, ","), I.items_at, I.buys_at[h] or 0, cfg.solo, table.concat(erole), tostring(I.tk or 1), I.ban_v or 0,
			sf and (tostring(sf.state) .. ":" .. table.concat(sf.lane or {}, ",")) or "-")
		local cached = I.builds[key]
		if cached then
			if cached.pub_names and not quiet then
				I.pub_want(h, cached.pub_names)
			end
			return cached
		end
		local T, per = {}, {}
		for _, e in ipairs(them) do
			per[e] = I.threats(e)
			for threat, v in pairs(per[e]) do
				T[threat] = (T[threat] or 0) + v
			end
		end
		I.team_threats(T, h)
		local cands, boots = I.collect(data, them, dpos, mates, h)
		local lineup = {}
		for name, cd in pairs(cands) do
			if cd.lm and math.abs(math.log(cd.vk or 1)) >= 0.2 then
				lineup[#lineup + 1] = { name = name, k = cd.vk, e = cd.vsh and cd.vsh.e, ally = cd.vsh and cd.vsh.ally }
			end
		end
		table.sort(lineup, function(a, b)
			if math.abs(math.log(a.k)) ~= math.abs(math.log(b.k)) then
				return math.abs(math.log(a.k)) > math.abs(math.log(b.k))
			end
			return a.name < b.name
		end)
		for n = #lineup, 9, -1 do
			lineup[n] = nil
		end
		local vs = {}
		for n, x in ipairs(lineup) do
			vs[n] = { item = cands[x.name] and cands[x.name].item, k = x.k, e = x.e, ally = x.ally }
			lineup[n] = ("%s x%.2f%s"):format(x.name, x.k, x.e and (" (" .. (x.ally and "with " or "vs ") .. x.e .. ")") or "")
		end
		if cfg.solo == 1 then
			local solo = K.SOLO[(dpos or 1) <= 3 and "core" or "sup"]
			for name, cd in pairs(cands) do
				local extra = solo[name]
				if extra then
					cd.rank = I.rank_with(data, cd.r, cd.lift + extra) * (cd.vk or 1)
					cd.solo_v = extra
				end
			end
		end
		local list = {}
		for name, cd in pairs(cands) do
			if not cd.drop then
				if not cd.vsh and not cd.lm then
					local k, why, vs = I.cnt_k(name, T, nil, dpos)
					if k ~= 1 then
						cd.rank, cd.tk = cd.rank * k, k
						if k >= 1.1 and #why > 0 then
							cd.why, cd.vs = why, vs_heroes(vs, them, per)
						end
					end
				end
				cd.score = cd.rank
				list[#list + 1] = cd
			end
		end
		local picked = { boots }
		local function fits(cd)
			for _, p in ipairs(picked) do
				if related(p.item, cd.item) or (p ~= boots and siblings(p.item, cd.item)) or I.subst(data, p.item, cd.item) then
					return false
				end
			end
			return true
		end
		local function by(field)
			table.sort(list, function(a, b)
				if a[field] ~= b[field] then
					return a[field] > b[field]
				end
				return a.item.name < b.item.name
			end)
		end
		by("rank")
		local core = 0
		for _, cd in ipairs(list) do
			if core >= K.CORE_LOCK or #picked >= K.SLOTS then
				break
			end
			if fits(cd) then
				cd.core = true
				core = core + 1
				picked[#picked + 1] = cd
			end
		end
		by("score")
		for _, cd in ipairs(list) do
			if #picked >= K.SLOTS then
				break
			end
			if not cd.core and fits(cd) then
				picked[#picked + 1] = cd
			end
		end
		I.must(picked, cands, T, per, them, h, dpos, function(s)
			return s.core
		end)
		for _, cd in ipairs(picked) do
			if not cd.core and cd ~= boots then
				local alts = {}
				for _, c in ipairs(list) do
					if #alts >= K.ALT_MAX then
						break
					end
					local ok = c ~= cd and c.count / data.g >= K.ALT_SHARE and not related(cd.item, c.item)
					for _, p in ipairs(picked) do
						if ok and (p == c or (p ~= cd and (related(p.item, c.item)
							or (p ~= boots and siblings(p.item, c.item)) or I.subst(data, p.item, c.item)))) then
							ok = false
						end
					end
					if ok then
						alts[#alts + 1] = c
					end
				end
				cd.alts = alts
			end
		end
		table.sort(picked, function(a, b)
			if math.abs(a.t - b.t) > 0.05 then
				return a.t < b.t
			end
			return a.item.cost < b.item.cost
		end)
		local fates = cfg.live == 1 and I.fates(data) or nil
		for _, cd in ipairs(picked) do
			cd.h = h
			cd.fate = fates and fates[cd.item.name]
			cd.pre = I.pre(cd, data)
			local up = I.upgrade(cd, cands, picked)
			if up then
				cd.after, cd.after_kind = up, "up"
			else
				cd.after, cd.after_kind = I.after(cd, cands, picked, data), "dis"
			end
			cd.body = item_body(cd)
		end
		local start, gold = start_items(data, h)
		local early = I.early(data, picked, start, h)
		local steps = {}
		for _, e in ipairs(early) do
			steps[#steps + 1] = { item = e.item, t = e.t, body = e.body, early = true }
		end
		for _, cd in ipairs(picked) do
			if cd.pre then
				steps[#steps + 1] = { item = cd.pre.item, t = cd.pre.t, body = L("cd_tip_upgrade"):format(cd.item.label) }
			end
			steps[#steps + 1] = cd
			if cd.after then
				steps[#steps + 1] = {
					item = cd.after.item,
					t = cd.after.t,
					base = cd.item,
					kind = cd.after_kind,
					body = L(cd.after_kind == "up" and "cd_tip_up_from" or "cd_tip_dis_from"):format(cd.item.label),
				}
			end
		end
		local late, extras, ext = {}, {}, {}
		if cfg.live == 1 then
			late, extras = I.late_items(data, picked, h), I.extras(data, picked, h)
			for _, e in ipairs(extras) do
				steps[#steps + 1] = e
			end
			ext = I.ext_items(data, picked, boots, cands, late, h)
		end
		table.sort(steps, function(a, b)
			if a.t ~= b.t then
				return a.t < b.t
			end
			return (a.base and 1 or 0) < (b.base and 1 or 0)
		end)
		local spare
		if (T.invis or 0) >= K.SPARE_MIN then
			local item = I.by_name[(pos and pos >= 4) and "ward_sentry" or "dust"]
			if item then
				spare = { item = item, q = 2, vs = vs_heroes({ invis = 1 }, them, per) }
			end
		end
		local build = {
			slots = picked,
			steps = steps,
			start = start,
			gold = gold,
			spare = spare,
			early = early,
			dpos = dpos,
			since = data.kmax and data.kmax > 1 and data.since or nil,
			pooled = data.pooled,
			lineup = table.concat(lineup, ", "),
			vs = vs,
			fates = I.fates(data),
			late = late,
			extras = extras,
			ext = ext,
		}
		if cfg.live == 1 then
			I.timeline(build)
			build.neutrals, build.enh = I.neutrals(data)
			local lane = {}
			local sf = I.state_for and I.state_for.h == h and I.state_for or nil
			if sf and sf.lane and #sf.lane > 0 then
				lane = sf.lane
			else
				for j, e in ipairs(them) do
					if epos[j] and epos[j] > 0 and (K.LANE_OPP[pos or 0] or {})[epos[j]] then
						lane[#lane + 1] = e
					end
				end
			end
			build.skills, build.talents = I.skills(data, h, dpos or pos, them, lane, sf and sf.state or nil)
			if I.skv_note and I.skv_note ~= I.skv_logged then
				I.skv_logged = I.skv_note
				log("skills for %s", I.skv_note)
			end
			local names = {}
			for _, cd in ipairs(picked) do
				names[#names + 1] = cd.item.name
				if cd.after then
					names[#names + 1] = cd.after.item.name
				end
			end
			for _, lt in ipairs(late) do
				names[#names + 1] = lt.item.name
			end
			build.pub_names = names
			if not quiet then
				I.pub_want(h, names)
			end
		end
		I.builds[key] = build
		if not quiet then
			I.log_fates(h, pos, data)
			I.log_build(h, pos, build)
		end
		return build
	end
end

local function STEPS()
	return draft.mode == 1 and K.FREE or K.STEPS
end

local function step_team(i)
	local step = STEPS()[i]
	return step.team or (step.side ~ draft.first)
end

local function cur_step()
	if draft.edit then
		return draft.edit
	end
	local list = STEPS()
	if draft.mode == 1 then
		local t = draft.target
		if not t and draft.me and not draft.steps[draft.me] then
			return draft.me
		end
		if t and list[t] then
			if not draft.steps[t] then
				return t
			end
			for i, step in ipairs(list) do
				if step.group == list[t].group and not draft.steps[i] then
					return i
				end
			end
		end
	end
	local last = draft.mode == 1 and K.FREE_PICKS or #list
	for i = 1, last do
		if not draft.steps[i] then
			return i
		end
	end
	return nil
end

local function picks(team)
	local out = {}
	for i, step in ipairs(STEPS()) do
		local h = draft.steps[i]
		if h and step.kind == "P" and step_team(i) == team then
			out[#out + 1] = h
		end
	end
	return out
end

local function used_set()
	local set = {}
	for i = 1, #STEPS() do
		local h = draft.steps[i]
		if h then
			set[h] = true
		end
	end
	if draft.mode == 1 then
		for h in pairs(draft.extra_bans) do
			set[h] = true
		end
		for h in pairs(draft.unavail) do
			set[h] = true
		end
	end
	return set
end

function M.summary()
	local rows, them = {}, picks(1)
	for i, step in ipairs(STEPS()) do
		local h = draft.steps[i]
		if h and step.kind == "P" and step_team(i) == 0 then
			rows[#rows + 1] = { h = h, pos = draft.slot_pos[i], slot = i }
		end
	end
	table.sort(rows, function(a, b)
		return (a.pos or 9) * 100 + a.slot < (b.pos or 9) * 100 + b.slot
	end)
	local sig = {}
	for _, row in ipairs(rows) do
		row.v, row.sum = {}, 0
		for j, e in ipairs(them) do
			local v = (sigm(K.ADV_W * M.adv(row.h, e)) - 0.5) * 100
			row.v[j] = v
			row.sum = row.sum + v
		end
		sig[#sig + 1] = row.h
	end
	for _, e in ipairs(them) do
		sig[#sig + 1] = e
	end
	return { rows = rows, them = them, sig = table.concat(sig, ",") }
end

local function hero_score(h, allies, enemies, reasons, pos)
	local delta = 0
	local lane = pos and cfg.lanes == 1 and K.LANE_OPP[pos]
	for _, e in ipairs(enemies) do
		local v = M.adv(h, e) * K.ADV_W
		local ep = lane and (draft.enemy_pos or {})[e]
		if ep and lane[ep] then
			v = v * (1 + K.LANE_W)
		end
		delta = delta + v
		if reasons then
			reasons[#reasons + 1] = { h = e, v = v, t = "vs" }
		end
	end
	for _, b in ipairs(allies) do
		local v = M.syn(h, b) * K.SYN_W
		delta = delta + v
		if reasons then
			reasons[#reasons + 1] = { h = b, v = v, t = "with" }
		end
	end
	return delta
end

local function companions(hero, pos, lineup, enemies, used)
	local slots, members = {}, {}
	for p, h in pairs(lineup) do
		slots[p] = h
		members[#members + 1] = h
	end
	slots[pos] = hero
	members[#members + 1] = hero
	local taken = { [hero] = true }
	for _, h in ipairs(members) do
		taken[h] = true
	end
	local out = {}
	while true do
		local best_p, best_h, best_s
		for p = 1, 5 do
			if not slots[p] then
				for _, cand in ipairs(D.heroes) do
					local h = cand.id
					if not used[h] and not taken[h] and M.games(h) >= K.MIN_GAMES then
						local lp = M.pos(h)[p]
						if math.exp(lp) >= K.POS_MIN then
							local s = draft.vs_cache[h]
							if not s then
								s = hero_score(h, {}, enemies) + K.BASE_W * logit(M.base(h)) + M.rarity(h)
								draft.vs_cache[h] = s
							end
							for _, b in ipairs(members) do
								s = s + M.syn(h, b) * K.SYN_W
							end
							s = s + K.FIT_W * lp
							if not best_s or s > best_s then
								best_p, best_h, best_s = p, h, s
							end
						end
					end
				end
			end
		end
		if not best_p then
			break
		end
		slots[best_p] = best_h
		taken[best_h] = true
		members[#members + 1] = best_h
		out[#out + 1] = { pos = best_p, h = best_h }
	end
	table.sort(out, function(a, b)
		return a.pos < b.pos
	end)
	return out
end

local function fixed_pos(i)
	local manual = draft.manual[draft.mode][i]
	if manual then
		return manual, true
	end
	if draft.mode == 1 then
		local h = draft.steps[i]
		return draft.known_pos[i] or (h and (draft.game_roles or {})[h]), false
	end
	return nil, false
end

local function known_role(h)
	for i, step in ipairs(STEPS()) do
		if draft.steps[i] == h and step.kind == "P" and step_team(i) == 0 then
			return fixed_pos(i)
		end
	end
	return nil, false
end

local function set_manual(i, p)
	local manual = draft.manual[draft.mode]
	if p then
		for j, q in pairs(manual) do
			if q == p then
				manual[j] = nil
			end
		end
	end
	manual[i] = p
	draft.dirty = true
end

local function recompute()
	draft.dirty = false
	local c0 = cur_step()
	if draft.filter_auto and c0 ~= draft.me then
		draft.filter, draft.filter_auto = 0, false
	end
	if draft.mode == 1 and c0 and c0 == draft.me and draft.my_role and draft.filter == 0 and not draft.filter_user then
		draft.filter, draft.filter_auto = draft.my_role, true
	end
	draft.result, draft.chance, draft.slot_pos, draft.vs_cache, draft.summary = nil, nil, {}, {}, nil
	local ours, ours_idx = {}, {}
	for i, step in ipairs(STEPS()) do
		if draft.steps[i] and step.kind == "P" and step_team(i) == 0 then
			ours[#ours + 1] = draft.steps[i]
			ours_idx[#ours_idx + 1] = i
		end
	end
	local known_block, unknown, unknown_idx = {}, {}, {}
	local claim = 0
	local cs = cur_step()
	if cs and draft.filter > 0 and STEPS()[cs].kind == "P" and step_team(cs) == 0 then
		claim = draft.filter
	end
	local placed = {}
	for pass = 1, 2 do
		for j, i in ipairs(ours_idx) do
			local kp, manual = fixed_pos(i)
			if kp and (kp == claim and not manual) then
				kp = nil
			end
			if kp and manual == (pass == 1) and not known_block[kp] then
				draft.slot_pos[i] = kp
				known_block[kp], placed[j] = true, true
			end
		end
	end
	for j, i in ipairs(ours_idx) do
		if not placed[j] then
			unknown[#unknown + 1] = ours[j]
			unknown_idx[#unknown_idx + 1] = i
		end
	end
	local claim_block = known_block
	if claim > 0 and not known_block[claim] then
		claim_block = { [claim] = true }
		for p in pairs(known_block) do
			claim_block[p] = true
		end
	end
	local _, our_map = M.assign(unknown, claim_block)
	for j, i in ipairs(unknown_idx) do
		draft.slot_pos[i] = our_map[j]
	end
	draft.enemy_pos, draft.enemy_fixed = {}, {}
	if cfg.lanes == 1 then
		local eblock, eunknown, eunknown_idx = {}, {}, {}
		for i, step in ipairs(STEPS()) do
			local h = draft.steps[i]
			if h and step.kind == "P" and step_team(i) == 1 then
				local kp = draft.manual[draft.mode][i] or (draft.mode == 1 and (draft.game_roles or {})[h] or nil)
				if kp and not eblock[kp] then
					draft.slot_pos[i], draft.enemy_pos[h] = kp, kp
					draft.enemy_fixed[h] = true
					eblock[kp] = true
				else
					eunknown[#eunknown + 1] = h
					eunknown_idx[#eunknown_idx + 1] = i
				end
			end
		end
		local _, emap = M.assign(eunknown, eblock)
		for j, i in ipairs(eunknown_idx) do
			draft.slot_pos[i], draft.enemy_pos[eunknown[j]] = emap[j], emap[j]
		end
	end
	if not D.sets[0].stats or not D.heroes then
		return
	end
	local us, them = picks(0), picks(1)
	if #us > 0 and #them > 0 then
		local d = 0
		for _, a in ipairs(us) do
			d = d + logit(M.base(a))
			for _, e in ipairs(them) do
				d = d + K.ADV_W * M.adv(a, e)
			end
		end
		for _, e in ipairs(them) do
			d = d - logit(M.base(e))
		end
		for _, side in ipairs({ { us, 1 }, { them, -1 } }) do
			local team = side[1]
			for j = 1, #team - 1 do
				for l = j + 1, #team do
					d = d + side[2] * K.SYN_W * M.syn(team[j], team[l])
				end
			end
		end
		draft.chance = sigm(d)
	end
	local c = cur_step()
	if not c then
		if #us == 5 and #them == 5 then
			local sm = M.summary()
			if sm.sig ~= draft.summary_sig then
				draft.summary_sig = sm.sig
				W.list_t0, W.list_scroll = os.clock(), 0
			end
			draft.summary = sm
		end
		return
	end
	local acting, kind = step_team(c), STEPS()[c].kind
	local persp = kind == "P" and acting or 1 - acting
	local allies, enemies = picks(persp), picks(1 - persp)
	local old = draft.edit and draft.steps[c]
	if old then
		for _, list in ipairs({ allies, enemies }) do
			for j = #list, 1, -1 do
				if list[j] == old then
					table.remove(list, j)
				end
			end
		end
	end
	local our_pick = acting == 0 and kind == "P"
	local our_ban = acting == 0 and kind == "B"
	local base_fit, base_map = 0, {}
	local lineup, taken, block, rest = {}, {}, {}, allies
	if draft.filter ~= 0 and acting ~= 0 then
		draft.filter = 0
	end
	local sel = draft.filter
	if our_pick then
		rest = {}
		local fixed = {}
		for pass = 1, 2 do
			for _, h in ipairs(allies) do
				local kp, manual = known_role(h)
				if kp and manual == (pass == 1) and not block[kp] and (kp ~= sel or manual) then
					block[kp] = true
					lineup[kp], fixed[h] = h, true
				end
			end
		end
		for _, h in ipairs(allies) do
			if not fixed[h] then
				rest[#rest + 1] = h
			end
		end
		local assign_block = {}
		for p in pairs(block) do
			assign_block[p] = true
		end
		if sel > 0 then
			assign_block[sel] = true
		end
		base_fit, base_map = M.assign(rest, assign_block)
		for j, p in ipairs(base_map) do
			lineup[p] = rest[j]
		end
		for p in pairs(lineup) do
			taken[p] = true
		end
		if sel > 0 then
			block = assign_block
		end
	end
	local used = used_set()
	if old then
		used[old] = nil
	end
	local early = #allies + #enemies < 4
	local pick_no = math.min(5, #allies + 1)
	local function order_bonus(pos)
		if not our_pick or sel > 0 or not pos then
			return 0
		end
		return K.ORDER_W * math.log(K.PICK_ORDER[pick_no][pos] / 0.2)
	end
	local rows = {}
	local team = { (table.unpack or unpack)(rest) }
	local slot = #team + 1
	for _, hero in ipairs(D.heroes) do
		local h = hero.id
		if not used[h] and M.games(h) >= K.MIN_GAMES and not (our_pick and #allies >= 5) then
			local lp = M.pos(h)
			local pos, fit, ok, jmap = nil, 0, true, nil
			if our_pick then
				if sel > 0 then
					pos, fit = sel, lp[sel]
					ok = math.exp(fit) >= K.POS_MIN
				else
					team[slot] = h
					local f, map = M.assign(team, block)
					fit = f - base_fit
					pos, jmap = map[slot], map
					ok = math.exp(fit) >= K.FIT_MIN
				end
			elseif our_ban and sel > 0 then
				pos, fit = sel, lp[sel]
				ok = math.exp(fit) >= K.POS_MIN
			end
			if ok then
				local reasons = {}
				local delta = hero_score(h, allies, enemies, reasons, our_pick and pos or nil)
				local counter = 0
				for _, r in ipairs(reasons) do
					if r.t == "vs" then
						counter = counter + K.COUNTER_EXTRA * r.v + K.COUNTERED_EXTRA * math.min(0, r.v)
					end
				end
				local contest = (source() == 1 and D.contest) and D.contest[h] or 0
				local solo = (our_pick and cfg.solo == 1) and K.SOLO_P * M.comeback(h) * 4 or 0
				rows[#rows + 1] = {
					h = h,
					delta = delta,
					pos = pos,
					share = pos and math.exp(lp[pos]) or nil,
					rank = delta + counter + K.BASE_W * logit(M.base(h)) + K.FIT_W * fit + (early and K.CONTEST_W * contest or 0)
						+ order_bonus(pos) + M.rarity(h) + solo,
					reasons = reasons,
					contest = contest,
					solo = solo,
					map = jmap,
				}
			end
		end
	end
	team[slot] = nil
	table.sort(rows, function(a, b)
		return a.rank > b.rank
	end)
	for i = #rows, K.LIST_MAX + 1, -1 do
		rows[i] = nil
	end
	for i, row in ipairs(rows) do
		table.sort(row.reasons, function(a, b)
			return a.v > b.v
		end)
		if our_pick and row.pos and i <= K.COMP_ROWS then
			local lu = {}
			for p in pairs(block) do
				lu[p] = lineup[p]
			end
			if row.map then
				for j, h in ipairs(rest) do
					lu[row.map[j]] = h
				end
			else
				for p, h in pairs(lineup) do
					lu[p] = h
				end
			end
			local comp = companions(row.h, row.pos, lu, enemies, used)
			if #comp > 0 then
				row.comp = comp
			end
		end
	end
	draft.result = { acting = acting, kind = kind, persp = persp, taken = taken, rows = rows, positional = acting == 0,
		context = #allies + #enemies > 0 }
	if acting == 0 and kind == "P" and c0 and not draft.edit and #rows > 0 then
		local top = {}
		for i = 1, math.min(K.REC_TOP, #rows) do
			top[i] = { rows[i].h, rows[i].pos or 0, math.floor(rows[i].delta * 1000 + 0.5) / 1000 }
		end
		draft.pick_recs = draft.pick_recs or {}
		draft.pick_recs[tostring(c0)] = top
	end
	W.list_t0 = os.clock()
end

local function reset_draft()
	draft.steps, draft.edit, draft.query, draft.filter, draft.dirty = {}, nil, "", 0, true
	draft.result, draft.chance, draft.summary, draft.filter_auto = nil, nil, nil, false
	draft.slot_pos, draft.enemy_pos, draft.enemy_fixed, draft.vs_cache = {}, {}, {}, {}
	draft.known_pos, draft.me, draft.my_role, draft.filter_user, draft.sync_sig = {}, nil, nil, false, nil
	draft.tentative, draft.build_h, draft.summary_sig, draft.pick_recs = {}, nil, nil, nil
	draft.extra_bans, draft.extra_key, draft.unavail, draft.unavail_key, draft.grid_at = {}, nil, {}, nil, 0
	draft.grid_cache, draft.bar_at, draft.bar_enemies, draft.bar_allies = nil, 0, nil, nil
	draft.store[draft.mode], draft.history[draft.mode], draft.target = draft.steps, {}, nil
	draft.manual[draft.mode] = {}
	W.list_scroll, W.card, W.card_auto = 0, nil, nil
end

local function set_mode(mode)
	if draft.mode == mode then
		return
	end
	draft.mode = mode
	draft.steps = draft.store[mode]
	draft.edit, draft.target, draft.filter, draft.dirty = nil, nil, 0, true
	draft.filter_auto = false
	W.list_scroll = 0
	W.placed = {}
end

local function put(h)
	local c = cur_step()
	if not c or not D.by_id[h] then
		return
	end
	local used = used_set()
	if used[h] and draft.steps[c] ~= h then
		return
	end
	if draft.steps[c] ~= h then
		draft.manual[draft.mode][c] = nil
	end
	if draft.mode == 1 then
		draft.tentative[c] = nil
		if c > K.FREE_PICKS then
			draft.target = nil
		end
	end
	draft.steps[c] = h
	local hist = draft.history[draft.mode]
	for j = #hist, 1, -1 do
		if hist[j] == c then
			table.remove(hist, j)
		end
	end
	hist[#hist + 1] = c
	draft.edit, draft.query, draft.dirty = nil, "", true
	W.list_scroll = 0
	log("step %d: %s %s", c, STEPS()[c].kind, D.by_id[h].name)
end

local function undo()
	if draft.edit then
		draft.edit, draft.dirty = nil, true
		return
	end
	local hist = draft.history[draft.mode]
	while #hist > 0 do
		local i = table.remove(hist)
		if draft.steps[i] then
			draft.steps[i] = nil
			draft.dirty = true
			if draft.mode == 1 then
				draft.target = i
			end
			return
		end
	end
	for i = #STEPS(), 1, -1 do
		if draft.steps[i] then
			draft.steps[i] = nil
			draft.dirty = true
			return
		end
	end
end

local enemy_panel_heroes

local function in_match()
	local gs = GameRules.GetGameState()
	if not gs or not K.MATCH_STATES[gs] then
		return false, "state " .. tostring(gs)
	end
	local me = Players.GetLocal()
	if not me then
		return false, "no local player"
	end
	return true, gs
end

local function sync_skip(reason)
	if draft.sync_sig ~= reason then
		draft.sync_sig = reason
		log("sync skipped: %s", reason)
	end
end

local function panel_unit(panel)
	local okt, kind = pcall(panel.GetPanelType, panel)
	if not okt or type(kind) ~= "string" or not kind:find("Image", 1, true) then
		return nil
	end
	local found
	local ok, src = pcall(panel.GetImageSrc, panel)
	if ok and type(src) == "string" then
		found = src:match("(npc_dota_hero_[%w_]+)")
	end
	if not found then
		return nil
	end
	if not draft.panel_kind then
		draft.panel_kind = kind
		log("hero portraits are %s panels", kind)
	end
	found = found:gsub("_png$", "")
	local raw = found
	while found and not D.by_unit[found] do
		found = found:match("^(npc_dota_hero_.+)_%w+$")
	end
	if found ~= raw then
		draft.portrait_log = draft.portrait_log or {}
		if not draft.portrait_log[raw] then
			draft.portrait_log[raw] = true
			log("portrait %s read as %s", raw, tostring(found))
		end
	end
	return found
end

local function collect_units(panel, out, seen, depth)
	if depth > K.PANEL_DEPTH then
		return
	end
	local okv, visible = pcall(panel.IsVisible, panel)
	if okv and visible == false then
		return
	end
	local unit = panel_unit(panel)
	if unit and not seen[unit] then
		seen[unit] = true
		out[#out + 1] = unit
	end
	local okc, count = pcall(panel.GetChildCount, panel)
	if not okc or not count then
		return
	end
	for i = 0, count - 1 do
		local okg, child = pcall(panel.GetChild, panel, i)
		if okg and child then
			collect_units(child, out, seen, depth + 1)
		end
	end
end

function enemy_panel_heroes(my_team)
	local id = my_team == K.TEAM_DIRE and "RadiantTeamPlayers" or "DireTeamPlayers"
	local ok, root = pcall(Panorama.GetPanelByName, id, false)
	local out = {}
	if ok and root then
		collect_units(root, out, {}, 0)
	end
	if draft.panel_log ~= (ok and root and "found" or "missing") .. #out then
		draft.panel_log = (ok and root and "found" or "missing") .. #out
		log("panel %s: %s, heroes: %s", id, (ok and root) and "found" or "missing", table.concat(out, " "))
	end
	return out
end

local function ally_panel_heroes(my_team)
	local id = my_team == K.TEAM_DIRE and "DireTeamPlayers" or "RadiantTeamPlayers"
	local ok, root = pcall(Panorama.GetPanelByName, id, false)
	local slots, all, seen = {}, {}, {}
	if not (ok and root) then
		return slots, all, "missing"
	end
	local node = root
	for _ = 1, 3 do
		local okc, count = pcall(node.GetChildCount, node)
		if not okc or count ~= 1 then
			break
		end
		local okg, child = pcall(node.GetChild, node, 0)
		if not okg or not child then
			break
		end
		node = child
	end
	local okc, count = pcall(node.GetChildCount, node)
	count = okc and count or 0
	for i = 0, count - 1 do
		local okg, child = pcall(node.GetChild, node, i)
		if okg and child then
			local out = {}
			collect_units(child, out, {}, 1)
			if #out == 1 and count == 5 then
				slots[i + 1] = out[1]
			end
			for _, unit in ipairs(out) do
				if not seen[unit] then
					seen[unit] = true
					all[#all + 1] = unit
				end
			end
		end
	end
	return slots, all, "found " .. count
end

local panel_roles
do
	local function lane_texts()
		if draft.lane_text then
			return draft.lane_text
		end
		local out = {}
		for token, p in pairs(K.LANE_TOKEN) do
			local ok, text = pcall(GameLocalizer.Find, token)
			if ok and type(text) == "string" and text ~= "" then
				out[text] = p
			end
		end
		draft.lane_text = out
		return out
	end

	local function panel_role(panel, texts)
		for cls, p in pairs(K.LANE_CLASS) do
			local ok, has = pcall(panel.HasClass, panel, cls)
			if ok and has then
				return p
			end
		end
		local okt, kind = pcall(panel.GetPanelType, panel)
		if okt and kind == "Label" then
			local ok, text = pcall(panel.GetText, panel)
			if ok and type(text) == "string" then
				return texts[text:match("^%s*(.-)%s*$")]
			end
		end
		return nil
	end

	local function role_walk(panel, depth, texts, out)
		local units, roles = {}, {}
		if depth > K.PANEL_DEPTH then
			return units, roles
		end
		local okv, visible = pcall(panel.IsVisible, panel)
		if okv and visible == false then
			return units, roles
		end
		local unit = panel_unit(panel)
		if unit then
			units[unit] = true
		end
		local r = panel_role(panel, texts)
		if r then
			roles[r] = true
		end
		local okc, count = pcall(panel.GetChildCount, panel)
		for i = 0, (okc and count or 0) - 1 do
			local okg, child = pcall(panel.GetChild, panel, i)
			if okg and child then
				local cu, cr = role_walk(child, depth + 1, texts, out)
				for u in pairs(cu) do
					units[u] = true
				end
				for x in pairs(cr) do
					roles[x] = true
				end
			end
		end
		local u1, r1 = next(units), next(roles)
		if u1 and r1 and next(units, u1) == nil and next(roles, r1) == nil and not out[u1] then
			out[u1] = r1
		end
		return units, roles
	end

	function panel_roles()
		local out, texts = {}, lane_texts()
		for _, id in ipairs({ "RadiantTeamPlayers", "DireTeamPlayers" }) do
			local ok, root = pcall(Panorama.GetPanelByName, id, false)
			if ok and root then
				role_walk(root, 0, texts, out)
			end
		end
		local roles, names = {}, {}
		for unit, p in pairs(out) do
			local info = D.by_unit[unit]
			if info then
				roles[info.id] = p
				names[#names + 1] = info.name .. " " .. p
			end
		end
		table.sort(names)
		return roles, table.concat(names, ", ")
	end
end

local function grid_cards(min)
	local gc = draft.grid_cache
	if gc and not min and os.clock() < gc.until_t then
		local out = {}
		for i, c in ipairs(gc.cards) do
			local okv, valid = pcall(c.panel.IsValid, c.panel)
			local oko, off = false, nil
			if okv and valid then
				oko, off = pcall(c.panel.HasClass, c.panel, K.GRID_OFF)
			end
			if not oko then
				out = nil
				break
			end
			out[i] = { h = c.h, open = not off }
		end
		if out and #out >= K.GRID_MIN then
			return out
		end
		draft.grid_cache = nil
	end
	local grid
	for _, id in ipairs({ "RadiantTeamPlayers", "DireTeamPlayers" }) do
		local ok, anchor = pcall(Panorama.GetPanelByName, id, false)
		if ok and anchor and not grid then
			local okr, root = pcall(anchor.GetRootParent, anchor)
			if okr and root then
				local okf, found = pcall(root.FindChildTraverse, root, K.GRID)
				grid = okf and found or nil
			end
		end
	end
	if not grid then
		local ok, found = pcall(Panorama.GetPanelByName, K.GRID, false)
		grid = ok and found or nil
	end
	if draft.grid_log ~= tostring(grid ~= nil) then
		draft.grid_log = tostring(grid ~= nil)
		log("hero grid: %s", grid and "found" or "missing")
	end
	if not grid then
		return nil
	end
	local out, seen, cards = {}, {}, {}
	local function open(panel)
		local p = panel
		for _ = 1, K.GRID_CARD_UP do
			local ok, parent = pcall(p.GetParent, p)
			if not ok or not parent then
				return false
			end
			p = parent
			local okc, is_card = pcall(p.HasClass, p, K.GRID_CARD)
			if okc and is_card then
				local oko, off = pcall(p.HasClass, p, K.GRID_OFF)
				return oko and not off, oko and p or nil
			end
		end
		return false
	end
	local function walk(panel, depth)
		if depth > K.GRID_DEPTH then
			return
		end
		local okv, visible = pcall(panel.IsVisible, panel)
		if okv and visible == false then
			return
		end
		local unit = panel_unit(panel)
		if unit then
			local info = D.by_unit[unit]
			if info and not seen[info.id] then
				seen[info.id] = true
				local is_open, card = open(panel)
				out[#out + 1] = { h = info.id, open = is_open }
				if card then
					cards[#cards + 1] = { panel = card, h = info.id }
				end
			end
			return
		end
		local okc, count = pcall(panel.GetChildCount, panel)
		if not okc or not count then
			return
		end
		for i = 0, count - 1 do
			local okg, child = pcall(panel.GetChild, panel, i)
			if okg and child then
				walk(child, depth + 1)
			end
		end
	end
	walk(grid, 0)
	if not min and #cards == #out and #out >= K.GRID_MIN then
		draft.grid_cache = { cards = cards, until_t = os.clock() + K.GRID_CACHE }
	end
	return #out >= (min or K.GRID_MIN) and out or nil
end

local function hero_list(set)
	local names = {}
	for h in pairs(set) do
		names[#names + 1] = D.by_id[h] and D.by_id[h].name or tostring(h)
	end
	table.sort(names)
	return #names > 0 and table.concat(names, ", ") or "none"
end

local function sync_free()
	if draft.mode ~= 1 or not D.heroes then
		return
	end
	local now = os.clock()
	if now < draft.sync_at then
		return
	end
	draft.sync_at = now + K.SYNC_EVERY
	local ok_match, why = in_match()
	if not ok_match then
		sync_skip(why)
		return
	end
	local picking = why == K.HERO_SELECTION or why == K.STRATEGY
	if now >= (draft.bar_at or 0) then
		draft.bar_at, draft.bar_enemies, draft.bar_allies = now + K.BAR_EVERY, nil, nil
	end
	if not picking then
		draft.sync_at = now + K.SYNC_GAME_EVERY
	end
	local gm = GameRules.GetGameMode()
	if not K.SYNC_MODES[gm] then
		sync_skip("game mode " .. tostring(gm))
		return
	end
	local me = Players.GetLocal()
	local my_team = Entity.GetTeamNum(me)
	local mates = {}
	for _, p in ipairs(Players.GetAll()) do
		if Entity.GetTeamNum(p) == my_team then
			mates[#mates + 1] = p
		end
	end
	table.sort(mates, function(a, b)
		return Player.GetPlayerID(a) < Player.GetPlayerID(b)
	end)
	local changed = false
	local function set(i, h)
		if draft.steps[i] == h then
			return
		end
		for j = 1, #K.FREE do
			if j ~= i and draft.steps[j] == h then
				draft.steps[j] = nil
				draft.manual[1][j] = nil
			end
		end
		draft.steps[i] = h
		draft.manual[1][i] = nil
		changed = true
	end
	local sig, hovers, hidden = {}, {}, {}
	local by_id, used = true, {}
	for _, p in ipairs(mates) do
		local pid = Player.GetPlayerID(p)
		if pid < 0 or pid > 9 or used[pid % 5] then
			by_id = false
		end
		used[pid % 5] = true
	end
	for n, p in ipairs(mates) do
		local k = by_id and Player.GetPlayerID(p) % 5 + 1 or n
		if n > 5 then
			break
		end
		local ok, td = pcall(Player.GetTeamData, p)
		if ok and type(td) == "table" then
			local hid = math.tointeger(tonumber(td.selected_hero_id) or 0) or 0
			local flags = math.tointeger(tonumber(td.lane_selection_flags) or 0) or 0
			local hover = 0
			if hid <= 0 and p ~= me then
				local okp, tp = pcall(Player.GetTeamPlayer, p)
				if okp and type(tp) == "table" then
					hover = math.tointeger(tonumber(tp.possible_hero_selection) or 0) or 0
				end
			end
			if hid > 0 and D.by_id[hid] then
				set(k, hid)
				if draft.tentative[k] then
					draft.tentative[k] = nil
					changed = true
				end
			elseif hid > 0 then
				hidden[#hidden + 1] = k
			else
				hovers[#hovers + 1] = { k = k, h = (hover > 0 and D.by_id[hover]) and hover or 0 }
			end
			local role = K.LANE_BITS[flags]
			if draft.known_pos[k] ~= role then
				draft.known_pos[k] = role
				changed = true
			end
			if p == me and (draft.me ~= k or draft.my_role ~= role) then
				draft.me, draft.my_role = k, role
				changed = true
			end
			sig[#sig + 1] = ("%d:%d:%d:%d"):format(Player.GetPlayerID(p), hid, hover, flags)
		end
	end
	if #hidden > 0 then
		if not draft.bar_allies then
			local s1, a1, h1 = ally_panel_heroes(my_team)
			draft.bar_allies = { slots = s1, all = a1, how = h1 }
		end
		local slots, all, how = draft.bar_allies.slots, draft.bar_allies.all, draft.bar_allies.how
		local taken, spare, notes = {}, {}, {}
		for i = 1, 5 do
			if draft.steps[i] and not draft.tentative[i] then
				taken[draft.steps[i]] = i
			end
		end
		for _, unit in ipairs(all) do
			local info = D.by_unit[unit]
			if info and not taken[info.id] then
				spare[#spare + 1] = info.id
			end
		end
		for _, k in ipairs(hidden) do
			local info = slots[k] and D.by_unit[slots[k]]
			local h = info and info.id or nil
			if h and taken[h] and taken[h] ~= k then
				h = nil
			end
			if not h and not taken[draft.steps[k] or 0] then
				for j, sh in ipairs(spare) do
					if not h and sh then
						h = sh
					end
				end
			end
			if not h and draft.steps[k] and taken[draft.steps[k]] == k then
				h = draft.steps[k]
			end
			if h then
				for j, sh in ipairs(spare) do
					if sh == h then
						spare[j] = false
					end
				end
				set(k, h)
				taken[h] = k
				if draft.tentative[k] then
					draft.tentative[k] = nil
					changed = true
				end
			end
			notes[#notes + 1] = k .. ":" .. (h and D.by_id[h].name or "?")
		end
		local note = how .. ", " .. table.concat(notes, " ")
		if note ~= draft.hidden_note then
			draft.hidden_note = note
			log("sync: hidden ally picks, panel %s", note)
		end
	end
	local okr, roles, rkey = false, nil, nil
	if picking and now >= (draft.roles_at or 0) then
		draft.roles_at = now + K.ROLES_EVERY
		okr, roles, rkey = pcall(panel_roles)
	end
	if okr and rkey ~= draft.game_roles_key then
		draft.game_roles, draft.game_roles_key = roles, rkey
		changed = true
		log("panel roles: %s", rkey ~= "" and rkey or "none")
	end
	local n = 5
	local seen = {}
	local enemies, source = {}, "panel"
	local foes = {}
	for _, p in ipairs(Players.GetAll()) do
		if Entity.GetTeamNum(p) ~= my_team then
			foes[#foes + 1] = p
		end
	end
	table.sort(foes, function(a, b)
		return Player.GetPlayerID(a) < Player.GetPlayerID(b)
	end)
	for _, p in ipairs(foes) do
		local ok, td = pcall(Player.GetTeamData, p)
		local hid = ok and type(td) == "table" and (math.tointeger(tonumber(td.selected_hero_id) or 0) or 0) or 0
		if hid > 0 and D.by_id[hid] then
			enemies[#enemies + 1] = D.by_id[hid].unit
		end
	end
	if #enemies > 0 then
		source = "team"
	end
	if #enemies < 5 then
		local had = {}
		for _, unit in ipairs(enemies) do
			had[unit] = true
		end
		if not draft.bar_enemies then
			draft.bar_enemies = enemy_panel_heroes(my_team)
		end
		for _, unit in ipairs(draft.bar_enemies) do
			if not had[unit] then
				had[unit] = true
				enemies[#enemies + 1] = unit
				source = source == "team" and "team+panel" or "panel"
			end
		end
	end
	if #enemies < 5 then
		local have = {}
		for _, unit in ipairs(enemies) do
			have[unit] = true
		end
		local added = 0
		for _, hero in ipairs(Heroes.GetAll()) do
			local unit = NPC.GetUnitName(hero)
			if Entity.GetTeamNum(hero) ~= my_team and not NPC.IsIllusion(hero) and unit and not have[unit] then
				have[unit] = true
				enemies[#enemies + 1] = unit
				added = added + 1
			end
		end
		if added > 0 then
			source = #enemies == added and "entities" or "panel+entities"
		end
	end
	for _, unit in ipairs(enemies) do
		local info = D.by_unit[unit]
		if info and not seen[info.id] and n < 10 then
			seen[info.id] = true
			n = n + 1
			set(n, info.id)
			sig[#sig + 1] = "e" .. info.id
		end
	end
	if n > 5 then
		draft.enemy_match = tostring(GameRules.GetMatchID()) .. ":" .. tostring(GameRules.GetLobbyID())
	end
	sig[#sig + 1] = source
	local bans = GameRules.GetBannedHeroes()
	if type(bans) == "table" then
		local list, dup = {}, {}
		for i = 0, 63 do
			local id = math.tointeger(tonumber(bans[i]) or 0) or 0
			if id > 0 and D.by_id[id] and not dup[id] then
				dup[id] = true
				list[#list + 1] = id
			end
		end
		local extra = {}
		for j, id in ipairs(list) do
			if j <= 10 then
				set(10 + j, id)
			else
				extra[id] = true
			end
			sig[#sig + 1] = "b" .. id
		end
		local key = hero_list(extra)
		if draft.extra_key ~= key then
			draft.extra_bans, draft.extra_key = extra, key
			changed = true
			log("bans past 10: %s", key)
		end
	end
	local hovered = {}
	for _, hv in ipairs(hovers) do
		local k, h = hv.k, hv.h
		local free = h > 0 and not hovered[h]
		if free then
			for j, sh in pairs(draft.steps) do
				if j ~= k and sh == h and not draft.tentative[j] then
					free = false
				end
			end
		end
		if free then
			hovered[h] = true
			set(k, h)
			if not draft.tentative[k] then
				draft.tentative[k] = true
				changed = true
			end
		elseif draft.tentative[k] then
			draft.steps[k], draft.tentative[k] = nil, nil
			changed = true
		end
	end
	if why ~= K.HERO_SELECTION then
		if next(draft.unavail) then
			draft.unavail, draft.unavail_key = {}, nil
			changed = true
			log("hero grid: picks are over, unavailable list cleared")
		end
	elseif now >= draft.grid_at then
		draft.grid_at = now + K.GRID_EVERY
		local sd = gm == Enum.GameMode.DOTA_GAMEMODE_SD
		local okg, grid = pcall(grid_cards, sd and 1 or nil)
		if okg and grid then
			local picked, off = {}, {}
			for _, h in pairs(draft.steps) do
				picked[h] = true
			end
			for _, hero in ipairs(Heroes.GetAll()) do
				local info = D.by_unit[NPC.GetUnitName(hero)]
				if info then
					picked[info.id] = true
				end
			end
			local offer, n_offer = {}, 0
			for _, card in ipairs(grid) do
				if not card.open and not picked[card.h] then
					off[card.h] = true
				elseif card.open and not picked[card.h] then
					offer[card.h], n_offer = true, n_offer + 1
				end
			end
			local mine = draft.me and draft.steps[draft.me]
			if sd and not mine and n_offer > 0 and n_offer <= K.SD_OFFER_MAX then
				off = {}
				for id in pairs(D.by_id) do
					if not offer[id] and not picked[id] then
						off[id] = true
					end
				end
			end
			local key = hero_list(off)
			if key ~= draft.unavail_key then
				draft.unavail, draft.unavail_key = off, key
				changed = true
				local count = 0
				for _ in pairs(off) do
					count = count + 1
				end
				if sd and n_offer > 0 and n_offer <= K.SD_OFFER_MAX and not mine then
					log("single draft offer: %s", hero_list(offer))
				elseif count > 30 then
					log("unavailable in the hero grid: %d heroes", count)
				else
					log("unavailable in the hero grid: %s", key)
				end
			end
		end
	end
	if changed then
		draft.dirty = true
	end
	local line = table.concat(sig, " ")
	if line ~= draft.sync_sig then
		draft.sync_sig = line
		log("sync: team %s, me %s role %s | %s", tostring(my_team), tostring(draft.me), tostring(draft.my_role), line)
	end
end

local G = {
	live = false,
	match = nil,
	hero = nil,
	pos = nil,
	pos_for = nil,
	them = {},
	seen = {},
	owned = {},
	ever = {},
	ev = {},
	got_at = {},
	bpos = nil,
	gold = 0,
	time = 0,
	plan = nil,
	sig = nil,
	next_at = 0,
}

do
	local function item_name(item)
		local ok, name = pcall(Ability.GetName, item)
		if ok and type(name) == "string" and name ~= "" then
			return (name:gsub("^item_", ""))
		end
		return nil
	end

	local function my_pos(h)
		for i, step in ipairs(STEPS()) do
			if draft.steps[i] == h and step.kind == "P" and step_team(i) == 0 and draft.slot_pos[i] then
				return draft.slot_pos[i]
			end
		end
		local ok, td = pcall(Player.GetTeamData, Players.GetLocal())
		local role = ok and type(td) == "table" and K.LANE_BITS[math.tointeger(tonumber(td.lane_selection_flags) or 0) or 0]
		if role then
			return role
		end
		local best, best_p = -math.huge, 1
		for p, lp in ipairs(M.pos(h)) do
			if lp > best then
				best, best_p = lp, p
			end
		end
		return best_p
	end

	local function copy(cd)
		local out = {}
		for k, v in pairs(cd) do
			out[k] = v
		end
		return out
	end

	local function mx_info(name)
		local cache = G.mx_cache
		if cache and cache[name] then
			return cache[name][1], cache[name][2]
		end
		local core = (G.bpos or 1) <= 3
		local role = core and "core" or "sup"
		local late, early, ally = K.MX[role], K.MXE[role], K.MXA[role]
		local best = {}
		for _, e in ipairs(G.them or {}) do
			local w = clamp(((G.ew or {})[e] or 1) * ((G.dw or {})[e] or 1), K.MX_W_LO, K.MX_W_HI)
			local seen_t = (G.seen_t or {})[e] or {}
			for x in pairs(G.seen[e] or {}) do
				local v, kind = late[x] and late[x][name], "foe"
				if (seen_t[x] or math.huge) <= K.MXE_T and early[x] and early[x][name] then
					v, kind = early[x][name], "early"
				end
				if v and (not best[x] or w > best[x].w) then
					best[x] = { x = x, e = e, w = w, v = v * w, kind = kind }
				end
			end
		end
		local total, list = 0, {}
		for _, c in pairs(best) do
			total = total + c.v
			list[#list + 1] = c
		end
		local mates = {}
		for e, items in pairs(G.ally_items or {}) do
			for x in pairs(items) do
				local v = ally[x] and ally[x][name]
				if v and not mates[x] then
					mates[x] = true
					total = total + v
					list[#list + 1] = { x = x, e = e, v = v, kind = "ally" }
				end
			end
		end
		local lane = G.lane
		if lane and core then
			for _, h in ipairs((G.ptime or 0) <= K.MXL_T and lane.opp or {}) do
				local row = K.MXL.core[tostring(h)]
				local v = row and row[name]
				if v then
					total = total + v
					list[#list + 1] = { x = tostring(h), e = h, v = v, kind = "lane" }
				end
			end
			local lv = K.LANE_LOST_MAP[name]
			if lv and (lane.result == "lost" or lane.result == "won") then
				local v = (lane.result == "lost" and 0.5 or -0.5) * lv
				total = total + v
				list[#list + 1] = { x = lane.result, v = v, kind = "lane_res" }
			end
		end
		if name == "black_king_bar" and core and (G.stun_rate or 0) >= K.STUN_HI and (G.ptime or 0) >= K.STUN_FROM then
			total = total + K.STUN_BKB
			list[#list + 1] = { x = "_stun", v = K.STUN_BKB, kind = "stun" }
		end
		table.sort(list, function(p, q)
			if math.abs(p.v) ~= math.abs(q.v) then
				return math.abs(p.v) > math.abs(q.v)
			end
			return p.x < q.x
		end)
		total = clamp(total, -K.MX_CAP, K.MX_CAP)
		if cache then
			cache[name] = { total, list }
		end
		return total, list
	end
	G.mx_info = mx_info

	local function mx_label(c)
		local hero = c.e and D.by_id[c.e]
		local hname = hero and hero.name or "?"
		if c.kind == "stun" then
			return L("cd_mx_stun")
		elseif c.kind == "lane" then
			return L("cd_mx_lane"):format(hname)
		elseif c.kind == "lane_res" then
			return L(c.x == "lost" and "cd_mx_lane_lost" or "cd_mx_lane_won")
		end
		local key = c.x:gsub("^n%.", "")
		local it = I.by_name[key]
		local label = it and it.label or key
		if c.kind == "ally" then
			return L("cd_mx_ally"):format(label, hname)
		end
		return L(c.kind == "early" and "cd_mx_early" or "cd_mx_foe"):format(label, hname)
	end
	G.mx_label = mx_label

	local function value(cd, T, cover, anti)
		local k = 1
		if not cd.vsh and not cd.lm then
			k = I.cnt_k(cd.item.name, T, cover, G.bpos)
		end
		local mx = (cd.share or 0) >= K.MX_MIN_SHARE and (cd.mx or 0) or 0
		return (cd.rank or cd.share) / (cd.tk or 1) * k - (anti[cd.item.name] or 0) + K.MX_W * mx
	end

	local function coverage(slots, skip)
		local left = {}
		for _, s in ipairs(slots) do
			if s ~= skip then
				for threat, w in pairs(K.COUNTERS[s.item.name] or {}) do
					left[threat] = (left[threat] or 1) * (1 - K.COVER * w)
				end
			end
		end
		return left
	end

	local function owns(item)
		if (G.owned[item.name] or 0) > 0 or G.ever[item.name] then
			return true
		end
		for name in pairs(G.ever) do
			local o = I.by_name[name]
			if o then
				for _, part in ipairs(o.parts) do
					if part == item.name then
						return true
					end
				end
			end
		end
		return false
	end

	local function progress(item, used, depth, min_cost, skip)
		local have = 0
		for _, part in ipairs(item.parts) do
			local p = I.by_name[part]
			if p and part ~= skip then
				if (G.owned[part] or 0) > (used[part] or 0) and p.cost >= (min_cost or 0) then
					used[part] = (used[part] or 0) + 1
					have = have + p.cost
				elseif depth < 3 and p.created then
					have = have + progress(p, used, depth + 1, min_cost, skip)
				end
			end
		end
		return have
	end

	local function eligible(name, item)
		return item and not K.SLOT_SKIP[name]
			and (K.BOOTS[name] or K.SLOT_EXTRA[name] or (item.created and item.cost >= K.SLOT_MIN_COST))
	end

	local function clash(slots, skip, cd)
		for _, s in ipairs(slots) do
			if s ~= skip and (s.item == cd.item or I.related(s.item, cd.item)
				or (not K.BOOTS[s.item.name] and I.siblings(s.item, cd.item))
				or (G.data and I.subst(G.data, s.item, cd.item))) then
				return true
			end
		end
		return false
	end

	local function add_threats(e, T, from, with_items)
		local t = {}
		for k, v in pairs(I.threats(e)) do
			t[k] = v
		end
		if with_items and G.dps_w and G.dps_w[e] then
			t.phys = math.max(G.dps_w[e], (t.phys or 0) * K.PHYS_PRIOR_KEEP)
		end
		if with_items then
			for name in pairs(G.seen[e] or {}) do
				for threat, w in pairs(K.ENEMY_ITEMS[name] or {}) do
					w = w * ((G.ew or {})[e] or 1) * ((G.dw or {})[e] or 1)
					t[threat] = (t[threat] or 0) + w
					from[#from + 1] = { e = e, item = name, threat = threat, w = w }
				end
			end
		end
		for k, v in pairs(t) do
			t[k] = math.min(1, v)
			T[k] = (T[k] or 0) + t[k]
		end
		return t
	end

	local function reason_for(cd, from)
		local vs, best = K.COUNTERS[cd.item.name] or {}, nil
		for _, f in ipairs(from) do
			local w = vs[f.threat]
			if w and (not best or w * f.w > best.x) then
				best = { e = f.e, item = f.item, x = w * f.w }
			end
		end
		return best
	end

	local function place_owned(slots, data, T1, anti)
		local function lowest(filter)
			local worst, worst_v
			for i, s in ipairs(slots) do
				if filter(s) then
					local v = value(s, T1, coverage(slots, s), anti)
					if not worst or v < worst_v then
						worst, worst_v = i, v
					end
				end
			end
			return worst
		end
		local names = {}
		for name in pairs(G.owned) do
			names[#names + 1] = name
		end
		table.sort(names)
		for _, name in ipairs(names) do
			local item = I.by_name[name]
			if eligible(name, item) then
				local placed = false
				for _, s in ipairs(slots) do
					if s.item == item then
						placed = true
					end
					for _, part in ipairs(s.item.parts) do
						if part == name then
							placed = true
						end
					end
				end
				if not placed then
					local idx, keep
					for i, s in ipairs(slots) do
						if not idx and not s.bought and (G.owned[s.item.name] or 0) == 0
							and ((s.after and s.after.item == item) or I.contains(item, s.item.name)
							or (K.BOOTS[name] and K.BOOTS[s.item.name])) then
							idx, keep = i, s
						end
					end
					for i, s in ipairs(slots) do
						if not idx and not owns(s.item) and ((K.BOOTS[name] and K.BOOTS[s.item.name])
							or (s.after and s.after.item == item) or I.related(s.item, item) or I.siblings(s.item, item)) then
							idx = i
						end
					end
					local function started(s)
						return progress(s.item, {}, 0, K.SIGNAL_MIN) > 0
					end
					idx = idx or lowest(function(s)
						return not owns(s.item) and not s.core and not started(s)
					end) or lowest(function(s)
						return not owns(s.item) and not started(s)
					end) or lowest(function(s)
						return not owns(s.item)
					end)
					if idx then
						local r = data.rows[name]
						slots[idx] = {
							item = item,
							count = r and r.n or 0,
							share = r and I.share(data, r) or 0,
							rank = r and I.rank(data, r) or 0,
							t = r and r.t or keep and keep.t or G.got_at[name] or G.ptime or 0,
							core = keep and keep.core or nil,
							bought = true,
						}
					end
				end
			end
		end
	end

	local function swap_slots(slots, cands, T0, T1, from, anti, anti_from)
		local swaps = 0
		while swaps < K.SWAPS_MAX do
			local best
			for i, s in ipairs(slots) do
				if not s.core and not s.bought and not s.swapped and not K.BOOTS[s.item.name] and not owns(s.item)
					and progress(s.item, {}, 0, cfg.autobuy == 1 and 1 or K.SIGNAL_MIN) == 0 then
					local cover = coverage(slots, s)
					local cur = value(s, T1, cover, anti)
					local hurt = (anti[s.item.name] or 0) > 0
					local guard = not hurt and I.sole_answer(slots, s, T1)
					for _, cd in pairs(cands) do
						if not cd.drop and not clash(slots, s, cd)
							and not (guard and ((K.COUNTERS[cd.item.name] or {})[guard] or 0) < K.MUST_COVER) then
							local v1 = value(cd, T1, cover, anti)
							local moved = (cd.adj or 0) - (s.adj or 0) >= K.ADJ_MIN
							local fresh = hurt or v1 > value(cd, T0, cover, anti) + 0.02 or moved
							local gain = v1 - cur
							if hurt and K.INSTEAD[s.item.name] and K.INSTEAD[s.item.name][cd.item.name] then
								gain = gain + K.INSTEAD_BONUS
							end
							if fresh and gain >= K.SWAP_MARGIN and (not best or gain > best.gain) then
								best = { i = i, cd = cd, gain = gain, hurt = hurt, moved = moved }
							end
						end
					end
				end
			end
			if not best then
				return
			end
			local old = slots[best.i]
			local new = copy(best.cd)
			new.swapped, new.from = true, old.item
			new.reason = best.hurt and anti_from[old.item.name] or reason_for(new, from)
			if not new.reason and best.moved and new.mx_top and new.mx_top.e and new.mx_top.v > 0 then
				new.reason = { e = new.mx_top.e, item = new.mx_top.x }
			end
			if not new.reason and best.moved then
				local rt = (new.rk or 1) > 1 and new.rtop or nil
				if best.cd.solo then
					new.adj_why = "solo"
				elseif new.lift_src then
					new.adj_why = new.lift_src
				elseif rt and rt.e then
					new.reason = { e = rt.e, item = rt.x }
				elseif rt then
					new.adj_why, new.adj_rt = "ally", rt
				else
					new.adj_why = "react"
				end
			end
			slots[best.i] = new
			swaps = swaps + 1
		end
	end

	local function sell_for(target, steps, done, fates, weak, swap)
		local main = {}
		for _, name in ipairs(G.main or {}) do
			main[#main + 1] = name
		end
		if target.ext and target.ext.swap then
			for _, name in ipairs(main) do
				local it = I.by_name[name]
				if K.BOOTS[name] and name ~= target.item.name and it then
					return { name = name, label = it.label, bag = false }
				end
			end
		end
		local function take(name)
			for i, n in ipairs(main) do
				if n == name then
					table.remove(main, i)
					return true
				end
			end
			return false
		end
		local function consume(item, depth)
			for _, part in ipairs(item.parts) do
				local p = I.by_name[part]
				if not take(part) and depth < 3 and p and p.created then
					consume(p, depth + 1)
				end
			end
		end
		if target.item.consumable or target.extra then
			return nil
		end
		consume(target.item, 0)
		if target.kind == "dis" and target.base then
			take(target.base.name)
		end
		local function soft(name)
			local item = I.by_name[name]
			return not item or item.consumable or item.cost < K.SELL_SOFT_COST
		end
		local hard = 0
		for _, name in ipairs(main) do
			if not soft(name) then
				hard = hard + 1
			end
		end
		if hard + 1 <= K.SLOTS then
			return nil
		end
		local function counter_now(name)
			local v = 0
			for threat, w in pairs(K.COUNTERS[name] or {}) do
				v = v + w * math.min(1, (G.T1 or {})[threat] or 0)
			end
			return v
		end
		local late_target = target.late or target.ext
		local best, best_v, young
		for _, name in ipairs(main) do
			local item = I.by_name[name]
			local fate = fates and fates[name]
			local drop = fate and (fate.sold + (fate.late_drop or 0)) or 0
			local late_ok = late_target and drop >= K.SELL_DROP
			local fresh = G.got_at[name] and (G.ptime or 0) - G.got_at[name] < K.SELL_HOLD
			if item and not soft(name) and not K.BOOTS[name] and not K.SELL_SKIP[name] and (item.cost <= K.SELL_MAX or late_ok)
				and counter_now(name) < K.SELL_COUNTER and fresh then
				local needed = target.dis ~= nil and target.dis.name == name
				for _, st in ipairs(steps) do
					if (not done(st) and I.contains(st.item, name)) or (((st.s and not st.pre) or st.late or st.ext)
						and (st.item == item or I.contains(item, st.item.name)) and not late_ok) then
						needed = true
					end
				end
				if not needed and (not young or item.cost < young.cost) then
					young = item
				end
			elseif item and not soft(name) and not K.BOOTS[name] and not K.SELL_SKIP[name] and (item.cost <= K.SELL_MAX or late_ok)
				and counter_now(name) < K.SELL_COUNTER then
				local needed = target.dis ~= nil and target.dis.name == name
				for _, st in ipairs(steps) do
					if not done(st) and I.contains(st.item, name) then
						needed = true
					elseif ((st.s and not st.pre) or st.late or st.ext) and (st.item == item or I.contains(item, st.item.name))
						and not late_ok then
						needed = true
					end
				end
				if not needed then
					local f = fate
					local v = drop
					if not best or v > best_v or (v == best_v and item.cost < best.cost) then
						best, best_v = item, v
					end
				end
			end
		end
		if not best and young and (swap or (G.bag_used or 0) < K.BACKPACK) then
			return { name = young.name, label = young.label, bag = true }
		end
		if not best and weak and not swap and (not target.base or (G.owned[target.base.name] or 0) == 0) then
			local data = G.data
			local need = target.item.cost - progress(target.item, {}, 0)
			local room = (G.bag_used or 0) < K.BACKPACK
			for _, name in ipairs(main) do
				local item = I.by_name[name]
				local fresh = G.got_at[name] and (G.ptime or 0) - G.got_at[name] < K.SELL_HOLD
				local gold = (G.gold or 0) + ((room and (G.gold or 0) >= need) and 0 or math.floor((item and item.cost or 0) / 2))
				if item and not soft(name) and not K.BOOTS[name] and not K.SELL_SKIP[name] and not fresh
					and counter_now(name) < K.SELL_COUNTER and gold >= need
					and target.item.cost >= item.cost * ((G.gold or 0) >= need and K.WEAK_COST_RICH or K.WEAK_COST) then
					local needed = target.dis ~= nil and target.dis.name == name
					for _, st in ipairs(steps) do
						if st ~= target and not done(st) and I.contains(st.item, name) then
							needed = true
						end
					end
					local late = data and (data.g40 or 0) > 0 and ((data.late or {})[item.id] or 0) / data.g40 or 0
					if not needed and (not best or late < best_v or (late == best_v and item.cost < best.cost)) then
						best, best_v = item, late
					end
				end
			end
			if not best then
				return nil
			end
			return { name = best.name, label = best.label, bag = room and (G.gold or 0) >= need, weak = true }
		end
		if not best then
			return nil
		end
		local f = fates and fates[best.name]
		local bag = not f or f.sold < K.SELL_MIN
		if bag and (G.bag_used or 0) >= K.BACKPACK then
			bag = false
		end
		return { name = best.name, label = best.label, bag = bag }
	end

	function G.own_steps(steps, slots, data, done, base)
		local listed, notes, planned = {}, {}, {}
		for _, st in ipairs(steps) do
			listed[st.item.name] = true
		end
		for _, sl in ipairs(base.slots or {}) do
			planned[sl.item.name] = true
			if sl.after then
				planned[sl.after.item.name] = true
			end
			if sl.pre then
				planned[sl.pre.item.name] = true
			end
		end
		for _, key in ipairs({ "early", "extras", "late", "ext" }) do
			for _, e in ipairs(base[key] or {}) do
				planned[e.item.name] = true
			end
		end
		local best_k = 0
		for _, st in ipairs(steps) do
			if not done(st) then
				best_k = math.max(best_k, progress(st.item, {}, 0, K.SIGNAL_MIN) / math.max(1, st.item.cost))
			end
		end
		local now = math.floor(G.ptime or 0)
		local start, start_k
		for name, r in pairs(data.rows) do
			local it = I.by_name[name]
			if it and it.created and #it.parts > 0 and not listed[name] and r.n >= K.SHOW_MIN and eligible(name, it)
				and not owns(it) and not I.banned(name, G.hero) then
				local skip = false
				for _, st in ipairs(steps) do
					if not done(st) and I.contains(st.item, name) then
						skip = true
					end
				end
				for _, part in ipairs(it.parts) do
					local p = I.by_name[part]
					if p and (G.owned[part] or 0) > 0 and p.created and eligible(part, p) then
						skip = true
					end
				end
				local k = progress(it, {}, 0, K.SIGNAL_MIN) / it.cost
				if not skip and k >= K.OWN_START and k >= best_k + K.OWN_LEAD
					and (not start or k > start_k or (k == start_k and name < start.name)) then
					start, start_k = it, k
				end
			end
		end
		if start then
			steps[#steps + 1] = { item = start, t = now, own = "start", own_k = start_k }
			listed[start.name] = true
			notes[#notes + 1] = ("started %s %.0f%%"):format(start.name, start_k * 100)
		end
		local drop = {}
		for _, sl in ipairs(slots) do
			if sl.bought and owns(sl.item) and not planned[sl.item.name] then
				local best, best_share, best_drop
				for up_name, up in pairs(I.by_name) do
					local direct = false
					for _, part in ipairs(up.parts or {}) do
						if part == sl.item.name then
							direct = true
						end
					end
					local r = direct and data.rows[up_name]
					local share = r and r.n >= K.SHOW_MIN and r.n / data.g or 0
					if direct and up.created and not listed[up_name] and not owns(up) and share >= K.REACT_RATE
						and not K.SLOT_SKIP[up_name] and not I.banned(up_name, G.hero) then
						local blocked, gone = false, {}
						for _, st in ipairs(steps) do
							if not done(st) and st.item ~= sl.item and not drop[st] and (I.siblings(st.item, up) or I.related(st.item, up)) then
								if progress(st.item, {}, 0, K.SIGNAL_MIN) > 0 or st.own then
									blocked = true
								else
									gone[#gone + 1] = st
								end
							end
						end
						if not blocked and (not best or share > best_share or (share == best_share and up_name < best.name)) then
							best, best_share, best_drop = up, share, gone
						end
					end
				end
				if best then
					local names = {}
					for _, st in ipairs(best_drop) do
						drop[st] = true
						names[#names + 1] = st.item.name
						for _, o in ipairs(steps) do
							if o.base == st.item or o.via == st.item then
								drop[o] = true
								names[#names + 1] = o.item.name
							end
						end
					end
					steps[#steps + 1] = { item = best, t = math.max(now, data.rows[best.name].t), base = sl.item, kind = "up",
						own = "up", own_k = best_share }
					listed[best.name] = true
					notes[#notes + 1] = ("%s -> %s %.0f%%%s"):format(sl.item.name, best.name, best_share * 100,
						#names > 0 and (" instead of " .. table.concat(names, ",")) or "")
				end
			end
		end
		local out = {}
		for _, st in ipairs(steps) do
			if not drop[st] then
				out[#out + 1] = st
			end
		end
		local note = #notes > 0 and table.concat(notes, ", ") or "-"
		if note ~= G.own_note then
			G.own_note = note
			log("own steps: %s", note)
		end
		return out
	end

	function G.inslot(data, steps, anti)
		local listed, out, hero = {}, {}, D.by_id[G.hero]
		for _, st in ipairs(steps) do
			listed[st.item.name] = true
		end
		for _, name in ipairs(G.main or {}) do
			local from = I.by_name[name]
			if from and not from.consumable and not K.SLOT_SKIP[name] and (from.cost >= K.SLOT_MIN_COST or K.BOOTS[name]) then
				for up_name, item in pairs(I.by_name) do
					local direct = false
					for _, part in ipairs(item.parts or {}) do
						if part == name then
							direct = true
						end
					end
					if direct and item.created and not item.consumable and item.cost > from.cost and not K.SLOT_SKIP[up_name]
						and not I.banned(up_name, G.hero)
						and not listed[up_name] and not owns(item) and (anti[up_name] or 0) == 0
						and not (K.FIT[up_name] and not I.fits(up_name, G.hero, G.bpos) and not I.fits(up_name, G.hero, 1)) then
						local r = data.rows[up_name]
						local share = r and r.n >= K.SHOW_MIN and r.n / data.g or nil
						local want = K.BLINK_ATTR[up_name]
						local fit = want and hero and want == hero.attr or false
						if not (want and hero and hero.attr ~= "all" and not fit and not share) then
							listed[up_name] = true
							local have = progress(item, {}, 0)
							out[#out + 1] = {
								item = item, base = from, kind = "up", t = math.floor(G.ptime or 0), have = have, signal = have,
								upg = { share = share, fit = fit, extra = item.cost - have },
							}
						end
					end
				end
			end
		end
		table.sort(out, function(a, b)
			local x, y = a.upg, b.upg
			if (x.share ~= nil) ~= (y.share ~= nil) then
				return x.share ~= nil
			end
			if x.share and y.share and x.share ~= y.share then
				return x.share > y.share
			end
			if x.fit ~= y.fit then
				return x.fit
			end
			if x.extra ~= y.extra then
				return x.extra < y.extra
			end
			return a.item.name < b.item.name
		end)
		for n = #out, K.UP_MAX + 1, -1 do
			out[n] = nil
		end
		return out
	end

	local function take_owned(item, used)
		if (G.owned[item.name] or 0) - (used[item.name] or 0) > 0 then
			used[item.name] = (used[item.name] or 0) + 1
			return true
		end
		return false
	end

	local function owned_value(item, used, depth, whole)
		if not whole and take_owned(item, used) then
			return item.cost
		end
		return depth < 3 and progress(item, used, depth + 1) or 0
	end

	local function full_buy(item, used, out, top)
		if not top and take_owned(item, used) then
			return
		end
		local parts = {}
		for _, part in ipairs(item.parts) do
			local p = I.by_name[part]
			if p then
				parts[#parts + 1] = p
			end
		end
		if #parts == 0 then
			out[#out + 1] = { id = item.id, name = item.name }
			return
		end
		for _, p in ipairs(parts) do
			full_buy(p, used, out, false)
		end
		local rname = item.recipe_name or ("recipe_" .. item.name)
		if item.recipe and (G.owned[rname] or 0) <= (used[rname] or 0) then
			out[#out + 1] = { id = item.recipe, name = rname }
		elseif item.recipe then
			used[rname] = (used[rname] or 0) + 1
		end
	end

	local function part_order(item, data)
		local parts = {}
		for _, part in ipairs(item.parts) do
			local p = I.by_name[part]
			if p then
				local r = data and data.rows[part]
				parts[#parts + 1] = { item = p, t = r and r.t > 0 and r.t or nil }
			end
		end
		table.sort(parts, function(a, b)
			if (a.t ~= nil) ~= (b.t ~= nil) then
				return a.t ~= nil
			end
			if a.t and b.t and math.abs(a.t - b.t) > K.PART_TIE then
				return a.t < b.t
			end
			if a.item.cost ~= b.item.cost then
				return a.item.cost > b.item.cost
			end
			return a.item.name < b.item.name
		end)
		local out = {}
		for _, p in ipairs(parts) do
			out[#out + 1] = p.item
		end
		return out
	end

	local function failed(item, depth)
		local until_at = (G.auto_fail or {})[item.name]
		if until_at and os.clock() < until_at then
			return true
		end
		if (depth or 0) < 3 then
			for _, part in ipairs(item.parts) do
				local p = I.by_name[part]
				if p and failed(p, (depth or 0) + 1) then
					return true
				end
			end
		end
		return false
	end

	local function buy_list(item, gold, used, out, depth, data)
		local probe = copy(used)
		local whole = depth == 0
		local need = item.cost - owned_value(item, probe, depth, whole)
		local rname = item.recipe_name or ("recipe_" .. item.name)
		if item.recipe and (G.owned[rname] or 0) > (used[rname] or 0) then
			local parts_cost = 0
			for _, part in ipairs(item.parts) do
				local p = I.by_name[part]
				parts_cost = parts_cost + (p and p.cost or 0)
			end
			need = need - math.max(0, item.cost - parts_cost)
		end
		if need <= 0 and not whole then
			owned_value(item, used, depth)
			return 0
		end
		if need <= gold and not failed(item) then
			full_buy(item, used, out, whole)
			return math.max(0, need)
		end
		if depth >= 3 then
			return 0
		end
		local order = part_order(item, data)
		if K.BOOTS[item.name] then
			for _, p in ipairs(order) do
				if (p.name == "boots" or K.BOOTS[p.name]) and (G.owned[p.name] or 0) - (used[p.name] or 0) <= 0
					and progress(p, copy(used), 0) < p.cost then
					return buy_list(p, gold, used, out, depth + 1, data)
				end
			end
		end
		local spent = 0
		for _, p in ipairs(order) do
			spent = spent + buy_list(p, gold - spent, used, out, depth + 1, data)
		end
		return spent
	end

	function G.buy(name)
		local item = I.by_name[name]
		if not item or not G.live then
			return false
		end
		local okg, gold = pcall(Player.GetTotalGold, Players.GetLocal())
		gold = okg and tonumber(gold) or 0
		local list = {}
		buy_list(item, gold, {}, list, 0, G.data)
		local hero, secret = Heroes.GetLocal(), {}
		if hero and G.fit_list then
			if not G.in_secret(hero) then
				for i = #list, 1, -1 do
					if G.is_secret(list[i].name) then
						local it = I.by_name[list[i].name]
						table.insert(secret, 1, it and it.label or list[i].name)
						table.remove(list, i)
					end
				end
			end
			local okh, home = pcall(NPC.IsInRangeOfShop, hero, Enum.ShopType.DOTA_SHOP_HOME)
			list = G.fit_list(list, hero, okh and home)
		end
		local names = {}
		for _, it in ipairs(list) do
			names[#names + 1] = it.name
		end
		log("buy %s: [%s], gold %d, secret shop only: [%s]", name, table.concat(names, ", "), gold, table.concat(secret, ", "))
		if #secret > 0 then
			W.ptoast = { key = "cd_buy_secret", arg = table.concat(secret, ", "), t = os.clock() }
		end
		if #list == 0 then
			if #secret == 0 then
				W.ptoast = { key = "cd_buy_gold", t = os.clock() }
			end
			return false
		end
		G.buyq, G.buy_at = list, 0
		return true
	end

	function G.buy_tick()
		local q = G.buyq
		if not q or os.clock() < (G.buy_at or 0) then
			return
		end
		local it = table.remove(q, 1)
		local hero = Heroes.GetLocal()
		if it and hero then
			local issuer = it.unit and Enum.PlayerOrderIssuer.DOTA_ORDER_ISSUER_PASSED_UNIT_ONLY
				or Enum.PlayerOrderIssuer.DOTA_ORDER_ISSUER_HERO_ONLY
			local ok, err = pcall(Player.PrepareUnitOrders, Players.GetLocal(), Enum.UnitOrder.DOTA_UNIT_ORDER_PURCHASE_ITEM, nil,
				Vector(0, 0, 0), it.id, issuer, it.unit or hero, false, false, false, false)
			if not ok then
				log("purchase %s failed: %s", it.name, tostring(err))
			end
			G.buy_at = os.clock() + K.BUY_GAP
		end
		if #q == 0 or not hero then
			G.buyq = nil
		end
	end

	local function find_item(hero, name)
		for slot = 0, K.INV_LAST do
			local it = NPC.GetItemByIndex(hero, slot)
			if it and item_name(it) == name then
				return it
			end
		end
		return nil
	end

	local function find_main(hero, name)
		for slot = 0, K.MAIN_LAST do
			local it = NPC.GetItemByIndex(hero, slot)
			if it and item_name(it) == name then
				return it
			end
		end
		return nil
	end

	local function free_bag(hero)
		for slot = K.MAIN_LAST + 1, K.MAIN_LAST + K.BACKPACK do
			if not NPC.GetItemByIndex(hero, slot) then
				return slot
			end
		end
		return nil
	end

	local function auto_order(kind, ability, hero, target)
		local ok, err = pcall(Player.PrepareUnitOrders, Players.GetLocal(), kind, target, Vector(0, 0, 0), ability,
			Enum.PlayerOrderIssuer.DOTA_ORDER_ISSUER_HERO_ONLY, hero, false, false, false, false)
		if not ok then
			log("auto: order failed: %s", tostring(err))
		end
		G.auto_sent = os.clock()
		return ok
	end

	local function bb_reserve()
		if cfg.abuy_bb ~= 1 or (G.ptime or 0) < ((G.bpos or 1) <= 3 and K.BB_CORE_FROM or K.BB_SUP_FROM) then
			return 0
		end
		local ok, tp = pcall(Player.GetTeamPlayer, Players.GetLocal())
		local nw = ok and type(tp) == "table" and tonumber(tp.networth) or 0
		return math.floor(K.BB_BASE + nw / K.BB_DIV)
	end

	local function stash_count(hero)
		local n = 0
		for slot = K.STASH_FIRST, K.INV_LAST do
			if NPC.GetItemByIndex(hero, slot) then
				n = n + 1
			end
		end
		return n
	end

	function G.courier_order(courier, ab)
		local ok, err = pcall(Player.PrepareUnitOrders, Players.GetLocal(), Enum.UnitOrder.DOTA_UNIT_ORDER_CAST_NO_TARGET, nil,
			Vector(0, 0, 0), ab, Enum.PlayerOrderIssuer.DOTA_ORDER_ISSUER_PASSED_UNIT_ONLY, courier, false, false, false, false)
		if not ok then
			log("auto: courier order failed: %s", tostring(err))
		end
		return ok
	end

	local function auto_courier(hero, now)
		if cfg.abuy_cour ~= 1 or now < (G.cour_at or 0) or G.sec_trip then
			return
		end
		local stash = stash_count(hero)
		if stash == 0 then
			G.cour_tries, G.cour_stash = 0, nil
			return
		end
		local courier = Couriers.GetLocal()
		local free = false
		for slot = 0, K.MAIN_LAST + K.BACKPACK do
			if not NPC.GetItemByIndex(hero, slot) then
				free = true
			end
		end
		if not courier or not Entity.IsAlive(courier) or not free then
			return
		end
		local st = Courier.GetCourierState(courier)
		if st ~= Enum.CourierState.COURIER_STATE_AT_BASE and st ~= Enum.CourierState.COURIER_STATE_IDLE then
			return
		end
		G.cour_tries = G.cour_stash == stash and (G.cour_tries or 0) + 1 or 0
		if G.cour_tries >= K.COURIER_TRIES then
			G.cour_at, G.cour_tries, G.cour_stash = now + K.COURIER_BACKOFF, 0, nil
			log("auto: courier did not take %d stash items, waiting %d s", stash, K.COURIER_BACKOFF)
			return
		end
		local ab = NPC.GetAbility(courier, "courier_take_stash_and_transfer_items")
		if ab and Ability.IsReady(ab) and G.courier_order(courier, ab) then
			G.cour_at, G.cour_stash = now + K.COURIER_EVERY, stash
			log("auto: courier sent with %d stash items", stash)
		end
	end

	local function in_secret(unit)
		for _, shop in ipairs({ Enum.ShopType.DOTA_SHOP_SECRET, Enum.ShopType.DOTA_SHOP_SECRET2 }) do
			local ok, v = pcall(NPC.IsInRangeOfShop, unit, shop)
			if ok and v then
				return true
			end
		end
		return false
	end

	local function is_secret(name)
		local it = I.by_name[name]
		local learned = type(store.data.secret) == "table" and store.data.secret[name] == true
		return it ~= nil and (it.secret or learned)
	end

	local function courier_cast(courier, name)
		local ab = NPC.GetAbility(courier, name)
		if ab and Ability.IsReady(ab) then
			return G.courier_order(courier, ab)
		end
		return false
	end

	local function secret_run(sec, now)
		local courier = Couriers.GetLocal()
		local names = {}
		for _, it in ipairs(sec) do
			names[#names + 1] = it.name
		end
		local note = table.concat(names, ", ")
		if cfg.abuy_cour ~= 1 or not courier or not Entity.IsAlive(courier) then
			if G.sec_note ~= note then
				G.sec_note = note
				log("auto: %s only at the secret shop, courier is %s", note, cfg.abuy_cour ~= 1 and "off" or "dead")
			end
			return {}
		end
		if in_secret(courier) then
			local used = 0
			for slot = 0, K.COURIER_SLOTS - 1 do
				if NPC.GetItemByIndex(courier, slot) then
					used = used + 1
				end
			end
			local out = {}
			for _, it in ipairs(sec) do
				if used + #out < K.COURIER_SLOTS then
					out[#out + 1] = { id = it.id, name = it.name, unit = courier }
				end
			end
			G.sec_trip, G.sec_wait = true, nil
			return out
		end
		if now < (G.sec_at or 0) then
			return {}
		end
		local st = Courier.GetCourierState(courier)
		if st == Enum.CourierState.COURIER_STATE_AT_BASE or st == Enum.CourierState.COURIER_STATE_IDLE
			or st == Enum.CourierState.COURIER_STATE_RETURNING_TO_BASE then
			if courier_cast(courier, "courier_go_to_secretshop") then
				G.sec_at, G.sec_trip, G.sec_wait = now + K.SECRET_EVERY, true, nil
				log("auto: courier goes to the secret shop for %s", note)
				G.rec("auto", { "secret", note })
			end
		end
		return {}
	end

	local function secret_finish(hero, now, pending)
		if not G.sec_trip or pending or now < (G.sec_at or 0) then
			return
		end
		local courier = Couriers.GetLocal()
		if not courier or not Entity.IsAlive(courier) then
			G.sec_trip = nil
			return
		end
		local st = Courier.GetCourierState(courier)
		if not in_secret(courier) then
			if st ~= Enum.CourierState.COURIER_STATE_MOVING and st ~= Enum.CourierState.COURIER_STATE_GOING_TO_SECRET_SHOP then
				G.sec_trip = nil
			end
			return
		end
		local mine, my_id = 0, Player.GetPlayerID(Players.GetLocal())
		for slot = 0, K.COURIER_SLOTS - 1 do
			local it = NPC.GetItemByIndex(courier, slot)
			if it then
				local okid, pid = pcall(Item.GetPlayerOwnerID, it)
				if not okid or pid == my_id then
					mine = mine + 1
				end
			end
		end
		if mine > 0 and Entity.IsAlive(hero) then
			if courier_cast(courier, "courier_transfer_items") then
				G.sec_at, G.sec_trip = now + K.SECRET_EVERY, nil
				log("auto: courier brings %d secret shop items", mine)
			end
		elseif mine == 0 then
			G.sec_wait = G.sec_wait or now
			if now - G.sec_wait >= K.SECRET_IDLE and courier_cast(courier, "courier_return_to_base") then
				G.sec_at, G.sec_trip, G.sec_wait = now + K.SECRET_EVERY, nil, nil
				log("auto: nothing to buy at the secret shop, courier returns")
			end
		end
	end

	local function start_ready(now)
		if not (G.bpos_note or "game"):find("^game") then
			return true
		end
		local key = tostring(G.match)
		if G.start_wait_m ~= key then
			G.start_wait_m, G.start_wait = key, now + K.START_POS_WAIT
			log("auto: start items wait up to %d s for the position from the draft", K.START_POS_WAIT)
		end
		return now >= G.start_wait
	end

	local function fit_list(list, hero, home)
		local team, stock, kept = Entity.GetTeamNum(hero), {}, {}
		local key = tostring(G.match)
		if G.stock_log_m ~= key then
			G.stock_log_m, G.stock_log = key, {}
		end
		for _, it in ipairs(list) do
			local ok = true
			if K.STOCKED[it.name] then
				if stock[it.name] == nil then
					local oks, n = pcall(GameRules.GetStockCount, it.id, team)
					stock[it.name] = oks and tonumber(n) or 99
				end
				ok = stock[it.name] > 0
				stock[it.name] = stock[it.name] - 1
			end
			if ok then
				kept[#kept + 1] = it
			elseif not G.stock_log[it.name] then
				G.stock_log[it.name] = true
				log("auto: %s is out of stock, skipped", it.name)
			end
		end
		if not home then
			local free = math.max(0, K.STASH_SLOTS - stash_count(hero))
			while #kept > free do
				table.remove(kept)
			end
		end
		return kept
	end

	G.fit_list, G.in_secret, G.is_secret = fit_list, in_secret, is_secret

	local function part_count(item, name, depth)
		local n = 0
		for _, part in ipairs(item.parts) do
			local p = I.by_name[part]
			if part == name then
				n = n + 1
			elseif p and depth < 3 then
				n = n + part_count(p, name, depth + 1)
			end
		end
		return n
	end

	local function where_items(hero)
		local inv, cour = {}, {}
		for slot = 0, K.TP_SLOT do
			local it = NPC.GetItemByIndex(hero, slot)
			if it then
				inv[#inv + 1] = slot .. ":" .. tostring(item_name(it))
			end
		end
		local courier = Couriers.GetLocal()
		if courier then
			for slot = 0, K.ENEMY_INV_LAST do
				local it = NPC.GetItemByIndex(courier, slot)
				if it then
					local okid, pid = pcall(Item.GetPlayerOwnerID, it)
					cour[#cour + 1] = tostring(item_name(it)) .. "@" .. tostring(okid and pid)
				end
			end
		end
		local okm, me = pcall(Player.GetPlayerID, Players.GetLocal())
		return ("me %s, hero [%s], courier [%s]"):format(tostring(okm and me), table.concat(inv, " "), table.concat(cour, " "))
	end

	local function rebuy_note(target, names, hero)
		local item = I.by_name[target]
		if not item then
			return
		end
		local key = tostring(G.match)
		if G.auto_hist_m ~= key then
			G.auto_hist_m, G.auto_hist = key, {}
		end
		local hist = G.auto_hist[target] or {}
		G.auto_hist[target] = hist
		for _, name in ipairs(names) do
			hist[name] = (hist[name] or 0) + 1
			local need = part_count(item, name, 0)
			if need > 0 and hist[name] > need then
				log("auto: %s bought again for %s (%d of %d), owned %d; %s", name, target, hist[name], need,
					(G.owned or {})[name] or 0, where_items(hero))
			end
		end
	end

	function G.auto_tick()
		if cfg.autobuy ~= 1 or cfg.live ~= 1 or not G.live or G.buyq then
			return
		end
		local now = os.clock()
		if now < (G.auto_at or 0) then
			return
		end
		G.auto_at = now + K.AUTO_EVERY
		local plan, hero, player = G.plan, Heroes.GetLocal(), Players.GetLocal()
		if not plan or plan.none or not hero or not player then
			return
		end
		local gs = GameRules.GetGameState()
		local pre = gs == Enum.GameState.DOTA_GAMERULES_STATE_PRE_GAME
		if GameRules.IsPaused() or (not pre and gs ~= Enum.GameState.DOTA_GAMERULES_STATE_GAME_IN_PROGRESS) then
			return
		end
		if now < (G.auto_sent or 0) + K.AUTO_SETTLE or (G.read_at or 0) < (G.auto_sent or 0) + 0.3 then
			return
		end
		local okm, gold = pcall(Player.GetTotalGold, player)
		gold = okm and tonumber(gold) or 0
		local last = G.auto_last
		if last then
			G.auto_last = nil
			local got = false
			for name, n in pairs(G.owned or {}) do
				if n > (last.owned[name] or 0) then
					got = true
					break
				end
			end
			if gold > last.gold - 25 and not got then
				G.auto_fail = G.auto_fail or {}
				for _, name in ipairs(last.names) do
					G.auto_fail[name] = now + K.AUTO_FAIL_SKIP
					local it = I.by_name[name]
					if it and #it.parts == 0 and not it.secret and not K.STOCKED[name] then
						local learned = type(store.data.secret) == "table" and store.data.secret[name]
						if last.courier and learned then
							store.data.secret[name] = nil
							log("auto: %s did not sell at the secret shop either, back to the normal shop", name)
						elseif not last.courier and not last.at_secret and not learned then
							G.sec_fail = G.sec_fail or {}
							G.sec_fail[name] = (G.sec_fail[name] or 0) + 1
							if G.sec_fail[name] >= K.SECRET_LEARN then
								store.data.secret = type(store.data.secret) == "table" and store.data.secret or {}
								store.data.secret[name] = true
								G.auto_fail[name] = nil
								log("auto: %s failed %d times away from the secret shop, the courier buys it there now", name,
									G.sec_fail[name])
							end
						end
					end
				end
				log("auto: purchase did not go through: %s", table.concat(last.names, ", "))
				G.rec("auto", { "fail", table.concat(last.names, ",") })
			end
		end
		local alive = Entity.IsAlive(hero)
		local home = NPC.IsInRangeOfShop(hero, Enum.ShopType.DOTA_SHOP_HOME)
		if alive and not home then
			auto_courier(hero, now)
		end
		local lift = plan.lift
		if lift and alive and not pre and cfg.abuy_sell == 1 and now >= (G.lift_at or 0) then
			local okn, near = pcall(Entity.GetHeroesInRadius, hero, K.LIFT_SAFE)
			if home or (okn and type(near) == "table" and #near == 0) then
				local x_it, dest
				for slot = K.MAIN_LAST + 1, K.MAIN_LAST + K.BACKPACK do
					local it = NPC.GetItemByIndex(hero, slot)
					if not x_it and it and item_name(it) == lift.name then
						x_it = it
					end
				end
				for slot = 0, K.MAIN_LAST do
					local it = NPC.GetItemByIndex(hero, slot)
					if not dest and ((lift.out and it and item_name(it) == lift.out) or (not lift.out and not it)) then
						dest = slot
					end
				end
				if x_it and dest then
					G.lift_at = now + K.LIFT_GAP
					G.lift_try = G.lift_try or {}
					G.lift_try[lift.name] = (G.lift_try[lift.name] or 0) + 1
					G.bagged = G.bagged or {}
					if G.lift_try[lift.name] > K.LIFT_TRIES then
						G.bagged[lift.name] = true
						log("auto: %s stays in the backpack, moving it did not work %d times", lift.name, K.LIFT_TRIES)
						return
					end
					auto_order(Enum.UnitOrder.DOTA_UNIT_ORDER_MOVE_ITEM, x_it, hero, dest)
					if lift.out then
						G.bagged[lift.out] = true
					end
					log("auto: %s from the backpack to slot %d%s", lift.name, dest, lift.out and (", " .. lift.out .. " to the backpack") or "")
					G.rec("auto", { "lift", lift.name, lift.out or "-", gold })
					return
				end
			end
		end
		local reserve = pre and 0 or bb_reserve()
		G.reserve = reserve
		local budget = gold - reserve
		local list, target = {}, nil
		if pre and plan.start and not plan.start.done then
			if not start_ready(now) then
				return
			end
			local used = {}
			for _, st in ipairs(plan.start.items) do
				local item = I.by_name[st.name]
				for _ = 1, math.max(0, st.q - st.have) do
					if item and not failed(item) and budget > 0 then
						budget = budget - buy_list(item, budget, used, list, 0, G.data)
					end
				end
			end
			target = "start"
		end
		if not pre and not home and stash_count(hero) >= K.STASH_MAX then
			if not G.stash_full then
				G.stash_full = true
				log("auto: stash is full, waiting for the courier")
			end
			return
		end
		G.stash_full = nil
		if #list == 0 and not pre and cfg.abuy_tp == 1 and not G.owned.tpscroll then
			local tp = NPC.GetItemByIndex(hero, K.TP_SLOT)
			local it = I.by_name.tpscroll
			if not (tp and item_name(tp) == "tpscroll") and it and it.cost <= budget and not failed(it) then
				list[1], target = { id = it.id, name = it.name }, "tpscroll"
				budget = budget - it.cost
			end
		end
		if G.rep_buy and (G.owned[G.rep_buy] or 0) > 0 then
			log("auto: replacement %s is in place", G.rep_buy)
			G.rep_buy = nil
		end
		local rep = plan.replace
		if #list == 0 and not pre and cfg.abuy_swap == 1 and cfg.abuy_sell == 1 and rep and (home or in_secret(hero)) and alive
			and not G.rep_buy then
			local s_it = find_item(hero, rep.old.name)
			local need = rep.new.cost - progress(rep.new, {}, 0)
			if s_it and Item.IsSellable(s_it) and budget + math.floor(rep.old.cost / 2) >= need then
				auto_order(Enum.UnitOrder.DOTA_UNIT_ORDER_SELL_ITEM, s_it, hero)
				G.rep_buy = rep.new.name
				log("auto: replace %s with %s, need %d, gold %d", rep.old.name, rep.new.name, need, gold)
				G.rec("auto", { "replace", rep.old.name, rep.new.name, gold })
				return
			end
		end
		if #list == 0 and not pre and plan.need_dust and not G.owned.dust then
			local it = I.by_name.dust
			if it and it.cost <= budget and not failed(it) then
				list[1], target = { id = it.id, name = it.name }, "dust (team has no detection)"
			end
		end
		if #list == 0 and not pre and G.rep_buy and I.by_name[G.rep_buy] then
			buy_list(I.by_name[G.rep_buy], budget, {}, list, 0, G.data)
			if #list > 0 then
				target = G.rep_buy .. " (replacement)"
			end
		end
		local d = plan.next
		local item = d and I.by_name[d.name]
		local partial = false
		if #list == 0 and item and not pre and d.base and d.kind == "dis" then
			local base_it = find_item(hero, d.base.name)
			if base_it and Item.IsDisassemblable(base_it) then
				local shared, fake = 0, {}
				for name, n in pairs(G.owned) do
					fake[name] = n
				end
				for _, part in ipairs((I.by_name[d.base.name] or {}).parts or {}) do
					local p = I.by_name[part]
					if p and I.contains(item, part) then
						shared = shared + p.cost
						fake[part] = (fake[part] or 0) + 1
					end
				end
				local need = item.cost - progress(item, {}, 0) - shared
				if budget >= need then
					auto_order(Enum.UnitOrder.DOTA_UNIT_ORDER_DISASSEMBLE_ITEM, base_it, hero)
					log("auto: disassemble %s for %s, need %d, gold %d", d.base.name, d.name, need, gold)
					G.rec("auto", { "disassemble", d.base.name, d.name, gold })
					return
				end
				local saved = G.owned
				G.owned = fake
				local ok, err = pcall(buy_list, item, budget, {}, list, 0, G.data)
				G.owned = saved
				if not ok then
					log("auto: parts for %s failed: %s", d.name, tostring(err))
				end
				partial, target = true, d.name .. " (before disassembling " .. d.base.name .. ")"
			end
		end
		if #list == 0 and item and not pre and not partial then
			local sell = d.sell
			if cfg.abuy_sell == 1 and sell and alive then
				local s_it, slot = find_main(hero, sell.name), free_bag(hero)
				local short = item.cost - progress(item, {}, 0)
				local value = math.floor(((I.by_name[sell.name] or {}).cost or 0) / 2)
				local shop = home or in_secret(hero)
				local act, why
				if not s_it then
					why = "not in the main slots"
				elseif (sell.bag or not shop) and slot and short <= budget then
					act = "bag"
				elseif not sell.bag and shop and Item.IsSellable(s_it) and short <= budget + value then
					act = "sell"
				elseif short > budget + ((sell.bag or not shop) and 0 or value) then
					why = "not enough gold yet"
				else
					why = shop and "not sellable" or "away from a shop with a full backpack"
				end
				if act == "bag" then
					auto_order(Enum.UnitOrder.DOTA_UNIT_ORDER_MOVE_ITEM, s_it, hero, slot)
					G.bagged = G.bagged or {}
					G.bagged[sell.name] = true
					log("auto: %s to backpack slot %d to make room for %s", sell.name, slot, d.name)
					G.rec("auto", { "bag", sell.name, d.name, gold })
					return
				elseif act == "sell" then
					auto_order(Enum.UnitOrder.DOTA_UNIT_ORDER_SELL_ITEM, s_it, hero)
					log("auto: sell %s to make room for %s, gold %d + %d", sell.name, d.name, budget, value)
					G.rec("auto", { "sell", sell.name, d.name, gold })
					return
				end
				local note = sell.name .. " for " .. d.name .. ": " .. why
				if note ~= G.room_wait then
					G.room_wait = note
					log("auto: room waits, %s (gold %d, missing %d, shop %s)", note, budget, short, tostring(shop))
				end
			end
			buy_list(item, budget, {}, list, 0, G.data)
			target = d.name
		end
		local via, pending = {}, false
		local at_secret = in_secret(hero)
		if #list > 0 and not pre and not at_secret then
			local normal, sec = {}, {}
			for _, it in ipairs(list) do
				if is_secret(it.name) then
					sec[#sec + 1] = it
				else
					normal[#normal + 1] = it
				end
			end
			if #sec > 0 then
				list, pending = normal, true
				via = secret_run(sec, now)
			end
		end
		secret_finish(hero, now, pending)
		list = fit_list(list, hero, home)
		for _, it in ipairs(via) do
			list[#list + 1] = it
		end
		if #list == 0 then
			return
		end
		local names = {}
		for _, it in ipairs(list) do
			names[#names + 1] = it.name
		end
		rebuy_note(target, names, hero)
		G.buyq, G.buy_at = list, 0
		G.auto_sent = now + #list * K.BUY_GAP
		G.auto_last = { gold = gold, names = names, owned = copy(G.owned or {}), courier = #via > 0, at_secret = at_secret }
		log("auto: %s <- [%s], gold %d, kept %d%s", tostring(target), table.concat(names, ", "), gold, reserve,
			#via > 0 and (", courier at the secret shop buys " .. #via) or "")
		G.rec("auto", { "buy", tostring(target), table.concat(names, ","), gold, reserve })
	end

	local function can_up(ab)
		local ok, v = pcall(Ability.CanBeUpgraded, ab)
		if not G.skill_probe then
			G.skill_probe = true
			log("skill: CanBeUpgraded returns %s %s", type(v), tostring(v))
		end
		if not ok or not (v == true or v == 0) then
			return false
		end
		local okh, hidden = pcall(Ability.IsHidden, ab)
		local okn, name = pcall(Ability.GetName, ab)
		return not (okh and hidden and not (okn and name == K.ATTR_BONUS)) and Ability.GetLevel(ab) < Ability.GetMaxLevel(ab)
			and os.clock() >= ((G.skill_fail or {})[Ability.GetName(ab)] or 0)
	end

	local function pick_skill(hero, base)
		local abil, talent_list, tier_of, sib = {}, {}, {}, {}
		for i = 0, K.REC_ABIL_LAST do
			local ab = NPC.GetAbilityByIndex(hero, i)
			local okn, name = pcall(Ability.GetName, ab)
			if ab and okn and type(name) == "string" and not Ability.IsInnate(ab) then
				abil[name] = ab
				if name ~= K.ATTR_BONUS and name:find("^special_bonus") then
					talent_list[#talent_list + 1] = ab
				end
			end
		end
		if #talent_list == 2 * #K.TALENT_TIERS then
			for i, ab in ipairs(talent_list) do
				tier_of[ab] = K.TALENT_TIERS[(i + 1) // 2]
				sib[ab] = talent_list[i % 2 == 1 and i + 1 or i - 1]
			end
		end
		if not abil[K.ATTR_BONUS] then
			local oka, ab = pcall(NPC.GetAbility, hero, K.ATTR_BONUS)
			if oka and ab then
				abil[K.ATTR_BONUS] = ab
			end
		end
		local lvl = NPC.GetCurrentLevel(hero)
		local function talent_ok(ab)
			local failed = (G.skill_fail_lv or {})[Ability.GetName(ab)]
			if failed and lvl <= failed then
				return false
			end
			if tier_of[ab] then
				if lvl < tier_of[ab] then
					return false
				end
				local k = 0
				for i, f in ipairs(K.TALENT_TIERS) do
					if f == tier_of[ab] then
						k = i
					end
				end
				if Ability.GetLevel(sib[ab]) > 0 and lvl < K.TALENT_ALL + k - 1 then
					return false
				end
			end
			return can_up(ab)
		end
		local seq, talents = base.skills or {}, base.talents or {}
		if #seq == 0 then
			return nil, "no data"
		end
		local count, by_from = {}, {}
		for _, t in ipairs(talents) do
			by_from[t.from] = t
		end
		for _, s in ipairs(seq) do
			if s.talent then
				local from = s.tier
				for _, f in ipairs(from and {} or K.TALENT_TIERS) do
					if s.lv >= f then
						from = f
					end
				end
				local t = from and by_from[from]
				local ab = t and abil[t.name]
				if ab and Ability.GetLevel(ab) == 0 and talent_ok(ab) then
					return ab, "plan talent " .. from
				end
			else
				count[s.name] = (count[s.name] or 0) + 1
				local ab = abil[s.name]
				if ab and Ability.GetLevel(ab) < count[s.name] and can_up(ab) then
					return ab, "plan " .. s.lv
				end
			end
		end
		for k, t in ipairs(talents) do
			local ab = abil[t.name]
			if ab and Ability.GetLevel(ab) == 0 and talent_ok(ab) then
				return ab, "talent " .. k
			end
		end
		local best, best_v
		for name, ab in pairs(abil) do
			if not name:find("^special_bonus") and can_up(ab) then
				local v = (Ability.GetMaxLevel(ab) <= 3 and 100 or 0) + (count[name] or 0) * 10 - Ability.GetLevel(ab)
				if not best or v > best_v then
					best, best_v = ab, v
				end
			end
		end
		if best then
			return best, "after plan"
		end
		for _, ab in ipairs(talent_list) do
			if Ability.GetLevel(ab) == 0 and talent_ok(ab) then
				return ab, "talent fallback"
			end
		end
		local attr = abil[K.ATTR_BONUS]
		if attr and can_up(attr) then
			return attr, "attributes"
		end
		if attr then
			local okc, v = pcall(Ability.CanBeUpgraded, attr)
			local okl, al = pcall(Ability.GetLevel, attr)
			local okm, am = pcall(Ability.GetMaxLevel, attr)
			al, am = okl and al or 0, okm and am or 0
			if not G.attr_probe then
				G.attr_probe = true
				log("skill: attributes CanBeUpgraded %s %s, level %s of %s", tostring(okc), tostring(v), tostring(al), tostring(am))
			end
			if al < math.max(am, 7) and lvl >= 2 and os.clock() >= ((G.skill_fail or {})[K.ATTR_BONUS] or 0) then
				return attr, "attributes (forced)"
			end
		else
			if not G.attr_probe then
				G.attr_probe = true
				log("skill: hero has no %s ability", K.ATTR_BONUS)
			end
		end
		return nil, nil
	end

	function G.skill_tick()
		if cfg.askill ~= 1 or cfg.live ~= 1 or not G.live then
			return
		end
		local now = os.clock()
		if now < (G.skill_at or 0) then
			return
		end
		G.skill_at = now + K.SKILL_EVERY
		local hero, base = Heroes.GetLocal(), G.base
		if not hero or not base or base.none then
			return
		end
		local paused = GameRules.IsPaused()
		local okn, pts = pcall(Hero.GetAbilityPoints, hero)
		pts = okn and tonumber(pts) or 0
		local last = G.skill_last
		if last then
			G.skill_last = nil
			local okl, lvl = pcall(Ability.GetLevel, last.ab)
			if pts >= last.pts and (not okl or (tonumber(lvl) or 0) <= last.lvl) then
				G.skill_fail, G.skill_fail_lv = G.skill_fail or {}, G.skill_fail_lv or {}
				local talent = last.name ~= K.ATTR_BONUS and last.name:find("^special_bonus") ~= nil
				if talent then
					G.skill_fail_lv[last.name] = NPC.GetCurrentLevel(hero)
				else
					G.skill_fail[last.name] = now + K.SKILL_FAIL_SKIP
				end
				log("skill: %s did not level, %s", last.name, talent and "trying it again at the next hero level"
					or ("skipping it for " .. K.SKILL_FAIL_SKIP .. " s"))
			end
		end
		if paused or pts <= 0 then
			return
		end
		local ab, why = pick_skill(hero, base)
		if not ab then
			local note = pts .. tostring(why)
			if G.skill_note ~= note then
				G.skill_note = note
				log("skill: %d points, nothing to learn (%s)", pts, tostring(why or "all done"))
			end
			return
		end
		local name = Ability.GetName(ab)
		local ok, err = pcall(Player.PrepareUnitOrders, Players.GetLocal(), Enum.UnitOrder.DOTA_UNIT_ORDER_TRAIN_ABILITY, nil,
			Vector(0, 0, 0), ab, Enum.PlayerOrderIssuer.DOTA_ORDER_ISSUER_HERO_ONLY, hero, false, false, false, false)
		if not ok then
			log("skill: order failed: %s", tostring(err))
			return
		end
		G.skill_at = now + K.SKILL_WAIT
		G.skill_last = { ab = ab, name = name, lvl = Ability.GetLevel(ab), pts = pts }
		log("skill: hero level %d -> %s (%s)", NPC.GetCurrentLevel(hero), name, tostring(why))
	end

	local function find_replace(cands, T1, anti, anti_from, data)
		local main, old, old_w, old_mx = G.main or {}, nil, 0, nil
		for _, name in ipairs(main) do
			local item = I.by_name[name]
			local w, mxw = anti[name] or 0, nil
			local mx, list = mx_info(name)
			if mx <= -K.MX_REP and -mx * 10 > w then
				w, mxw = -mx * 10, { mx = mx, top = list[1] }
			end
			if item and not item.consumable and not K.BOOTS[name] and not K.SELL_SKIP[name]
				and w >= K.REP_ANTI and w > old_w then
				old, old_w, old_mx = item, w, mxw
			end
		end
		if not old then
			return nil
		end
		local cover = {}
		for _, name in ipairs(main) do
			if name ~= old.name then
				for threat, w in pairs(K.COUNTERS[name] or {}) do
					cover[threat] = (cover[threat] or 1) * (1 - K.COVER * w)
				end
			end
		end
		local function as_cd(item)
			local cd = cands[item.name]
			if not cd then
				local r = data.rows[item.name]
				cd = { item = item, share = r and I.share(data, r) or 0, rank = r and I.rank(data, r) or 0 }
				cd.mx = mx_info(item.name)
			end
			return cd
		end
		local ocd = copy(as_cd(old))
		ocd.mx = mx_info(old.name)
		ocd.share = math.max(ocd.share or 0, K.MX_MIN_SHARE)
		local cur = value(ocd, T1, cover, anti)
		local pool, best, best_v = {}, nil, nil
		for name in pairs(cands) do
			pool[name] = true
		end
		for name in pairs(K.INSTEAD[old.name] or {}) do
			pool[name] = true
		end
		for name in pairs(pool) do
			local item = I.by_name[name]
			local ok = item and eligible(name, item) and not K.BOOTS[name] and (G.owned[name] or 0) == 0 and (anti[name] or 0) == 0
				and not (name == "ultimate_scepter" and (G.owned.ultimate_scepter_2 or 0) > 0)
				and item.cost >= old.cost * K.REP_COST_LO and not I.related(old, item) and not I.same_line(old.name, name)
			if ok and K.FIT[name] and not I.fits(name, G.hero, G.bpos) then
				ok = false
			end
			if ok then
				for _, o in ipairs(main) do
					local oi = I.by_name[o]
					if oi and o ~= old.name and (oi == item or I.related(oi, item) or (not K.BOOTS[o] and I.siblings(oi, item))) then
						ok = false
					end
				end
			end
			if ok then
				local v = value(as_cd(item), T1, cover, anti)
				if (K.INSTEAD[old.name] or {})[name] then
					v = v + K.INSTEAD_BONUS
				end
				if v - cur >= K.SWAP_MARGIN and (not best or v > best_v or (v == best_v and name < best.name)) then
					best, best_v = item, v
				end
			end
		end
		if not best then
			return nil
		end
		if old_mx then
			local top = old_mx.top or {}
			return { old = old, new = best, gain = best_v - cur, e = top.e, item = top.x, mx = old_mx.mx,
				mx_why = old_mx.top and mx_label(old_mx.top) or "-" }
		end
		local src = anti_from[old.name]
		return { old = old, new = best, gain = best_v - cur, e = src and src.e, item = src and src.item,
			team = K.TEAM_ONE[old.name] ~= nil and (G.team_items or {})[K.TEAM_ONE[old.name]] ~= nil }
	end

	function G.compute()
		I.state_for = { h = G.hero, state = G.state, lane = G.lane and G.lane.opp or nil }
		local base = I.build(G.hero, G.bpos, G.them, G.mates)
		G.base = base
		if not base then
			return nil
		end
		if base.none then
			return { none = true, hero = G.hero, pos = G.bpos, slots = {} }
		end
		local bpos = base.dpos or G.bpos
		local data = I.buys[G.hero].pos[bpos]
		G.data = data
		if #base.slots == 0 then
			return nil
		end
		local adapt = cfg.padapt == 1
		G.mx_cache = {}
		G.lr_have = adapt and I.lr_counts(G.seen, G.ally_items) or nil
		local T0, T1, from, per1 = {}, {}, {}, {}
		for _, e in ipairs(G.them) do
			add_threats(e, T0, {}, false)
			per1[e] = add_threats(e, T1, from, adapt)
		end
		I.team_threats(T0, G.hero)
		I.team_threats(T1, G.hero)
		local own = table.concat(I.self_cover(G.hero).names, ", ")
		if own ~= G.self_note then
			G.self_note = own
			log("own abilities that cover threats: %s", own ~= "" and own or "none")
		end
		local press = adapt and cfg.pdanger == 1 and G.press
		if press and per1[press.e] then
			T1[press.threat] = (T1[press.threat] or 0) + press.w
			per1[press.e][press.threat] = math.min(1, (per1[press.e][press.threat] or 0) + press.w)
			from[#from + 1] = { e = press.e, item = L(press.threat == "phys" and "cd_dmg_attack" or "cd_dmg_spell"),
				threat = press.threat, w = press.w }
		end
		I.leader = adapt and cfg.pdanger == 1 and G.leader and G.leader.e or nil
		G.T1 = T1
		local anti, anti_from = {}, {}
		if adapt then
			for _, e in ipairs(G.them) do
				for name in pairs(G.seen[e] or {}) do
					for target, w in pairs(K.ANTI[name] or {}) do
						if w > (anti[target] or 0) then
							anti[target], anti_from[target] = w, { e = e, item = name }
						end
					end
				end
			end
			for name, group in pairs(K.TEAM_ONE) do
				local mate = G.team_items and G.team_items[group]
				if mate and K.TEAM_DUP_W > (anti[name] or 0) then
					anti[name], anti_from[name] = K.TEAM_DUP_W, mate
				end
			end
		end
		local slots = {}
		for i, cd in ipairs(base.slots) do
			slots[i] = copy(cd)
		end
		place_owned(slots, data, T1, anti)
		local cands = I.collect(data, G.them, bpos, G.mates, G.hero)
		local live = cfg.live == 1
		if live then
			local behind = G.state == "behind"
			local dx = 0
			for _, e in ipairs(G.them) do
				local w = G.dps_w and G.dps_w[e]
				if w then
					local prior = I.threats(e).phys or 0
					dx = dx + math.max(w, prior * K.PHYS_PRIOR_KEEP) - prior
				end
			end
			dx = clamp(dx, -1, 1)
			if math.abs(dx - (G.phys_dx or 0)) >= K.DPS_DX_LOG then
				G.phys_dx = dx
				log("phys threat from enemy dps vs draft: %+.2f", dx)
			end
			local cnt = K.CNT[(G.bpos or 1) <= 3 and "core" or "sup"]
			local function adjust(cd)
				local r = cd.r or data.rows[cd.item.name]
				if not r or cd.core or cd.bought or owns(cd.item) then
					return
				end
				local timing = cd.timing or I.timing(data, r)
				local b = cd.behind or I.behind(data, r)
				local lift
				cd.lift_src = nil
				if behind and b then
					lift = I.lift(data, r) + K.BEHIND_W * b.lift
					cd.lift_src = "behind"
				elseif not behind and timing and timing.gap >= K.TIMING_GAP and (G.ptime or 0) > r.t + K.LATE_GRACE then
					lift = timing.off_lift
					cd.lift_src = "late"
				end
				local extra = (G.solo or cfg.solo == 1) and K.SOLO[(G.bpos or 1) <= 3 and "core" or "sup"][cd.item.name] or 0
				if extra ~= 0 then
					lift = (lift or I.lift(data, r)) + extra
					cd.solo, cd.solo_v = true, extra
				end
				local mx, rk = 0, 1
				if adapt then
					local list
					mx, list = mx_info(cd.item.name)
					if mx ~= 0 then
						cd.mx, cd.mx_top = mx, list[1]
					end
					local rtop
					rk, rtop = I.react_k(cd.item.name, G.bpos, cd.share or I.share(data, r), G.lr_have)
					cd.rk, cd.rtop = rk, rtop
				end
				local row = cnt[cd.item.name]
				local dk = (row and row.phys and dx ~= 0) and row.phys ^ dx or 1
				cd.dk = dk ~= 1 and dk or nil
				if not lift and mx == 0 and rk == 1 and dk == 1 then
					return
				end
				local rank = lift and I.rank_with(data, r, lift) * (cd.vk or 1) * (cd.tk or 1) or cd.rank or I.rank(data, r)
				rank = rank * rk * dk
				cd.adj = rank - (cd.rank or rank) + K.MX_W * mx
				cd.rank = rank
			end
			for _, cd in pairs(cands) do
				adjust(cd)
			end
			for _, s in ipairs(slots) do
				adjust(s)
			end
			local rl = {}
			for name, cd in pairs(cands) do
				if cd.rk and math.abs(math.log(cd.rk)) >= 0.2 then
					rl[#rl + 1] = { name = name, k = cd.rk, x = cd.rtop and cd.rtop.x or "-" }
				end
			end
			table.sort(rl, function(a, b)
				if math.abs(math.log(a.k)) ~= math.abs(math.log(b.k)) then
					return math.abs(math.log(a.k)) > math.abs(math.log(b.k))
				end
				return a.name < b.name
			end)
			for n = #rl, 9, -1 do
				rl[n] = nil
			end
			for n, x in ipairs(rl) do
				rl[n] = ("%s x%.2f (%s)"):format(x.name, x.k, x.x)
			end
			local line = table.concat(rl, ", ")
			if line ~= (G.lr_logged or "") then
				G.lr_logged = line
				log("react model: %s", line == "" and "-" or line)
			end
		end
		if adapt then
			swap_slots(slots, cands, T0, T1, from, anti, anti_from)
			local function locked(sl)
				return sl.core or sl.bought or owns(sl.item) or progress(sl.item, {}, 0, cfg.autobuy == 1 and 1 or K.SIGNAL_MIN) > 0
			end
			for _, new in ipairs(I.must(slots, cands, T1, per1, G.them, G.hero, bpos, locked)) do
				new.swapped, new.from = true, new.replaced
				new.reason = reason_for(new, from)
			end
			local function locked_hard(sl)
				return sl.bought or owns(sl.item) or progress(sl.item, {}, 0, cfg.autobuy == 1 and 1 or K.SIGNAL_MIN) > 0
			end
			for _, new in ipairs(I.react(slots, cands, G.them, G.seen, G.hero, bpos, locked, live and locked_hard or nil, T1)) do
				new.swapped, new.from = true, new.replaced
				new.urgent = K.REACT_URGENT[new.must] or nil
			end
			if I.guard_note ~= G.guard_note then
				G.guard_note = I.guard_note
				log("react guard: %s", tostring(I.guard_note))
			end
			local notes = {}
			for _, sl in ipairs(slots) do
				if sl.swapped then
					local hero = sl.reason and D.by_id[sl.reason.e]
					notes[#notes + 1] = ("%s -> %s (%s %s)"):format(sl.from and sl.from.name or "?", sl.item.name,
						hero and hero.name or "-", sl.reason and sl.reason.item or sl.adj_why or "-")
				end
			end
			local note = table.concat(notes, "; ")
			if note ~= G.swap_note then
				G.swap_note = note
				log("panel swaps: %s", note ~= "" and note or "none")
				G.rec("swaps", { note ~= "" and note or "none" })
			end
			G.toasted = G.toasted or {}
			for _, sl in ipairs(slots) do
				local src = sl.reason and I.by_name[sl.reason.item]
				local key = sl.urgent and src and sl.item.name .. ":" .. src.name
				if key and not G.toasted[key] and not owns(sl.item) then
					G.toasted[key] = true
					local hero = D.by_id[sl.reason.e]
					W.ptoast = { key = "cd_counter_toast", t = os.clock(), life = K.COUNTER_TOAST,
						arg = L("cd_counter_vs"):format(sl.item.label, src.label, hero and hero.name or "?") }
					log("counter toast: %s for %s", sl.item.name, src.name)
				end
			end
		end
		local replace = adapt and live and find_replace(cands, T1, anti, anti_from, data) or nil
		local rnote = replace and ("%s -> %s"):format(replace.old.name, replace.new.name) or "-"
		if rnote ~= G.rep_note then
			G.rep_note = rnote
			log("replace: %s (%s, gain %.2f)", rnote, replace and (replace.team and "ally has it" or tostring(replace.item)) or "-",
				replace and replace.gain or 0)
			G.rec("replace", { replace and replace.old.name or "-", replace and replace.new.name or "-",
				replace and tostring(replace.item or "-") or "-" })
		end
		table.sort(slots, function(a, b)
			if a.t ~= b.t then
				return a.t < b.t
			end
			return a.item.cost < b.item.cost
		end)
		local steps = {}
		for _, sl in ipairs(slots) do
			if sl.pre then
				steps[#steps + 1] = { s = sl, item = sl.pre.item, t = sl.pre.t, pre = true }
			end
			steps[#steps + 1] = { s = sl, item = sl.item, t = sl.urgent and math.min(sl.t, math.floor(G.ptime or 0)) or sl.t,
				via = sl.pre and sl.pre.item }
			if sl.after then
				steps[#steps + 1] = { s = sl, item = sl.after.item, t = sl.after.t, base = sl.item, kind = sl.after_kind }
			end
		end
		for _, e in ipairs(base.early or {}) do
			steps[#steps + 1] = { item = e.item, t = e.t, early = e }
		end
		if live then
			for _, e in ipairs(base.extras or {}) do
				steps[#steps + 1] = { item = e.item, t = e.t, extra = e, base = e.base, kind = e.kind }
			end
		end
		local scepter, blessing = I.by_name.ultimate_scepter, I.by_name.ultimate_scepter_2
		if live and scepter and blessing and (G.owned.ultimate_scepter or 0) > 0 and (G.owned.ultimate_scepter_2 or 0) == 0 then
			local have = false
			for _, st in ipairs(steps) do
				if st.item == blessing then
					have = true
				end
			end
			local r = data.rows.ultimate_scepter_2
			local hard = 0
			for _, name in ipairs(G.main or {}) do
				local it = I.by_name[name]
				if it and not it.consumable and it.cost >= K.SELL_SOFT_COST then
					hard = hard + 1
				end
			end
			if not have and ((r and r.n >= K.SHOW_MIN and (G.ptime or 0) >= r.t) or hard >= K.SLOTS) then
				local body = L("cd_tip_bless"):format(scepter.label)
				steps[#steps + 1] = { item = blessing, t = math.max(r and r.t or 0, math.floor(G.ptime or 0)), base = scepter, kind = "up",
					extra = { body = body, kind = "up" } }
			end
		end
		local function by_time(a, b)
			if a.t ~= b.t then
				return a.t < b.t
			end
			return (a.base and 1 or 0) < (b.base and 1 or 0)
		end
		table.sort(steps, by_time)
		local function step_done(st)
			if st.base or st.pre or st.early or st.extra or st.late or st.ext or st.own then
				return owns(st.item)
			end
			return st.s.bought or owns(st.item)
		end
		if live and #(base.late or {}) > 0 then
			local open, started = false, false
			for _, st in ipairs(steps) do
				if not step_done(st) then
					open = true
				end
			end
			for _, lt in ipairs(base.late) do
				if owns(lt.item) then
					started = true
				end
			end
			if not open or started or G.solo == "4v5" then
				for _, lt in ipairs(base.late) do
					steps[#steps + 1] = { item = lt.item, t = lt.t, late = lt }
				end
				table.sort(steps, by_time)
			end
		end
		if live and cfg.pext == 1 and #(base.ext or {}) > 0 then
			local open, last_t = false, 0
			for _, st in ipairs(steps) do
				if not step_done(st) then
					open = true
				end
				last_t = math.max(last_t, st.t or 0)
			end
			if not open then
				local cover, list = coverage(slots), {}
				for _, e in ipairs(base.ext) do
					list[#list + 1] = { e = e, v = value(cands[e.item.name] or e.cd, T1, cover, anti) }
				end
				table.sort(list, function(a, b)
					if a.v ~= b.v then
						return a.v > b.v
					end
					return a.e.item.name < b.e.item.name
				end)
				for i, x in ipairs(list) do
					steps[#steps + 1] = { item = x.e.item, t = last_t + i, ext = x.e, base = x.e.base, kind = x.e.base and "up" or nil }
				end
			end
		end
		if live then
			steps = G.own_steps(steps, slots, data, step_done, base)
			table.sort(steps, by_time)
		end
		local listed, uniq = {}, {}
		for _, st in ipairs(steps) do
			if not listed[st.item.name] then
				listed[st.item.name] = true
				uniq[#uniq + 1] = st
			end
		end
		steps = uniq
		local last = 0
		for i, st in ipairs(steps) do
			if step_done(st) then
				last = i
			end
		end
		local order, skipped = {}, {}
		for i, st in ipairs(steps) do
			local done = step_done(st)
			st.have = done and 0 or progress(st.item, {}, 0)
			st.signal = done and 0 or progress(st.item, {}, 0, K.SIGNAL_MIN, (st.base or st.via or {}).name)
			if not done and i < last and st.signal == 0 and not (st.s and st.s.urgent) then
				if not st.early then
					st.skipped = true
					skipped[#skipped + 1] = st
				end
			else
				order[#order + 1] = st
			end
		end
		for _, st in ipairs(skipped) do
			order[#order + 1] = st
		end
		steps = order
		local bare, had_boots, boots_step = (G.owned.boots or 0) == 0, false, nil
		for name in pairs(K.BOOTS) do
			if (G.owned[name] or 0) > 0 then
				bare = false
			end
			if G.ever[name] then
				had_boots = true
			end
		end
		if live and bare and had_boots then
			for _, st in ipairs(steps) do
				if not boots_step and K.BOOTS[st.item.name] and not step_done(st) then
					boots_step = st
				end
			end
		end
		local late_game = live and cfg.pup == 1 and (G.ptime or 0) >= K.UP_FROM
		local ups = live and cfg.pup == 1 and G.inslot(data, steps, anti) or {}
		local weak = late_game and #ups == 0
		local function ext_room(st)
			local hard = (boots_step and st ~= boots_step) and 1 or 0
			for _, name in ipairs(G.main or {}) do
				local it = I.by_name[name]
				if it and (name == (st.base and st.base.name) or I.contains(st.item, name, 0)) then
					return true
				end
				if it and not it.consumable and it.cost >= K.SELL_SOFT_COST then
					hard = hard + 1
				end
			end
			return hard < K.SLOTS or sell_for(st, steps, step_done, base.fates, weak) ~= nil
		end
		local function can(st)
			if step_done(st) or not (st.ext or ((late_game or st.late) and ((st.s and not st.pre) or st.late) and (st.signal or 0) == 0)) then
				return true
			end
			st.blocked = not ext_room(st)
			return not st.blocked
		end
		local function sold_out(st)
			if not live or not K.STOCKED[st.item.name] then
				return false
			end
			local ok, n = pcall(GameRules.GetStockCount, st.item.id, G.team)
			st.sold_out = ok and tonumber(n) == 0
			return st.sold_out
		end
		local target, target_k
		local claimed = {}
		for _, st in ipairs(steps) do
			st.claim = step_done(st) and 0 or progress(st.item, claimed, 0, K.SIGNAL_MIN, (st.base or st.via or {}).name)
		end
		for _, st in ipairs(steps) do
			if not step_done(st) and st.claim > 0 and can(st) and not sold_out(st) then
				local k = st.claim / math.max(1, st.item.cost)
				if not target or k > target_k then
					target, target_k = st, k
				end
			end
		end
		if not target then
			for _, st in ipairs(steps) do
				if not target and not step_done(st) and can(st) and not sold_out(st) then
					target = st
				end
			end
		end
		if boots_step and can(boots_step) and not sold_out(boots_step) then
			target = boots_step
		end
		if not target and #ups > 0 then
			for _, st in ipairs(ups) do
				steps[#steps + 1] = st
				if not target and not sold_out(st) then
					target = st
				end
			end
		end
		if live and target and not (target.base or target.via or target.upg or target.item.consumable) then
			for _, name in ipairs(G.main or {}) do
				local b = I.by_name[name]
				local fate = base.fates and base.fates[name]
				local drop = fate and (fate.sold + (fate.late_drop or 0)) or 0
				if not target.dis and b and K.DISASSEMBLE[name] and drop >= K.SELL_DROP and name ~= target.item.name
					and not I.contains(target.item, name) then
					local needed = false
					for _, o in ipairs(steps) do
						if o ~= target and not step_done(o) and (o.item.name == name or I.contains(o.item, name)) then
							needed = true
						end
					end
					for _, part in ipairs(b.parts) do
						local p = I.by_name[part]
						if not needed and not target.dis and p and p.cost >= K.DIS_MIN and (G.owned[part] or 0) == 0
							and I.contains(target.item, part) then
							target.dis = b
						end
					end
				end
			end
			local dnote = target.dis and (target.dis.name .. " for " .. target.item.name) or "-"
			if dnote ~= G.dis_note then
				G.dis_note = dnote
				log("panel disassemble: %s", dnote)
			end
		end
		local plan = { hero = G.hero, slots = {}, pos = G.bpos, dpos = bpos, since = base.since, pooled = base.pooled }
		local start = { items = {}, gold = base.gold, done = true }
		for _, st in ipairs(base.start) do
			local name = st.item.name
			local have = K.STACK[name] and (G.stacks or {})[name] or G.owned[name] or 0
			if have < st.q and G.ever[name] and G.time > 0 then
				have = st.q
			end
			local d = { name = name, label = st.item.label, cost = st.item.cost, q = st.q, have = math.min(have, st.q) }
			d.state = d.have >= st.q and "done" or "next"
			d.title = st.q > 1 and ("%s x%d"):format(st.item.label, st.q) or st.item.label
			start.done = start.done and d.state == "done"
			start.items[#start.items + 1] = d
		end
		plan.start = #start.items > 0 and start or nil
		for i, st in ipairs(steps) do
			local s = st.s
			local d = { name = st.item.name, label = st.item.label, cost = st.item.cost, t = not (st.ext or st.upg) and st.t or nil }
			if step_done(st) then
				d.state = "done"
			elseif st == target then
				d.state, d.have = "next", st.have
				plan.next = d
			else
				d.state = "later"
			end
			local lines = {}
			if st.own == "start" then
				lines[1] = L("cd_tip_own_start"):format(math.floor((st.own_k or 0) * 100 + 0.5))
			elseif st.own == "up" then
				d.base, d.kind = { name = st.base.name, label = st.base.label }, "up"
				lines[1] = L("cd_tip_own_up"):format(st.base.label, math.floor((st.own_k or 0) * 100 + 0.5))
			elseif st.early then
				lines[1] = st.early.up and L("cd_tip_upgrade"):format(st.early.up.label) or nil
			elseif st.pre then
				lines[1] = L("cd_tip_upgrade"):format(s.item.label)
			elseif st.upg then
				d.base, d.kind = { name = st.base.name, label = st.base.label }, "up"
				lines[1] = L("cd_tip_inslot"):format(st.base.label)
				lines[2] = st.upg.share and L("cd_tip_inslot_pro"):format(math.floor(st.upg.share * 100 + 0.5))
					or (st.upg.fit and L("cd_tip_inslot_attr") or L("cd_tip_inslot_rule"))
			elseif st.base then
				if not (st.kind == "dis" and (G.owned[st.base.name] or 0) == 0) then
					d.base, d.kind = { name = st.base.name, label = st.base.label }, st.kind
					lines[1] = st.extra and st.extra.body or L(st.kind == "up" and "cd_tip_up_from" or "cd_tip_dis_from"):format(st.base.label)
				end
			elseif st.extra then
				lines[1] = st.extra.body
			elseif st.late then
				lines[1] = L("cd_tip_late"):format(math.floor(st.late.share * 100 + 0.5), st.late.g40)
			elseif st.ext then
				lines[1] = L("cd_tip_ext"):format(math.floor(st.ext.share * 100 + 0.5))
			else
				if s.swapped then
					d.from = s.from.label
					lines[1] = L("cd_tip_swap"):format(s.from.label)
					local r = s.reason
					if r then
						local hero = D.by_id[r.e]
						local it = I.by_name[r.item]
						lines[2] = L("cd_tip_swap_why"):format(hero and hero.name or "?", it and it.label or r.item)
						d.reason = r.e
					elseif s.adj_why == "ally" and s.adj_rt then
						local it = I.by_name[s.adj_rt.x]
						lines[2] = L("cd_tip_lr_ally_more"):format(it and it.label or s.adj_rt.x, s.adj_rt.k)
					elseif s.adj_why then
						lines[2] = L(s.adj_why == "solo" and "cd_tip_swap_solo" or s.adj_why == "behind" and "cd_tip_swap_behind"
							or s.adj_why == "late" and "cd_tip_swap_late" or "cd_tip_swap_react")
					end
				elseif s.must and s.vs then
					d.reason = s.vs[1]
				end
				if st.via then
					d.base, d.kind = { name = st.via.name, label = st.via.label }, "up"
				end
				lines[#lines + 1] = I.body(s)
			end
			if st.dis and not d.base then
				d.base, d.kind = { name = st.dis.name, label = st.dis.label }, "dis"
				table.insert(lines, 1, L("cd_tip_dis_from"):format(st.dis.label))
			end
			if st.skipped then
				lines[#lines + 1] = L("cd_tip_skipped")
			end
			if st.blocked then
				lines[#lines + 1] = L("cd_tip_room")
			end
			if st.sold_out and not step_done(st) then
				lines[#lines + 1] = L("cd_tip_stock")
			end
			if adapt and live then
				local mx, list = mx_info(st.item.name)
				if math.abs(mx) >= K.MX_SHOW then
					local parts = {}
					for k = 1, math.min(3, #list) do
						parts[#parts + 1] = ("%s %+.1f"):format(mx_label(list[k]), list[k].v * 100)
					end
					lines[#lines + 1] = L("cd_mx"):format(mx * 100, table.concat(parts, ", "))
					d.mx = mx
				end
			end
			d.body = table.concat(lines, "\n")
			plan.slots[i] = d
		end
		if live and plan.next and target then
			local sell = sell_for(target, steps, step_done, base.fates, weak)
			local note = sell and ("%s %s for %s%s"):format(sell.bag and "bag" or "sell", sell.name, target.item.name,
				sell.weak and " (weakest)" or "") or "-"
			if note ~= G.sell_note then
				G.sell_note = note
				log("panel sell: %s (main: %s)", note, table.concat(G.main or {}, ", "))
			end
			if sell then
				plan.next.sell = sell
				local line = L(sell.bag and "cd_bag" or "cd_sell"):format(sell.label, plan.next.label)
				if sell.weak then
					line = L("cd_tip_weak"):format(sell.label) .. "\n" .. line
				end
				plan.next.body = plan.next.body ~= "" and (plan.next.body .. "\n" .. line) or line
			end
		end
		if live then
			local empty = #(G.main or {}) < K.SLOTS
			for _, name in ipairs(G.bag_names or {}) do
				local it = I.by_name[name]
				if not plan.lift and it and not it.consumable and it.cost >= K.SELL_SHOW_COST and not (G.bagged or {})[name]
					and not (plan.next and plan.next.sell and plan.next.sell.name == name) then
					local planned = false
					for _, st in ipairs(steps) do
						if st.item == it and step_done(st) then
							planned = true
						end
					end
					if planned and empty then
						plan.lift = { name = name }
					elseif planned then
						local out = sell_for({ item = it }, steps, step_done, base.fates, false, true)
						local o = out and I.by_name[out.name]
						if o and o.cost < it.cost then
							plan.lift = { name = name, out = out.name }
						end
					end
				end
			end
			local note = plan.lift and (plan.lift.name .. " over " .. (plan.lift.out or "an empty slot")) or "-"
			if note ~= G.lift_note then
				G.lift_note = note
				log("panel backpack: %s (main: %s, backpack: %s)", note, table.concat(G.main or {}, ", "),
					table.concat(G.bag_names or {}, ", "))
			end
		end
		if live and target and target.upg then
			local note = ("%s from %s, pro %s, attr %s"):format(target.item.name, target.base.name,
				target.upg.share and ("%.0f%%"):format(target.upg.share * 100) or "-", tostring(target.upg.fit))
			if note ~= G.up_note then
				G.up_note = note
				log("plan done, in-slot upgrade: %s", note)
			end
		end
		if live and G.state ~= "behind" then
			local warn
			for _, st in ipairs(steps) do
				if not step_done(st) and not st.early and not st.pre and not st.ext and not st.upg and not st.skipped then
					local r = data.rows[st.item.name]
					local tm = r and I.timing(data, r)
					local pt = r and I.pub_timing(G.hero, st.item.name, r.t)
					local sensitive = (tm and tm.gap >= K.TIMING_GAP) or (pt and pt.gap >= K.TIMING_GAP)
					if sensitive and (G.ptime or 0) > r.t + K.LATE_GRACE
						and (st.item.cost - (st.have or 0)) * 2 > st.item.cost and (not warn or r.t < warn.t) then
						warn = { label = st.item.label, t = r.t }
					end
				end
			end
			if warn then
				plan.warn = L("cd_late_warn"):format(warn.label, math.floor(warn.t * (G.tk or 1) / 60 + 0.5))
			end
		end
		if live and G.state and G.state ~= "even" then
			plan.state = { behind = G.state == "behind", diff = G.diff or 0, us = G.items_us or 0, them = G.items_them or 0 }
		end
		plan.solo = live and G.solo or nil
		plan.danger = adapt and live and cfg.pdanger == 1 and G.leader or nil
		plan.replace = replace
		if plan.next then
			plan.next.body = (plan.next.body ~= "" and plan.next.body .. "\n" or "") .. L("cd_tip_buy")
		end
		if live then
			local phys = I.physical(G.hero, bpos)
			for _, rule in ipairs(K.REACT) do
				local n, src = 0, nil
				for _, e in ipairs(G.them) do
					local has
					for _, name in ipairs(rule.items) do
						if G.seen[e] and G.seen[e][name] then
							has = name
						end
					end
					if has then
						n, src = n + 1, src or has
					end
				end
				local triggered = n >= (rule.min or 1) and (not rule.phys or phys)
				if triggered then
					G.fired = G.fired or {}
					if not G.fired[rule.threat] then
						G.rec("threats", { rule.threat, src or "-", n })
					end
					G.fired[rule.threat] = true
				end
				if not plan.threat and triggered then
					local owned = false
					for name in pairs(G.owned) do
						if ((K.COUNTERS[name] or {})[rule.threat] or 0) >= K.MUST_COVER then
							owned = true
						end
					end
					local answer
					for _, s in ipairs(slots) do
						if not answer and ((K.COUNTERS[s.item.name] or {})[rule.threat] or 0) >= K.MUST_COVER then
							answer = s.item
						end
					end
					if not answer then
						for _, name in ipairs(rule.counters) do
							if not answer and I.by_name[name] and I.fits(name, G.hero, bpos) and I.buys_it(name, G.hero, bpos) then
								answer = I.by_name[name]
							end
						end
					end
					local detect = G.owned.dust or G.owned.ward_sentry or G.owned.ward_dispenser or G.owned.gem
					if rule.threat == "invis" and not detect and not G.ally_detect then
						plan.threat = L("cd_threat_invis_team")
						plan.threat_hard = true
						plan.need_dust = true
					elseif rule.threat == "invis" and (bpos or 1) >= 4 and not owned and not detect then
						plan.threat = L("cd_threat_invis_sup")
					elseif answer and not owned then
						plan.threat = L("cd_threat_warn"):format(I.item_label(src), n, answer.label)
						plan.threat_hard = rule.hard ~= nil
					end
				end
			end
			if not plan.threat and (G.ptime or 0) >= K.INVIS_FROM and not G.ally_detect
				and not (G.owned.dust or G.owned.ward_sentry or G.owned.ward_dispenser or G.owned.gem) then
				for _, e in ipairs(G.them) do
					if not plan.threat and (I.threats(e).invis or 0) >= K.INVIS_HERO then
						plan.threat, plan.threat_hard, plan.need_dust = L("cd_threat_invis_team"), true, true
					end
				end
			end
			if plan.threat then
				if plan.warn and not plan.threat_hard then
					plan.warn2 = plan.threat
				else
					plan.warn, plan.warn2 = plan.threat, plan.warn
				end
			end
			if G.solo and (G.ptime or 0) >= K.BB_CORE_FROM and not (cfg.autobuy == 1 and cfg.abuy_bb == 1) then
				if not plan.warn then
					plan.warn = L("cd_solo_bb")
				elseif not plan.warn2 then
					plan.warn2 = L("cd_solo_bb")
				end
			end
			local note = tostring(plan.warn) .. " | " .. tostring(plan.warn2)
			if note ~= G.threat_note then
				G.threat_note = note
				log("panel warn: %s", note)
				G.rec("warns", { plan.warn or "-", plan.warn2 or "-" })
			end
		end
		plan.complete = plan.next == nil
		return plan
	end

	function G.stack_add(stacks, item, name)
		if name == "ward_dispenser" then
			stacks.ward_observer = (stacks.ward_observer or 0) + Item.GetCurrentCharges(item)
			stacks.ward_sentry = (stacks.ward_sentry or 0) + Item.GetSecondaryCharges(item)
		elseif K.STACK[name] then
			local init = math.max(1, Item.GetInitialCharges(item))
			stacks[name] = (stacks[name] or 0) + math.max(1, math.ceil(Item.GetCurrentCharges(item) / init))
		end
	end

	function G.rec_min()
		return math.floor((G.time or 0) / 6 + 0.5) / 10
	end

	function G.rec_start(match)
		local okr, kept = pcall(G.rec_resume, match)
		if okr and kept then
			G.R, G.rec_lv = kept, {}
			G.rec_next, G.rec_nw_m, G.rec_build_at = nil, nil, 0
			for _, s in ipairs(kept.skills or {}) do
				local name, lv = s[2], tonumber(s[3])
				if name and lv and lv > (G.rec_lv[name] or 0) then
					G.rec_lv[name] = lv
				end
			end
			return
		end
		local mode = GameRules.GetGameMode()
		G.R = {
			v = K.REC_VER, match = match, date = os.date("%Y-%m-%d %H:%M"), mode = mode or -1,
			heroes = {}, buys = {}, plan = {}, warns = {}, swaps = {}, threats = {}, auto = {}, nw = {}, states = {}, danger = {},
			replace = {}, lane = {}, foes = {},
			skills = {},
		}
		G.rec_lv = {}
		G.rec_next, G.rec_nw_m, G.rec_build_at = nil, nil, 0
		local sm = draft.summary
		if sm then
			local rows = {}
			for _, r in ipairs(sm.rows) do
				rows[#rows + 1] = { r.h, r.pos or 0, math.floor((r.sum or 0) * 1000 + 0.5) / 1000 }
			end
			G.R.draft = { chance = draft.chance, ours = rows, them = sm.them }
		end
		G.R.pick_recs = draft.pick_recs
	end

	function G.rec(list, entry)
		local t = G.R and G.R[list]
		if t and #t < K.REC_MAX then
			table.insert(entry, 1, G.rec_min())
			t[#t + 1] = entry
		end
	end

	function G.rec_hero(key, side)
		local hr = G.R.heroes[key]
		if not hr then
			hr = { team = side, items = {}, final = {} }
			G.R.heroes[key] = hr
		end
		return hr
	end

	function G.rec_summary(b)
		local s = { core = {}, slots = {}, steps = {}, late = {}, start = {}, dpos = b.dpos, since = b.since }
		for _, cd in ipairs(b.slots) do
			s.slots[#s.slots + 1] = { cd.item.name, math.floor((cd.t or 0) / 6 + 0.5) / 10 }
			if cd.core then
				s.core[#s.core + 1] = cd.item.name
			end
		end
		for _, st in ipairs(b.steps or {}) do
			s.steps[#s.steps + 1] = st.item.name
		end
		for _, lt in ipairs(b.late or {}) do
			s.late[#s.late + 1] = lt.item.name
		end
		for _, st in ipairs(b.start or {}) do
			s.start[#s.start + 1] = { st.item.name, st.q }
		end
		return s
	end

	function G.rec_heroes(team)
		if not G.R then
			return
		end
		local m = G.rec_min()
		for _, e in ipairs(Heroes.GetAll()) do
			local info = not NPC.IsIllusion(e) and D.by_unit[NPC.GetUnitName(e)]
			if info and not Entity.IsDormant(e) then
				local hr = G.rec_hero(tostring(info.id), Entity.GetTeamNum(e) == team and "us" or "them")
				local final = {}
				for slot = 0, K.ENEMY_INV_LAST do
					local it = NPC.GetItemByIndex(e, slot)
					local name = it and item_name(it)
					if name then
						final[#final + 1] = name
						local item = I.by_name[name]
						if hr.items[name] == nil and item and not item.consumable and item.cost > 0 then
							hr.items[name] = m
						end
					end
				end
				local nt = NPC.GetItemByIndex(e, K.NEUTRAL_SLOT)
				hr.final, hr.seen, hr.neutral = final, m, nt and item_name(nt) or hr.neutral
			end
		end
	end

	function G.rec_skills(hero)
		if not G.R then
			return
		end
		G.rec_lv = G.rec_lv or {}
		local short = NPC.GetUnitName(hero):gsub("^npc_dota_hero_", "")
		local own = (K.REC_SKILL_OWN[short] or short) .. "_"
		for i = 0, K.REC_ABIL_LAST do
			local ab = NPC.GetAbilityByIndex(hero, i)
			if ab and not Ability.IsInnate(ab) then
				local name = Ability.GetName(ab)
				local lv = Ability.GetLevel(ab)
				local mine = name and (name:sub(1, #own) == own or name:find("^special_bonus_")) and not name:find("_portal_warp$")
				if mine and lv and lv > (G.rec_lv[name] or 0) then
					G.rec_lv[name] = lv
					G.rec("skills", { name, lv, NPC.GetCurrentLevel(hero) })
				end
			end
		end
	end

	function G.rec_builds(us, them)
		if not G.R or os.clock() < (G.rec_build_at or 0) then
			return
		end
		G.rec_build_at = os.clock() + K.REC_BUILD_EVERY
		local function side(list, opp, fixed, name)
			local rest, block, pos = {}, {}, {}
			for _, h in ipairs(list) do
				local p = fixed[h]
				if p and not block[p] then
					pos[h], block[p] = p, true
				else
					rest[#rest + 1] = h
				end
			end
			local _, map = M.assign(rest, block)
			for j, h in ipairs(rest) do
				pos[h] = map[j]
			end
			for _, h in ipairs(list) do
				local hr = G.rec_hero(tostring(h), name)
				hr.pos = pos[h]
				if not hr.build and pos[h] then
					local mates = {}
					for _, x in ipairs(list) do
						if x ~= h then
							mates[#mates + 1] = x
						end
					end
					table.sort(mates)
					local b = I.build(h, pos[h], opp, mates, h ~= G.hero)
					if b and b.none then
						hr.build = { none = true }
					elseif b and #b.slots > 0 then
						hr.build = G.rec_summary(b)
					end
				end
				if name == "them" and not hr.pred and I.buys[h] then
					hr.pred = {}
					for _, p in ipairs(I.predicted(h)) do
						hr.pred[#hr.pred + 1] = { p.name, math.floor(p.share * 100 + 0.5) }
					end
				end
			end
		end
		local fixed = { [G.hero] = G.bpos }
		for i, step in ipairs(STEPS()) do
			local h, p = draft.steps[i], draft.slot_pos[i]
			if h and p and h ~= G.hero and p ~= G.bpos and step.kind == "P" and step_team(i) == 0 then
				fixed[h] = p
			end
		end
		side(us, them, fixed, "us")
		side(them, us, draft.enemy_pos or {}, "them")
	end

	local function rec_fill(R, win)
		R.win = win
		R.minutes = G.rec_min()
		R.me = {
			hero = G.hero, pos = G.bpos, pos_src = G.bpos_note, autobuy = cfg.autobuy, live = cfg.live, solo = G.solo_max,
			fired = G.fired, owned = G.main,
		}
		if not ui.enable:Get() then
			R.off = 1
		end
		local okt, tp = pcall(Player.GetTeamPlayer, Players.GetLocal())
		if okt and type(tp) == "table" then
			local stats = {}
			for _, key in ipairs(K.REC_STATS) do
				local v = tp[key]
				if type(v) == "number" then
					stats[key] = math.floor(v * 10 + 0.5) / 10
				end
			end
			R.me.stats = stats
		end
		local ok, text = pcall(JSON.encode, JSON, R)
		if not ok or type(text) ~= "string" then
			log("record: encode failed: %s", tostring(text))
			return nil
		end
		return (text:gsub("[\r\n]", " "))
	end

	local function rec_send(text, meta)
		pcall(LOGR.match, text, meta)
		local dir = LOGR.dir()
		local f = dir and io.open(dir .. "configs\\" .. K.REC_FILE, "ab")
		if not f then
			log("record: no access to %s", K.REC_FILE)
			return
		end
		f:write(text .. "\n")
		f:close()
		log("record: match %s saved, %d bytes, result %s", tostring(meta.match), #text, tostring(meta.win))
	end

	local function rec_parked()
		local dir = LOGR.dir()
		local path = dir and dir .. "configs\\" .. K.REC_PARK_FILE
		local f = path and io.open(path, "rb")
		if not f then
			return nil
		end
		local head, text = f:read("l"), f:read("a")
		f:close()
		local match, hero, pos, minutes, at = tostring(head or ""):match("^(%d+)\t(%-?%d*)\t(%-?%d*)\t([%-%d%.]*)\t(%d+)%s*$")
		if not match or type(text) ~= "string" or text:sub(1, 1) ~= "{" then
			os.remove(path)
			return nil
		end
		return {
			path = path, text = (text:gsub("%s+$", "")), at = tonumber(at),
			meta = { match = match, hero = tonumber(hero), pos = tonumber(pos), minutes = tonumber(minutes) },
		}
	end

	function G.rec_park()
		local R = G.R
		if not R or R.written then
			return
		end
		R.parked = (R.parked or 0) + 1
		local text = rec_fill(R, nil)
		local dir = LOGR.dir()
		local f = text and dir and io.open(dir .. "configs\\" .. K.REC_PARK_FILE, "wb")
		if not f then
			return
		end
		f:write(("%s\t%s\t%s\t%s\t%d\n"):format(tostring(R.match), tostring(G.hero or ""), tostring(G.bpos or ""),
			tostring(R.minutes), os.time()), text, "\n")
		f:close()
		log("record: match %s left at %.1f min, kept open for %d s", tostring(R.match), R.minutes, K.REC_PARK_WAIT)
	end

	function G.rec_flush_parked(force)
		local p = rec_parked()
		if not p or (G.R and G.R.match == p.meta.match and not G.R.written) then
			return
		end
		if not force and os.time() - (p.at or 0) < K.REC_PARK_WAIT then
			return
		end
		os.remove(p.path)
		log("record: match %s was not continued, sending what was kept", p.meta.match)
		rec_send('{"left":1,' .. p.text:sub(2), p.meta)
	end

	function G.rec_resume(match)
		local p = rec_parked()
		if not p then
			return nil
		end
		if p.meta.match ~= match then
			G.rec_flush_parked(true)
			return nil
		end
		os.remove(p.path)
		local ok, R = pcall(JSON.decode, JSON, p.text)
		if not ok or type(R) ~= "table" or type(R.heroes) ~= "table" then
			rec_send('{"left":1,' .. p.text:sub(2), p.meta)
			return nil
		end
		R.resumed, R.off = (R.resumed or 0) + 1, nil
		log("record: match %s continued from %.1f min", match, tonumber(R.minutes) or 0)
		return R
	end

	function G.rec_write(win)
		local R = G.R
		if not R or R.written then
			return
		end
		R.written = true
		local text = rec_fill(R, win)
		local p = rec_parked()
		if p and p.meta.match == R.match then
			os.remove(p.path)
		end
		if text then
			rec_send(text, { match = R.match, hero = G.hero, pos = G.bpos, minutes = R.minutes, win = win })
		end
	end

	local function stop()
		G.live, I.want, I.want_more, D.in_match, I.eroles, I.tk = false, nil, nil, false, nil, nil
		I.state_for = nil
	end

	function G.record()
		if not G.match or not G.hero or G.recorded == G.match then
			return
		end
		local alive, teams = {}, 0
		local okf, forts = pcall(NPCs.GetAll, Enum.UnitTypeFlags.TYPE_FORT)
		for _, f in ipairs(okf and type(forts) == "table" and forts or {}) do
			if NPC.IsFort(f) and Entity.IsAlive(f) and Entity.GetHealth(f) > 0 then
				local t = Entity.GetTeamNum(f)
				if not alive[t] then
					alive[t] = true
					teams = teams + 1
				end
			end
		end
		local win = "?"
		if teams == 1 then
			win = alive[G.team] and "1" or "0"
		end
		if win == "?" and GameRules.GetGameState() ~= Enum.GameState.DOTA_GAMERULES_STATE_POST_GAME then
			local okp, perr = pcall(G.rec_park)
			if not okp then
				log("record: %s", tostring(perr))
			end
			return
		end
		G.recorded = G.match
		local okw, werr = pcall(G.rec_write, win == "?" and nil or tonumber(win))
		if not okw then
			log("record: %s", tostring(werr))
		end
		local base = I.build(G.hero, G.bpos, G.them, G.mates, true)
		local core, slots, followed = {}, {}, 0
		for _, cd in ipairs(base and base.slots or {}) do
			slots[#slots + 1] = cd.item.name
			if cd.core then
				core[#core + 1] = cd.item.name
				if G.ever[cd.item.name] then
					followed = followed + 1
				end
			end
		end
		local dir = Engine.GetCheatDirectory()
		if not dir:match("[\\/]$") then
			dir = dir .. "\\"
		end
		local path = dir .. "configs\\" .. K.HISTORY_FILE
		local f = io.open(path, "rb")
		local fresh = not f
		if f then
			f:close()
		end
		f = io.open(path, "ab")
		if not f then
			log("history: no access to %s", path)
			return
		end
		if fresh then
			f:write("time;match;hero;pos;minutes;win;core_owned;core;build;final\n")
		end
		local line = ("%s;%s;%d;%s;%d;%s;%d;%s;%s;%s"):format(os.date("%Y-%m-%d %H:%M"), G.match, G.hero,
			tostring(G.bpos or "?"), math.floor((G.time or 0) / 60), win, followed, table.concat(core, ","),
			table.concat(slots, ","), table.concat(G.main or {}, ","))
		f:write(line .. "\n")
		f:close()
		local threats = {}
		for threat in pairs(G.fired or {}) do
			local answered = 0
			for name in pairs(G.ever) do
				if ((K.COUNTERS[name] or {})[threat] or 0) >= K.MUST_COVER then
					answered = 1
				end
			end
			threats[#threats + 1] = threat .. ":" .. answered
		end
		table.sort(threats)
		local path2 = dir .. "configs\\" .. K.HISTORY2
		local f2 = io.open(path2, "rb")
		local fresh2 = not f2
		if f2 then
			f2:close()
		end
		f2 = io.open(path2, "ab")
		if f2 then
			if fresh2 then
				f2:write("time;match;hero;pos;minutes;win;core_owned;core;build;final;threats;solo;auto\n")
			end
			f2:write(("%s;%s;%s;%d\n"):format(line, table.concat(threats, ","), G.solo_max or "-", cfg.autobuy))
			f2:close()
		end
		log("history: match %s recorded, win %s, core owned %d of %d", G.match, win, followed, #core)
	end

	function G.hurt(data)
		G.hurt_seen = true
		local target = data and data.target
		if not G.my_idx or not target or Entity.GetIndex(target) ~= G.my_idx then
			return
		end
		local src = data.source
		if not src or not Entity.IsNPC(src) then
			return
		end
		if not Entity.IsHero(src) then
			local owner = Entity.GetOwner(src)
			if not owner or not Entity.IsHero(owner) then
				return
			end
			src = owner
		end
		local info = D.by_unit[NPC.GetUnitName(src)]
		local dmg = tonumber(data.damage) or 0
		if not info or dmg <= 0 or Entity.GetTeamNum(src) == G.team then
			return
		end
		local phys = true
		if data.ability then
			local okd, dt = pcall(Ability.GetDamageType, data.ability)
			phys = okd and dt == Enum.DamageTypes.DAMAGE_TYPE_PHYSICAL
		end
		local now = G.time or 0
		G.dmg = G.dmg or {}
		local d = G.dmg[info.id]
		if not d then
			d = { phys = 0, spell = 0, t = now, all_phys = 0, all_spell = 0 }
			G.dmg[info.id] = d
		end
		local k = 0.5 ^ (math.max(0, now - d.t) / K.DMG_HALF)
		d.phys, d.spell, d.t = d.phys * k, d.spell * k, now
		if phys then
			d.phys, d.all_phys = d.phys + dmg, d.all_phys + dmg
		else
			d.spell, d.all_spell = d.spell + dmg, d.all_spell + dmg
		end
	end

	local function danger_tick(team, them, hero)
		local stats, ksum, dsum = {}, 0, 0
		for _, pl in ipairs(Players.GetAll()) do
			if Entity.GetTeamNum(pl) ~= team then
				local okd, td = pcall(Player.GetTeamData, pl)
				local h = okd and type(td) == "table" and math.tointeger(tonumber(td.selected_hero_id))
				if h then
					stats[h] = { k = tonumber(td.kills) or 0, d = tonumber(td.deaths) or 0 }
					ksum = ksum + stats[h].k
				end
			end
		end
		local now, dmg = G.time or 0, G.dmg or {}
		local live = {}
		for _, e in ipairs(them) do
			local d = dmg[e]
			if d then
				local k = 0.5 ^ (math.max(0, now - d.t) / K.DMG_HALF)
				live[e] = { phys = d.phys * k, spell = d.spell * k }
				dsum = dsum + live[e].phys + live[e].spell
			end
		end
		local hp = math.max(1, Entity.GetMaxHealth(hero) or 1)
		local use_k, use_d = ksum >= K.DANGER_KILLS_MIN, dsum >= hp * K.DMG_MIN_HP
		local dw, best = {}, nil
		for _, e in ipairs(them) do
			local st = stats[e] or { k = 0, d = 0 }
			local ks = use_k and st.k / ksum or nil
			local ds = use_d and live[e] and (live[e].phys + live[e].spell) / dsum or (use_d and 0 or nil)
			local s = ks and ds and (1 - K.DANGER_DMG_W) * ks + K.DANGER_DMG_W * ds or ks or ds
			if s then
				dw[e] = math.floor(clamp(K.DANGER_BASE + K.DANGER_K * (s - 0.1), K.DANGER_LO, K.DANGER_HI) * 10 + 0.5) / 10
				if s >= K.DANGER_LEAD and st.k >= K.DANGER_LEAD_KILLS and (not best or s > best.s) then
					best = { e = e, s = s, k = st.k, d = st.d, ks = ks or 0, ds = ds }
				end
			end
		end
		local press
		if best then
			local l = live[best.e]
			if l and l.phys + l.spell >= hp * K.DMG_LEAD_HP then
				best.att, best.src = l.phys / (l.phys + l.spell), "live"
			else
				best.att, best.src = (K.HERO_ATT_MAP[best.e] or 30) / 100, "hero"
			end
			best.kind = best.att >= K.DMG_ATT_HI and "phys" or (best.att <= K.DMG_ATT_LO and "spell" or nil)
			best.w = dw[best.e] or 1
			local p = clamp((best.s - K.DMG_PRESS_LO) / K.DMG_PRESS_SPAN, 0, 1)
			if best.kind and p > 0 then
				press = { e = best.e, threat = best.kind == "phys" and "phys" or "magic", w = math.floor(K.DMG_T * p * 20 + 0.5) / 20 }
			end
		end
		G.dw, G.leader, G.press = dw, best, press
		if not G.hurt_seen and now >= K.HURT_WAIT and not G.hurt_note then
			G.hurt_note = true
			log("danger: damage tracking is %s, using kills and hero data only", cfg.dmgtrack == 1 and "on but silent (unsafe mode off?)" or "off")
		end
		local parts = {}
		for _, e in ipairs(them) do
			parts[#parts + 1] = ("%d:%.1f"):format(e, dw[e] or 1)
		end
		local sig = ("%s|%s|%s"):format(best and best.e or "-", table.concat(parts, ","),
			press and (press.threat .. press.w) or "-")
		if sig ~= G.danger_sig then
			G.danger_sig = sig
			local hero_info = best and D.by_id[best.e]
			log("danger: leader %s k %s share %.2f dmg %s att %.2f (%s) press %s | weights %s | kills %d, dmg %.0f/%d hp",
				hero_info and hero_info.name or "-", best and best.k or "-", best and best.s or 0,
				best and best.ds and ("%.2f"):format(best.ds) or "-", best and best.att or 0, best and best.src or "-",
				press and (press.threat .. " +" .. press.w) or "-", table.concat(parts, " "), ksum, dsum, hp)
			G.rec("danger", { best and best.e or 0, best and best.k or 0, best and math.floor(best.s * 100 + 0.5) or 0,
				best and math.floor(best.att * 100 + 0.5) or 0, best and best.src or "-", press and press.threat or "-",
				press and press.w or 0 })
		end
		return sig
	end

	local function nw_by_hero()
		local out = {}
		for _, pl in ipairs(Players.GetAll()) do
			local okd, td = pcall(Player.GetTeamData, pl)
			local okt, tp = pcall(Player.GetTeamPlayer, pl)
			local h = okd and type(td) == "table" and math.tointeger(tonumber(td.selected_hero_id))
			if h and okt and type(tp) == "table" then
				out[h] = tonumber(tp.networth) or 0
			end
		end
		return out
	end

	function G.hero_xp(e)
		local okx, xp = pcall(Hero.GetCurrentXP, e)
		xp = okx and tonumber(xp) or 0
		if xp > 0 then
			return xp
		end
		local okl, lv = pcall(NPC.GetCurrentLevel, e)
		lv = okl and math.floor(tonumber(lv) or 1) or 1
		return K.XP_LEVEL[clamp(lv, 1, #K.XP_LEVEL)]
	end

	local function lane_tick(team, hero, my_id, dt)
		local pt = G.ptime or 0
		if G.lane or G.lane_done or pt < K.LANE_FROM then
			return
		end
		local acc = G.lane_acc
		if not acc then
			acc = { t = 0, foe = {}, ally = {} }
			G.lane_acc = acc
		end
		if pt <= K.LANE_TO then
			if not Entity.IsAlive(hero) then
				return
			end
			acc.t = acc.t + dt
			local my_pos, my_idx = Entity.GetAbsOrigin(hero), Entity.GetIndex(hero)
			for _, e in ipairs(Heroes.GetAll()) do
				if Entity.GetIndex(e) ~= my_idx and not NPC.IsIllusion(e) and Entity.IsAlive(e) and not Entity.IsDormant(e) then
					local ei = D.by_unit[NPC.GetUnitName(e)]
					if ei and (Entity.GetAbsOrigin(e) - my_pos):Length2D() <= K.LANE_R then
						local side = Entity.GetTeamNum(e) == team and acc.ally or acc.foe
						side[ei.id] = (side[ei.id] or 0) + dt
					end
					if ei then
						acc.xp, acc.xp_t = acc.xp or {}, acc.xp_t or {}
						acc.xp[ei.id], acc.xp_t[ei.id] = G.hero_xp(e), pt
					end
				end
			end
			return
		end
		G.lane_done = true
		if acc.t < 60 then
			log("lane: not enough lane time (%.0f s)", acc.t)
			return
		end
		local opp, mates = {}, {}
		for id, t in pairs(acc.foe) do
			if t >= K.LANE_SHARE * acc.t then
				opp[#opp + 1] = id
			end
		end
		for id, t in pairs(acc.ally) do
			if t >= K.LANE_SHARE * acc.t then
				mates[#mates + 1] = id
			end
		end
		table.sort(opp)
		if #opp == 0 then
			log("lane: nobody stood against you (%.0f s sampled)", acc.t)
			return
		end
		local xp = acc.xp or {}
		xp[my_id] = G.hero_xp(hero)
		local mine, theirs = xp[my_id] or 0, 0
		for _, id in ipairs(mates) do
			mine = mine + (xp[id] or 0)
		end
		local stale = false
		for _, id in ipairs(opp) do
			theirs = theirs + (xp[id] or 0)
			if pt - ((acc.xp_t or {})[id] or 0) > K.LANE_STALE then
				stale = true
			end
		end
		local diff = mine / (#mates + 1) - theirs / #opp
		local result = stale and "unknown" or diff <= K.LANE_Q_LO and "lost" or (diff >= K.LANE_Q_HI and "won" or "even")
		G.lane = { opp = opp, mates = mates, diff = math.floor(diff + 0.5), result = result }
		local names = {}
		for _, id in ipairs(opp) do
			names[#names + 1] = D.by_id[id] and D.by_id[id].name or tostring(id)
		end
		log("lane: vs %s, with %d allies, xp diff %d per hero -> %s (opponent pairs affect items until minute 15)", table.concat(names, ", "), #mates,
			G.lane.diff, result)
		G.rec("lane", { table.concat(opp, ","), #mates, G.lane.diff, result })
	end

	local function foe_tick(them)
		local now = os.clock()
		if now < (G.foe_at or 0) then
			return
		end
		G.foe_at = now + K.FOE_EVERY
		G.foe = G.foe or {}
		G.dps, G.dps_w = G.dps or {}, G.dps_w or {}
		local fresh = {}
		for _, e in ipairs(Heroes.GetAll()) do
			local hi = not NPC.IsIllusion(e) and not Entity.IsDormant(e) and D.by_unit[NPC.GetUnitName(e)]
			local ei = hi and Entity.GetTeamNum(e) ~= G.team and hi
			if ei then
				local miss = 1
				for name in pairs(G.seen[ei.id] or {}) do
					local ev = K.EVASION[name]
					if ev then
						miss = miss * (1 - ev / 100)
					end
				end
				local okp, pm = pcall(NPC.GetArmorDamageMultiplier, e)
				local okm, mm = pcall(NPC.GetMagicalArmorDamageMultiplier, e)
				G.foe[ei.id] = { phys = okp and tonumber(pm) or 1, mag = okm and tonumber(mm) or 1, hp = Entity.GetMaxHealth(e) or 0,
					eva = 1 - miss }
			end
			if hi then
				local okd, dmg = pcall(NPC.GetTrueDamage, e)
				local oka, aps = pcall(NPC.GetAttacksPerSecond, e)
				local raw = (okd and tonumber(dmg) or 0) * (oka and tonumber(aps) or 0)
				if raw ~= raw then
					raw = 0
				end
				raw = clamp(raw, 0, K.DPS_MAX)
				local old = G.dps[hi.id]
				G.dps[hi.id] = old and old + (raw - old) * K.DPS_NEW or raw
				if ei then
					fresh[hi.id] = true
				end
			end
		end
		local vals = {}
		for _, v in pairs(G.dps) do
			vals[#vals + 1] = v
		end
		table.sort(vals)
		local nv = #vals
		G.dps_med = nv >= K.DPS_HEROES and (vals[(nv + 1) // 2] + vals[nv // 2 + 1]) / 2 or nil
		if G.dps_med and G.dps_med > 0 then
			for id in pairs(fresh) do
				G.dps_w[id] = clamp((G.dps[id] / G.dps_med - K.DPS_FROM) / (K.DPS_FULL - K.DPS_FROM), 0, 1)
			end
		end
		local dnote, moved = {}, false
		G.dps_logw = G.dps_logw or {}
		for _, e in ipairs(them) do
			local w = G.dps_w[e]
			if w then
				dnote[#dnote + 1] = ("%s %d %.1f"):format(D.by_id[e] and D.by_id[e].name or e, math.floor(G.dps[e] + 0.5),
					math.floor(w * 10 + 0.5) / 10)
				if not G.dps_logw[e] or math.abs(w - G.dps_logw[e]) >= K.DPS_LOG_STEP then
					moved = true
				end
			end
		end
		if moved and now >= (G.dps_log_at or 0) then
			G.dps_log_at = now + K.DPS_LOG_GAP
			for _, e in ipairs(them) do
				G.dps_logw[e] = G.dps_w[e]
			end
			log("enemy dps vs match median %d, phys threat: %s", math.floor((G.dps_med or 0) + 0.5), table.concat(dnote, ", "))
		end
		local n, phys, mag, hp, eva, eva_h = 0, 0, 0, 0, 0, nil
		for _, e in ipairs(them) do
			local f = G.foe[e]
			if f then
				n = n + 1
				phys, mag, hp = phys + f.phys, mag + f.mag, hp + f.hp
				if f.eva > eva then
					eva, eva_h = f.eva, e
				end
			end
		end
		if n > 0 then
			G.foe_sum = { phys = phys / n, mag = mag / n, hp = hp / n, eva = eva, eva_h = eva_h, n = n }
			local m = math.floor((G.ptime or 0) / 300)
			if m ~= G.foe_rec_m then
				G.foe_rec_m = m
				G.rec("foes", { math.floor(phys / n * 100 + 0.5), math.floor(mag / n * 100 + 0.5), math.floor(hp / n + 0.5),
					math.floor(eva * 100 + 0.5), eva_h or 0, n })
			end
		end
	end

	function G.tick()
		if cfg.panel ~= 1 then
			stop()
			return
		end
		local now = os.clock()
		if now < G.next_at then
			return
		end
		G.next_at = now + K.PANEL_EVERY
		local gs = GameRules.GetGameState()
		if gs == Enum.GameState.DOTA_GAMERULES_STATE_POST_GAME and cfg.live == 1 then
			G.record()
		end
		local hero = K.PANEL_STATES[gs] and Heroes.GetLocal()
		local info = hero and D.by_unit[NPC.GetUnitName(hero)]
		if not info then
			stop()
			return
		end
		local match = tostring(GameRules.GetMatchID())
		if G.match ~= match then
			if G.R and not G.R.written then
				G.R.left = 1
				pcall(G.rec_write, nil)
			end
			pcall(G.rec_start, match)
			G.match, G.seen, G.plan, G.sig, G.pos_for, G.ever, G.probed = match, {}, nil, nil, nil, {}, {}
			G.ev, G.got_at, G.ew_note, G.erole_note, I.eroles = {}, {}, nil, nil, nil
			G.state, G.diff, G.state_at = "even", 0, nil
			G.solo, G.solo_until, G.solo_max, G.conn, G.fired = nil, nil, nil, {}, {}
			G.auto_fail, G.auto_last, G.reserve, G.bagged, G.lift_note, G.lift_try = {}, nil, 0, {}, nil, {}
			G.dmg, G.dw, G.leader, G.press, G.danger_sig, G.hurt_seen, G.hurt_note = {}, nil, nil, nil, nil, nil, nil
			G.turbo = GameRules.GetGameMode() == Enum.GameMode.DOTA_GAMEMODE_TURBO
			G.tk = G.turbo and cfg.pturbo == 1 and K.TURBO_T or 1
			G.rep_buy, G.skill_at, G.skill_note, G.skill_fail, G.skill_fail_lv, G.attr_probe = nil, 0, nil, nil, nil, nil
			G.sec_trip, G.sec_at, G.sec_wait, G.sec_note, G.sec_fail = nil, 0, nil, nil, nil
			G.stunned, G.stun_rate, G.stun_at = 0, 0, nil
			G.seen_t, G.ally_items, G.lane, G.lane_acc, G.lane_done, G.lane_at = {}, {}, nil, nil, nil, nil
			G.foe, G.foe_sum, G.foe_at, G.foe_rec_m = {}, nil, 0, nil
			G.dps, G.dps_w, G.dps_logw, G.dps_med, G.dps_log_at, G.toasted = {}, {}, {}, nil, nil, {}
			log("match %s: mode %s, time scale %.2f", match, tostring(okm and gm or "?"), G.tk)
		end
		local team = Entity.GetTeamNum(hero)
		G.team, G.my_idx, D.in_match = team, Entity.GetIndex(hero), true
		local them, taken = {}, {}
		for _, e in ipairs(Heroes.GetAll()) do
			if Entity.GetTeamNum(e) ~= team and not NPC.IsIllusion(e) then
				local ei = D.by_unit[NPC.GetUnitName(e)]
				if ei and not taken[ei.id] and #them < 5 then
					taken[ei.id] = true
					them[#them + 1] = ei.id
					if not Entity.IsDormant(e) then
						local old = G.seen[ei.id] or {}
						local now = {}
						for slot = 0, K.ENEMY_INV_LAST do
							local item = NPC.GetItemByIndex(e, slot)
							local name = item and item_name(item)
							if name then
								now[name] = true
							end
						end
						local nitem = NPC.GetItemByIndex(e, K.NEUTRAL_SLOT)
						local nname = nitem and item_name(nitem)
						if nname then
							now["n." .. nname] = true
						end
						if NPC.HasShard(e) then
							now.aghanims_shard = true
						end
						if NPC.HasScepter(e) then
							now.ultimate_scepter = true
						end
						G.seen_t = G.seen_t or {}
						G.seen_t[ei.id] = G.seen_t[ei.id] or {}
						for name in pairs(now) do
							if not old[name] then
								G.seen_t[ei.id][name] = G.seen_t[ei.id][name] or (G.ptime or 0)
								if K.ENEMY_ITEMS[name] or K.ANTI[name] or K.MX_X[name] then
									log("panel: %s has %s", ei.name, name)
								end
							end
						end
						for name in pairs(old) do
							if not now[name] and (K.ENEMY_ITEMS[name] or K.ANTI[name]) then
								log("panel: %s no longer has %s", ei.name, name)
							end
						end
						G.seen[ei.id] = now
						local value = 0
						for name in pairs(now) do
							local it = I.by_name[name]
							if it and not it.consumable then
								value = value + it.cost
							end
						end
						G.ev[ei.id] = math.max(G.ev[ei.id] or 0, value)
					end
				end
			end
		end
		local dm = tostring(GameRules.GetMatchID()) .. ":" .. tostring(GameRules.GetLobbyID())
		if #them < 5 and (draft.match == dm or draft.enemy_match == dm) then
			local added = {}
			for i, step in ipairs(STEPS()) do
				local h = draft.steps[i]
				if h and #them < 5 and step.kind == "P" and step_team(i) == 1 and not taken[h] and h ~= info.id then
					taken[h] = true
					them[#them + 1] = h
					added[#added + 1] = D.by_id[h] and D.by_id[h].name or tostring(h)
				end
			end
			local note = table.concat(added, ", ")
			if note ~= (G.unseen_note or "") then
				G.unseen_note = note
				log("enemies not seen yet, taken from the draft: %s", note ~= "" and note or "none")
			end
		end
		table.sort(them)
		local ew = {}
		if cfg.live == 1 and cfg.lanes == 1 then
			local known, rest, epos, block = draft.enemy_pos or {}, {}, {}, {}
			for _, e in ipairs(them) do
				epos[e] = known[e]
				if epos[e] then
					block[epos[e]] = true
				else
					rest[#rest + 1] = e
				end
			end
			local _, map = M.assign(rest, block)
			for j, e in ipairs(rest) do
				epos[e] = map[j]
			end
			local eroles = {}
			for _, e in ipairs(them) do
				ew[e] = (epos[e] or 1) >= 4 and K.SUPPORT_ITEM_W or 1
				eroles[e] = (epos[e] or 4) <= 3 and "core" or "sup"
			end
			local fixed, guess, cores = draft.enemy_fixed or {}, {}, 3
			for _, e in ipairs(them) do
				if fixed[e] then
					cores = cores - ((epos[e] or 4) <= 3 and 1 or 0)
				else
					guess[#guess + 1] = e
				end
			end
			if (G.ptime or 0) >= K.EW_ITEMS_T and #guess >= 2 then
				table.sort(guess, function(a, b)
					if (G.ev[a] or 0) ~= (G.ev[b] or 0) then
						return (G.ev[a] or 0) > (G.ev[b] or 0)
					end
					return a < b
				end)
				local note = {}
				for j, e in ipairs(guess) do
					ew[e] = j <= cores and 1 or K.SUPPORT_ITEM_W
					note[#note + 1] = ("%s %s %d"):format(D.by_id[e] and D.by_id[e].name or e, j <= cores and "core" or "sup",
						G.ev[e] or 0)
					local by_items = j <= cores and "core" or "sup"
					local other = guess[j <= cores and cores + 1 or cores]
					if by_items ~= eroles[e] and other and math.abs((G.ev[e] or 0) - (G.ev[other] or 0)) >= K.ROLE_FLIP_GAP then
						eroles[e] = by_items
					end
				end
				local line = table.concat(note, ", ")
				if line:gsub("%d+", "") ~= (G.ew_note or ""):gsub("%d+", "") then
					G.ew_note = line
					log("enemy cores by items: %s", line)
				end
			end
			local flips = {}
			for _, e in ipairs(them) do
				if eroles[e] ~= ((epos[e] or 4) <= 3 and "core" or "sup") then
					flips[#flips + 1] = ("%s %s"):format(D.by_id[e] and D.by_id[e].name or e, eroles[e])
				end
			end
			local fnote = table.concat(flips, ", ")
			if fnote ~= (G.erole_note or "") then
				G.erole_note = fnote
				log("enemy roles for predictions: %s", fnote ~= "" and fnote or "as in the draft")
			end
			I.eroles = eroles
		end
		G.ew = ew
		local team_items, team_sig, ally_items, ally_detect = {}, {}, {}, false
		local amx = K.MXA[(G.bpos or 1) <= 3 and "core" or "sup"]
		for _, e in ipairs(Heroes.GetAll()) do
			if Entity.GetTeamNum(e) == team and not NPC.IsIllusion(e) then
				local ai = D.by_unit[NPC.GetUnitName(e)]
				if ai and ai.id ~= info.id then
					if not ally_items[ai.id] then
						team_sig[#team_sig + 1] = "m" .. ai.id
					end
					ally_items[ai.id] = ally_items[ai.id] or {}
					for slot = 0, K.ENEMY_INV_LAST do
						local item = NPC.GetItemByIndex(e, slot)
						local name = item and item_name(item)
						local group = slot <= K.MAIN_LAST and name and K.TEAM_ONE[name]
						if group and not team_items[group] then
							team_items[group] = { e = ai.id, item = name }
							team_sig[#team_sig + 1] = group
						end
						if name == "dust" or name == "ward_sentry" or name == "ward_dispenser" or name == "gem" then
							ally_detect = true
						end
						if name and (amx[name] or I.lr_known(name)) and not ally_items[ai.id][name] then
							ally_items[ai.id][name] = true
							team_sig[#team_sig + 1] = ai.id .. name
						end
					end
				end
			end
		end
		G.ally_items, G.ally_detect = ally_items, ally_detect
		local mates = {}
		for id in pairs(ally_items) do
			mates[#mates + 1] = id
		end
		table.sort(mates)
		G.mates = mates
		team_sig[#team_sig + 1] = ally_detect and "detect" or "nodetect"
		table.sort(team_sig)
		G.team_items = team_items
		local us = {}
		for _, e in ipairs(Heroes.GetAll()) do
			local ai = Entity.GetTeamNum(e) == team and not NPC.IsIllusion(e) and D.by_unit[NPC.GetUnitName(e)]
			if ai and #us < 5 then
				local dup = false
				for _, h in ipairs(us) do
					if h == ai.id then
						dup = true
					end
				end
				if not dup then
					us[#us + 1] = ai.id
				end
			end
		end
		G.us = us
		local more = {}
		for _, h in ipairs(us) do
			if h ~= info.id then
				more[#more + 1] = h
			end
		end
		for _, h in ipairs(them) do
			more[#more + 1] = h
		end
		I.want_more = more
		local owned, main, bag, stacks, bagn = {}, {}, 0, {}, {}
		for slot = 0, K.INV_LAST do
			local item = NPC.GetItemByIndex(hero, slot)
			local name = item and item_name(item)
			if name then
				owned[name] = (owned[name] or 0) + 1
				G.stack_add(stacks, item, name)
				if slot <= K.MAIN_LAST then
					main[#main + 1] = name
					if G.lift_try and G.lift_try[name] and G.bagged then
						G.bagged[name] = true
					end
				elseif slot <= K.MAIN_LAST + K.BACKPACK then
					bag = bag + 1
					bagn[#bagn + 1] = name
				end
			end
		end
		G.bag_used, G.bag_names = bag, bagn
		local tp_item = NPC.GetItemByIndex(hero, K.TP_SLOT)
		local tp_name = tp_item and item_name(tp_item)
		if tp_name then
			owned[tp_name] = (owned[tp_name] or 0) + 1
		end
		local courier = Couriers.GetLocal()
		if courier then
			local my_id = Player.GetPlayerID(Players.GetLocal())
			for slot = 0, K.ENEMY_INV_LAST do
				local item = NPC.GetItemByIndex(courier, slot)
				local name = item and item_name(item)
				if name then
					local okid, pid = pcall(Item.GetPlayerOwnerID, item)
					if not okid or pid == my_id then
						owned[name] = (owned[name] or 0) + 1
						G.stack_add(stacks, item, name)
					end
				end
			end
		end
		G.read_at = os.clock()
		if NPC.HasShard(hero) then
			owned.aghanims_shard = owned.aghanims_shard or 1
		end
		if NPC.HasScepter(hero) and not owned.ultimate_scepter and not owned.ultimate_scepter_roshan then
			owned.ultimate_scepter_2 = 1
		end
		G.main, G.stacks = main, stacks
		local okp, tp = pcall(Player.GetTeamPlayer, Players.GetLocal())
		G.gold = (okp and type(tp) == "table") and (tonumber(tp.reliable_gold) or 0) + (tonumber(tp.unreliable_gold) or 0) or 0
		if G.pos_for ~= info.id then
			G.pos, G.pos_for = my_pos(info.id), info.id
		end
		G.time = GameRules.GetDOTATime(true, true)
		if gs == Enum.GameState.DOTA_GAMERULES_STATE_PRE_GAME and G.time > 0 then
			G.time = K.REC_PRE_T
		end
		G.tk = G.turbo and cfg.pturbo == 1 and K.TURBO_T or 1
		G.ptime = G.time / G.tk
		local resumed = G.time > K.RESUME_T and G.ever_seeded ~= G.match
		G.ever_seeded = G.match
		for name in pairs(owned) do
			if not G.ever[name] then
				G.rec("buys", resumed and { name, "had" } or { name })
				G.got_at[name] = resumed and 0 or G.ptime
			end
			G.ever[name] = true
		end
		G.hero, G.them, G.owned, G.live, I.want, I.tk = info.id, them, owned, true, info.id, G.tk
		local okq, tq = pcall(Player.GetTeamData, Players.GetLocal())
		local queued = okq and type(tq) == "table" and K.LANE_BITS[math.tointeger(tonumber(tq.lane_selection_flags) or 0) or 0]
		G.bpos = I.bpos[info.id] or queued or I.shown_pos[info.id] or G.pos
		local pos_src = I.bpos[info.id] and "manual" or queued and "queue" or I.shown_pos[info.id] and "draft" or "game"
		if G.bpos_note ~= pos_src .. G.bpos then
			G.bpos_note = pos_src .. G.bpos
			log("panel position %d from %s (game guess %s)", G.bpos, pos_src, tostring(G.pos))
		end
		if cfg.live == 1 and G.time > 0 and not GameRules.IsPaused() then
			local dt = math.min(1, now - (G.stun_at or now))
			for _, e in ipairs(Heroes.GetAll()) do
				if Entity.GetTeamNum(e) == team and not NPC.IsIllusion(e) and Entity.IsAlive(e)
					and (NPC.IsStunned(e) or NPC.HasState(e, Enum.ModifierState.MODIFIER_STATE_HEXED)) then
					G.stunned = (G.stunned or 0) + dt
				end
			end
			G.stun_rate = (G.stunned or 0) / math.max(1, G.ptime / 60)
			local okl, lerr = pcall(lane_tick, team, hero, info.id, math.min(1, now - (G.lane_at or now)))
			if not okl and tostring(lerr) ~= G.lane_err then
				G.lane_err = tostring(lerr)
				log("lane: %s", G.lane_err)
			end
			local okf, ferr = pcall(foe_tick, them)
			if not okf and tostring(ferr) ~= G.foe_err then
				G.foe_err = tostring(ferr)
				log("foes: %s", G.foe_err)
			end
		end
		G.stun_at, G.lane_at = now, now
		local okr, rerr = pcall(G.rec_heroes, team)
		if okr then
			okr, rerr = pcall(G.rec_builds, us, them)
		end
		if okr then
			okr, rerr = pcall(G.rec_skills, hero)
		end
		if not okr and tostring(rerr) ~= G.rec_err then
			G.rec_err = tostring(rerr)
			log("record: %s", G.rec_err)
		end
		if cfg.live == 1 and G.time - (G.state_at or -1e9) >= K.STATE_EVERY then
			G.state_at = G.time
			local function worth(names)
				local sum = 0
				for name in pairs(names) do
					local it = I.by_name[name]
					if it and not it.consumable and it.cost > 0 then
						sum = sum + it.cost
					end
				end
				return sum
			end
			local us, foes, all_seen, mates = 0, 0, #them == 5, {}
			for _, e in ipairs(Heroes.GetAll()) do
				if Entity.GetTeamNum(e) == team and not NPC.IsIllusion(e) then
					local ei = D.by_unit[NPC.GetUnitName(e)]
					if ei and not mates[ei.id] then
						mates[ei.id] = true
						local names = {}
						for slot = 0, K.ENEMY_INV_LAST do
							local item = NPC.GetItemByIndex(e, slot)
							local name = item and item_name(item)
							if name then
								names[name] = true
							end
						end
						if NPC.HasShard(e) then
							names.aghanims_shard = true
						end
						if NPC.HasScepter(e) then
							names.ultimate_scepter = true
						end
						us = us + worth(names)
					end
				end
			end
			for _, e in ipairs(them) do
				if G.seen[e] then
					foes = foes + worth(G.seen[e])
				else
					all_seen = false
				end
			end
			local diff, state = us - foes, "even"
			local b = K.WIN_B[clamp(math.floor(math.max(0, G.ptime or 0) / 300 + 0.5) + 1, 1, #K.WIN_B)]
			local swing = math.max(K.GOLD_SWING, K.STATE_LOGIT / b * 1000)
			local out = swing * K.GOLD_SWING_OUT / K.GOLD_SWING
			local out_b = G.state == "behind" and out or swing
			local out_a = G.state == "ahead" and out or swing
			if all_seen and diff <= -out_b then
				state = "behind"
			elseif all_seen and diff >= out_a then
				state = "ahead"
			end
			G.diff, G.items_us, G.items_them = us - foes, us, foes
			if state ~= G.state then
				log("panel state: %s, us %d, them %d, all seen %s, gap needed %d", state, us, foes, tostring(all_seen),
					math.floor(swing))
				G.rec("states", { state, us, foes, math.floor(swing) })
				G.state = state
			end
			local me = Players.GetLocal()
			local my_nw, team_nw, my_d, ally_d, allies, left, away = 0, 0, 0, 0, 0, false, false
			local my_k, my_a, team_k = 0, 0, 0
			local okme, pme = pcall(Player.GetPlayerData, me)
			local my_cs = okme and type(pme) == "table" and tonumber(pme.connectionState) or -1
			local sane = my_cs == K.CONN_CONNECTED
			if G.my_cs ~= my_cs then
				G.my_cs = my_cs
				log("my connection state %d", my_cs)
			end
			G.conn = G.conn or {}
			for _, pl in ipairs(Players.GetAll()) do
				if Entity.GetTeamNum(pl) == team then
					local okt, tpl = pcall(Player.GetTeamPlayer, pl)
					local okd, tdl = pcall(Player.GetTeamData, pl)
					local nw = okt and type(tpl) == "table" and tonumber(tpl.networth) or 0
					local deaths = okd and type(tdl) == "table" and tonumber(tdl.deaths) or 0
					local kills = okd and type(tdl) == "table" and tonumber(tdl.kills) or 0
					local assists = okd and type(tdl) == "table" and tonumber(tdl.assists) or 0
					team_nw, team_k = team_nw + nw, team_k + kills
					if pl == me then
						my_nw, my_d, my_k, my_a = nw, deaths, kills, assists
					else
						allies, ally_d = allies + 1, ally_d + deaths
						local okc, pdl = pcall(Player.GetPlayerData, pl)
						local cs = okc and type(pdl) == "table" and tonumber(pdl.connectionState) or -1
						local pid = Player.GetPlayerID(pl)
						local c = G.conn[pid]
						if not c or c.state ~= cs then
							c = { state = cs, since = G.time }
							G.conn[pid] = c
							log("ally %d connection state %d", pid, cs)
						end
						if sane and cs == K.CONN_ABANDONED then
							left = true
						elseif sane and cs == K.CONN_DISCONNECTED and G.time - c.since >= K.SOLO_AWAY then
							away = true
						end
					end
				end
			end
			local share = team_nw > 0 and my_nw / team_nw or 0
			local dying = allies > 0 and ally_d / allies >= my_d + K.SOLO_DEATHS
			local solo
			if left then
				solo = "4v5"
			elseif (G.ptime or 0) >= K.SOLO_FROM and G.state == "behind" and (share >= K.SOLO_SHARE or dying or away) then
				solo = "solo"
			end
			if solo then
				G.solo_until = G.time + K.SOLO_HOLD
			elseif G.solo and G.time < (G.solo_until or 0) then
				solo = G.solo
			end
			if solo ~= G.solo then
				log("solo state: %s (share %.2f, ally deaths %.1f, mine %d, left %s, away %s)", tostring(solo), share,
					allies > 0 and ally_d / allies or 0, my_d, tostring(left), tostring(away))
				G.rec("states", { "solo", solo or "-", math.floor(share * 100 + 0.5), my_d, ally_d })
				G.solo = solo
			end
			local minute = math.floor(G.time / 60)
			if G.time >= 0 and minute > (G.rec_nw_m or -1) then
				G.rec_nw_m = minute
				local okl, tpm = pcall(Player.GetTeamPlayer, me)
				local lh = okl and type(tpm) == "table" and tonumber(tpm.lasthit_count) or 0
				local dn = okl and type(tpm) == "table" and tonumber(tpm.deny_count) or 0
				G.rec("nw", { my_nw, team_nw, us, foes, all_seen and 1 or 0, G.state or "even", G.gold or 0, my_k, my_d, my_a,
					team_k, ally_d, NPC.GetCurrentLevel(hero), lh, dn, math.floor((G.stun_rate or 0) * 10 + 0.5) / 10 })
			end
			if solo == "4v5" or (solo and not G.solo_max) then
				G.solo_max = solo
			end
			if cfg.pdanger == 1 then
				local okd, derr = pcall(danger_tick, team, them, hero)
				if not okd and tostring(derr) ~= G.danger_err then
					G.danger_err = tostring(derr)
					log("danger: %s", G.danger_err)
				end
			else
				G.dw, G.leader, G.press, G.danger_sig = nil, nil, nil, nil
			end
		end
		if cfg.debug == 1 then
			G.probed = G.probed or {}
			for _, at in ipairs(K.NW_PROBE) do
				if G.time >= at and not G.probed[at] then
					G.probed[at] = true
					log("networth probe at %ds, my team %s", at, tostring(team))
					for _, pl in ipairs(Players.GetAll()) do
						local okt, pt = pcall(Player.GetTeamPlayer, pl)
						local okh, ph = pcall(Player.GetAssignedHero, pl)
						log("networth probe: id %s team %s hero %s networth %s", tostring(Player.GetPlayerID(pl)),
							tostring(Entity.GetTeamNum(pl)), okh and ph and NPC.GetUnitName(ph) or "-",
							tostring(okt and type(pt) == "table" and pt.networth or nil))
					end
				end
			end
		end
		local sig = { info.id, G.bpos, table.concat(them, ","), I.items_at, I.buys_at[info.id] or 0, cfg.padapt, cfg.live, I.pub_at,
			table.concat(main, ",") .. "/" .. table.concat(bagn, ","), G.state or "even", table.concat(team_sig, ","), G.solo or "-", G.danger_sig or "-",
			cfg.pdanger, cfg.pext, G.tk, math.floor((G.ptime or 0) / 60), cfg.autobuy, cfg.solo, cfg.abuy_bb, cfg.lanes, G.erole_note or "",
			cfg.pup, math.floor((G.gold or 0) / K.UP_GOLD_STEP), I.ban_v or 0 }
		local names = {}
		for name, n in pairs(owned) do
			names[#names + 1] = name .. n
		end
		for name in pairs(G.ever) do
			names[#names + 1] = "~" .. name
		end
		table.sort(names)
		sig[#sig + 1] = table.concat(names, ",")
		for _, e in ipairs(them) do
			local list = {}
			for name in pairs(G.seen[e] or {}) do
				if K.ENEMY_ITEMS[name] or K.ANTI[name] or K.MX_X[name] then
					list[#list + 1] = name
				end
			end
			table.sort(list)
			sig[#sig + 1] = e .. ":" .. table.concat(list, ",")
		end
		if G.lane then
			sig[#sig + 1] = "lane:" .. table.concat(G.lane.opp, ",") .. ":" .. tostring(G.lane.result)
		end
		sig = table.concat(sig, "|")
		if sig ~= G.sig then
			G.plan = G.compute()
			G.sig = G.plan and sig or nil
			if G.plan then
				if G.plan_timed ~= G.match then
					G.plan_timed = G.match
					log("load: first plan %.1f s after script start", os.clock() - D.t_start)
				end
				if G.plan_slots ~= #G.plan.slots then
					G.plan_slots = #G.plan.slots
					log("panel plan for %d: %d slots", info.id, #G.plan.slots)
				end
				local nx = G.plan.next and G.plan.next.name or "-"
				if nx ~= G.rec_next then
					G.rec_next = nx
					local order = {}
					for _, d in ipairs(G.plan.slots) do
						if d.state ~= "done" then
							order[#order + 1] = d.name
						end
					end
					G.rec("plan", { nx, G.gold or 0, table.concat(order, ",") })
				end
			end
		end
	end
end

local function match_score(hero, q)
	if q == "" then
		return 1
	end
	if hero.initials == q then
		return 5
	end
	if hero.key:sub(1, #q) == q then
		return 4
	end
	if #q >= 2 and hero.initials:sub(1, #q) == q then
		return 3
	end
	for _, word in ipairs(hero.words) do
		if word:sub(1, #q) == q then
			return 2
		end
	end
	if hero.key:find(q, 1, true) or hero.short:find(q, 1, true) then
		return 1
	end
	return 0
end

local function best_match()
	local q = norm(draft.query)
	if q == "" or not D.heroes then
		return nil
	end
	local used = used_set()
	local best, best_score
	for _, hero in ipairs(D.heroes) do
		if not used[hero.id] then
			local s = match_score(hero, q)
			if s > 0 and (not best or s > best_score or (s == best_score and hero.name < best.name)) then
				best, best_score = hero, s
			end
		end
	end
	return best
end

local function over_menu(x, y)
	local now = os.clock()
	local mc = W.menu_box
	if not mc or now - mc.t > K.MENU_CACHE then
		local open = Menu.Opened()
		mc = { t = now, open = open }
		if open then
			local pos, size = Menu.Pos(), Menu.Size()
			mc.x0, mc.y0, mc.x1, mc.y1 = pos.x, pos.y, pos.x + size.x, pos.y + size.y
		end
		W.menu_box = mc
	end
	return mc.open and x >= mc.x0 and x <= mc.x1 and y >= mc.y0 and y <= mc.y1 or false
end

local function in_rect(r, cx, cy)
	return r and cx >= r[1] and cx <= r[3] and cy >= r[2] and cy <= r[4]
end

local function cursor_in_window()
	local cx, cy = Input.GetCursorPos()
	if W.panel_rect and in_rect(W.panel_rect, cx, cy) and not over_menu(cx, cy) then
		return true
	end
	if not W.open or W.vis <= 0 or W.w == 0 or not W.x then
		return false
	end
	if over_menu(cx, cy) then
		return false
	end
	if W.pm_rect and in_rect(W.pm_rect, cx, cy) then
		return true
	end
	return cx >= W.x and cx <= W.x + W.w and cy >= W.y and cy <= W.y + W.h
end

local function hit_at(cx, cy)
	for i = math.min(W.nhits or 0, #W.hits), 1, -1 do
		local hit = W.hits[i]
		if cx >= hit[1] and cx <= hit[3] and cy >= hit[2] and cy <= hit[4] then
			return hit
		end
	end
	return nil
end

function W.grab()
	if not cursor_in_window() then
		return false
	end
	if not G.live then
		return true
	end
	local cx, cy = Input.GetCursorPos()
	return cy < Render.ScreenSize().y * (1 - K.HUD_SHARE) and hit_at(cx, cy) ~= nil
end

local function toast(key, arg)
	W.toast = { key = key, arg = arg, t = os.clock() }
end

local function my_hero_id()
	local ok, td = pcall(Player.GetTeamData, Players.GetLocal())
	local id = ok and type(td) == "table" and (math.tointeger(tonumber(td.selected_hero_id) or 0) or 0) or 0
	return D.by_id[id] and id or 0
end

local function pick_block(h)
	if GameRules.GetGameState() ~= K.HERO_SELECTION then
		return "cd_pk_stage"
	end
	if my_hero_id() > 0 then
		return "cd_pk_have"
	end
	for i, x in pairs(draft.steps) do
		if x == h and not draft.tentative[i] then
			return "cd_pk_taken"
		end
	end
	if draft.extra_bans[h] or draft.unavail[h] then
		return "cd_pk_taken"
	end
	return nil
end

local function pick_hero(h)
	local hero = D.by_id[h]
	local why = hero and pick_block(h)
	if not hero or why then
		toast(why or "cd_pk_taken")
		return
	end
	Engine.ExecuteCommand("dota_select_hero " .. hero.unit)
	W.pick_check = { h = h, at = os.clock() + K.PICK_CHECK }
	log("pick %s", hero.unit)
end

function W.sug_send(x, on)
	local hero = D.by_id[x.h]
	if not hero or type(hero.unit) ~= "string" then
		return false
	end
	local short = hero.unit:gsub("^npc_dota_hero_", "")
	Engine.ExecuteCommand(("suggest_hero_pick %s %d%s"):format(short, on and 1 or 0, x.ban and " ban" or ""))
	log("suggest %s: %s%s", on and "on" or "off", short, x.ban and " (ban)" or "")
	return true
end

function W.sug_list()
	local id = tostring(draft.match or "")
	if W.sug_match ~= id then
		W.sug, W.sug_match = {}, id
	end
	return W.sug
end

function W.suggested(h)
	for _, x in ipairs(W.sug_list()) do
		if x.h == h then
			return true
		end
	end
	return false
end

function W.suggest(h, quiet)
	local hero = D.by_id[h]
	if not hero then
		return
	end
	local list = W.sug_list()
	for i, x in ipairs(list) do
		if x.h == h then
			table.remove(list, i)
			W.sug_send(x, false)
			if not quiet then
				toast("cd_sug_off", hero.name)
			end
			return
		end
	end
	while #list >= K.SAY_TOP do
		W.sug_send(table.remove(list, 1), false)
	end
	local x = { h = h, ban = draft.result ~= nil and draft.result.kind == "B" }
	if W.sug_send(x, true) then
		list[#list + 1] = x
		if not quiet then
			toast("cd_sug_sent", hero.name)
		end
	end
end

function W.suggest_top()
	local res = draft.result
	if not res then
		return
	end
	local now = os.clock()
	if now < (W.say_at or 0) then
		toast("cd_say_wait")
		return
	end
	W.say_at = now + K.SAY_GAP
	local want, names = {}, {}
	for _, r in ipairs(res.rows) do
		local hero = D.by_id[r.h]
		if hero and #want < K.SAY_TOP then
			want[#want + 1], names[#names + 1] = r.h, hero.name
		end
	end
	if #want == 0 then
		return
	end
	local list = W.sug_list()
	for i = #list, 1, -1 do
		W.sug_send(table.remove(list, i), false)
	end
	for _, h in ipairs(want) do
		W.suggest(h, true)
	end
	toast("cd_sug_sent", table.concat(names, ", "))
end

function W.order_tick()
	G.buy_tick()
	G.auto_tick()
	G.skill_tick()
	local c = W.pick_check
	if not c or os.clock() < c.at then
		return
	end
	W.pick_check = nil
	local hid = my_hero_id()
	if hid == c.h then
		log("pick ok: %d", hid)
		return
	end
	local ok, td = pcall(Player.GetTeamData, Players.GetLocal())
	local raw = ok and type(td) == "table" and (math.tointeger(tonumber(td.selected_hero_id) or 0) or 0) or 0
	if hid == 0 and (c.tries or 0) < K.PICK_TRIES then
		c.tries, c.at = (c.tries or 0) + 1, os.clock() + K.PICK_CHECK
		W.pick_check = c
		return
	end
	if hid ~= 0 or raw <= 0 then
		toast("cd_pk_fail")
	end
	log("pick check: selected %d, raw %d", hid, raw)
end

local function click(right)
	local cx, cy = Input.GetCursorPos()
	local hit = hit_at(cx, cy)
	local kind, arg = hit and hit[5], hit and hit[6]
	if W.pos_menu and kind ~= "posset" and kind ~= "posbadge" and kind ~= "pmbg" then
		W.pos_menu = nil
	end
	if W.set_gear and kind ~= "set_gear" and not in_rect(W.gear_pop, cx, cy) then
		W.set_gear = nil
	end
	if W.pick and kind ~= "pick_ok" and kind ~= "pick_dont" and kind ~= "pickcard" then
		W.pick = nil
		return
	end
	if not hit then
		return
	end
	if kind == "pmbg" or kind == "stgbg" or kind == "pickcard" or kind == "pickbg" or kind == "cardbg" then
		return
	elseif kind == "pick_ok" then
		if not right then
			local p = W.pick
			W.pick = nil
			if p.dont then
				set_cfg("pick_ask", 0)
			end
			pick_hero(p.h)
		end
	elseif kind == "pick_dont" then
		if not right then
			W.pick.dont = not W.pick.dont
		end
	elseif kind == "settings" then
		W.settings = not W.settings
		W.pos_menu, W.set_gear, W.card = nil, nil, nil
	elseif kind == "set_back" then
		W.settings, W.set_gear = false, nil
	elseif kind == "set_preview" then
		W.preview = not W.preview
	elseif kind == "set_gear" then
		W.set_gear = W.set_gear ~= arg and arg or nil
	elseif kind == "set_lang" then
		set_cfg("lang", arg)
		localization.apply_lang()
		I.builds, G.sig = {}, nil
		draft.dirty = true
	elseif kind == "set_src" then
		set_cfg("source", arg)
		draft.dirty = true
	elseif kind == "set_rank" then
		set_cfg("rank", arg)
		draft.dirty = true
	elseif kind == "set_vol" then
		set_cfg("volume", arg)
	elseif kind == "set_scale_up" or kind == "set_scale_down" then
		set_cfg("zoom", clamp(cfg.zoom + (kind == "set_scale_up" and 10 or -10), 70, 130))
	elseif kind == "set_bg" then
		W.slider = true
	elseif kind == "set_toggle" then
		set_cfg(arg, cfg[arg] == 1 and 0 or 1)
		if arg == "live" then
			I.builds, I.threat_of = {}, {}
		elseif arg == "lanes" then
			I.builds, draft.dirty = {}, true
		elseif arg == "solo" then
			draft.dirty = true
		elseif arg == "autobuy" then
			G.auto_fail, G.auto_last = {}, nil
			log("auto buy %s", cfg.autobuy == 1 and "on" or "off")
		end
	elseif kind == "set_refresh" then
		refresh_data()
	elseif kind == "set_logsend" then
		LOGR.send("manual")
	elseif kind == "posbadge" then
		if right then
			set_manual(arg, nil)
			W.pos_menu = nil
		else
			W.pos_menu = not (W.pos_menu and W.pos_menu.slot == arg) and { slot = arg } or nil
			W.settings = false
		end
	elseif kind == "posset" then
		if W.pos_menu then
			set_manual(W.pos_menu.slot, arg > 0 and arg or nil)
		end
		W.pos_menu = nil
	elseif kind == "set_pview" then
		set_cfg("pview", arg)
	elseif kind == "set_pzoom_up" or kind == "set_pzoom_down" then
		set_cfg("pzoom", clamp(cfg.pzoom + (kind == "set_pzoom_up" and 10 or -10), 60, 160))
	elseif kind == "bpos" then
		I.bpos[arg.h] = arg.p
	elseif kind == "iban" then
		local h = right and 0 or arg.h
		local on = I.ban_toggle(arg.name, h)
		local it, hero = I.by_name[arg.name], D.by_id[h]
		local label = it and it.label or arg.name
		if on then
			toast(h == 0 and "cd_ban_all" or "cd_ban_one", h == 0 and label or (label .. " / " .. (hero and hero.name or "?")))
		else
			toast("cd_ban_off", label)
		end
		G.sig = nil
	elseif kind == "unban" then
		if not right then
			I.ban_toggle(arg.name, arg.h)
			G.sig = nil
		end
	elseif kind == "unban_all" then
		if not right then
			for _, b in ipairs(I.ban_list()) do
				I.ban_toggle(b.name, b.h)
			end
			G.sig = nil
		end
	elseif kind == "qbuy" then
		local shift = Input.IsKeyDown(Enum.ButtonCode.KEY_LSHIFT, true) or Input.IsKeyDown(Enum.ButtonCode.KEY_RSHIFT, true)
		if not right and shift then
			if pcall(Engine.SetQuickBuy, arg.name, true) then
				W.qflash = { id = arg.id, t = os.clock() }
				log("quick buy reset to %s", arg.name)
			end
		elseif not right then
			local item = I.by_name[arg.name]
			local ok, info = pcall(Player.GetQuickBuyInfo, Players.GetLocal())
			local has = false
			for _, id in ipairs(ok and type(info) == "table" and type(info.m_quickBuyItems) == "table" and info.m_quickBuyItems or {}) do
				if item and id == item.id then
					has = true
				end
			end
			if has or pcall(Engine.SetQuickBuy, arg.name, false) then
				W.qflash = { id = arg.id, t = os.clock() }
			end
		elseif G.buy(arg.name) then
			W.qflash = { id = arg.id, t = os.clock() }
		end
	elseif kind == "pdrag" then
		if not right then
			W.pdrag, W.pdx, W.pdy = true, cx - W.px, cy - W.py
		end
	elseif kind == "sbar" then
		if not right then
			local grab = cy - arg.ty
			if grab < 0 or grab > arg.th then
				grab = arg.th / 2
			end
			W.sdrag = { id = arg.id, grab = grab }
		end
	elseif kind == "search" then
		W.focus = true
	elseif kind == "head" then
		if not right then
			W.drag, W.dx, W.dy = true, cx - W.x, cy - W.y
		end
	elseif kind == "slot" then
		if right then
			draft.steps[arg] = nil
			draft.manual[draft.mode][arg] = nil
			draft.edit = nil
			if draft.mode == 1 then
				draft.target = arg
			end
		elseif draft.steps[arg] then
			draft.tentative[arg] = nil
			draft.edit = draft.edit ~= arg and arg or nil
			W.grid_on = draft.edit ~= nil
		else
			draft.edit = nil
			if draft.mode == 1 then
				draft.target = arg
			end
			W.grid_on = true
		end
		W.card = nil
		draft.dirty = true
	elseif kind == "mode" then
		set_mode(arg)
	elseif kind == "sumrow" or kind == "card_hero" then
		draft.build_h = arg
		W.card, W.settings, W.set_gear = arg, false, nil
	elseif kind == "nav_draft" then
		W.card, W.settings, W.set_gear = nil, false, nil
	elseif kind == "grid_toggle" then
		W.grid_on, W.focus = not W.grid_on, true
	elseif kind == "card_close" then
		W.card = nil
	elseif kind == "suggest" then
		if not right then
			W.suggest(arg)
		end
	elseif kind == "suggest_top" then
		if not right then
			W.suggest_top()
		end
	elseif kind == "hero" or kind == "row" then
		if not right then
			put(arg)
			W.grid_on = false
		elseif kind == "row" then
			local why = pick_block(arg)
			if why then
				toast(why)
			elseif cfg.pick_ask == 1 then
				W.pick = { h = arg, dont = false }
			else
				pick_hero(arg)
			end
		end
	elseif kind == "pos" then
		draft.filter = arg
		draft.filter_user, draft.filter_auto = true, false
		draft.dirty = true
		W.list_scroll = 0
	elseif kind == "first" then
		draft.first = arg
		draft.dirty = true
	elseif kind == "undo" then
		undo()
	elseif kind == "reset" then
		reset_draft()
	elseif kind == "close" then
		W.open, W.auto, W.pos_menu, W.settings = false, false, nil, false
	end
end

local function type_key(key)
	local now = os.clock()
	local ch = K.CHARS[key]
	if ch then
		if W.down[key] then
			return
		end
		W.down[key] = true
	elseif now - (W.typed[key] or -1) < K.TYPE_GAP then
		return
	end
	W.typed[key] = now
	if ch then
		if #draft.query < 24 then
			draft.query = draft.query .. ch
			W.grid_scroll = 0
		end
	elseif key == K.BACKSPACE then
		if #draft.query > 0 then
			draft.query = draft.query:sub(1, -2)
		else
			undo()
		end
	elseif key == K.ENTER or key == K.PAD_ENTER then
		local hero = best_match()
		if hero then
			put(hero.id)
		end
	elseif key == K.ESCAPE then
		if W.pick then
			W.pick = nil
		elseif W.pos_menu then
			W.pos_menu = nil
		elseif W.card then
			W.card = nil
		elseif W.settings then
			W.settings = false
		elseif W.grid_on and #draft.query == 0 then
			W.grid_on = false
		elseif #draft.query > 0 then
			draft.query = ""
		else
			W.open = false
		end
	end
end

local function open_window()
	W.open, W.focus = true, not K.PANEL_STATES[GameRules.GetGameState()]
end

function W.timed(name, f)
	local t0 = os.clock()
	local ok, err = pcall(f)
	W.cost = W.cost or {}
	W.cost[name] = (W.cost[name] or 0) + os.clock() - t0
	return ok, err
end

function W.slow(kind)
	local total = 0
	local cost = W.cost or {}
	for name, t in pairs(cost) do
		if name:sub(1, 1) ~= "." then
			total = total + t
		end
	end
	local mem = collectgarbage("count")
	local freed = (mem and W.mem_last) and (W.mem_last - mem) / 1024 or 0
	local loads, sizes = W.img_new or 0, W.tw_n or 0
	local now = os.clock()
	local pf = W.perf
	if not pf then
		pf = { at = now, parts = {}, n = {}, sum = {}, max = {}, alloc = 0, drops = 0, drop_mb = 0, sizes = 0 }
		W.perf = pf
	end
	pf.n[kind] = (pf.n[kind] or 0) + 1
	pf.sum[kind] = (pf.sum[kind] or 0) + total
	pf.max[kind] = math.max(pf.max[kind] or 0, total)
	pf.sizes = pf.sizes + sizes
	for name, t in pairs(W.cost or {}) do
		pf.parts[name] = (pf.parts[name] or 0) + t
	end
	if freed < 0 then
		pf.alloc = pf.alloc - freed
	elseif freed > 2 then
		pf.drops, pf.drop_mb = pf.drops + 1, pf.drop_mb + freed
	end
	if now - pf.at >= K.PERF_EVERY then
		local span = now - pf.at
		if cfg.debug == 1 then
			local top = {}
			for name, t in pairs(pf.parts) do
				if name:sub(1, 1) ~= "." then
					top[#top + 1] = { name, t }
				end
			end
			table.sort(top, function(x, y)
				return x[2] > y[2]
			end)
			for i = #top, 1, -1 do
				if i > 6 then
					top[i] = nil
				else
					top[i] = ("%s %.2f"):format(top[i][1], top[i][2] / math.max(1, pf.n.frame or 1) * 1000)
				end
			end
			log("perf %.0fs: %d frames, frame %.2f ms avg %.1f max, update %.2f ms avg %.1f max, per frame [%s], lua %s MB, alloc %.1f MB/s, gc drops %d (%.0f MB), text sizes %d, gc %s",
				span, pf.n.frame or 0, (pf.sum.frame or 0) / math.max(1, pf.n.frame or 1) * 1000, (pf.max.frame or 0) * 1000,
				(pf.sum.update or 0) / math.max(1, pf.n.update or 1) * 1000, (pf.max.update or 0) * 1000, table.concat(top, ", "),
				mem and ("%.0f"):format(mem / 1024) or "?", pf.alloc / span, pf.drops, pf.drop_mb, pf.sizes,
				tostring(W.gc_mode or collectgarbage("isrunning")))
		end
		W.perf = nil
	end
	if total * 1000 < K.SLOW_MS or now < (W.slow_at or 0) then
		for name in pairs(cost) do
			cost[name] = 0
		end
		W.mem_last, W.img_new, W.tw_n = mem, 0, 0
		return
	end
	local parts = {}
	for name, t in pairs(cost) do
		if t >= K.SLOW_PART then
			parts[#parts + 1] = { name, t }
		end
	end
	W.cost = {}
	W.mem_last, W.img_new, W.tw_n = mem, 0, 0
	W.slow_at = now + K.SLOW_GAP
	table.sort(parts, function(a, b)
		return a[2] > b[2]
	end)
	for i, p in ipairs(parts) do
		parts[i] = ("%s %d ms"):format(p[1], math.floor(p[2] * 1000 + 0.5))
	end
	log("slow %s: %d ms (%s), window %s, focus %s, grid %s, umbrella menu %s, lua %s MB, freed %.1f MB, new images %d, text sizes %d",
		kind, math.floor(total * 1000 + 0.5), table.concat(parts, ", "), tostring(W.open and W.vis > 0), tostring(W.focus),
		tostring(W.grid_on), tostring(Menu.Opened()), mem and ("%.0f"):format(mem / 1024) or "?", freed, loads, sizes)
end

local draw_window, draw_panel, draw_tips
local load_stage, spinner, STAGE_TEXT

do
	local s, m, dt, twc = nil, {}, 0, { n = 0 }
	local Q = { v1 = Vec2(0, 0), v2 = Vec2(0, 0), v3 = Vec2(0, 0), v4 = Vec2(0, 0), col = { n = 0 }, paths = {}, ek = {}, pxs = {}, gk = {}, tip_r = {}, rs = setmetatable({}, { __mode = "k" }), hargs = {}, nharg = 0 }
	local PX

	Q.pxmt = {
		__index = function(t, v)
			local r = math.floor(v * t.s + 0.5)
			t[v] = r
			return r
		end,
	}

	function Q.scale(v)
		s = v
		local t = Q.pxs[v]
		if not t then
			Q.npx = (Q.npx or 0) + 1
			if Q.npx > K.SCALES then
				Q.pxs, Q.npx = {}, 1
			end
			t = setmetatable({ s = v }, Q.pxmt)
			Q.pxs[v] = t
		end
		PX = t
	end
	local A = W.anim

	local function ease(k)
		local q = 1 - clamp(k, 0, 1)
		return 1 - q * q * q
	end

	local function approach(key, target, speed)
		local v = A[key]
		if v == nil then
			v = target
		else
			local e = Q.ek[speed]
			if not e then
				e = 1 - math.exp(-dt * speed)
				Q.ek[speed] = e
			end
			v = v + (target - v) * e
			if math.abs(target - v) < 0.002 then
				v = target
			end
		end
		A[key] = v
		return v
	end

	local function tween(key, target, dur)
		local t = A[key]
		if type(t) ~= "table" or W.snap then
			t = { v = target, from = target, to = target, k = 1 }
			A[key] = t
		elseif t.to ~= target then
			t.from, t.to, t.k = t.v, target, 0
		end
		if t.k < 1 then
			t.k = math.min(1, t.k + dt / dur)
			t.v = t.from + (t.to - t.from) * ease(t.k)
		else
			t.v = t.to
		end
		return t.v
	end

	local function rgba(r, g, b, a)
		if a > 255 then
			a = 255
		elseif a < 0 then
			a = 0
		end
		local key = ((r * 256 + g) * 256 + b) * 256 + a
		local cc = Q.col
		local c = cc[key]
		if not c then
			if cc.n >= K.COLOR_MAX then
				cc = { n = 0 }
				Q.col = cc
			end
			c = Color(r, g, b, a)
			cc[key], cc.n = c, cc.n + 1
		end
		return c
	end

	local function mix(c1, c2, k)
		return rgba(
			math.floor(c1.r + (c2.r - c1.r) * k + 0.5),
			math.floor(c1.g + (c2.g - c1.g) * k + 0.5),
			math.floor(c1.b + (c2.b - c1.b) * k + 0.5),
			math.floor(c1.a + (c2.a - c1.a) * k + 0.5))
	end

	local function load_font(weight)
		local flags = Enum.FontCreate.FONTFLAG_ANTIALIAS
		for _, name in ipairs(K.FONTS) do
			local ok, handle = pcall(Render.LoadFont, name, flags, weight)
			if ok and handle and handle ~= 0 then
				return handle
			end
		end
		return Render.LoadFont(K.FONTS[#K.FONTS], flags, weight)
	end

	local function ensure_fonts()
		if not W.fonts then
			W.fonts = {
				bold = load_font(Enum.FontWeight.BOLD),
				semi = load_font(Enum.FontWeight.SEMIBOLD),
				medium = load_font(Enum.FontWeight.MEDIUM),
				regular = load_font(Enum.FontWeight.NORMAL),
				icon = Render.LoadFont("FontAwesomeEx", Enum.FontCreate.FONTFLAG_ANTIALIAS, 400),
			}
		end
	end

	local function image(path)
		local handle = W.images[path]
		if handle == nil then
			local ok, result = pcall(Render.LoadImage, path)
			handle = (ok and result and result ~= 0) and result or false
			W.images[path] = handle
			W.img_new = (W.img_new or 0) + 1
		end
		return handle or nil
	end

	function Q.asset(dir, name, tail)
		local t = Q.paths[dir]
		if not t then
			t = {}
			Q.paths[dir] = t
		end
		local p = t[name]
		if not p then
			p = "panorama/images/" .. dir .. name .. (tail or "_png.vtex_c")
			t[name] = p
		end
		return image(p)
	end

	local function portrait(h)
		local hero = D.by_id[h]
		return hero and Q.asset("heroes/", hero.unit)
	end

	local function mini(h)
		local hero = D.by_id[h]
		return hero and Q.asset("heroes/icons/", hero.unit)
	end

	local function fade(c, a)
		if a >= 1 then
			return c
		end
		return rgba(c.r, c.g, c.b, math.floor(c.a * clamp(a, 0, 1) + 0.5))
	end

	local function tw(font, size, text)
		if text == "" then
			return 0
		end
		local fc = twc[font]
		if not fc then
			fc = {}
			twc[font] = fc
		end
		local sc = fc[size]
		if not sc then
			sc = {}
			fc[size] = sc
		end
		local w = sc[text]
		if w then
			return w
		end
		W.tw_n = (W.tw_n or 0) + 1
		w = Render.TextSize(font, size, text).x
		if w and w > 0 then
			if twc.n >= K.TW_MAX then
				twc = { n = 0 }
				fc, sc = {}, {}
				twc[font], fc[size] = fc, sc
			end
			sc[text] = w
			twc.n = twc.n + 1
		end
		return w
	end

	local function th(font, size)
		local fm = m[font]
		if not fm then
			fm = {}
			m[font] = fm
		end
		local h = fm[size]
		if not h then
			local v = Render.TextSize(font, size, "Ay").y
			h = (v and v > 0) and v or size
			fm[size] = h
		end
		return h
	end

	local function text(font, size, str, x, cy, color, free)
		local y = math.floor(cy - th(font, size) / 2 + 0.5)
		local tx
		if free then
			tx = x
		else
			tx = math.floor(x + 0.5)
		end
		Render.Text(font, size, str, Q.v1:Set(tx, y), color)
		return tw(font, size, str)
	end

	local function rect(x0, y0, x1, y1, color, r)
		Render.FilledRect(Q.v1:Set(x0, y0), Q.v2:Set(x1, y1), color, r or 0, K.ROUND)
	end

	local function grad(x0, y0, x1, y1, ca, cb, r, vertical)
		if vertical then
			Render.Gradient(Q.v1:Set(x0, y0), Q.v2:Set(x1, y1), ca, ca, cb, cb, r or 0, K.ROUND)
		else
			Render.Gradient(Q.v1:Set(x0, y0), Q.v2:Set(x1, y1), ca, cb, ca, cb, r or 0, K.ROUND)
		end
	end

	local function logo(cx, cy, size, a)
		if W.logo == nil then
			local svg = '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 64"><path fill="#ffffff" fill-rule="evenodd" d="'
				.. K.LOGO_PATH .. '"/></svg>'
			local ok, h = pcall(Render.LoadSvgString, svg, Vec2(128, 128), "dh_logo")
			W.logo = ok and h or false
			log("logo svg: %s", ok and tostring(h) or ("failed " .. tostring(h)))
		end
		if not W.logo then
			return false
		end
		local x0, y0 = math.floor(cx - size / 2), math.floor(cy - size / 2)
		local n = K.LOGO_BANDS
		for i = 0, n - 1 do
			local by0 = y0 + math.floor(size * i / n)
			local by1 = y0 + math.floor(size * (i + 1) / n)
			Render.PushClip(Q.v1:Set(x0, by0), Q.v2:Set(x0 + size, by1), true)
			Render.Image(W.logo, Q.v1:Set(x0, y0), Q.v2:Set(size, size), fade(mix(P.ACC_A, P.ACC_B, (i + 0.5) / n), a))
			Render.PopClip()
		end
		return true
	end

	function Q.harg(k1, v1, k2, v2, k3, v3)
		local n = Q.nharg + 1
		Q.nharg = n
		local t = Q.hargs[n]
		if t then
			for k in pairs(t) do
				t[k] = nil
			end
		else
			t = {}
			Q.hargs[n] = t
		end
		t[k1], t[k2] = v1, v2
		if k3 then
			t[k3] = v3
		end
		return t
	end

	local function hit(x0, y0, x1, y1, kind, arg)
		if W.nohit then
			return
		end
		local clip = W.hit_clip
		if clip then
			y0, y1 = math.max(y0, clip[1]), math.min(y1, clip[2])
			if y1 <= y0 then
				return
			end
		end
		local n = (W.nhits or 0) + 1
		W.nhits = n
		local h = W.hits[n]
		if h then
			h[1], h[2], h[3], h[4], h[5], h[6] = x0, y0, x1, y1, kind, arg
		else
			W.hits[n] = { x0, y0, x1, y1, kind, arg }
		end
	end

	local function hovered(x0, y0, x1, y1)
		local cx, cy = Input.GetCursorPos()
		if W.gear_block and in_rect(W.gear_block, cx, cy) then
			return false
		end
		return cx >= x0 and cx <= x1 and cy >= y0 and cy <= y1 and not over_menu(cx, cy) and not W.drag
	end

	local function glyph(str, x, cy, size, color)
		local w = tw(W.fonts.icon, size, str)
		text(W.fonts.icon, size, str, x - w / 2, cy, color)
	end

	local function vline(x, cy, half, a)
		rect(x, cy - half, x + math.max(1, PX[1]), cy + half, fade(P.SEP, a))
	end

	local function fmt_games(n)
		if n >= 10000 then
			return ("%dk"):format(math.floor(n / 1000 + 0.5))
		elseif n >= 1000 then
			return ("%.1fk"):format(n / 1000)
		end
		return tostring(n)
	end

	local function pct(v)
		return (sigm(v) - 0.5) * 100
	end

	local function fmt_eta(sec, short)
		if not sec then
			return nil
		end
		local key = short and "cd_eta_short_" or "cd_eta_"
		if sec < 60 then
			return L(key .. "s"):format(math.max(5, math.floor(sec / 5 + 0.5) * 5))
		end
		return L(key .. "m"):format(math.floor(sec / 60 + 0.5))
	end

	local function fmt_updated(ts)
		if not ts or ts <= 0 then
			return L("cd_upd_never")
		end
		local age = os.time() - ts
		if age < 120 then
			return L("cd_upd_now")
		elseif age < 3600 then
			return L("cd_upd_min"):format(math.floor(age / 60))
		elseif age < 86400 then
			return L("cd_upd_hour"):format(math.floor(age / 3600))
		end
		return L("cd_upd_day"):format(math.floor(age / 86400))
	end

	STAGE_TEXT = {
		heroes = "cd_ld_heroes",
		pro = "cd_ld_pro",
		matches = "cd_ld_matches",
		build = "cd_ld_build",
		wait = "cd_ld_wait",
		error = "cd_ld_error",
		slow = "cd_ld_slow",
	}

	function load_stage()
		if D.error and os.clock() < D.next_request then
			return D.error:lower():find("timeout", 1, true) and "slow" or "error"
		end
		local sets = source() == 1 and { D.sets[0], D.sets[1] } or { D.sets[0] }
		for _, S in ipairs(sets) do
			if S.job then
				return "matches"
			end
		end
		if D.status == "cd_st_heroes" then
			return "heroes"
		end
		if D.status == "cd_st_pro" then
			return "pro"
		end
		for _, S in ipairs(sets) do
			if S.build then
				return "build"
			end
		end
		if not D.heroes or not D.sets[0].stats then
			return "wait"
		end
		return nil
	end

	function spinner(cx, cy, r, a, color, thick)
		local t = os.clock()
		local p = Vec2(cx, cy)
		Render.Circle(p, r, fade(P.CELL, a * 2), thick, 0, 1, false, 48)
		if color == P.BAD then
			Render.Circle(p, r, fade(color, a), thick, 270, 1, false, 48)
			return
		end
		Render.Circle(p, r, fade(color, a), thick, (t * 320) % 360, 0.22 + 0.1 * math.sin(t * 2.4), true, 48)
	end

	local function kilo(n)
		return ("%dk"):format(math.floor(n / 1000 + 0.5))
	end

	local function pos_icon(p)
		return Q.asset("rank_tier_icons/handicap/", K.POS_ICON[p], "icon_psd.vtex_c")
	end

	local function draw_pos(p, x, cy, size, a)
		local img = pos_icon(p)
		if img then
			Render.Image(img, Q.v1:Set(x, math.floor(cy - size / 2 + 0.5)), Q.v2:Set(size, size), fade(K.POS_COLOR[p], a))
		end
		return size
	end

	local function tip_at(x0, y0, x1, y1)
		if W.nohit or not hovered(x0, y0, x1, y1) then
			return false
		end
		local r = Q.tip_r
		r[1], r[2], r[3], r[4] = x0, y0, x1, y1
		return true
	end

	local function tip_put(id, title, body, pos)
		if W.pos_menu and id:sub(1, 2) ~= "pm" then
			return
		end
		local r = Q.tip_r
		W.tip_cand = { id = id, x0 = r[1], y0 = r[2], x1 = r[3], y1 = r[4], title = title, body = body, pos = pos, s = s }
	end

	local function tip(id, x0, y0, x1, y1, title, body, pos)
		if tip_at(x0, y0, x1, y1) then
			tip_put(id, title, body, pos)
		end
	end

	local function draw_tip(a)
		local c = cfg.tips == 1 and W.tip_cand or nil
		W.tip_cand = nil
		local now = os.clock()
		if c and not cursor_in_window() then
			c = nil
		end
		if c then
			if W.tip_id ~= c.id then
				local warm = W.tip_on or (W.tip_off and now - W.tip_off < K.TIP_GRACE and (W.tip_off_a or 0) > 0.5)
				W.tip_id, W.tip_t, W.tip_warm = c.id, warm and now - 1 or now, warm
			end
			W.tip_last = c
		else
			W.tip_id = nil
		end
		local show = c ~= nil and now - W.tip_t > K.TIP_DELAY
		local ta
		if show then
			if not W.tip_on then
				W.tip_on = true
				W.tip_from = W.tip_warm and now - K.TIP_FADE or now
			end
			ta = clamp((now - W.tip_from) / K.TIP_FADE, 0, 1)
		else
			if W.tip_on then
				W.tip_on, W.tip_off, W.tip_off_a = false, now, W.tip_cur or 1
			end
			local since = W.tip_off and now - W.tip_off - K.TIP_HOLD
			if not since then
				ta = 0
			elseif since < 0 then
				ta = W.tip_off_a
			else
				ta = W.tip_off_a * clamp(1 - since / K.TIP_FADE, 0, 1)
			end
		end
		W.tip_cur = ta
		ta = ta * a
		local t = W.tip_last
		if ta <= 0.01 or not t then
			return
		end
		Q.scale(t.s or s)
		local lines = {}
		for line in (t.body or ""):gmatch("[^\n]+") do
			lines[#lines + 1] = line
		end
		local icon = t.pos and PX[14] + PX[6] or 0
		local w = icon + tw(W.fonts.bold, PX[12], t.title)
		for _, line in ipairs(lines) do
			w = math.max(w, tw(W.fonts.regular, PX[11], line))
		end
		local pad_x, pad_y, line_h = PX[10], PX[8], PX[15]
		w = math.floor(w + pad_x * 2 + 0.5)
		local h = pad_y * 2 + PX[16] + #lines * line_h + (#lines > 0 and PX[2] or 0)
		local screen = Render.ScreenSize()
		local x = math.floor(clamp((t.x0 + t.x1) / 2 - w / 2, 4, screen.x - w - 4))
		local y = math.floor(t.y1 + PX[6])
		if y + h > screen.y - 4 then
			y = math.floor(t.y0 - PX[6] - h)
		end
		rect(x, y, x + w, y + h, fade(P.TIP, ta), PX[8])
		local cy = y + pad_y + PX[8]
		local tx = x + pad_x
		if t.pos then
			draw_pos(t.pos, tx, cy, PX[14], ta)
			tx = tx + icon
		end
		text(W.fonts.bold, PX[12], t.title, tx, cy, fade(P.TEXT, ta))
		cy = cy + PX[10] + PX[2] + line_h / 2
		for _, line in ipairs(lines) do
			text(W.fonts.regular, PX[11], line, x + pad_x, cy, fade(P.MUTED, ta))
			cy = cy + line_h
		end
	end

	local function draw_loader(x0, y0, x1, y1, a, stage)
		local cx, cy = (x0 + x1) / 2, (y0 + y1) / 2 - PX[10]
		local err = stage == "error"
		if err then
			glyph("\u{f071}", cx, cy - PX[34], PX[22], fade(P.WARN, a))
		else
			spinner(cx, cy - PX[34], PX[14], a, P.TEXT, math.max(1.5, PX[2.5]))
		end
		local title = L(STAGE_TEXT[stage] or "cd_ld_wait")
		text(W.fonts.bold, PX[13], title, cx - tw(W.fonts.bold, PX[13], title) / 2, cy, fade(P.TEXT, a))
		local sub, eta
		if err or stage == "slow" then
			sub = L("cd_ld_retry"):format(math.max(1, math.ceil(D.next_request - os.clock())))
		elseif stage == "matches" then
			local have, target = job_counts()
			local days = job_days()
			if days then
				sub = L("cd_ld_days"):format(kilo(have), days, K.CM_DAYS)
			else
				sub = L("cd_ld_count"):format(kilo(have), kilo(target))
			end
			eta = fmt_eta(job_eta(), false)
		end
		if sub then
			local sw = tw(W.fonts.regular, PX[11], sub)
			local ew = eta and tw(W.fonts.regular, PX[11], eta) + PX[16] or 0
			local sx = cx - (sw + ew) / 2
			text(W.fonts.regular, PX[11], sub, sx, cy + PX[20], fade(P.MUTED, a))
			if eta then
				vline(sx + sw + PX[8], cy + PX[20], PX[6], a)
				text(W.fonts.regular, PX[11], eta, sx + sw + PX[16], cy + PX[20], fade(P.MUTED, a))
			end
		end
		if err then
			return
		end
		local bw, bh = PX[180], math.max(2, PX[3])
		local by = cy + PX[38]
		local prog = tween("loader_p", stage == "matches" and job_progress() or (stage == "build" and 1 or 0), 0.4)
		rect(cx - bw / 2, by, cx + bw / 2, by + bh, fade(P.CELL, a * 1.6), bh / 2)
		if prog > 0 then
			grad(cx - bw / 2, by, cx - bw / 2 + bw * prog, by + bh, fade(P.ACC_A, a * 0.9), fade(P.ACC_B, a * 0.9), bh / 2)
		end
		if not D.sets[0].stats then
			local hint = L("cd_ld_first")
			text(W.fonts.regular, PX[10], hint, cx - tw(W.fonts.regular, PX[10], hint) / 2, by + PX[22], fade(P.DIM, a))
		end
	end

	local function draw_slot(i, x, y, w, h, a)
		local badge
		local step = STEPS()[i]
		local hero = draft.steps[i]
		local r = PX[4]
		local placed = W.placed[i]
		if hero and (not placed or placed.h ~= hero) then
			placed = { h = hero, t = os.clock() }
			W.placed[i] = placed
		elseif not hero then
			W.placed[i] = nil
			placed = nil
		end
		local e = placed and ease((os.clock() - placed.t) / K.POP) or 0
		if e < 1 then
			rect(x, y, x + w, y + h, fade(P.CELL, a * (1 - e)), r)
		end
		if hero then
			local sc = 0.84 + 0.16 * e
			local dw, dh = w * sc, h * sc
			local x0, y0 = x + (w - dw) / 2, y + (h - dh) / 2
			local ha = a * e * approach("tent" .. i, (draft.mode == 1 and draft.tentative[i]) and K.TENTATIVE or 1, 12)
			local img = portrait(hero)
			if step.kind == "P" then
				if img then
					Render.Image(img, Q.v1:Set(x0, y0), Q.v2:Set(dw, dh), fade(P.WHITE, ha), r, K.ROUND)
				else
					rect(x0, y0, x0 + dw, y0 + dh, fade(P.FIELD, ha), r)
				end
				local pos = draft.slot_pos[i]
				if pos then
					local pa = a * approach("sp" .. i .. ":" .. pos, 1, 14) * e
					local size = PX[12]
					local manual = draft.manual[draft.mode][i] ~= nil
					local bh = approach("bh" .. i, (step_team(i) == 0 and hovered(x, y + h - size - PX[5], x + size + PX[8], y + h)) and 1 or 0, 20)
					local bg = mix(P.SHADE, P.TIP, math.max(bh, manual and 0.6 or 0))
					rect(x + PX[1], y + h - size - PX[3], x + size + PX[5], y + h - PX[1], fade(bg, pa * 0.9), PX[3])
					draw_pos(pos, x + PX[3], y + h - PX[2] - size / 2, size, pa)
					if step_team(i) == 0 then
						badge = { x, y + h - size - PX[5], x + size + PX[8], y + h }
					end
				end
			else
				if img then
					Render.Image(img, Q.v1:Set(x0, y0), Q.v2:Set(dw, dh), fade(P.BAN, ha), r, K.ROUND, Q.v3:Set(0, 0), Q.v4:Set(1, 1), 1.0)
				else
					rect(x0, y0, x0 + dw, y0 + dh, fade(P.FIELD, ha), r)
				end
				local k = ease((os.clock() - placed.t - K.POP * 0.5) / K.POP)
				if k > 0 then
					local ax, ay = x + w - PX[8], y + PX[3]
					local bx, by = x + PX[8], y + h - PX[3]
					Render.Line(Q.v1:Set(ax, ay), Q.v2:Set(ax + (bx - ax) * k, ay + (by - ay) * k), fade(P.BAD, a * 0.85),
						math.max(1, PX[1.5]))
				end
			end
		end
		local hv = approach("sh" .. i, hovered(x, y, x + w, y + h) and 1 or 0, 20)
		if hv > 0 then
			rect(x, y, x + w, y + h, fade(P.HOVER, a * hv), r)
		end
		if i == cur_step() then
			W.cur_target = { x - 1 - W.ox, y - 1 - W.oy, w + 2, h + 2 }
		end
		hit(x, y, x + w, y + h, "slot", i)
		if badge then
			W.badge_rect[i] = { badge[1] - W.ox, badge[2] - W.oy, badge[3] - W.ox, badge[4] - W.oy }
			hit(badge[1], badge[2], badge[3], badge[4], "posbadge", i)
			if tip_at(badge[1], badge[2], badge[3], badge[4]) then
				tip_put("badge" .. i, L("cd_tip_badge_t"), L("cd_tip_badge"))
			end
		else
			W.badge_rect[i] = nil
		end
	end

	local function draw_pos_menu(a)
		local menu = W.pos_menu
		if menu and not W.badge_rect[menu.slot] then
			W.pos_menu, menu = nil, nil
		end
		local ma = approach("pm_a", menu and 1 or 0, 22) * a
		if menu then
			W.pm_last = menu
		end
		menu = menu or W.pm_last
		local anchor = menu and W.badge_rect[menu.slot]
		if ma <= 0.01 or not anchor then
			return
		end
		local size, gap, pad = PX[26], PX[3], PX[4]
		local w = pad * 2 + 6 * size + 5 * gap
		local h = size + pad * 2
		local screen = Render.ScreenSize()
		local x = math.floor(clamp(anchor[1] + W.ox, 4, screen.x - w - 4))
		local y = math.floor(anchor[4] + W.oy + PX[4])
		if y + h > screen.y - 4 then
			y = math.floor(anchor[2] + W.oy - PX[4] - h)
		end
		rect(x, y, x + w, y + h, fade(P.TIP, ma), PX[8])
		if W.pos_menu then
			hit(x, y, x + w, y + h, "pmbg")
			W.pm_rect = { x, y, x + w, y + h }
		end
		local current = draft.manual[draft.mode][menu.slot] or 0
		local cy = y + pad + size / 2
		for k = 0, 5 do
			local bx = x + pad + k * (size + gap)
			local hv = approach("pm_h" .. k, (W.pos_menu and hovered(bx, y + pad, bx + size, y + pad + size)) and 1 or 0, 20)
			local bg = current == k and P.CHIP_ON or mix(P.CELL, P.HOVER, hv)
			rect(bx, y + pad, bx + size, y + pad + size, fade(bg, ma), PX[6])
			if k == 0 then
				glyph("\u{f0d0}", bx + size / 2, cy, PX[12], fade(current == 0 and P.TEXT or P.MUTED, ma))
			else
				draw_pos(k, bx + (size - PX[16]) / 2, cy, PX[16], ma)
			end
			if W.pos_menu then
				hit(bx, y + pad, bx + size, y + pad + size, "posset", k)
				if tip_at(bx, y + pad, bx + size, y + pad + size) then
					tip_put("pm" .. k, k == 0 and L("cd_tip_auto_t") or L("cd_posT" .. k), k == 0 and L("cd_tip_pm_auto") or L("cd_tip_pm"), k > 0 and k or nil)
				end
			end
		end
	end

	local function draw_cursor(a)
		local t = W.cur_target
		local ca = approach("cur_a", t and 1 or 0, 16)
		if not t then
			t = W.cur_last
			if not t or ca <= 0 then
				return
			end
		end
		W.cur_last = t
		local x = tween("cur_x", t[1], K.MOVE) + W.ox
		local y = tween("cur_y", t[2], K.MOVE) + W.oy
		local w = tween("cur_w", t[3], K.MOVE)
		local h = tween("cur_h", t[4], K.MOVE)
		local col = mix(P.ACC, P.MUTED, approach("cur_edit", draft.edit and 1 or 0, 16))
		Render.Rect(Q.v1:Set(x, y), Q.v2:Set(x + w, y + h), fade(col, a * ca), PX[5], K.ROUND, math.max(1, PX[1.5]))
	end

	local function segment(id, x, cy, labels, value, kind, a)
		local seg_h, pad = PX[24], PX[9]
		local widths, total = {}, PX[4]
		for i, label in ipairs(labels) do
			widths[i] = tw(W.fonts.medium, PX[11], label) + pad * 2
			total = total + widths[i]
		end
		rect(x, cy - seg_h / 2, x + total, cy + seg_h / 2, fade(P.FIELD, a), PX[8])
		local bx = x + PX[2]
		local on_x = bx
		for i = 1, value do
			on_x = on_x + widths[i]
		end
		local kx = tween(id .. "_x", on_x - x, K.MOVE) + x
		local kw = tween(id .. "_w", widths[value + 1], K.MOVE)
		rect(kx, cy - seg_h / 2 + PX[2], kx + kw, cy + seg_h / 2 - PX[2], fade(P.CHIP_ON, a), PX[6])
		for i, label in ipairs(labels) do
			local on = approach(id .. "_t" .. i, value == i - 1 and 1 or 0, 18)
			text(W.fonts.medium, PX[11], label, bx + pad, cy, fade(mix(P.MUTED, P.TEXT, on), a))
			hit(bx, cy - seg_h / 2, bx + widths[i], cy + seg_h / 2, kind, i - 1)
			bx = bx + widths[i]
		end
		return total, seg_h
	end

	local function segment_width(labels)
		local total = PX[4]
		for _, label in ipairs(labels) do
			total = total + tw(W.fonts.medium, PX[11], label) + PX[9] * 2
		end
		return total
	end

	local SB = { field = { grid = "grid_scroll", list = "list_scroll", set = "set_scroll" } }

	function SB.scroll(id, key, max)
		local field = SB.field[id]
		local geo = W.sb_geo and W.sb_geo[id]
		local drag = W.sdrag and W.sdrag.id == id
		if drag and geo then
			if Input.IsKeyDown(K.MOUSE1, true) then
				local _, cy = Input.GetCursorPos()
				W[field] = clamp((cy - W.sdrag.grab - geo.y0) / math.max(1, geo.track - geo.th), 0, 1) * max
			else
				W.sdrag, drag = nil, false
			end
		end
		W[field] = clamp(W[field] or 0, 0, max)
		if drag then
			A[key] = { v = W[field], from = W[field], to = W[field], k = 1 }
		end
		return math.floor(tween(key, W[field], K.MOVE) + 0.5)
	end

	function SB.bar(id, x1, y0, y1, shown, max, a)
		W.sb_geo = W.sb_geo or {}
		if not max or max <= 0 then
			W.sb_geo[id] = nil
			return
		end
		local track = y1 - y0
		local th = math.max(PX[24], math.floor(track * track / (track + max)))
		local ty = y0 + (track - th) * clamp(shown / max, 0, 1)
		local drag = W.sdrag and W.sdrag.id == id
		local hv = approach("sb_h" .. id, (drag or hovered(x1 - PX[12], y0, x1, y1)) and 1 or 0, 18)
		local bw = PX[4] + PX[3] * hv
		local x0 = x1 - PX[3] - bw
		rect(x0, y0, x0 + bw, y1, fade(rgba(255, 255, 255, math.floor(10 + 10 * hv)), a), bw / 2)
		rect(x0, ty, x0 + bw, ty + th, fade(rgba(255, 255, 255, math.floor(60 + 60 * hv)), a), bw / 2)
		W.sb_geo[id] = { y0 = y0, track = track, th = th }
		hit(x1 - PX[12], y0, x1, y1, "sbar", Q.harg("id", id, "ty", ty, "th", th))
	end

	local function draw_update_pill(right, cy, a)
		local st = U.status
		local show = st == "available" or st == "downloading" or st == "done" or (st == "error" and U.remote ~= nil)
		local pa = approach("pill_a", show and 1 or 0, 14)
		if pa <= 0.01 then
			return right
		end
		if show then
			W.pill_st = st
		end
		st = W.pill_st or st
		local label, icon, fg, bg
		if st == "downloading" then
			label, fg, bg = L("cd_pill_down"):format(U.remote or ""), rgba(176, 236, 220, 255), rgba(P.ACC.r, P.ACC.g, P.ACC.b, 26)
		elseif st == "done" then
			label, icon, fg, bg = L("cd_pill_done"), "\u{f00c}", P.ACC, nil
		elseif st == "error" then
			label, icon, fg, bg = L("cd_upd_failed"), "\u{f071}", P.WARN, rgba(236, 178, 82, 30)
		else
			label, icon, fg, bg = L("cd_pill_get"):format(U.remote or ""), "\u{f063}", rgba(160, 240, 214, 255), rgba(P.ACC.r, P.ACC.g, P.ACC.b, 41)
		end
		local ph = PX[24]
		local pad = PX[10]
		local iw = icon and PX[16] or 0
		local target = pad * 2 + iw + tw(W.fonts.semi, PX[11], label)
		local pw = math.floor(tween("pill_w", target, K.MOVE) + 0.5)
		local x0 = right - pw
		local ea = a * pa
		if bg then
			rect(x0, cy - ph / 2, right, cy + ph / 2, fade(bg, ea), PX[7])
		end
		Render.PushClip(Q.v1:Set(x0, cy - ph / 2), Q.v2:Set(right, cy + ph / 2), true)
		local tx = x0 + pad
		if icon then
			glyph(icon, tx + PX[5], cy, PX[10], fade(fg, ea))
			tx = tx + iw
		end
		text(W.fonts.semi, PX[11], label, tx, cy, fade(fg, ea))
		Render.PopClip()
		if st == "downloading" then
			local bx0, bx1 = x0 + PX[7], right - PX[7]
			local by = cy + ph / 2 - PX[4]
			local seg = (bx1 - bx0) * 0.4
			local phase = (os.clock() % 1.1) / 1.1
			local sx = bx0 + (bx1 - bx0 + seg) * phase - seg
			Render.PushClip(Q.v1:Set(bx0, by - PX[1]), Q.v2:Set(bx1, by + PX[3]), true)
			grad(sx, by, sx + seg, by + PX[2], fade(P.ACC_A, ea), fade(P.ACC_B, ea), PX[1])
			Render.PopClip()
		end
		if show and st == "error" and U.error then
			tip("pill", x0, cy - ph / 2, right, cy + ph / 2, L("cd_tip_err_t"), U.error:sub(1, 80))
		end
		return x0 - PX[8] * pa
	end

	local function draw_status(right, cy, a)
		right = draw_update_pill(right, cy, a)
		local stage = load_stage()
		local busy = stage and D.sets[0].stats and draft.result
		local ba = approach("head_load", busy and 1 or 0, 10)
		if ba > 0 then
			local str = stage == "matches" and L("cd_ld_short"):format(math.floor(job_progress() * 100))
				or L(STAGE_TEXT[stage] or "cd_ld_wait")
			local eta = stage == "matches" and fmt_eta(job_eta(), true)
			if eta then
				str = str .. "  " .. eta
			end
			local sw = tw(W.fonts.regular, PX[11], str)
			local sx = right - sw
			text(W.fonts.regular, PX[11], str, sx, cy, fade(P.MUTED, a * ba))
			if stage == "error" then
				glyph("\u{f071}", sx - PX[10], cy, PX[10], fade(P.WARN, a * ba))
			else
				spinner(sx - PX[10], cy, PX[5], a * ba, P.MUTED, math.max(1, PX[1.5]))
			end
			if (stage == "error" or stage == "slow") and D.error then
				tip("err", sx - PX[18], cy - PX[10], right, cy + PX[10], L("cd_tip_err_t"), D.error:sub(1, 80))
			end
			right = sx - PX[26]
		end
		return right
	end

	local function draw_head(x, y, w, a)
		local hh = PX[K.HEAD_H]
		local cy = y + hh / 2
		local left = x + PX[18]
		hit(x, y, x + w, y + hh, "head")
		local page = W.settings and "set" or (W.card and "card" or "draft")
		local title = page == "set" and L("cd_set_title") or (page == "card" and L("cd_nav_build_t") or L("cd_title"))
		left = left + text(W.fonts.bold, PX[17], title, left, cy, fade(P.TEXT, a)) + PX[16]
		if page == "draft" then
			local mode = L(draft.mode == 0 and "cd_mode_order" or "cd_mode_free")
			local gk = draft.gm and K.GM_KEY[draft.gm]
			local game = gk and ("  \u{00b7}  " .. L(gk)) or ""
			local mh, pad = PX[24], PX[9]
			local mt = tw(W.fonts.medium, PX[11], mode)
			local mw = mt + tw(W.fonts.regular, PX[11], game) + pad * 2
			rect(left, cy - mh / 2, left + mw, cy + mh / 2, fade(P.FIELD, a), PX[8])
			text(W.fonts.medium, PX[11], mode, left + pad, cy, fade(P.TEXT, a))
			if game ~= "" then
				text(W.fonts.regular, PX[11], game, left + pad + mt, cy, fade(P.MUTED, a))
			end
			tip("mode", left, cy - mh / 2, left + mw, cy + mh / 2, L("cd_tip_mode_t"), L("cd_tip_mode"))
			left = left + mw + PX[14]
			if draft.mode == 0 then
				local label = L("cd_first")
				local lw = text(W.fonts.regular, PX[11], label, left, cy, fade(P.MUTED, a))
				local sw, sh = segment("first", left + lw + PX[8], cy, { L("cd_us"), L("cd_enemy") }, draft.first, "first", a)
				tip("first", left, cy - sh / 2, left + lw + PX[8] + sw, cy + sh / 2, L("cd_tip_first_t"), L("cd_tip_first"))
			end
		else
			local sub = page == "set" and L("cd_set_ver"):format(K.VERSION) or L("cd_card_head_sub")
			vline(left - PX[8], cy, PX[7], a)
			text(W.fonts.regular, PX[11], sub, left, cy, fade(P.MUTED, a))
		end
		draw_status(x + w - PX[18], cy, a)
	end

	local function draw_rail(x, y, w, h, a, bg)
		rect(x, y, x + w, y + h, fade(bg, a), PX[K.RADIUS], K.ROUND_L)
		hit(x, y, x + w, y + h, "head")
		local cx = x + w / 2
		local ly = y + PX[28]
		if not logo(cx, ly, PX[26], a) then
			glyph("\u{f0c0}", cx, ly, PX[15], fade(P.ACC, a))
		end
		local bs = PX[36]
		local function btn(icon, kind, arg, by, active, enabled, key)
			local x0, y0, x1, y1 = cx - bs / 2, by - bs / 2, cx + bs / 2, by + bs / 2
			local hv = approach("rail_h" .. kind, (enabled and hovered(x0, y0, x1, y1)) and 1 or 0, 20)
			local on = approach("rail_on" .. kind, active and 1 or 0, 16)
			if on > 0.01 then
				rect(x0, y0, x1, y1, fade(P.CHIP_ON, a * on), PX[9])
				local bar = math.max(2, PX[3])
				grad(x0 - PX[7], by - PX[10], x0 - PX[7] + bar, by + PX[10], fade(P.ACC_A, a * on), fade(P.ACC_B, a * on), bar / 2, true)
			end
			if hv > 0.01 then
				rect(x0, y0, x1, y1, fade(P.HOVER, a * hv), PX[9])
			end
			local ic = mix(mix(P.MUTED, P.TEXT, hv), P.ACC, on)
			glyph(icon, cx, by, PX[14], fade(ic, a * (enabled and 1 or 0.35)))
			if enabled then
				hit(x0, y0, x1, y1, kind, arg)
			end
			if tip_at(x0, y0, x1, y1) then
				tip_put("rail" .. kind, L(key .. "_t"), L(key))
			end
		end
		local by = ly + PX[52]
		btn("\u{f0ca}", "nav_draft", nil, by, not W.card and not W.settings, true, "cd_tip_nav_draft")
		btn("\u{f290}", "card_hero", W.nav_h, by + PX[42], W.card ~= nil and not W.settings, W.nav_h ~= nil, "cd_tip_nav_build")
		local bb = y + h - PX[28]
		btn("\u{f00d}", "close", nil, bb, false, true, "cd_tip_close")
		btn("\u{f013}", "settings", nil, bb - PX[42], W.settings, true, "cd_tip_settings")
		btn("\u{f1f8}", "reset", nil, bb - PX[84], false, true, "cd_tip_reset")
		btn("\u{f2ea}", "undo", nil, bb - PX[126], false, true, "cd_tip_undo")
	end

	local function draw_gauge(cx, cy, r, a)
		local ca = approach("chance_a", draft.chance and 1 or 0, 10)
		local value = tween("chance", draft.chance or A.chance_last or 0.5, 0.45)
		if draft.chance then
			A.chance_last = draft.chance
		end
		local th = math.max(2, PX[4])
		Render.Circle(Q.v1:Set(cx, cy), r, fade(P.FIELD, a * 1.6), th, 0, 1, false, 48)
		if ca > 0.01 then
			local col = mix(P.BAD, P.GOOD, clamp((value - 0.42) / 0.16, 0, 1))
			Render.Circle(Q.v1:Set(cx, cy), r, fade(col, a * ca), th, 270, clamp(value, 0.01, 1), true, 48)
			local num = ("%d%%"):format(math.floor(value * 100 + 0.5))
			text(W.fonts.bold, PX[15], num, cx - tw(W.fonts.bold, PX[15], num) / 2, cy, fade(P.TEXT, a * ca))
		else
			glyph("\u{f141}", cx, cy, PX[12], fade(P.DIM, a))
		end
		local cl = L("cd_chance")
		text(W.fonts.regular, PX[10], cl, cx - tw(W.fonts.regular, PX[10], cl) / 2, cy + r + PX[11], fade(P.MUTED, a))
	end

	local function draw_arena_free(x, y, w, h, a)
		W.cur_target = nil
		local pad = PX[18]
		local cw, ch, cg = PX[K.CARD_W], PX[K.CARD_PIC], PX[6]
		local team_w = 5 * cw + 4 * cg
		local c = cur_step()
		local label_y = y + PX[13]
		local py0 = y + PX[26]
		local function team(first, x0, key, to_right)
			local lab = L(key)
			local lx = to_right and (x0 + team_w - tw(W.fonts.semi, PX[10], lab)) or x0
			text(W.fonts.semi, PX[10], lab, lx, label_y, fade(P.MUTED, a))
			for k = 0, 4 do
				local i = first + k
				local sx = x0 + k * (cw + cg)
				local cx0, cy0, cx1, cy1 = sx - PX[4], py0 - PX[4], sx + cw + PX[4], py0 + ch + PX[22]
				local over = hovered(cx0, cy0, cx1, cy1)
				local rh = approach("brow" .. i, over and 1 or 0, 20)
				if over and draft.steps[i] then
					W.side_hover = { h = draft.steps[i], pos = draft.slot_pos[i] }
				end
				if i == c then
					rect(cx0, cy0, cx1, cy1, fade(P.FIELD, a), PX[8])
				elseif rh > 0.01 then
					rect(cx0, cy0, cx1, cy1, fade(P.HOVER, a * rh), PX[8])
				end
				hit(cx0, cy0, cx1, cy1, "slot", i)
				if draft.tentative[i] then
					if tip_at(cx0, cy0, cx1, cy1) then
						tip_put("slot" .. i, L("cd_tip_tent_t"), L("cd_tip_tent"))
					end
				else
					if tip_at(cx0, cy0, cx1, cy1) then
						tip_put("slot" .. i, L("cd_tip_slot_t"), L("cd_tip_free"))
					end
				end
				draw_slot(i, sx, py0, cw, ch, a)
				local ny = py0 + ch + PX[10]
				local hero = draft.steps[i] and D.by_id[draft.steps[i]]
				local str, font, col, ta = L("cd_slot_empty"), W.fonts.regular, P.DIM, 1
				if hero then
					str, font, col = hero.name, W.fonts.semi, P.TEXT
					ta = (draft.mode == 1 and draft.tentative[i]) and 0.55 or 1
				elseif i == c then
					str, font, col = L("cd_slot_now"), W.fonts.semi, P.ACC
				end
				local nw = tw(font, PX[10], str)
				Render.PushClip(Q.v1:Set(sx - PX[2], ny - PX[8]), Q.v2:Set(sx + cw + PX[2], ny + PX[8]), true)
				text(font, PX[10], str, sx + math.max(0, (cw - nw) / 2), ny, fade(col, a * ta))
				Render.PopClip()
			end
		end
		team(1, x + pad, "cd_us", false)
		team(6, x + w - pad - team_w, "cd_enemy", true)
		draw_gauge(x + w / 2, y + PX[42], PX[K.GAUGE_R], a)
		local bw, bh, bg = PX[K.BAN_SW], PX[K.BAN_SH], PX[4]
		local row_w = 10 * bw + 9 * bg
		local by = y + h - bh - PX[8]
		local bl = L("cd_bans")
		local blw = tw(W.fonts.semi, PX[10], bl)
		local bx0 = math.floor(x + w / 2 - (row_w + blw + PX[12]) / 2)
		text(W.fonts.semi, PX[10], bl, bx0, by + bh / 2, fade(P.MUTED, a))
		bx0 = bx0 + blw + PX[12]
		for i = 11, 20 do
			draw_slot(i, bx0 + (i - 11) * (bw + bg), by, bw, bh, a)
		end
		draw_cursor(a)
	end

	local function mini_switch(key, x, cy, a)
		local tw_, th_ = PX[24], PX[14]
		local k = approach("sw_" .. key, cfg[key] == 1 and 1 or 0, 18)
		rect(x - tw_, cy - th_ / 2, x, cy + th_ / 2, fade(rgba(214, 236, 255, 41), a * (1 - k)), th_ / 2)
		if k > 0.01 then
			grad(x - tw_, cy - th_ / 2, x, cy + th_ / 2, fade(rgba(P.ACC_A.r, P.ACC_A.g, P.ACC_A.b, 190), a * k),
				fade(rgba(P.ACC_B.r, P.ACC_B.g, P.ACC_B.b, 190), a * k), th_ / 2)
		end
		local kx = x - tw_ + th_ / 2 + (tw_ - th_) * k
		Render.FilledCircle(Q.v1:Set(kx, cy), th_ / 2 - PX[2], fade(mix(rgba(174, 178, 184, 255), P.WHITE, k), a))
	end

	local function draw_settings_page(x, y, w, h, a)
		local left, right = x + PX[18], x + w - PX[18]
		local row_h = PX[K.SET_ROW]
		local top = y + PX[6]
		local scroll = SB.scroll("set", "set_scroll", W.set_max or 0)
		W.set_rect = { x, top, x + w, y + h }
		W.hit_clip = { top, y + h }
		Render.PushClip(Q.v1:Set(x, top), Q.v2:Set(x + w, y + h), true)
		local cx0, cy0 = Input.GetCursorPos()
		local covered = W.gear_pop and in_rect(W.gear_pop, cx0, cy0)
		W.gear_block = W.gear_pop
		local colgap = PX[14]
		local colw = math.floor((w - PX[18] * 2 - colgap) / 2)
		local function column(cx)
			return { l = cx + PX[14], r = cx + colw - PX[14], x0 = cx + PX[4], x1 = cx + colw - PX[4], y = top + PX[10] - scroll,
				a = a, cx0 = cx, cx1 = cx + colw }
		end
		local C1, C2 = column(x + PX[18]), column(x + PX[18] + colw + colgap)
		local C = C1
		left, right = C.l, C.r
		W.sec_h = W.sec_h or {}
		local function card_end(c)
			if c.card then
				c.y = c.y + PX[8]
				W.sec_h[c.card] = c.y - c.card_y
				c.y = c.y + PX[14]
				c.card = nil
			end
		end
		local function section(c, key)
			card_end(c)
			local y0 = c.y
			local hh = W.sec_h[key] or PX[64]
			rect(c.cx0, y0, c.cx1, y0 + hh, fade(P.CARD, c.a), PX[12])
			Render.Rect(Q.v1:Set(c.cx0, y0), Q.v2:Set(c.cx1, y0 + hh), fade(P.LINE, c.a), PX[12], K.ROUND, math.max(1, PX[1]))
			rect(c.cx0 + PX[14], y0 + PX[10], c.cx0 + PX[14] + math.max(2, PX[3]), y0 + PX[22], fade(P.ACC, c.a), PX[1])
			text(W.fonts.semi, PX[10], L(key), c.l + PX[9], y0 + PX[16], fade(P.TEXT, c.a))
			c.card, c.card_y = key, y0
			c.y = y0 + PX[30]
		end
		local function row(c, icon, label, id)
			local cy = c.y + row_h / 2
			local inside = cx0 >= c.x0 and cx0 <= c.x1 and cy0 >= c.y and cy0 < c.y + row_h
			local rh = approach("st_row" .. id, (inside and not W.drag and (c.popup or not covered)) and 1 or 0, 20)
			if rh > 0 then
				rect(c.x0, c.y, c.x1, c.y + row_h, fade(rgba(255, 255, 255, c.popup and 12 or 8), c.a * rh), PX[7])
			end
			local tx = c.l
			if icon then
				glyph(icon, c.l + PX[7], cy, PX[11], fade(P.MUTED, c.a))
				tx = c.l + PX[22]
			end
			local lw = label and text(W.fonts.regular, PX[12], label, tx, cy, fade(P.TEXT, c.a)) or 0
			c.y = c.y + row_h
			return cy, tx, tx + lw
		end
		local function seg(c, id, labels, value, kind, cy)
			segment(id, c.r - segment_width(labels), cy, labels, value, kind, c.a)
		end
		local function toggle(c, icon, key, label, id)
			local cy = row(c, icon, label, id)
			mini_switch(key, c.r, cy, c.a)
			hit(c.x0, cy - row_h / 2, c.x1, cy + row_h / 2, "set_toggle", key)
			return cy
		end
		local function stepper(c, cy, value, up, down, id)
			local sb = PX[20]
			local vw = PX[42]
			for n, item in ipairs({ { "+", up, c.r - sb }, { "-", down, c.r - sb * 2 - vw } }) do
				local sx = item[3]
				local h2 = approach(id .. n, hovered(sx, cy - sb / 2, sx + sb, cy + sb / 2) and 1 or 0, 20)
				rect(sx, cy - sb / 2, sx + sb, cy + sb / 2, fade(mix(P.CELL, P.HOVER, h2), c.a), PX[6])
				local gw = tw(W.fonts.medium, PX[12], item[1])
				text(W.fonts.medium, PX[12], item[1], sx + (sb - gw) / 2, cy, fade(P.TEXT, c.a))
				hit(sx, cy - sb / 2, sx + sb, cy + sb / 2, item[2])
			end
			local label = ("%d%%"):format(value)
			local tvw = tw(W.fonts.medium, PX[11], label)
			text(W.fonts.medium, PX[11], label, c.r - sb - vw / 2 - tvw / 2, cy, fade(P.TEXT, c.a))
		end
		local function gear(c, key, cy)
			local size = PX[20]
			local on = W.set_gear == key
			local gh = approach("st_g" .. key, (on or (not covered and hovered(c.r - size, cy - size / 2, c.r, cy + size / 2))) and 1 or 0, 20)
			if gh > 0 then
				rect(c.r - size, cy - size / 2, c.r, cy + size / 2, fade(on and P.CHIP_ON or P.HOVER, c.a * gh), PX[6])
			end
			glyph("\u{f013}", c.r - size / 2, cy, PX[10], fade(mix(P.MUTED, P.TEXT, gh), c.a))
			hit(c.r - size, cy - size / 2, c.r, cy + size / 2, "set_gear", key)
			W.gear_anchor[key] = { cy - size / 2, cy + size / 2, c.r }
			return size
		end

		section(C, "cd_sec_data")
		local cy = row(C, "\u{f1c0}", L("cd_set_source"), "src")
		seg(C, "st_src", { L("cd_src_short0"), L("cd_src_long1") }, source(), "set_src", cy)
		local note_h = math.floor(tween("st_cm_note", source() == 1 and PX[K.CM_NOTE_H] or 0, K.PAGE_TIME) + 0.5)
		if note_h > 0.5 then
			local na = a * clamp(note_h / PX[K.CM_NOTE_H], 0, 1)
			Render.PushClip(Q.v1:Set(x, C.y), Q.v2:Set(x + w, C.y + note_h), true)
			local CM = D.sets[1]
			local n = #CM.recs
			local days = CM.oldest and math.max(1, math.floor((os.time() - CM.oldest) / 86400 + 0.5)) or nil
			local rate = (days and n > 0) and n / days or nil
			local l1 = C.y + PX[12]
			local l2 = C.y + PX[29]
			glyph("\u{f05a}", left + PX[7], l1, PX[10], fade(P.MUTED, na))
			local tx = left + PX[22]
			if n == 0 or not days then
				text(W.fonts.regular, PX[11], L("cd_cm_wait"), tx, l1, fade(P.MUTED, na))
			elseif CM.exhausted then
				text(W.fonts.regular, PX[11], L("cd_cm_done"):format(fmt_games(n), math.min(days, K.CM_DAYS)), tx, l1, fade(P.MUTED, na))
			else
				local lx = tx + text(W.fonts.regular, PX[11], L("cd_cm_now"):format(fmt_games(n), math.min(days, K.CM_DAYS), K.CM_DAYS), tx, l1, fade(P.MUTED, na)) + PX[8]
				if rate and days < K.CM_DAYS then
					vline(lx, l1, PX[6], na)
					text(W.fonts.regular, PX[11], L("cd_cm_total"):format(fmt_games(math.min(K.CM_MAX, math.floor(rate * K.CM_DAYS)))), lx + PX[8], l1, fade(P.MUTED, na))
				end
			end
			local why = rate and L("cd_cm_why"):format(math.floor(rate + 0.5)) or L("cd_cm_why0")
			text(W.fonts.regular, PX[10], why, tx, l2, fade(P.DIM, na))
			Render.PopClip()
			C.y = C.y + note_h
		end
		cy = row(C, "\u{f091}", L("cd_set_rank"), "rank")
		seg(C, "st_rank", { L("cd_rk0"), L("cd_rk1"), L("cd_rk2"), L("cd_rk3") }, cfg.rank, "set_rank", cy)
		local vy = C.y
		local vcy, _, label_end = row(C, "\u{f5fd}", L("cd_set_volume"), "vol")
		seg(C, "st_vol", { "50k", "100k", "200k" }, cfg.volume, "set_vol", vcy)
		tip("st_vol_tip", left, vy, label_end, vy + row_h, L("cd_set_volume"), L("cd_set_volume_tip"))

		local tx
		cy, tx = row(C, "\u{f1da}", nil, "info")
		local S = D.sets[source()]
		local parts = {}
		if S.stats then
			parts[#parts + 1] = L("cd_matches"):format(fmt_games(S.stats.n))
		end
		parts[#parts + 1] = S.job and L("cd_upd_loading") or fmt_updated(S.updated)
		local lx = tx
		for n, part in ipairs(parts) do
			if n > 1 then
				vline(lx, cy, PX[6], a)
				lx = lx + PX[8]
			end
			lx = lx + text(W.fonts.regular, PX[11], part, lx, cy, fade(P.MUTED, a)) + PX[8]
		end
		local label = L("cd_set_refresh")
		local bw = tw(W.fonts.medium, PX[11], label) + PX[32]
		local bh = PX[22]
		local busy = any_busy()
		local rb = approach("st_refresh", (not busy and not covered and hovered(right - bw, cy - bh / 2, right, cy + bh / 2)) and 1 or 0, 20)
		local ba = a * (busy and 0.45 or 1)
		rect(right - bw, cy - bh / 2, right, cy + bh / 2, fade(mix(P.CELL, P.HOVER, rb), ba), PX[6])
		glyph("\u{f021}", right - bw + PX[13], cy, PX[10], fade(P.MUTED, ba))
		text(W.fonts.medium, PX[11], label, right - bw + PX[23], cy, fade(P.TEXT, ba))
		if not busy then
			hit(right - bw, cy - bh / 2, right, cy + bh / 2, "set_refresh")
		end

		section(C, "cd_sec_view")
		local lang_y = C.y
		local lcy, _, lang_end = row(C, "\u{f1ab}", L("cd_set_lang"), "lang")
		seg(C, "st_lang", { L("cd_lang0"), L("cd_lang1"), L("cd_lang2") }, cfg.lang, "set_lang", lcy)
		tip("st_lang_tip", left, lang_y, lang_end, lang_y + row_h, L("cd_set_lang"), L("cd_tip_lang"))
		cy = row(C, "\u{f2d0}", L("cd_set_window"), "win")
		gear(C, "window", cy)
		hit(C.x0, cy - row_h / 2, C.r - PX[24], cy + row_h / 2, "set_gear", "window")
		cy = row(C, "\u{f290}", L("cd_set_panel"), "panel")
		local gs = gear(C, "panel", cy)
		mini_switch("panel", C.r - gs - PX[8], cy, a)
		hit(C.x0, cy - row_h / 2, C.r - gs - PX[4], cy + row_h / 2, "set_toggle", "panel")
		if cfg.panel == 1 then
			cy = row(C, "\u{f06e}", L("cd_set_preview"), "preview")
			local plabel = W.preview and L("cd_preview_hide") or L("cd_preview_show")
			local pbw = tw(W.fonts.medium, PX[11], plabel) + PX[24]
			local pbh = PX[22]
			local pon = W.preview == true
			local pbx0 = C.r - pbw
			local phv = approach("st_prev", (not covered and hovered(C.x0, cy - row_h / 2, C.x1, cy + row_h / 2)) and 1 or 0, 20)
			rect(pbx0, cy - pbh / 2, C.r, cy + pbh / 2, fade(pon and P.CHIP_ON or mix(P.CELL, P.HOVER, phv), a), PX[6])
			text(W.fonts.medium, PX[11], plabel, pbx0 + PX[12], cy, fade(P.TEXT, a))
			hit(C.x0, cy - row_h / 2, C.x1, cy + row_h / 2, "set_preview")
			tip("st_prev", pbx0, cy - pbh / 2, C.r, cy + pbh / 2, L("cd_set_preview"), L("cd_tip_preview"))
		end
		cy = toggle(C, "\u{f201}", "live", L("cd_set_live"), "live")
		tip("st_live", C.x0, cy - row_h / 2, C.x1, cy + row_h / 2, L("cd_set_live"), L("cd_tip_live"))
		cy = toggle(C, "\u{f0e8}", "lanes", L("cd_set_lanes"), "lanes")
		tip("st_lanes", C.x0, cy - row_h / 2, C.x1, cy + row_h / 2, L("cd_set_lanes"), L("cd_tip_lanes"))
		cy = toggle(C, "\u{f505}", "solo", L("cd_set_solo"), "solo")
		tip("st_solo", C.x0, cy - row_h / 2, C.x1, cy + row_h / 2, L("cd_set_solo"), L("cd_tip_solo"))
		cy = toggle(C, "\u{f058}", "pick_ask", L("cd_set_pick_ask"), "pick_ask")
		tip("st_pick", C.x0, cy - row_h / 2, C.x1, cy + row_h / 2, L("cd_set_pick_ask"), L("cd_tip_pick_ask"))
		toggle(C, "\u{f52b}", "auto", L("cd_set_auto"), "auto")
		card_end(C)
		C = C2
		left, right = C.l, C.r
		section(C, "cd_sec_auto")
		cy = row(C, "\u{f07a}", L("cd_set_autobuy"), "autobuy")
		local ags = gear(C, "abuy", cy)
		mini_switch("autobuy", C.r - ags - PX[8], cy, a)
		hit(C.x0, cy - row_h / 2, C.r - ags - PX[4], cy + row_h / 2, "set_toggle", "autobuy")
		tip("st_autobuy", C.x0, cy - row_h / 2, C.r - ags - PX[4], cy + row_h / 2, L("cd_set_autobuy"), L("cd_tip_autobuy"))
		cy = toggle(C, "\u{f062}", "askill", L("cd_set_askill"), "askill")
		tip("st_askill", C.x0, cy - row_h / 2, C.x1, cy + row_h / 2, L("cd_set_askill"), L("cd_tip_askill"))

		section(C, "cd_sec_logs")
		toggle(C, "\u{f188}", "debug", L("cd_set_debug"), "debug")
		cy = toggle(C, "\u{f0e0}", "logauto", L("cd_set_logauto"), "logauto")
		tip("st_logauto", C.x0, cy - row_h / 2, C.x1, cy + row_h / 2, L("cd_set_logauto"), L("cd_tip_logauto"))
		cy = row(C, "\u{f1d8}", L("cd_set_log"), "logsend")
		do
			local busy = LOGR.busy()
			local llabel = busy and L("cd_log_sending") or L("cd_log_send")
			local lbw = tw(W.fonts.medium, PX[11], llabel) + PX[32]
			local lbh = PX[22]
			local lhv = approach("st_logsend", (not busy and not covered and hovered(right - lbw, cy - lbh / 2, right, cy + lbh / 2)) and 1 or 0, 20)
			local lba = a * (busy and 0.45 or 1)
			rect(right - lbw, cy - lbh / 2, right, cy + lbh / 2, fade(mix(P.CELL, P.HOVER, lhv), lba), PX[6])
			glyph("\u{f093}", right - lbw + PX[13], cy, PX[10], fade(P.MUTED, lba))
			text(W.fonts.medium, PX[11], llabel, right - lbw + PX[23], cy, fade(P.TEXT, lba))
			if not busy then
				hit(right - lbw, cy - lbh / 2, right, cy + lbh / 2, "set_logsend")
			end
			tip("st_logsend", C.x0, cy - row_h / 2, right - lbw - PX[4], cy + row_h / 2, L("cd_set_log"), L("cd_tip_log"))
		end

		section(C, "cd_sec_bans")
		do
			local bl = I.ban_list()
			if #bl == 0 then
				local by = C.y + row_h / 2
				glyph("\u{f165}", left + PX[7], by, PX[10], fade(P.MUTED, a))
				text(W.fonts.regular, PX[11], L("cd_bans_none"), left + PX[22], by, fade(P.MUTED, a))
				C.y = C.y + row_h
			else
				local cw, chh, gap = PX[150], PX[30], PX[6]
				local per = math.max(1, math.floor((right - left + gap) / (cw + gap)))
				for i, b in ipairs(bl) do
					local col, line = (i - 1) % per, (i - 1) // per
					local bx0 = left + col * (cw + gap)
					local by0 = C.y + PX[2] + line * (chh + gap)
					local bx1, by1 = bx0 + cw, by0 + chh
					local hv = approach("bn_" .. b.h .. b.name, (not covered and hovered(bx0, by0, bx1, by1)) and 1 or 0, 20)
					rect(bx0, by0, bx1, by1, fade(mix(P.CELL, P.HOVER, hv), a), PX[7])
					local icon = Q.asset("items/", b.name)
					if icon then
						Render.Image(icon, Q.v1:Set(bx0 + PX[4], by0 + PX[4]), Q.v2:Set(PX[32], chh - PX[8]), fade(P.WHITE, a), PX[5], K.ROUND)
					end
					local face = b.h > 0 and mini(b.h)
					local tx = bx0 + PX[42]
					if face then
						Render.Image(face, Q.v1:Set(tx, by0 + chh / 2 - PX[8]), Q.v2:Set(PX[16], PX[16]), fade(P.WHITE, a))
						tx = tx + PX[20]
					end
					local it, hero = I.by_name[b.name], D.by_id[b.h]
					local label = b.h == 0 and L("cd_ban_everyone") or (hero and hero.name or tostring(b.h))
					Render.PushClip(Q.v1:Set(tx, by0), Q.v2:Set(bx1 - PX[20], by1), true)
					text(W.fonts.regular, PX[11], label, tx, by0 + chh / 2, fade(P.MUTED, a))
					Render.PopClip()
					glyph("\u{f00d}", bx1 - PX[11], by0 + chh / 2, PX[10], fade(mix(P.DIM, P.BAD, hv), a))
					hit(bx0, by0, bx1, by1, "unban", b)
					if tip_at(bx0, by0, bx1, by1) then
						tip_put("bn_" .. b.h .. b.name, it and it.label or b.name, L("cd_tip_unban"))
					end
				end
				C.y = C.y + PX[2] + math.ceil(#bl / per) * (chh + gap)
				local label = L("cd_bans_clear")
				local bw, bh = tw(W.fonts.medium, PX[11], label) + PX[24], PX[22]
				local ccy = C.y + row_h / 2
				local ch = approach("bn_clear", (not covered and hovered(right - bw, ccy - bh / 2, right, ccy + bh / 2)) and 1 or 0, 20)
				rect(right - bw, ccy - bh / 2, right, ccy + bh / 2, fade(mix(P.CELL, P.HOVER, ch), a), PX[6])
				text(W.fonts.medium, PX[11], label, right - bw + PX[12], ccy, fade(P.TEXT, a))
				hit(right - bw, ccy - bh / 2, right, ccy + bh / 2, "unban_all")
				text(W.fonts.regular, PX[10], L("cd_bans_hint"), left, ccy, fade(P.DIM, a))
				C.y = C.y + row_h
			end
		end

		card_end(C1)
		card_end(C2)
		Render.PopClip()
		W.hit_clip = nil
		W.set_max = math.max(0, math.max(C1.y, C2.y) + scroll - top - (y + h - top))
		SB.bar("set", x + w - PX[1], top, y + h, scroll, W.set_max, a)

		local g = W.set_gear
		local ga = approach("st_gear_a", g and 1 or 0, 22) * a
		if g then
			W.gear_last = g
		end
		g = g or W.gear_last
		W.gear_pop = nil
		local anchor = g and W.gear_anchor[g]
		if ga <= 0.01 or not anchor then
			return
		end
		local rows = g == "window" and 4 or (g == "abuy" and 5 or 10)
		local pw = PX[280]
		local ph = PX[40] + rows * row_h + PX[6]
		local px1 = math.min(x + w - PX[8], (anchor[3] or (x + w)) + PX[8])
		local px0 = px1 - pw
		local py = math.floor(anchor[2] + PX[4])
		if py + ph > y + h - PX[4] then
			py = math.floor(anchor[1] - PX[4] - ph)
		end
		py = math.floor(clamp(py, top, math.max(top, y + h - PX[4] - ph)))
		local nohit = W.nohit
		W.nohit = nohit or not W.set_gear
		W.gear_block = nil
		rect(x + PX[4], top, x + w - PX[4], y + h - PX[4], fade(rgba(0, 0, 0, 110), ga), PX[8])
		rect(px0, py, px1, py + ph, fade(P.POP, ga), PX[10])
		hit(px0, py, px1, py + ph, "stgbg")
		if W.set_gear then
			W.gear_pop = { px0, py, px1, py + ph }
		end
		local title_icon = g == "window" and "\u{f2d0}" or (g == "abuy" and "\u{f07a}" or "\u{f290}")
		local title = g == "window" and L("cd_set_window") or (g == "abuy" and L("cd_set_autobuy") or L("cd_set_panel"))
		glyph(title_icon, px0 + PX[19], py + PX[17], PX[11], fade(P.MUTED, ga))
		text(W.fonts.semi, PX[11], title, px0 + PX[34], py + PX[17], fade(P.MUTED, ga))
		rect(px0 + PX[12], py + PX[31], px1 - PX[12], py + PX[31] + math.max(1, PX[1]), fade(rgba(255, 255, 255, 22), ga))
		local Q = { l = px0 + PX[12], r = px1 - PX[12], x0 = px0 + PX[4], x1 = px1 - PX[4], y = py + PX[36], a = ga, popup = true }
		if g == "window" then
			cy = row(Q, "\u{f065}", L("cd_set_scale"), "g_scale")
			stepper(Q, cy, cfg.zoom, "set_scale_up", "set_scale_down", "st_b")
			cy = row(Q, "\u{f043}", L("cd_set_bg"), "g_bg")
			local val_txt = ("%d%%"):format(cfg.bg)
			local val_w = tw(W.fonts.medium, PX[11], "100%")
			local tx1 = Q.r - val_w - PX[K.SLIDER_GAP]
			local tx0 = tx1 - PX[100]
			local k = (cfg.bg - 50) / 50
			rect(tx0, cy - PX[2], tx1, cy + PX[2], fade(rgba(255, 255, 255, 30), ga), PX[2])
			rect(tx0, cy - PX[2], tx0 + (tx1 - tx0) * k, cy + PX[2], fade(rgba(255, 255, 255, 140), ga), PX[2])
			Render.FilledCircle(Q.v1:Set(tx0 + (tx1 - tx0) * k, cy), PX[6], fade(P.WHITE, ga))
			text(W.fonts.medium, PX[11], val_txt, Q.r - tw(W.fonts.medium, PX[11], val_txt), cy, fade(P.TEXT, ga))
			if W.set_gear then
				W.slider_rect = { tx0, tx1 }
			end
			hit(tx0 - PX[8], cy - PX[10], tx1 + PX[4], cy + PX[10], "set_bg")
			toggle(Q, "\u{f042}", "blur", L("cd_set_blur"), "g_blur")
			toggle(Q, "\u{f05a}", "tips", L("cd_set_tips"), "g_tips")
		elseif g == "abuy" then
			toggle(Q, "\u{f0d6}", "abuy_sell", L("cd_set_abuy_sell"), "g_abuy_sell")
			toggle(Q, "\u{f01e}", "abuy_bb", L("cd_set_abuy_bb"), "g_abuy_bb")
			toggle(Q, "\u{f70e}", "abuy_tp", L("cd_set_abuy_tp"), "g_abuy_tp")
			cy = toggle(Q, "\u{f0d1}", "abuy_cour", L("cd_set_abuy_cour"), "g_abuy_cour")
			tip("g_abuy_cour_tip", Q.x0, cy - row_h / 2, Q.x1, cy + row_h / 2, L("cd_set_abuy_cour"), L("cd_tip_abuy_cour"))
			toggle(Q, "\u{f362}", "abuy_swap", L("cd_set_abuy_swap"), "g_abuy_swap")
		else
			cy = row(Q, "\u{f009}", L("cd_set_pview"), "g_pview")
			seg(Q, "st_pview", { L("cd_pview0"), L("cd_pview1"), L("cd_pview2") }, cfg.pview, "set_pview", cy)
			cy = row(Q, "\u{f065}", L("cd_set_scale"), "g_pzoom")
			stepper(Q, cy, cfg.pzoom, "set_pzoom_up", "set_pzoom_down", "st_pz")
			toggle(Q, "\u{f54e}", "pshop", L("cd_set_pshop"), "g_pshop")
			toggle(Q, "\u{f3ed}", "padapt", L("cd_set_padapt"), "g_padapt")
			cy = toggle(Q, "\u{f05b}", "pdanger", L("cd_set_pdanger"), "g_pdanger")
			tip("g_pdanger_tip", Q.x0, cy - row_h / 2, Q.x1, cy + row_h / 2, L("cd_set_pdanger"), L("cd_tip_pdanger"))
			cy = toggle(Q, "\u{f1e6}", "dmgtrack", L("cd_set_dmgtrack"), "g_dmgtrack")
			tip("g_dmgtrack_tip", Q.x0, cy - row_h / 2, Q.x1, cy + row_h / 2, L("cd_set_dmgtrack"), L("cd_tip_dmgtrack"))
			cy = toggle(Q, "\u{f067}", "pext", L("cd_set_pext"), "g_pext")
			tip("g_pext_tip", Q.x0, cy - row_h / 2, Q.x1, cy + row_h / 2, L("cd_set_pext"), L("cd_tip_pext"))
			cy = toggle(Q, "\u{f062}", "pup", L("cd_set_pup"), "g_pup")
			tip("g_pup_tip", Q.x0, cy - row_h / 2, Q.x1, cy + row_h / 2, L("cd_set_pup"), L("cd_tip_pup"))
			cy = toggle(Q, "\u{f0e7}", "pturbo", L("cd_set_pturbo"), "g_pturbo")
			tip("g_pturbo_tip", Q.x0, cy - row_h / 2, Q.x1, cy + row_h / 2, L("cd_set_pturbo"), L("cd_tip_pturbo"))
			toggle(Q, "\u{f070}", "phide", L("cd_set_phide"), "g_phide")
		end
		W.nohit = nohit
	end

	local function draw_arena(x, y, w, h, a)
		if draft.mode == 1 then
			draw_arena_free(x, y, w, h, a)
			return
		end
		W.cur_target = nil
		local pad = PX[18]
		local label_w = PX[44]
		local gauge_w = PX[96]
		local sx0 = x + pad + label_w
		local sx1 = x + w - pad - gauge_w
		local mid = y + h / 2 - PX[2]
		local lane = { mid - PX[22], mid + PX[22] }
		text(W.fonts.semi, PX[10], L("cd_us"), x + pad, lane[1], fade(P.MUTED, a))
		text(W.fonts.semi, PX[10], L("cd_enemy"), x + pad, lane[2], fade(P.MUTED, a))
		local pos, lane_end, prev = {}, { -math.huge, -math.huge }, -math.huge
		for i, step in ipairs(K.STEPS) do
			local side = step_team(i)
			local bw = step.kind == "P" and K.PICK_W or K.BAN_W
			local cx = i == 1 and bw / 2 or math.max(prev + K.STRIP_STEP, lane_end[side + 1] + K.TL_SAME + bw / 2)
			prev = cx
			lane_end[side + 1] = cx + bw / 2
			pos[i] = cx
		end
		local total = math.max(lane_end[1], lane_end[2])
		local k = math.min(s, (sx1 - sx0) / math.max(1, total))
		rect(sx0, mid, sx0 + total * k, mid + math.max(1, PX[1]), fade(P.LINE, a * 1.2))
		local c = cur_step()
		for i, step in ipairs(K.STEPS) do
			local side = step_team(i)
			local is_pick = step.kind == "P"
			local bw = math.floor((is_pick and K.PICK_W or K.BAN_W) * k + 0.5)
			local bh = math.floor((is_pick and K.PICK_H or K.BAN_H) * k + 0.5)
			local cx = sx0 + pos[i] * k
			local cy = lane[side + 1]
			local num = tostring(i)
			local col = i == c and P.TEXT or (draft.steps[i] and P.MUTED or P.DIM)
			local font = i == c and W.fonts.bold or W.fonts.semi
			local nw = tw(font, PX[9], num)
			rect(cx - nw / 2 - PX[3], mid - PX[6], cx + nw / 2 + PX[3], mid + PX[7], fade(P.BG, a), PX[4])
			text(font, PX[9], num, cx - nw / 2, mid + PX[0.5], fade(col, a))
			if is_pick and draft.steps[i] and hovered(cx - bw / 2, cy - bh / 2, cx + bw / 2, cy + bh / 2) then
				W.side_hover = { h = draft.steps[i], pos = draft.slot_pos[i] }
			end
			draw_slot(i, math.floor(cx - bw / 2), math.floor(cy - bh / 2), bw, bh, a)
		end
		draw_gauge(x + w - pad - gauge_w / 2, mid - PX[6], PX[K.GAUGE_R] - PX[2], a)
		draw_cursor(a)
	end

	local function draw_search(fx0, fy0, fx1, fy1, a)
		local fcy = (fy0 + fy1) / 2
		local focus = approach("focus", W.focus and 1 or 0, 16)
		local field_hover = approach("field_h", hovered(fx0, fy0, fx1, fy1) and 1 or 0, 20)
		rect(fx0, fy0, fx1, fy1, fade(P.FIELD, a * (1 + 0.5 * math.max(focus, field_hover * 0.5))), PX[9])
		glyph("\u{f002}", fx0 + PX[16], fcy, PX[11], fade(mix(P.MUTED, P.TEXT, focus), a))
		hit(fx0, fy0, fx1, fy1, "search")
		local gb = fy1 - fy0 - PX[8]
		local gx1 = fx1 - PX[4]
		local gx0 = gx1 - gb
		local gon = approach("grid_on", (W.grid_on or draft.query ~= "") and 1 or 0, 16)
		local gh = approach("grid_btn", hovered(gx0, fy0 + PX[4], gx1, fy1 - PX[4]) and 1 or 0, 20)
		if gon > 0.01 or gh > 0.01 then
			rect(gx0, fy0 + PX[4], gx1, fy1 - PX[4], fade(P.CHIP_ON, a * math.max(gon, gh * 0.6)), PX[7])
		end
		glyph("\u{f00a}", (gx0 + gx1) / 2, fcy, PX[11], fade(mix(P.MUTED, P.TEXT, math.max(gon, gh)), a))
		hit(gx0, fy0 + PX[4], gx1, fy1 - PX[4], "grid_toggle")
		tip("grid_toggle", gx0, fy0 + PX[4], gx1, fy1 - PX[4], L("cd_tip_grid_t"), L("cd_tip_grid"))
		local tx = fx0 + PX[30]
		local ph = approach("placeholder", draft.query == "" and 1 or 0, 22)
		if ph > 0 then
			Render.PushClip(Q.v1:Set(tx, fy0), Q.v2:Set(gx0 - PX[6], fy1), true)
			text(W.fonts.medium, PX[11], L("cd_search"), tx, fcy, fade(P.DIM, a * ph))
			Render.PopClip()
		end
		local qw = 0
		if draft.query ~= "" then
			qw = text(W.fonts.medium, PX[12], draft.query, tx, fcy, fade(P.TEXT, a))
		end
		if W.focus and os.clock() % 1 < 0.55 then
			local cx0 = tx + qw + (qw > 0 and PX[2] or 0)
			rect(cx0, fcy - PX[7], cx0 + math.max(1, PX[1]), fcy + PX[7], fade(P.TEXT, a * focus))
		end
	end

	function Q.grid_miss(hero, q)
		if Q.miss_q ~= q then
			Q.miss_q, Q.miss = q, {}
		end
		local v = Q.miss[hero.id]
		if v == nil then
			v = match_score(hero, q) == 0
			Q.miss[hero.id] = v
		end
		return v
	end

	local function draw_grid(x, y, w, h, a)
		local gx0, gy0, gx1, gy1 = x, y, x + w - PX[10], y + h
		W.grid_rect = { gx0, gy0, gx1, gy1 }
		if not D.heroes then
			spinner((gx0 + gx1) / 2, (gy0 + gy1) / 2, PX[12], a, P.MUTED, math.max(1.5, PX[2]))
			return
		end
		local col_w = (gx1 - gx0 - 3 * PX[K.COL_GAP]) / 4
		local cell_gap = PX[K.CELL_GAP]
		local head_h = PX[18]
		local per, cell_w, cell_h = 2, (col_w - cell_gap) / 2, PX[K.CELL_H]
		local best = 0
		for n = 2, 4 do
			local rows = 0
			for _, group in pairs(D.by_attr) do
				rows = math.max(rows, math.ceil(#group / n))
			end
			local cw = (col_w - (n - 1) * cell_gap) / n
			local ch = math.min(math.floor(cw * 9 / 16), math.floor((gy1 - gy0 - head_h + cell_gap) / math.max(1, rows) - cell_gap))
			if ch >= PX[16] and ch > best then
				best, per, cell_w, cell_h = ch, n, cw, ch
			end
		end
		local q = norm(draft.query)
		local used = used_set()
		local content = 0
		for _, group in pairs(D.by_attr) do
			content = math.max(content, head_h + math.ceil(#group / per) * (cell_h + cell_gap) - cell_gap)
		end
		local gmax = math.max(0, content - (gy1 - gy0))
		local scroll = SB.scroll("grid", "grid_scroll", gmax)
		Render.PushClip(Q.v1:Set(gx0, gy0), Q.v2:Set(gx1, gy1), true)
		local oy = gy0 - scroll
		local cx, cy = Input.GetCursorPos()
		local inside = in_rect(W.grid_rect, cx, cy) and not over_menu(cx, cy) and not W.drag
		for n, attr in ipairs({ "str", "agi", "int", "all" }) do
			local x0 = gx0 + (n - 1) * (col_w + PX[K.COL_GAP])
			text(W.fonts.semi, PX[10], L("cd_attr_" .. attr), x0, oy + head_h / 2 - PX[2], fade(P.MUTED, a))
			for j, hero in ipairs(D.by_attr[attr]) do
				local col, row = (j - 1) % per, (j - 1) // per
				local hx = math.floor(x0 + col * (cell_w + cell_gap) + 0.5)
				local hy = math.floor(oy + head_h + row * (cell_h + cell_gap) + 0.5)
				local hw = math.floor(cell_w + 0.5)
				local id = hero.id
				local is_used = used[id] and true or false
				local miss = q ~= "" and Q.grid_miss(hero, q)
				local gk = Q.gk[id]
				if not gk then
					gk = { "gu" .. id, "gm" .. id, "gh" .. id }
					Q.gk[id] = gk
				end
				local u = approach(gk[1], is_used and 1 or 0, 14)
				local mv = approach(gk[2], miss and 1 or 0, 18)
				local hov = inside and not is_used and cx >= hx and cx <= hx + hw and cy >= hy and cy <= hy + cell_h
				if hov then
					W.side_hover = { h = id }
				end
				local hv = approach(gk[3], hov and 1 or 0, 22)
				if hy + cell_h >= gy0 and hy <= gy1 then
					local alpha = a * (1 - 0.85 * mv)
					local img = portrait(id)
					local grow = PX[2] * hv
					local ix0, iy0 = hx - grow, hy - grow
					local iw, ih = hw + grow * 2, cell_h + grow * 2
					if img then
						local r = (iw / math.max(1, ih)) / (16 / 9)
						local u0, v0, u1, v1 = 0, 0, 1, 1
						if r > 1 then
							v0 = (1 - 1 / r) * K.CELL_CROP_Y
							v1 = v0 + 1 / r
						elseif r < 1 then
							u0 = (1 - r) / 2
							u1 = u0 + r
						end
						Render.Image(img, Q.v1:Set(ix0, iy0), Q.v2:Set(iw, ih), fade(mix(P.WHITE, P.USED, u), alpha), PX[4], K.ROUND,
							Q.v3:Set(u0, v0), Q.v4:Set(u1, v1), u)
					else
						rect(ix0, iy0, ix0 + iw, iy0 + ih, fade(P.FIELD, alpha), PX[4])
					end
					if hv > 0 then
						rect(ix0, iy0, ix0 + iw, iy0 + ih, fade(P.HOVER, a * hv * 1.6), PX[4])
					end
					if not is_used then
						local vy0, vy1 = math.max(hy, gy0), math.min(hy + cell_h, gy1)
						if vy1 > vy0 then
							hit(hx, vy0, hx + hw, vy1, "hero", id)
						end
					end
				end
			end
		end
		Render.PopClip()
		SB.bar("grid", x + w, gy0, gy1, scroll, gmax, a)
	end

	function Q.reasons_layout(row, size, icon, room)
		local items, lx = {}, 0
		local function word(str, color)
			if lx < room then
				items[#items + 1] = { 1, lx, str, color }
				lx = lx + tw(W.fonts.regular, size, str) + PX[4]
			end
		end
		local function sep()
			items[#items + 1] = { 2, lx }
			lx = lx + PX[7]
		end
		local function face(h, v)
			local val = pct(v)
			local str = (val >= 0 and "+" or "") .. ("%.1f"):format(val)
			items[#items + 1] = { 3, lx, str, val >= 0 and P.GOOD or P.BAD, h }
			lx = lx + icon + PX[2] + tw(W.fonts.medium, size, str) + PX[6]
		end
		local sv = row.solo and pct(row.solo) or 0
		if math.abs(sv) >= K.REASON_MIN then
			word(L("cd_reason_solo"):format((sv >= 0 and "+" or "") .. ("%.1f"):format(sv)), sv >= 0 and P.GOOD or P.BAD)
			sep()
		end
		local good, bad = {}, nil
		for _, r in ipairs(row.reasons) do
			if pct(r.v) >= K.REASON_MIN and #good < K.REASONS then
				good[#good + 1] = r
			end
		end
		local last = row.reasons[#row.reasons]
		if last and pct(last.v) <= -K.REASON_MIN then
			bad = last
		end
		if #good == 0 and not bad then
			if #row.reasons == 0 then
				items[#items + 1] = { 4, lx }
			end
			return items
		end
		local groups = {
			{ label = L("cd_vs"), faces = {} },
			{ label = L("cd_with"), faces = {} },
			{ label = bad and (bad.t == "vs" and L("cd_weak") or L("cd_bad_with")), faces = { bad } },
		}
		for _, r in ipairs(good) do
			local g = groups[r.t == "vs" and 1 or 2]
			g.faces[#g.faces + 1] = r
		end
		local function face_w(r)
			local val = pct(r.v)
			return icon + PX[2] + tw(W.fonts.medium, size, (val >= 0 and "+" or "") .. ("%.1f"):format(val)) + PX[6]
		end
		local function total()
			local w, any = 0, false
			for _, g in ipairs(groups) do
				if #g.faces > 0 then
					if any then
						w = w + PX[7]
					end
					any = true
					w = w + tw(W.fonts.regular, size, g.label) + PX[4]
					for _, r in ipairs(g.faces) do
						w = w + face_w(r)
					end
				end
			end
			return w
		end
		for _, d in ipairs(K.REASON_DROP) do
			if lx + total() <= room then
				break
			end
			local list = groups[d[1]].faces
			if #list >= d[2] then
				table.remove(list, d[2])
			end
		end
		local drawn = false
		for _, g in ipairs(groups) do
			if #g.faces > 0 then
				if drawn then
					sep()
				end
				drawn = true
				word(g.label, P.MUTED)
				for _, r in ipairs(g.faces) do
					face(r.h, r.v)
				end
			end
		end
		return items
	end

	local function draw_reasons(row, x, cy, max_x, a)
		local size = PX[11]
		local icon = PX[18]
		local room = max_x - x
		local c = Q.rs[row]
		if not c or c.room ~= room or c.size ~= size or c.memo ~= localization.memo then
			c = { room = room, size = size, memo = localization.memo, items = Q.reasons_layout(row, size, icon, room) }
			Q.rs[row] = c
		end
		for _, it in ipairs(c.items) do
			local kind, lx = it[1], x + it[2]
			if kind == 1 then
				text(W.fonts.regular, size, it[3], lx, cy, fade(it[4], a), true)
			elseif kind == 2 then
				vline(lx, cy, PX[5], a)
			elseif kind == 4 then
				if lx < max_x then
					lx = lx + text(W.fonts.regular, size, L("cd_rate"):format(M.base(row.h) * 100), lx, cy, fade(P.MUTED, a), true) + PX[4]
				end
				if row.contest >= 0.05 then
					vline(lx, cy, PX[5], a)
					lx = lx + PX[7]
					if lx < max_x then
						text(W.fonts.regular, size, L("cd_pro"):format(math.floor(row.contest * 100 + 0.5)), lx, cy, fade(P.MUTED, a), true)
					end
				end
			else
				local img = mini(it[5])
				if img then
					Render.Image(img, Q.v1:Set(lx, math.floor(cy - icon / 2)), Q.v2:Set(icon, icon), fade(P.WHITE, a))
				end
				text(W.fonts.medium, size, it[3], lx + icon + PX[2], cy, fade(it[4], a), true)
			end
		end
	end

	local function draw_comp(row, x, cy, max_x, a)
		local lx = x + text(W.fonts.regular, PX[10], L("cd_with_him"), x, cy, fade(P.DIM, a), true) + PX[6]
		local icon = PX[18]
		for _, c in ipairs(row.comp) do
			if lx + icon > max_x then
				break
			end
			lx = lx + draw_pos(c.pos, lx, cy, PX[11], a) + PX[2]
			local img = mini(c.h)
			if img then
				Render.Image(img, Q.v1:Set(lx, math.floor(cy - icon / 2)), Q.v2:Set(icon, icon), fade(P.WHITE, a))
			end
			lx = lx + icon + PX[7]
		end
	end

	local function draw_pos_buttons(res, xr, cy, a)
		local size = PX[K.BTN]
		local items = { { p = 0 } }
		for p = 1, 5 do
			items[#items + 1] = { p = p, busy = res.kind == "P" and res.taken[p] and draft.filter ~= p }
		end
		local total = PX[4] * (#items - 1)
		for _, it in ipairs(items) do
			it.on = draft.filter == it.p
			it.label = it.p == 0 and L("cd_auto_pos") or L("cd_pos" .. it.p)
			it.open = tween("pb_o" .. it.p, it.on and 1 or 0, K.MOVE)
			it.bw = size + (tw(W.fonts.medium, PX[11], it.label) + PX[6]) * it.open
			total = total + it.bw
		end
		local bx = xr - total
		for _, it in ipairs(items) do
			local bw, open = it.bw, it.open
			local hv = approach("pb_h" .. it.p, hovered(bx, cy - size / 2, bx + bw, cy + size / 2) and 1 or 0, 20)
			local bg = it.on and P.CHIP_ON or mix(P.CELL, P.HOVER, hv)
			local ba = a * (it.busy and 0.55 or 1)
			rect(bx, cy - size / 2, bx + bw, cy + size / 2, fade(bg, ba), PX[7])
			if it.p == 0 then
				glyph("\u{f0d0}", bx + size / 2, cy, PX[12], fade(mix(P.MUTED, P.TEXT, open), ba))
			else
				draw_pos(it.p, bx + (size - PX[15]) / 2, cy, PX[15], ba)
			end
			if open > 0.02 then
				Render.PushClip(Q.v1:Set(bx + size - PX[4], cy - size / 2), Q.v2:Set(bx + bw, cy + size / 2), true)
				text(W.fonts.medium, PX[11], it.label, bx + size - PX[4], cy, fade(P.TEXT, ba * open), true)
				Render.PopClip()
			end
			hit(bx, cy - size / 2, bx + bw, cy + size / 2, "pos", it.p)
			local title, body
			if it.p == 0 then
				title, body = L("cd_tip_auto_t"), L("cd_tip_auto")
			else
				title = L("cd_posT" .. it.p)
				if it.busy then
					local owner = "?"
					for i, pos in pairs(draft.slot_pos) do
						if pos == it.p and draft.steps[i] and D.by_id[draft.steps[i]] then
							owner = D.by_id[draft.steps[i]].name
						end
					end
					body = L("cd_tip_taken"):format(owner)
				else
					body = L(res.kind == "B" and "cd_tip_ban" or "cd_tip_pick")
				end
			end
			if tip_at(bx, cy - size / 2, bx + bw, cy + size / 2) then
				tip_put("pos" .. it.p, title, body, it.p > 0 and it.p or nil)
			end
			bx = bx + bw + PX[4]
		end
		return total
	end

	local SM = {}

	function SM.signed(v)
		if math.abs(v) < 0.05 then
			return "0.0"
		end
		return (v > 0 and "+" or "") .. ("%.1f"):format(v)
	end

	function SM.tone(v)
		return v >= K.SUM_MIN and P.GOOD or (v <= -K.SUM_MIN and P.BAD or P.MUTED)
	end

	function SM.item(name, x, y, w, h, q, a)
		local img = Q.asset("items/", name)
		if img then
			Render.Image(img, Q.v1:Set(x, y), Q.v2:Set(w, h), fade(P.WHITE, a), PX[5], K.ROUND)
		else
			rect(x, y, x + w, y + h, fade(P.FIELD, a), PX[5])
		end
		if q and q > 1 then
			local label = tostring(q)
			local lw = tw(W.fonts.bold, PX[9], label) + PX[6]
			local bx1, by1 = x + w - PX[2], y + h - PX[2]
			rect(bx1 - lw, by1 - PX[11], bx1, by1, fade(P.SHADE, a), PX[3])
			text(W.fonts.bold, PX[9], label, bx1 - lw + PX[3], by1 - PX[11] / 2, fade(P.TEXT, a))
		end
	end

	function SM.sell_badge(sell, x, y, w, h, a)
		local ring = math.max(2, PX[2])
		local bw = math.max(PX[16], math.floor(w * 0.5 + 0.5))
		local bh = math.floor(bw * 0.73 + 0.5)
		local bx, by = x + w - bw + PX[6], y + h - bh + PX[6]
		rect(bx - ring, by - ring, bx + bw + ring, by + bh + ring, fade(P.BG, a), PX[5])
		local img = Q.asset("items/", sell.name)
		if img then
			Render.Image(img, Q.v1:Set(bx, by), Q.v2:Set(bw, bh), fade(P.WHITE, sell.bag and a * 0.45 or a), PX[3], K.ROUND)
		end
		if not sell.bag then
			glyph("\u{f00d}", bx + bw / 2, by + bh / 2, math.floor(bh * 0.9 + 0.5), fade(P.BAD, a))
		end
	end

	function SM.sell_line(sell, label)
		return L(sell.bag and "cd_bag" or "cd_sell"):format(sell.label, label)
	end

	function SM.pick(x, y, w, h, a)
		local p = W.pick
		local k = approach("pick_k", p and 1 or 0, 18)
		if p then
			W.pick_last = p
		end
		p = p or W.pick_last
		local pa = k * a
		if pa <= 0.01 or not p then
			return
		end
		rect(x, y, x + w, y + h, fade(P.SCRIM, pa), PX[K.RADIUS])
		if W.pick then
			hit(x, y, x + w, y + h, "pickbg")
		end
		local cw, ch, pad = PX[340], PX[168], PX[20]
		local cx0 = math.floor(x + (w - cw) / 2)
		local cy0 = math.floor(y + (h - ch) / 2 + (1 - k) * PX[K.SLIDE])
		rect(cx0, cy0, cx0 + cw, cy0 + ch, fade(P.CARD, pa), PX[12])
		if W.pick then
			hit(cx0, cy0, cx0 + cw, cy0 + ch, "pickcard")
		end
		local iw, ih = PX[88], PX[50]
		local img = portrait(p.h)
		if img then
			Render.Image(img, Q.v1:Set(cx0 + pad, cy0 + pad), Q.v2:Set(iw, ih), fade(P.WHITE, pa), PX[6], K.ROUND)
		end
		local hero = D.by_id[p.h]
		local tx = cx0 + pad + iw + PX[14]
		text(W.fonts.medium, PX[12], L("cd_pk_t"), tx, cy0 + pad + PX[13], fade(P.MUTED, pa))
		text(W.fonts.bold, PX[16], hero and hero.name or "?", tx, cy0 + pad + PX[35], fade(P.TEXT, pa))
		local by = cy0 + PX[92]
		local box = PX[14]
		local lw = tw(W.fonts.regular, PX[12], L("cd_pk_dont"))
		local dx1 = cx0 + pad + box + PX[8] + lw
		local dhv = approach("pick_dh", (W.pick and hovered(cx0 + pad - PX[4], by - PX[10], dx1 + PX[4], by + PX[10])) and 1 or 0, 20)
		rect(cx0 + pad, by - box / 2, cx0 + pad + box, by + box / 2, fade(p.dont and P.CHIP_ON or mix(P.CELL, P.HOVER, dhv), pa), PX[4])
		if p.dont then
			glyph("\u{f00c}", cx0 + pad + box / 2, by, PX[9], fade(P.TEXT, pa))
		end
		text(W.fonts.regular, PX[12], L("cd_pk_dont"), cx0 + pad + box + PX[8], by, fade(mix(P.MUTED, P.TEXT, dhv), pa))
		if W.pick then
			hit(cx0 + pad - PX[4], by - PX[10], dx1 + PX[4], by + PX[10], "pick_dont")
		end
		if p.dont then
			text(W.fonts.regular, PX[10], L("cd_pk_dont2"), cx0 + pad + box + PX[8], by + PX[16], fade(P.DIM, pa))
		end
		local bh = PX[28]
		local by1 = cy0 + ch - PX[16]
		local bx1 = cx0 + cw - pad
		for n, b in ipairs({ { "pick_ok", L("cd_pk_ok"), true }, { "pick_no", L("cd_pk_no"), false } }) do
			local bw = tw(W.fonts.semi, PX[12], b[2]) + PX[32]
			local bx0 = bx1 - bw
			local bhv = approach("pick_b" .. n, (W.pick and hovered(bx0, by1 - bh, bx1, by1)) and 1 or 0, 20)
			rect(bx0, by1 - bh, bx1, by1, fade(mix(b[3] and P.CHIP_ON or P.CELL, rgba(255, 255, 255, 60), bhv), pa), PX[7])
			text(W.fonts.semi, PX[12], b[2], bx0 + PX[16], by1 - bh / 2, fade(P.TEXT, pa))
			if W.pick then
				hit(bx0, by1 - bh, bx1, by1, b[1])
			end
			bx1 = bx0 - PX[8]
		end
	end

	function SM.toast(x, y, w, h, a, field)
		field = field or "toast"
		local t = W[field]
		if not t then
			return
		end
		local age = os.clock() - t.t
		local life = t.life or K.TOAST
		if age > life then
			W[field] = nil
			return
		end
		local ta = a * clamp(math.min(age / 0.15, (life - age) / 0.3), 0, 1)
		local label = t.arg and L(t.key):format(t.arg) or L(t.key)
		local bw, bh = tw(W.fonts.medium, PX[12], label) + PX[44], PX[32]
		local bx0 = math.floor(x + (w - bw) / 2)
		local by0 = y + h - bh - PX[18]
		rect(bx0, by0, bx0 + bw, by0 + bh, fade(P.TIP, ta), PX[8])
		Render.Rect(Q.v1:Set(bx0, by0), Q.v2:Set(bx0 + bw, by0 + bh), fade(P.SEP, ta), PX[8], K.ROUND, math.max(1, PX[1]))
		glyph("\u{f05a}", bx0 + PX[16], by0 + bh / 2, PX[11], fade(P.WARN, ta))
		text(W.fonts.medium, PX[12], label, bx0 + PX[28], by0 + bh / 2, fade(P.TEXT, ta))
	end

	function SM.caption(label, sub, x, cy, a)
		local lx = x + text(W.fonts.semi, PX[10], label, x, cy, fade(P.DIM, a))
		if sub then
			lx = lx + PX[8]
			vline(lx, cy, PX[6], a)
			text(W.fonts.regular, PX[10], sub, lx + PX[8], cy, fade(P.MUTED, a))
		end
	end

	function SM.posbar(h, auto_pos, right, cy, a)
		local size, gap = PX[22], PX[3]
		local have = I.positions(h)
		local loaded = I.buys[h] ~= nil
		local pos = I.bpos[h] or auto_pos
		local x = right - 5 * size - 4 * gap
		for k = 1, 5 do
			local bx = x + (k - 1) * (size + gap)
			local on = pos == k
			local avail = not loaded or have[k] ~= nil
			local hv = approach("sbp" .. k, hovered(bx, cy - size / 2, bx + size, cy + size / 2) and 1 or 0, 20)
			rect(bx, cy - size / 2, bx + size, cy + size / 2, fade(on and P.CHIP_ON or mix(P.CELL, P.HOVER, hv), a), PX[6])
			draw_pos(k, bx + (size - PX[14]) / 2, cy, PX[14], a * ((avail or on) and 1 or 0.35))
			hit(bx, cy - size / 2, bx + size, cy + size / 2, "bpos", Q.harg("h", h, "p", k))
			local body = have[k] and I.pos_tip(h, k) or (avail and "" or L("cd_tip_bpos_none"))
			if tip_at(bx, cy - size / 2, bx + size, cy + size / 2) then
				tip_put("sbpt" .. k, L("cd_posT" .. k), body, k)
			end
		end
		return x
	end

	function SM.qbuy(id, name, x0, y0, x1, y1, a, r)
		hit(x0, y0, x1, y1, "qbuy", Q.harg("id", id, "name", name))
		local over = hovered(x0, y0, x1, y1)
		local hv = approach("qb_" .. id, over and 1 or 0, 20)
		local fl = W.qflash and W.qflash.id == id and clamp(1 - (os.clock() - W.qflash.t) / K.QFLASH, 0, 1) or 0
		local k = 0.08 * hv + 0.3 * fl
		if k > 0.005 then
			rect(x0, y0, x1, y1, fade(rgba(255, 255, 255, math.floor(255 * k)), a), r or PX[4])
		end
		local it, h = I.by_name[name], W.item_h
		if not h or not it or it.consumable or K.BAN_SKIP[name] or x1 - x0 < PX[K.BAN_MIN_W] then
			return
		end
		local bs = math.max(PX[13], math.floor(math.min(x1 - x0, y1 - y0) * 0.44))
		local bx1, by0 = x1 - PX[2], y0 + PX[2]
		local bx0, by1 = bx1 - bs, by0 + bs
		local bh = approach("qban_" .. id, (over and hovered(bx0, by0, bx1, by1)) and 1 or 0, 22)
		local va = a * math.max(hv, bh)
		if va <= 0.02 then
			return
		end
		rect(bx0, by0, bx1, by1, fade(mix(rgba(P.BG.r, P.BG.g, P.BG.b, 220), rgba(P.BAD.r, P.BAD.g, P.BAD.b, 235), bh), va), bs / 2)
		glyph("\u{f165}", (bx0 + bx1) / 2, (by0 + by1) / 2 + PX[1], math.floor(bs * 0.56 + 0.5), fade(mix(P.MUTED, P.WHITE, bh), va))
		if over then
			hit(bx0, by0, bx1, by1, "iban", Q.harg("name", name, "h", h))
			local hero = D.by_id[h]
			if tip_at(bx0, by0, bx1, by1) then
				tip_put("qban" .. id, L("cd_ban_t"):format(it.label), L("cd_tip_ban"):format(hero and hero.name or "?"))
			end
		end
	end

	function SM.my_row(sm)
		local mine = my_hero_id()
		if mine <= 0 then
			mine = draft.mode == 1 and draft.me and not draft.tentative[draft.me] and draft.steps[draft.me]
		end
		for _, row in ipairs(sm.rows) do
			if row.h == mine then
				return row
			end
		end
		return nil
	end

	function SM.card_row()
		local sm = draft.summary
		local hid = W.card or W.card_last
		if not sm or not hid then
			return nil, nil
		end
		for _, row in ipairs(sm.rows) do
			if row.h == hid then
				return sm, row
			end
		end
		return nil, nil
	end

	function SM.timeline(build, x0, x1, y, a)
		local iw, ih, gap, lane_h = PX[46], PX[34], PX[6], PX[52]
		local tmax = 2400
		for _, st in ipairs(build.steps) do
			tmax = math.max(tmax, math.ceil((st.t or 0) / 600) * 600)
		end
		local span = x1 - x0 - iw
		local last = { -math.huge, -math.huge }
		local tl = build.tl_cache
		local placed
		if tl and tl.x0 == x0 and tl.x1 == x1 and tl.iw == iw and tl.gap == gap and tl.tmax == tmax and tl.n == #build.steps then
			placed = tl.placed
		else
			placed = {}
			build.tl_cache = { x0 = x0, x1 = x1, iw = iw, gap = gap, tmax = tmax, n = #build.steps, placed = placed }
		end
		for _, st in ipairs(#placed == 0 and build.steps or I.none) do
			local cx = x0 + iw / 2 + span * clamp((st.t or 0) / tmax, 0, 1)
			local lane
			for l = 1, 2 do
				if not lane and cx - iw / 2 >= last[l] + gap then
					lane = l
				end
			end
			if not lane then
				lane = last[1] <= last[2] and 1 or 2
				cx = last[lane] + gap + iw / 2
			end
			cx = math.min(cx, x1 - iw / 2)
			last[lane] = cx + iw / 2
			placed[#placed + 1] = { st = st, cx = cx, lane = lane }
		end
		local ruler = y + lane_h * 2 + PX[4]
		local line = math.max(1, PX[1])
		rect(x0, ruler, x1, ruler + line, fade(P.LINE, a * 1.4))
		for t = 0, tmax, 600 do
			local tx = x0 + iw / 2 + span * t / tmax
			local label = t == tmax and L("cd_p_min"):format(t // 60) or tostring(t // 60)
			local lw = tw(W.fonts.regular, PX[10], label)
			text(W.fonts.regular, PX[10], label, math.min(tx - lw / 2, x1 - lw), ruler + PX[11], fade(P.DIM, a))
		end
		for n, p in ipairs(placed) do
			local st = p.st
			local tx = math.floor(x0 + iw / 2 + span * clamp((st.t or 0) / tmax, 0, 1))
			rect(tx, ruler - PX[4], tx + line, ruler, fade(P.SEP, a))
			local ix = math.floor(p.cx - iw / 2)
			local iy = y + (p.lane - 1) * lane_h
			SM.item(st.item.name, ix, iy, iw, ih, nil, a)
			SM.qbuy("cdi" .. n, st.item.name, ix, iy, ix + iw, iy + ih, a)
			local src = st.base or (st.pre and st.pre.item)
			if src then
				local ring = math.max(2, PX[2])
				local bs = PX[22]
				local bh = math.floor(bs * 0.73 + 0.5)
				local bx, by = ix + iw - bs + PX[6], iy - PX[6]
				rect(bx - ring, by - ring, bx + bs + ring, by + bh + ring, fade(P.BG, a), PX[5])
				local img = Q.asset("items/", src.name)
				if img then
					Render.Image(img, Q.v1:Set(bx, by), Q.v2:Set(bs, bh), fade(P.WHITE, a), PX[3], K.ROUND)
				end
			end
			if st.vs and #st.vs > 0 then
				local icon = PX[14]
				local count = math.min(#st.vs, 3)
				local vx = ix + math.floor((iw - (count * icon + (count - 1) * PX[2])) / 2)
				for k = 1, count do
					local img = mini(st.vs[k])
					if img then
						Render.Image(img, Q.v1:Set(vx, iy + ih + PX[3]), Q.v2:Set(icon, icon), fade(P.WHITE, a))
					end
					vx = vx + icon + PX[2]
				end
			end
			local body = st.body or ""
			local sell = build.sells and build.sells[st]
			if sell then
				SM.sell_badge(sell, ix, iy, iw, ih, a)
				body = (body ~= "" and body .. "\n" or "") .. SM.sell_line(sell, st.item.label)
			end
			if tip_at(ix, iy, ix + iw, iy + ih) then
				tip_put("cdi" .. n, st.item.label, body)
			end
		end
		return ruler + PX[24]
	end

	function SM.card_side(sm, build, x0, x1, y, a, part)
		if part ~= "more" and build.skills and #build.skills > 0 then
			SM.caption(L("cd_card_skills"), nil, x0, y, a)
			y = y + PX[12]
			local ks, sg = PX[22], PX[3]
			local per = math.max(1, math.floor((x1 - x0 + sg) / (ks + sg)))
			for n, sk in ipairs(build.skills) do
				local kx = x0 + ((n - 1) % per) * (ks + sg)
				local ky = y + ((n - 1) // per) * (ks + sg)
				local title, body
				if sk.attr then
					rect(kx, ky, kx + ks, ky + ks, fade(P.FIELD, a), PX[4])
					glyph("\u{f067}", kx + ks / 2, ky + ks / 2, math.floor(ks * 0.5 + 0.5), fade(P.GOOD, a))
					title = L("cd_attr")
					body = L("cd_tip_skill"):format(sk.lv, math.floor(sk.share * 100 + 0.5))
				elseif sk.talent then
					rect(kx, ky, kx + ks, ky + ks, fade(P.FIELD, a), PX[4])
					glyph("\u{f005}", kx + ks / 2, ky + ks / 2, math.floor(ks * 0.55 + 0.5), fade(P.WARN, a))
					local pick
					for _, t in ipairs(build.talents or {}) do
						if (sk.tier and t.from == sk.tier) or (not sk.tier and sk.lv >= t.from and sk.lv <= t.upto) then
							pick = t
						end
					end
					title = pick and I.ability_label(pick.name) or L("cd_talent_tier"):format(sk.tier or sk.lv)
					body = L("cd_tip_talent"):format(sk.lv, math.floor((pick and pick.share or sk.share) * 100 + 0.5))
					if pick and pick.why then
						body = body .. "\n" .. pick.why
					end
				else
					local img = Q.asset("spellicons/", sk.name)
					if img then
						Render.Image(img, Q.v1:Set(kx, ky), Q.v2:Set(ks, ks), fade(P.WHITE, a), PX[4], K.ROUND)
					else
						rect(kx, ky, kx + ks, ky + ks, fade(P.FIELD, a), PX[4])
					end
					title = I.ability_label(sk.name)
					body = L("cd_tip_skill"):format(sk.lv, math.floor(sk.share * 100 + 0.5))
					if sk.why then
						body = body .. "\n" .. sk.why
						Render.Rect(Q.v1:Set(kx, ky), Q.v2:Set(kx + ks, ky + ks), fade(P.ACC, a), PX[4], K.ROUND, math.max(1, PX[1.5]))
					end
				end
				if tip_at(kx, ky, kx + ks, ky + ks) then
					tip_put("cdk" .. n, title, body)
				end
			end
			y = y + math.ceil(#build.skills / per) * (ks + sg) + PX[10]
			for _, t in ipairs(build.talents or {}) do
				local label = I.ability_label(t.name)
				text(W.fonts.semi, PX[11], tostring(t.from), x0, y, fade(P.MUTED, a))
				Render.PushClip(Q.v1:Set(x0 + PX[24], y - PX[9]), Q.v2:Set(x1, y + PX[9]), true)
				text(W.fonts.regular, PX[11], label, x0 + PX[24], y, fade(t.why and P.ACC or P.TEXT, a))
				Render.PopClip()
				local tb = L("cd_tip_talent"):format(t.from, math.floor(t.share * 100 + 0.5))
				if tip_at(x0, y - PX[8], x1, y + PX[8]) then
					tip_put("cdt" .. t.from, label, t.why and (tb .. "\n" .. t.why) or tb)
				end
				y = y + PX[17]
			end
			y = y + PX[16]
		end
		if part ~= "skills" and build.neutrals and #build.neutrals > 0 then
			SM.caption(L("cd_card_neutral"), nil, x0, y, a)
			y = y + PX[12]
			local nw, nh = PX[34], PX[25]
			local nx = x0
			for n, tr in ipairs(build.neutrals) do
				local best = tr.items[1]
				SM.item(best.name, nx, y, nw, nh, nil, a)
				local num = tostring(tr.tier)
				local bw = tw(W.fonts.bold, PX[9], num) + PX[6]
				rect(nx + PX[2], y + PX[2], nx + PX[2] + bw, y + PX[13], fade(P.SHADE, a), PX[3])
				text(W.fonts.bold, PX[9], num, nx + PX[5], y + PX[7.5], fade(P.TEXT, a))
				local lines = { L("cd_tip_neutral"):format(tr.tier, math.floor(best.share * 100 + 0.5)) }
				local alts = {}
				for k = 2, math.min(#tr.items, K.NEUTRAL_ALTS + 1) do
					alts[#alts + 1] = I.item_label(tr.items[k].name)
				end
				if #alts > 0 then
					lines[#lines + 1] = L("cd_tip_neutral_alt"):format(table.concat(alts, ", "))
				end
				if tip_at(nx, y, nx + nw, y + nh) then
					tip_put("cdn" .. n, I.item_label(best.name), table.concat(lines, "\n"))
				end
				nx = nx + nw + PX[5]
			end
			y = y + nh
			if build.enh then
				y = y + PX[14]
				local label = L("cd_neutral_enh"):format(I.item_label(build.enh.name))
				Render.PushClip(Q.v1:Set(x0, y - PX[9]), Q.v2:Set(x1, y + PX[9]), true)
				local ew = text(W.fonts.regular, PX[11], label, x0, y, fade(P.MUTED, a))
				Render.PopClip()
				if tip_at(x0, y - PX[8], math.min(x1, x0 + ew), y + PX[8]) then
					tip_put("cde", label, L("cd_tip_enh"):format(math.floor(build.enh.share * 100 + 0.5)))
				end
			end
			y = y + PX[26]
		end
		if part ~= "skills" and cfg.live == 1 then
			local them = sm.them or I.none
			local pc = sm.pred_cache
			local fresh = pc and pc.n == #them
			if fresh then
				for i, e in ipairs(them) do
					if pc[i] ~= I.predicted(e) then
						fresh = false
						break
					end
				end
			end
			if not fresh then
				pc = { n = #them, list = {} }
				for i, e in ipairs(them) do
					pc[i] = I.predicted(e)
					for _, p in ipairs(pc[i]) do
						pc.list[#pc.list + 1] = { name = p.name, share = p.share, e = e }
					end
				end
				table.sort(pc.list, function(p, q)
					if p.share ~= q.share then
						return p.share > q.share
					end
					return p.name < q.name
				end)
				sm.pred_cache = pc
			end
			local list = pc.list
			if #list > 0 then
				SM.caption(L("cd_card_enemy"), nil, x0, y, a)
				y = y + PX[12]
				for n = 1, math.min(#list, K.PREDICT_SHOW) do
					local p = list[n]
					local cy = y + PX[9]
					local face = mini(p.e)
					if face then
						Render.Image(face, Q.v1:Set(x0, cy - PX[9]), Q.v2:Set(PX[18], PX[18]), fade(P.WHITE, a))
					end
					SM.item(p.name, x0 + PX[24], cy - PX[9], PX[24], PX[18], nil, a)
					local label = L("cd_card_pred"):format(I.item_label(p.name), math.floor(p.share * 100 + 0.5))
					Render.PushClip(Q.v1:Set(x0 + PX[54], cy - PX[9]), Q.v2:Set(x1, cy + PX[9]), true)
					text(W.fonts.regular, PX[11], label, x0 + PX[54], cy, fade(P.MUTED, a))
					Render.PopClip()
					y = y + PX[22]
				end
			end
		end
	end

	function SM.card(x, y, w, h, a)
		local sm, row = SM.card_row()
		W.item_h = row and row.h or nil
		if not row then
			W.card = nil
			return
		end
		if W.card then
			hit(x, y, x + w, y + h, "cardbg")
		end
		local pad = PX[16]
		local left, right = x + pad, x + w - pad
		local hero = D.by_id[row.h]
		local pos = I.bpos[row.h] or row.pos
		if pos then
			I.shown_pos[row.h] = pos
		end
		local mates = {}
		for _, r in ipairs(sm.rows) do
			if r.h ~= row.h then
				mates[#mates + 1] = r.h
			end
		end
		table.sort(mates)
		local build = I.build(row.h, pos, sm.them, mates)
		local bt, bb = y + PX[12], y + PX[92]
		rect(left, bt, right, bb, fade(P.CARD, a), PX[12])
		grad(left, bt, left + (right - left) * 0.55, bb, fade(rgba(P.ACC.r, P.ACC.g, P.ACC.b, 30), a),
			fade(rgba(P.ACC.r, P.ACC.g, P.ACC.b, 0), a), PX[12])
		Render.Rect(Q.v1:Set(left, bt), Q.v2:Set(right, bb), fade(P.LINE, a), PX[12], K.ROUND, math.max(1, PX[1]))
		local iw, ih = PX[118], PX[66]
		local ix, iy = left + PX[8], math.floor((bt + bb - ih) / 2)
		local img = portrait(row.h)
		if img then
			Render.Image(img, Q.v1:Set(ix, iy), Q.v2:Set(iw, ih), fade(P.WHITE, a), PX[9], K.ROUND)
		else
			rect(ix, iy, ix + iw, iy + ih, fade(P.FIELD, a), PX[9])
		end
		local cb = PX[26]
		local cx0, ccy = right - PX[8] - cb, bt + PX[20]
		local chv = approach("card_x", (W.card and hovered(cx0, ccy - cb / 2, cx0 + cb, ccy + cb / 2)) and 1 or 0, 20)
		if chv > 0 then
			rect(cx0, ccy - cb / 2, cx0 + cb, ccy + cb / 2, fade(P.HOVER, a * chv), PX[7])
		end
		glyph("\u{f00d}", cx0 + cb / 2, ccy, PX[12], fade(mix(P.MUTED, P.TEXT, chv), a))
		hit(cx0, ccy - cb / 2, cx0 + cb, ccy + cb / 2, "card_close")
		local fs, fg = PX[24], PX[4]
		local fx = cx0 - PX[12] - #sm.rows * (fs + fg) + fg
		for k, r in ipairs(sm.rows) do
			local bx = fx + (k - 1) * (fs + fg)
			local on = r.h == row.h
			local hv = approach("cdh" .. r.h, (W.card and hovered(bx, ccy - fs / 2, bx + fs, ccy + fs / 2)) and 1 or 0, 20)
			rect(bx, ccy - fs / 2, bx + fs, ccy + fs / 2, fade(on and P.CHIP_ON or mix(P.CELL, P.HOVER, hv), a), PX[7])
			local face = mini(r.h)
			if face then
				local fi = PX[18]
				Render.Image(face, Q.v1:Set(bx + (fs - fi) / 2, ccy - fi / 2), Q.v2:Set(fi, fi), fade(P.WHITE, a * ((on or hv > 0) and 1 or 0.6)))
			end
			hit(bx, ccy - fs / 2, bx + fs, ccy + fs / 2, "card_hero", r.h)
			local rh = D.by_id[r.h]
			if tip_at(bx, ccy - fs / 2, bx + fs, ccy + fs / 2) then
				tip_put("cdh" .. r.h, rh and rh.name or "?", "")
			end
		end
		local pcy = bb - PX[20]
		local bar_x = SM.posbar(row.h, row.pos, right - PX[12], pcy, a)
		if draft.chance then
			local num = ("%d%%"):format(math.floor(draft.chance * 100 + 0.5))
			local cl = L("cd_chance")
			local nx = bar_x - PX[16] - tw(W.fonts.bold, PX[13], num)
			text(W.fonts.bold, PX[13], num, nx, pcy, fade(draft.chance >= 0.5 and P.GOOD or P.BAD, a))
			text(W.fonts.regular, PX[10], cl, nx - PX[6] - tw(W.fonts.regular, PX[10], cl), pcy, fade(P.MUTED, a))
		end
		local tx = ix + iw + PX[16]
		Render.PushClip(Q.v1:Set(tx, bt), Q.v2:Set(fx - PX[12], bb), true)
		text(W.fonts.bold, PX[18], hero and hero.name or "?", tx, bt + PX[22], fade(P.TEXT, a))
		local sub = build and build.pooled and I.pool_note(build.pooled)
			or (build and build.since and L("cd_build_since"):format(build.since)) or L("cd_build_sub")
		text(W.fonts.regular, PX[11], sub, tx, bt + PX[42], fade(P.MUTED, a))
		Render.PopClip()
		local vx = tx + text(W.fonts.regular, PX[10], L("cd_card_vs"), tx, bb - PX[20], fade(P.DIM, a)) + PX[8]
		for _, e in ipairs(sm.them or {}) do
			local face = mini(e)
			if face and vx + PX[18] < bar_x - PX[120] then
				Render.Image(face, Q.v1:Set(vx, bb - PX[29]), Q.v2:Set(PX[18], PX[18]), fade(P.WHITE, a))
				vx = vx + PX[21]
			end
		end
		local by = bb + PX[20]
		if not build or build.none or #build.slots == 0 then
			local msg, warn, spin
			if build and build.none then
				msg = L("cd_build_nopos"):format(pos and L("cd_acc" .. pos) or "?")
			elseif build then
				msg = L("cd_build_none")
			elseif I.error and not I.busy then
				msg, warn = L("cd_ld_error"), true
			else
				msg, spin = L("cd_build_loading"), true
			end
			local mx = left
			if warn then
				glyph("\u{f071}", left + PX[6], by, PX[10], fade(P.WARN, a))
				mx = left + PX[18]
			elseif spin then
				spinner(left + PX[6], by, PX[5], a, P.MUTED, math.max(1, PX[1.5]))
				mx = left + PX[18]
			end
			text(W.fonts.medium, PX[12], msg, mx, by, fade(P.TEXT, a))
			if build and build.none then
				text(W.fonts.regular, PX[10], L("cd_build_nopos2"), left, by + PX[18], fade(P.DIM, a))
			end
			return
		end
		Render.PushClip(Q.v1:Set(x, bb), Q.v2:Set(x + w, y + h), true)
		SM.caption(L("cd_card_order"), nil, left, by, a)
		local hint = L("cd_card_qbuy")
		text(W.fonts.regular, PX[10], hint, right - tw(W.fonts.regular, PX[10], hint), by, fade(P.DIM, a))
		by = SM.timeline(build, left, right, by + PX[16], a)
		local line = math.max(1, PX[1])
		local gap = PX[22]
		local colw = math.floor((right - left - gap * 2) / 3)
		local c1, c2, c3 = left, left + colw + gap, left + 2 * (colw + gap)
		local top = by - PX[4]
		rect(c2 - gap / 2, top, c2 - gap / 2 + line, y + h - PX[14], fade(P.LINE, a))
		rect(c3 - gap / 2, top, c3 - gap / 2 + line, y + h - PX[14], fade(P.LINE, a))
		local cy = by + PX[6]
		SM.caption(L("cd_build_start"), nil, c1, cy, a)
		local gold = L("cd_build_gold"):format(build.gold, K.START_GOLD)
		text(W.fonts.regular, PX[10], gold, c1 + colw - tw(W.fonts.regular, PX[10], gold), cy, fade(P.MUTED, a))
		cy = cy + PX[12]
		local sw, sh = PX[36], PX[26]
		local sx = c1
		for n, st in ipairs(build.start) do
			if sx + sw > c1 + colw then
				sx, cy = c1, cy + sh + PX[5]
			end
			SM.item(st.item.name, sx, cy, sw, sh, st.q, a)
			SM.qbuy("cds" .. n, st.item.name, sx, cy, sx + sw, cy + sh, a)
			if tip_at(sx, cy, sx + sw, cy + sh) then
				tip_put("cds" .. n, st.q > 1 and ("%s x%d"):format(st.item.label, st.q) or st.item.label, "")
			end
			sx = sx + sw + PX[5]
		end
		cy = cy + sh + PX[22]
		local more = {}
		for _, lt in ipairs(build.late or {}) do
			more[#more + 1] = lt
		end
		for _, e in ipairs(build.ext or {}) do
			more[#more + 1] = e
		end
		if #more > 0 then
			SM.caption(L(#(build.ext or {}) > 0 and "cd_card_next" or "cd_card_late"), nil, c1, cy, a)
			cy = cy + PX[12]
			local lx = c1
			for n, lt in ipairs(more) do
				if lx + sw > c1 + colw then
					lx, cy = c1, cy + sh + PX[5]
				end
				SM.item(lt.item.name, lx, cy, sw, sh, nil, a)
				SM.qbuy("cdl" .. n, lt.item.name, lx, cy, lx + sw, cy + sh, a)
				local body
				if lt.g40 then
					body = L("cd_tip_late"):format(math.floor(lt.share * 100 + 0.5), lt.g40)
				else
					body = L("cd_tip_ext"):format(math.floor(lt.share * 100 + 0.5))
					if lt.base then
						body = L("cd_tip_up_from"):format(lt.base.label) .. "\n" .. body
					elseif lt.swap then
						body = L("cd_tip_ext_swap"):format(lt.swap.label) .. "\n" .. body
					end
				end
				local sell = build.sells and build.sells[lt]
				if sell then
					SM.sell_badge(sell, lx, cy, sw, sh, a)
					body = body .. "\n" .. SM.sell_line(sell, lt.item.label)
				end
				if tip_at(lx, cy, lx + sw, cy + sh) then
					tip_put("cdl" .. n, lt.item.label, body)
				end
				lx = lx + sw + PX[8]
			end
			cy = cy + sh + PX[20]
		end
		local sp = build.spare
		if sp then
			SM.item(sp.item.name, c1, cy, sw, sh, sp.q, a)
			SM.qbuy("cdsp", sp.item.name, c1, cy, c1 + sw, cy + sh, a)
			local scy = cy + sh / 2
			local stx = c1 + sw + PX[10]
			stx = stx + text(W.fonts.regular, PX[11], L("cd_build_spare"), stx, scy, fade(P.MUTED, a)) + PX[5]
			for _, e in ipairs(sp.vs) do
				local face = mini(e)
				if face and stx + PX[18] < c1 + colw then
					Render.Image(face, Q.v1:Set(stx, math.floor(scy - PX[9])), Q.v2:Set(PX[18], PX[18]), fade(P.WHITE, a))
					stx = stx + PX[20]
				end
			end
		end
		SM.card_side(sm, build, c2, c2 + colw, by + PX[6], a, "skills")
		SM.card_side(sm, build, c3, c3 + colw, by + PX[6], a, "more")
		Render.PopClip()
	end

	function SM.draw(sm, x, y, w, h, a)
		local left, right = x + PX[14], x + w - PX[14]
		local ty = y + PX[20]
		local ta = a * ease((os.clock() - W.step_t) / 0.25)
		local lx = left + text(W.fonts.bold, PX[13], L("cd_sum_t"), left, ty, fade(P.TEXT, ta)) + PX[8]
		if draft.chance then
			vline(lx, ty, PX[7], ta)
			lx = lx + PX[8]
			lx = lx + text(W.fonts.regular, PX[11], L("cd_sum_chance"), lx, ty, fade(P.MUTED, ta)) + PX[6]
			text(W.fonts.bold, PX[12], ("%d%%"):format(math.floor(draft.chance * 100 + 0.5)), lx, ty,
				fade(draft.chance >= 0.5 and P.GOOD or P.BAD, ta))
		end

		local top, bottom = y + PX[34], y + h - PX[8]
		W.list_rect = { x + PX[8], top, x + w - PX[8], bottom }
		local scroll = SB.scroll("list", "list_scroll", W.sum_max or 0)
		Render.PushClip(Q.v1:Set(x, top), Q.v2:Set(x + w, bottom), true)
		W.hit_clip = { top, bottom }
		local now = os.clock()
		local function fade_in(k)
			return a * ease((now - W.list_t0 - k * K.STAGGER) / K.ROW_IN)
		end
		local cxm, cym = Input.GetCursorPos()
		local inside = in_rect(W.list_rect, cxm, cym) and not over_menu(cxm, cym) and not W.drag

		local cy = top + PX[12] - scroll
		SM.caption(L("cd_sum_vs"), L("cd_sum_vs_sub"), left, cy, fade_in(0))
		local gap = PX[3]
		local head_w, sum_w = PX[50], PX[44]
		local cell_w = math.floor((right - left - head_w - sum_w - gap * 6) / 5)
		local pw, ph = PX[44], PX[25]
		local col_x = {}
		for j = 1, 5 do
			col_x[j] = left + head_w + gap + (j - 1) * (cell_w + gap)
		end
		local sum_x = col_x[5] + cell_w + gap
		local hy = cy + PX[11]
		local ha = fade_in(1)
		for j, e in ipairs(sm.them) do
			local img = portrait(e)
			if img then
				Render.Image(img, Q.v1:Set(col_x[j] + math.floor((cell_w - pw) / 2), hy), Q.v2:Set(pw, ph), fade(P.WHITE, ha), PX[4], K.ROUND)
			end
		end
		local total = L("cd_sum_total")
		text(W.fonts.regular, PX[10], total, sum_x + (sum_w - tw(W.fonts.regular, PX[10], total)) / 2, hy + ph / 2,
			fade(P.MUTED, ha))

		local sel = I.hero(sm)
		local row_h = PX[26]
		local ry = hy + ph + PX[5]
		for k, row in ipairs(sm.rows) do
			local ra = fade_in(k + 1)
			local y0 = ry + (k - 1) * (row_h + gap)
			local y1 = y0 + row_h
			local rcy = y0 + row_h / 2
			local hov = inside and cym >= y0 - PX[1] and cym < y1 + PX[2]
			local hv = approach("sm_h" .. row.h, hov and 1 or 0, 20)
			local on = approach("sm_s" .. row.h, (sel and sel.h == row.h) and 1 or 0, 16)
			local bg = math.max(on, hv * 0.6)
			if bg > 0 then
				rect(left - PX[6], y0 - PX[2], right + PX[6], y1 + PX[2], fade(P.HOVER, ra * bg * 1.4), PX[7])
			end
			local iy = y0 + math.floor((row_h - ph) / 2)
			local img = portrait(row.h)
			if img then
				Render.Image(img, Q.v1:Set(left, iy), Q.v2:Set(pw, ph), fade(P.WHITE, ra), PX[4], K.ROUND)
			else
				rect(left, iy, left + pw, iy + ph, fade(P.FIELD, ra), PX[4])
			end
			if row.pos then
				local size = PX[11]
				rect(left + PX[1], iy + ph - size - PX[3], left + size + PX[5], iy + ph - PX[1], fade(P.SHADE, ra * 0.9), PX[3])
				draw_pos(row.pos, left + PX[3], iy + ph - PX[2] - size / 2, size, ra)
			end
			local hero = D.by_id[row.h]
			local name = hero and hero.name or "?"
			for j, v in ipairs(row.v) do
				local c0 = col_x[j]
				local base = v >= 0 and P.GOOD or P.BAD
				local mag = math.min(1, math.abs(v) / 4)
				local cell = mag >= 0.0125 and rgba(base.r, base.g, base.b, math.floor(56 * mag + 0.5)) or P.CELL
				rect(c0, y0, c0 + cell_w, y1, fade(cell, ra), PX[5])
				local str = SM.signed(v)
				text(W.fonts.semi, PX[12], str, c0 + (cell_w - tw(W.fonts.semi, PX[12], str)) / 2, rcy, fade(SM.tone(v), ra))
				local enemy = D.by_id[sm.them[j]]
				if tip_at(c0, y0, c0 + cell_w, y1) then
					tip_put("smc" .. row.h .. ":" .. j, L("cd_tip_cell_t"):format(name, enemy and enemy.name or "?"), L("cd_tip_cell"):format(str))
				end
			end
			local str = SM.signed(row.sum)
			text(W.fonts.bold, PX[12], str, sum_x + (sum_w - tw(W.fonts.bold, PX[12], str)) / 2, rcy, fade(SM.tone(row.sum), ra))
			if tip_at(sum_x, y0, sum_x + sum_w, y1) then
				tip_put("sms" .. row.h, L("cd_tip_sum_t"):format(name), L("cd_tip_sum"))
			end
			hit(left - PX[6], y0 - PX[1], right + PX[6], y1 + PX[1], "sumrow", row.h)
		end
		local by = ry + #sm.rows * (row_h + gap) + PX[8]
		text(W.fonts.regular, PX[10], L("cd_sum_hint"), left, by, fade(P.DIM, fade_in(7)))
		by = by + PX[24]
		if sel then
			local sp = I.bpos[sel.h] or sel.pos
			if sp then
				I.shown_pos[sel.h] = sp
			end
		end
		Render.PopClip()
		W.hit_clip = nil
		W.sum_max = math.max(0, by + scroll - bottom)
		SB.bar("list", x + w - PX[1], top, bottom, scroll, W.sum_max, a)
	end

	local function draw_list_view(x, y, w, h, a)
		local left = x + PX[14]
		local res = draft.result
		if not res and draft.summary then
			SM.draw(draft.summary, x, y, w, h, a)
			return
		end
		local ty = y + PX[20]
		local hk = ease((os.clock() - W.step_t) / 0.25)
		local list_top = y + PX[40]
		if res then
			local key
			if res.acting == 0 then
				key = res.kind == "B" and "ban" or "pick"
			else
				key = res.kind == "B" and "eban" or "epick"
			end
			local title = L("cd_t_" .. key)
			if res.positional and draft.filter > 0 then
				title = L("cd_on"):format(title, L("cd_acc" .. draft.filter))
			end
			if draft.edit then
				title = L("cd_replace")
			end
			local sub = res.context and L("cd_s_" .. key) or L("cd_s_none")
			local lx = left
			local sub_x1 = x + w - PX[14]
			if res.acting == 0 and (res.kind == "P" or res.kind == "B") and #res.rows > 0 then
				local label = L("cd_suggest_top")
				local bw = tw(W.fonts.medium, PX[11], label) + PX[30]
				local bh = PX[22]
				local bx0 = sub_x1 - bw
				local bhv = approach("sug_top", hovered(bx0, ty - bh / 2, sub_x1, ty + bh / 2) and 1 or 0, 20)
				rect(bx0, ty - bh / 2, sub_x1, ty + bh / 2, fade(mix(P.CELL, P.HOVER, bhv), a * hk), PX[6])
				glyph("\u{f0a1}", bx0 + PX[13], ty, PX[10], fade(P.MUTED, a * hk))
				text(W.fonts.medium, PX[11], label, bx0 + PX[23], ty, fade(P.TEXT, a * hk))
				hit(bx0, ty - bh / 2, sub_x1, ty + bh / 2, "suggest_top")
				tip("sug_top", bx0, ty - bh / 2, sub_x1, ty + bh / 2, label, L("cd_tip_suggest_top"))
				sub_x1 = bx0 - PX[8]
			end
			lx = lx + text(W.fonts.bold, PX[13], title, lx, ty, fade(P.TEXT, a * hk), true) + PX[8]
			vline(lx, ty, PX[7], a * hk)
			Render.PushClip(Q.v1:Set(lx + PX[8], ty - PX[10]), Q.v2:Set(sub_x1, ty + PX[10]), true)
			text(W.fonts.regular, PX[11], sub, lx + PX[8], ty, fade(P.MUTED, a * hk), true)
			Render.PopClip()
		elseif not cur_step() then
			text(W.fonts.bold, PX[13], L("cd_done"), left, ty, fade(P.TEXT, a), true)
		end

		local lx0, ly0 = x + PX[8], list_top
		local lx1, ly1 = x + w - PX[8], y + h - PX[8]
		W.list_rect = { lx0, ly0, lx1, ly1 }
		local stage = load_stage()
		local la = approach("loader", (stage and not res) and 1 or 0, 9)
		if la > 0 then
			draw_loader(lx0, y, lx1, ly1, a * la, stage or A.last_stage)
		end
		if stage then
			A.last_stage = stage
		end
		if not res then
			if not stage and not cur_step() then
				local msg = L("cd_done_tip")
				text(W.fonts.regular, PX[12], msg, (lx0 + lx1) / 2 - tw(W.fonts.regular, PX[12], msg) / 2,
					(ly0 + ly1) / 2 - PX[20], fade(P.MUTED, a * (1 - la)), true)
			end
		else
			local rows = res.rows
			if #rows == 0 then
				text(W.fonts.regular, PX[12], L("cd_empty"), left, ly0 + PX[24], fade(P.MUTED, a), true)
			end
			local content = 0
			for _, row in ipairs(rows) do
				content = content + (row.comp and PX[K.ROW_COMP] or PX[K.ROW])
			end
			local lmax = math.max(0, content - (ly1 - ly0))
			local scroll = SB.scroll("list", "list_scroll", lmax)
			Render.PushClip(Q.v1:Set(lx0, ly0), Q.v2:Set(lx1, ly1), true)
			local cxm, cym = Input.GetCursorPos()
			local inside = in_rect(W.list_rect, cxm, cym) and not over_menu(cxm, cym) and not W.drag
			local now = os.clock()
			local ry = ly0 - scroll
			local order = 0
			for _, row in ipairs(rows) do
				local row_h = row.comp and PX[K.ROW_COMP] or PX[K.ROW]
				if ry + row_h >= ly0 and ry <= ly1 then
					local e = ease((now - W.list_t0 - order * K.STAGGER) / K.ROW_IN)
					order = order + 1
					local ra = a * e
					local hov = inside and cym >= ry and cym < ry + row_h
					if hov then
						W.side_hover = { h = row.h, pos = res.positional and row.pos or nil }
					end
					local hv = approach("lh" .. row.h, hov and 1 or 0, 20)
					if order == 1 then
						rect(lx0, ry + PX[1], lx1, ry + row_h - PX[1], fade(P.CELL, ra), PX[9])
					end
					if hv > 0 then
						rect(lx0, ry + PX[1], lx1, ry + row_h - PX[1], fade(P.HOVER, ra * hv), PX[9])
					end
					local top_cy = ry + PX[K.ROW] / 2
					local ix, iw, ih = lx0 + PX[8], PX[58], PX[33]
					local iy = math.floor(top_cy - ih / 2)
					local img = portrait(row.h)
					if img then
						Render.Image(img, Q.v1:Set(ix, iy), Q.v2:Set(iw, ih), fade(P.WHITE, ra), PX[6], K.ROUND)
					else
						rect(ix, iy, ix + iw, iy + ih, fade(P.FIELD, ra), PX[6])
					end
					local nx = ix + iw + PX[11]
					local ny = top_cy - PX[8]
					local hero = D.by_id[row.h]
					local nw = text(W.fonts.bold, PX[13], hero and hero.name or "?", nx, ny, fade(P.TEXT, ra), true)
					if row.pos and res.positional then
						local px0 = nx + nw + PX[6]
						px0 = px0 + draw_pos(row.pos, px0, ny, PX[14], ra) + PX[3]
						text(W.fonts.medium, PX[11], ("%d%%"):format(math.floor(row.share * 100 + 0.5)), px0, ny, fade(P.MUTED, ra), true)
					end
					local val = pct(row.delta)
					local rate = ("%.1f%%"):format(M.base(row.h) * 100)
					local games = fmt_games(M.shown_games(row.h))
					local rx = lx1 - PX[8]
					local sy = top_cy + PX[9]
					local num, num_col, sub_w
					if res.context then
						num = (val >= 0 and "+" or "") .. ("%.1f"):format(val)
						row.num = num
						num_col = val >= 0.05 and P.GOOD or (val <= -0.05 and P.BAD or P.MUTED)
						local games_w = tw(W.fonts.regular, PX[10], games)
						sub_w = tw(W.fonts.regular, PX[10], rate) + games_w + PX[13]
						text(W.fonts.regular, PX[10], games, rx - games_w, sy, fade(P.MUTED, ra), true)
						vline(rx - games_w - PX[7], sy, PX[4], ra)
						text(W.fonts.regular, PX[10], rate, rx - sub_w, sy, fade(P.MUTED, ra), true)
					else
						num, num_col = rate, P.TEXT
						local label = L("cd_matches"):format(games)
						sub_w = tw(W.fonts.regular, PX[10], label)
						text(W.fonts.regular, PX[10], label, rx - sub_w, sy, fade(P.MUTED, ra), true)
					end
					local num_w = tw(W.fonts.bold, PX[15], num)
					text(W.fonts.bold, PX[15], num, rx - num_w, top_cy - PX[7], fade(num_col, ra), true)
					local max_x = rx - math.max(num_w, sub_w) - PX[10]
					local vy0, vy1 = math.max(ry, ly0), math.min(ry + row_h, ly1)
					if vy1 > vy0 then
						if res.context then
							if tip_at(max_x + PX[6], vy0, rx + PX[4], vy1) then
								tip_put("num" .. row.h, L("cd_tip_num_t"):format(num), L("cd_tip_num"):format(rate, games))
							end
						else
							if tip_at(max_x + PX[6], vy0, rx + PX[4], vy1) then
								tip_put("num" .. row.h, L("cd_tip_wr_t"):format(rate), L("cd_tip_wr"):format(games))
							end
						end
					end
					Render.PushClip(Q.v1:Set(nx, ry), Q.v2:Set(max_x, ry + row_h), true)
					draw_reasons(row, nx, top_cy + PX[9], max_x, ra)
					if row.comp then
						draw_comp(row, nx, top_cy + PX[27], max_x, ra)
					end
					Render.PopClip()
					local vy0, vy1 = math.max(ry, ly0), math.min(ry + row_h, ly1)
					if vy1 > vy0 then
						hit(lx0, vy0, lx1, vy1, "row", row.h)
					end
					local sugd = W.suggested(row.h)
					if (hov or sugd) and res.acting == 0 and (res.kind == "P" or res.kind == "B") then
						local label = L(sugd and "cd_suggested" or "cd_suggest")
						local bw = tw(W.fonts.medium, PX[10], label) + PX[26]
						local bh = PX[20]
						local bx0 = max_x - bw
						local shv = approach("sug" .. row.h, hovered(bx0, ny - bh / 2, max_x, ny + bh / 2) and 1 or 0, 20)
						local sbg = sugd and rgba(P.ACC.r, P.ACC.g, P.ACC.b, math.floor(34 + 30 * shv)) or mix(P.FIELD, P.CHIP_ON, shv)
						rect(bx0, ny - bh / 2, max_x, ny + bh / 2, fade(sbg, ra), PX[6])
						glyph(sugd and "\u{f00c}" or "\u{f0a1}", bx0 + PX[11], ny, PX[9], fade(sugd and P.ACC or P.MUTED, ra))
						text(W.fonts.medium, PX[10], label, bx0 + PX[20], ny, fade(sugd and P.ACC or P.TEXT, ra))
						if ny - bh / 2 >= vy0 and ny + bh / 2 <= vy1 then
							hit(bx0, ny - bh / 2, max_x, ny + bh / 2, "suggest", row.h)
							if tip_at(bx0, ny - bh / 2, max_x, ny + bh / 2) then
								tip_put("sug" .. row.h, label, L("cd_tip_suggest"))
							end
						end
					end
				end
				ry = ry + row_h
			end
			Render.PopClip()
			SB.bar("list", x + w - PX[1], ly0, ly1, scroll, lmax, a)
		end

	end

	local function draw_main(x, y, w, h, a)
		local pad = PX[16]
		local fy0 = y + PX[12]
		local fy1 = fy0 + PX[K.SEARCH_H]
		local res = draft.result
		local fx1 = x + w - pad
		local ck = approach("chips_a", (res and res.positional and not W.grid_on and draft.query == "") and 1 or 0, 14)
		if ck > 0.01 and res and res.positional then
			local bw = draw_pos_buttons(res, fx1, (fy0 + fy1) / 2, a * ck)
			fx1 = fx1 - (bw + PX[10]) * ck
		end
		draw_search(x + pad, fy0, fx1, fy1, a)
		local gk = approach("grid_k", (W.grid_on or draft.query ~= "") and 1 or 0, 14)
		local top = fy1 + PX[4]
		local outer = W.nohit
		Render.PushClip(Q.v1:Set(x, top), Q.v2:Set(x + w, y + h), true)
		if gk < 0.99 then
			W.nohit = outer or gk > 0.5
			draw_list_view(x, top, w, y + h - top, a * (1 - gk))
			W.nohit = outer
		else
			W.list_rect = nil
		end
		if gk > 0.01 then
			W.nohit = outer or gk < 0.5
			draw_grid(x + pad, top + PX[8], w - pad * 2 + PX[10], y + h - top - PX[16], a * gk)
			W.nohit = outer
		else
			W.grid_rect = nil
		end
		Render.PopClip()
	end

	local function side_pos(h)
		local all = I.buys[h]
		local best, games = nil, 0
		for p, d in pairs(all and all.pos or {}) do
			if (d.g or 0) > games then
				best, games = p, d.g
			end
		end
		return best
	end

	local function draw_side(x, y, w, h, a)
		local pad = PX[16]
		local left, right = x + pad, x + w - pad
		local sm, res = draft.summary, draft.result
		local hid, pos, in_draft
		local hv = W.side_hover
		W.side_hover = nil
		if hv then
			hid, pos = hv.h, hv.pos
		end
		local es = draft.edit and STEPS()[draft.edit]
		if not hid and es and es.kind == "P" and draft.steps[draft.edit] then
			hid, pos = draft.steps[draft.edit], draft.slot_pos[draft.edit]
		end
		if not hid and sm then
			local r = SM.my_row(sm)
			if r then
				hid, pos = r.h, I.bpos[r.h] or r.pos
			end
		end
		if not hid and res and res.rows[1] then
			hid, pos = res.rows[1].h, res.positional and res.rows[1].pos or nil
		end
		if not hid then
			text(W.fonts.semi, PX[12], L("cd_side_empty"), left, y + PX[24], fade(P.MUTED, a))
			return
		end
		for _, r in ipairs(sm and sm.rows or {}) do
			if r.h == hid then
				in_draft = true
				pos = pos or I.bpos[r.h] or r.pos
			end
		end
		local foe = 0
		for _, e in ipairs(picks(1)) do
			if e == hid then
				foe = 1
			end
		end
		I.want_preview = hid
		pos = pos or (foe == 1 and (draft.enemy_pos or {})[hid]) or (foe == 0 and draft.filter > 0 and draft.filter or nil)
			or side_pos(hid)
		local them, mates = {}, {}
		for _, e in ipairs(picks(1 - foe)) do
			them[#them + 1] = e
		end
		for _, m in ipairs(picks(foe)) do
			if m ~= hid then
				mates[#mates + 1] = m
			end
		end
		table.sort(them)
		table.sort(mates)
		local build = pos and I.build(hid, pos, them, mates)
		W.item_h = hid
		local hero = D.by_id[hid]
		local cy = y + PX[28]
		local iw, ih = PX[56], PX[32]
		local img = portrait(hid)
		if img then
			Render.Image(img, Q.v1:Set(left, cy - ih / 2), Q.v2:Set(iw, ih), fade(P.WHITE, a), PX[6], K.ROUND)
		end
		local tx = left + iw + PX[10]
		Render.PushClip(Q.v1:Set(tx, cy - PX[16]), Q.v2:Set(right, cy + PX[16]), true)
		text(W.fonts.bold, PX[13], hero and hero.name or "?", tx, cy - PX[7], fade(P.TEXT, a))
		local data = pos and I.buys[hid] and I.buys[hid].pos[pos]
		local sub = pos and (data and L("cd_side_sub"):format(pos, math.floor(data.g + 0.5)) or L("cd_side_pos"):format(pos)) or ""
		text(W.fonts.regular, PX[11], sub, tx, cy + PX[9], fade(P.MUTED, a))
		Render.PopClip()
		local by = cy + PX[30]
		if not build or build.none or #build.slots == 0 then
			local msg, spin
			if build and build.none then
				msg = L("cd_build_nopos"):format(pos and L("cd_acc" .. pos) or "?")
			elseif build then
				msg = L("cd_build_none")
			else
				msg, spin = L("cd_build_loading"), true
			end
			local mx = left
			if spin then
				spinner(left + PX[6], by + PX[8], PX[5], a, P.MUTED, math.max(1, PX[1.5]))
				mx = left + PX[18]
			end
			Render.PushClip(Q.v1:Set(left, by), Q.v2:Set(right, by + PX[20]), true)
			text(W.fonts.regular, PX[11], msg, mx, by + PX[8], fade(P.MUTED, a))
			Render.PopClip()
			return
		end
		local function caption(key)
			text(W.fonts.semi, PX[11], L(key), left, by + PX[6], fade(P.MUTED, a))
			by = by + PX[18]
		end
		caption("cd_side_core")
		local n = math.min(6, #build.slots)
		local gap = PX[5]
		local cw = math.floor((right - left - gap * 5) / 6)
		local ch = math.floor(cw * 0.73 + 0.5)
		for k = 1, n do
			local cd = build.slots[k]
			local ix = left + (k - 1) * (cw + gap)
			SM.item(cd.item.name, ix, by, cw, ch, nil, a)
			SM.qbuy("sd" .. k, cd.item.name, ix, by, ix + cw, by + ch, a)
			if tip_at(ix, by, ix + cw, by + ch) then
				tip_put("sd" .. k, cd.item.label, "")
			end
			local m = tostring(math.floor((cd.t or 0) * (G.tk or 1) / 60 + 0.5))
			text(W.fonts.regular, PX[10], m, ix + cw / 2 - tw(W.fonts.regular, PX[10], m) / 2, by + ch + PX[8], fade(P.DIM, a))
		end
		by = by + ch + PX[24]
		local vs = {}
		for _, v in ipairs(build.vs or {}) do
			if v.item and math.abs(math.log(v.k)) >= math.log(1.3) and #vs < 4 then
				vs[#vs + 1] = v
			end
		end
		if #vs > 0 then
			caption("cd_side_vs")
			for _, v in ipairs(vs) do
				local rcy = by + PX[11]
				SM.item(v.item.name, left, rcy - PX[9], PX[26], PX[19], nil, a)
				local more = v.k > 1
				local num = (more and "x%.1f" or "x%.2f"):format(v.k)
				local nw = tw(W.fonts.bold, PX[12], num)
				text(W.fonts.bold, PX[12], num, right - nw, rcy, fade(more and P.GOOD or P.BAD, a))
				local face = v.e and mini(v.e)
				local fx = right - nw - PX[24]
				if face then
					Render.Image(face, Q.v1:Set(fx, rcy - PX[9]), Q.v2:Set(PX[18], PX[18]), fade(P.WHITE, a * (v.ally and 0.6 or 1)))
				end
				Render.PushClip(Q.v1:Set(left + PX[32], by), Q.v2:Set(fx - PX[6], by + PX[22]), true)
				text(W.fonts.regular, PX[11], v.item.label, left + PX[34], rcy, fade(P.TEXT, a))
				Render.PopClip()
				if tip_at(left, by, right, by + PX[22]) then
					tip_put("sv" .. v.item.name, v.item.label, L(more and "cd_tip_lm_more" or "cd_tip_lm_less"):format(more and v.k or 1 / v.k, (v.e and D.by_id[v.e] and D.by_id[v.e].name or "?")))
				end
				by = by + PX[24]
			end
			by = by + PX[8]
		end
		if build.skills and #build.skills > 0 then
			caption("cd_side_skills")
			local ks, kg = PX[20], PX[3]
			local per = math.max(1, math.floor((right - left + kg) / (ks + kg)))
			for k, sk in ipairs(build.skills) do
				if k > per * 2 then
					break
				end
				local kx = left + ((k - 1) % per) * (ks + kg)
				local ky = by + ((k - 1) // per) * (ks + kg)
				if sk.attr or sk.talent then
					rect(kx, ky, kx + ks, ky + ks, fade(P.FIELD, a), PX[4])
					glyph(sk.attr and "\u{f067}" or "\u{f005}", kx + ks / 2, ky + ks / 2, math.floor(ks * 0.5), fade(sk.attr and P.GOOD or P.WARN, a))
				else
					local si = Q.asset("spellicons/", sk.name)
					if si then
						Render.Image(si, Q.v1:Set(kx, ky), Q.v2:Set(ks, ks), fade(P.WHITE, a), PX[4], K.ROUND)
					else
						rect(kx, ky, kx + ks, ky + ks, fade(P.FIELD, a), PX[4])
					end
				end
			end
			by = by + (ks + kg) * math.min(2, math.ceil(#build.skills / per)) + PX[10]
		end
		if in_draft then
			local label = L("cd_side_open")
			local bh = PX[30]
			local y1 = y + h - pad
			local y0 = y1 - bh
			local bhv = approach("side_open", hovered(left, y0, right, y1) and 1 or 0, 20)
			rect(left, y0, right, y1, fade(mix(P.FIELD, P.CHIP_ON, bhv), a), PX[8])
			local lw = tw(W.fonts.semi, PX[12], label)
			text(W.fonts.semi, PX[12], label, (left + right) / 2 - lw / 2, (y0 + y1) / 2, fade(P.TEXT, a))
			hit(left, y0, right, y1, "card_hero", hid)
		end
	end

	local PN = {}

	PN.DEMO = {
		hero = 48,
		gold = 1300,
		pos = 1,
		slots = {
			{ name = "power_treads", label = "Power Treads", state = "done", t = 346, cost = 1400 },
			{ name = "mask_of_madness", label = "Mask of Madness", state = "done", t = 608, cost = 1900 },
			{ name = "manta", label = "Manta Style", state = "next", t = 1028, cost = 4650, have = 2100 },
			{ name = "black_king_bar", label = "Black King Bar", state = "later", t = 1559, cost = 4050 },
			{ name = "butterfly", label = "Butterfly", state = "later", t = 1598, cost = 5450 },
			{ name = "monkey_king_bar", label = "Monkey King Bar", state = "later", t = 1880, cost = 5000,
				reason = 44, counter = { "Phantom Assassin", "evasion" } },
			{ name = "satanic", label = "Satanic", state = "later", t = 2084, cost = 5050,
				base = { name = "mask_of_madness", label = "Mask of Madness" }, kind = "dis" },
		},
		start = {
			gold = 565,
			items = {
				{ name = "branches", label = "Iron Branch", cost = 55, q = 2, state = "done" },
				{ name = "quelling_blade", label = "Quelling Blade", cost = 100, q = 1, state = "done" },
				{ name = "magic_stick", label = "Magic Stick", cost = 200, q = 1, state = "done" },
				{ name = "tango", label = "Tango", cost = 90, q = 1, state = "done" },
				{ name = "faerie_fire", label = "Faerie Fire", cost = 65, q = 1, state = "done" },
			},
		},
	}
	PN.DEMO.next = PN.DEMO.slots[3]
	PN.NONE = { hero = 48, pos = 3, none = true, slots = {} }

	function PN.demo()
		local D0 = PN.DEMO
		if not D0.ready then
			D0.ready = true
			for _, d in ipairs(D0.slots) do
				local lines = {}
				if d.counter then
					lines[1] = L("cd_tip_item_vs"):format(d.counter[1])
					lines[2] = L("cd_th_" .. d.counter[2])
				end
				if d.base then
					lines[#lines + 1] = L(d.kind == "up" and "cd_tip_up_from" or "cd_tip_dis_from"):format(d.base.label)
				end
				d.body = table.concat(lines, "\n")
			end
			for _, d in ipairs(D0.start.items) do
				d.title = d.q > 1 and ("%s x%d"):format(d.label, d.q) or d.label
			end
		end
		local chosen = I.bpos[D0.hero]
		if chosen and chosen ~= 1 then
			PN.NONE.pos = chosen
			return PN.NONE
		end
		return D0
	end

	function PN.item_img(name)
		return Q.asset("items/", name)
	end

	function PN.slot(d, x, y, w, h, a)
		local img = PN.item_img(d.name)
		if img then
			Render.Image(img, Q.v1:Set(x, y), Q.v2:Set(w, h), fade(P.WHITE, a), PX[4], K.ROUND)
		else
			rect(x, y, x + w, y + h, fade(P.FIELD, a), PX[4])
		end
		if d.q and d.q > 1 then
			local label = tostring(d.q)
			local lw = tw(W.fonts.bold, PX[9], label) + PX[6]
			rect(x + PX[1], y + h - PX[12], x + PX[1] + lw, y + h - PX[1], fade(P.SHADE, a), PX[3])
			text(W.fonts.bold, PX[9], label, x + PX[4], y + h - PX[6.5], fade(P.TEXT, a))
		end
		local ring = math.max(2, PX[2])
		if d.reason then
			local bs = math.max(PX[15], math.floor(h * 0.62 + 0.5))
			local bx, by = x + w - bs + PX[6], y - PX[6]
			rect(bx - ring, by - ring, bx + bs + ring, by + bs + ring, fade(P.BG, a), PX[5])
			local face = mini(d.reason)
			if face then
				Render.Image(face, Q.v1:Set(bx, by), Q.v2:Set(bs, bs), fade(P.WHITE, a))
			end
		elseif d.base then
			local bw = math.max(PX[16], math.floor(w * 0.56 + 0.5))
			local bh = math.floor(bw * 0.73 + 0.5)
			local bx, by = x + w - bw + PX[6], y - PX[6]
			rect(bx - ring, by - ring, bx + bw + ring, by + bh + ring, fade(P.BG, a), PX[5])
			local src = PN.item_img(d.base.name)
			if src then
				Render.Image(src, Q.v1:Set(bx, by), Q.v2:Set(bw, bh), fade(P.WHITE, a), PX[3], K.ROUND)
			end
		end
		if d.sell then
			SM.sell_badge(d.sell, x, y, w, h, a)
		end
	end

	function PN.qbuy(plan, id, name, x0, y0, x1, y1, a, r)
		if plan ~= PN.DEMO and plan ~= PN.NONE then
			W.item_h = plan.hero
			SM.qbuy("p" .. id, name, x0, y0, x1, y1, a, r)
		end
	end

	function PN.need(plan, d)
		local gold = plan == PN.DEMO and PN.DEMO.gold or G.gold
		local need = math.max(0, (d.cost or 0) - (d.have or 0))
		local k = tween("pn_prog", (d.cost or 0) > 0 and ((d.have or 0) + math.min(gold, need)) / d.cost or 0, 0.4)
		if gold >= need then
			return L("cd_p_enough"), P.GOOD, k
		end
		return L("cd_p_more"):format(need - gold), P.MUTED, k
	end

	function PN.bar(x0, x1, cy, k, a)
		local bh = math.max(2, PX[3])
		local y0 = math.floor(cy - bh / 2)
		rect(x0, y0, x1, y0 + bh, fade(rgba(214, 236, 255, 26), a), bh / 2)
		if k > 0 then
			grad(x0, y0, x0 + (x1 - x0) * clamp(k, 0, 1), y0 + bh, fade(P.ACC_A, a), fade(P.ACC_B, a), bh / 2)
		end
	end

	function PN.back(x, y, w, h, a, r)
		r = r or PX[12]
		if cfg.blur == 1 then
			local strength = clamp((a - 0.5) / 0.5, 0, 1)
			if strength > 0.01 then
				Render.Blur(Q.v1:Set(x, y), Q.v2:Set(x + w, y + h), strength, 1.0, r, K.ROUND)
			end
		end
		rect(x, y, x + w, y + h, fade(rgba(P.BG.r, P.BG.g, P.BG.b, math.floor(255 * cfg.bg / 100 + 0.5)), a), r)
	end

	function PN.head(plan, x, y, w, a)
		local hy = y + PX[20]
		local lx = x + PX[12]
		local face = mini(plan.hero)
		if face then
			Render.Image(face, Q.v1:Set(lx, hy - PX[10]), Q.v2:Set(PX[20], PX[20]), fade(P.WHITE, a))
			lx = lx + PX[26]
		end
		lx = lx + text(W.fonts.bold, PX[12], L("cd_p_title"), lx, hy, fade(P.TEXT, a)) + PX[8]
		local hero = D.by_id[plan.hero]
		if hero then
			vline(lx, hy, PX[6], a)
			text(W.fonts.regular, PX[11], hero.name, lx + PX[8], hy, fade(P.MUTED, a))
		end
		if plan == PN.DEMO or plan == PN.NONE then
			local tag = L("cd_p_preview")
			text(W.fonts.regular, PX[10], tag, x + w - PX[12] - tw(W.fonts.regular, PX[10], tag), hy, fade(P.DIM, a))
		elseif plan.state then
			local amount = ("%.1fk"):format(math.abs(plan.state.diff) / 1000)
			local tag = L(plan.state.behind and "cd_state_behind" or "cd_state_ahead"):format(amount)
			text(W.fonts.medium, PX[10], tag, x + w - PX[12] - tw(W.fonts.medium, PX[10], tag), hy,
				fade(plan.state.behind and P.BAD or P.GOOD, a))
		elseif plan.since or plan.pooled then
			local tag = plan.pooled and I.pool_note(plan.pooled, true) or L("cd_p_since"):format(plan.since)
			text(W.fonts.regular, PX[10], tag, x + w - PX[12] - tw(W.fonts.regular, PX[10], tag), hy, fade(P.DIM, a))
		end
		hit(x, y, x + w, y + PX[34], "pdrag")
	end

	function PN.warn(plan, x, cy, w, a, str)
		glyph("\u{f071}", x + PX[6], cy, PX[10], fade(P.WARN, a))
		Render.PushClip(Q.v1:Set(x + PX[16], cy - PX[9]), Q.v2:Set(x + w, cy + PX[9]), true)
		text(W.fonts.medium, PX[11], str or plan.warn, x + PX[18], cy, fade(P.WARN, a))
		Render.PopClip()
	end

	function PN.roles_w(size)
		return 5 * size + 4 * PX[4]
	end

	function PN.roles(plan, x, cy, size, a)
		local gap = PX[4]
		local hero = plan.hero
		local demo = plan == PN.DEMO or plan == PN.NONE
		local have = demo and not I.buys[hero] and { [1] = 400 } or I.positions(hero)
		local loaded = demo or I.buys[hero] ~= nil
		for p = 1, 5 do
			local bx = x + (p - 1) * (size + gap)
			local on = plan.pos == p
			local avail = not loaded or have[p] ~= nil
			local hv = approach("pr" .. p, hovered(bx, cy - size / 2, bx + size, cy + size / 2) and 1 or 0, 20)
			rect(bx, cy - size / 2, bx + size, cy + size / 2, fade(on and P.CHIP_ON or mix(P.CELL, P.HOVER, hv), a), PX[6])
			local icon = math.floor(size * 0.64 + 0.5)
			draw_pos(p, bx + (size - icon) / 2, cy, icon, a * ((avail or on) and 1 or 0.35))
			hit(bx, cy - size / 2, bx + size, cy + size / 2, "bpos", Q.harg("h", hero, "p", p))
			local body = have[p] and I.pos_tip(hero, p) or (avail and "" or L("cd_tip_bpos_none"))
			if tip_at(bx, cy - size / 2, bx + size, cy + size / 2) then
				tip_put("pr" .. p, L("cd_posT" .. p), body, p)
			end
		end
		return PN.roles_w(size)
	end

	function PN.start_fit(plan, avail, max_w)
		local n = plan.start and #plan.start.items or 0
		if n == 0 then
			return 0, 0
		end
		local gap = PX[3]
		local iw = math.min(max_w, math.floor((avail - gap * (n - 1)) / n))
		return iw, math.floor(iw * 0.72 + 0.5)
	end

	function PN.start(plan, x, cy, w, a)
		local st = plan.start
		if not st then
			return
		end
		local label = L("cd_p_start")
		local lw = text(W.fonts.medium, PX[11], label, x, cy, fade(P.MUTED, a))
		local gold = ("%d / %d"):format(st.gold, K.START_GOLD)
		local gw = tw(W.fonts.regular, PX[11], gold)
		text(W.fonts.regular, PX[11], gold, x + w - gw, cy, fade(P.DIM, a))
		local ix0 = x + lw + PX[10]
		local iw, ih = PN.start_fit(plan, w - lw - gw - PX[20], PX[30])
		for i, d in ipairs(st.items) do
			local sx = ix0 + (i - 1) * (iw + PX[3])
			PN.slot(d, sx, math.floor(cy - ih / 2), iw, ih, a)
			PN.qbuy(plan, "st" .. i, d.name, sx, math.floor(cy - ih / 2), sx + iw, math.floor(cy - ih / 2) + ih, a)
			if tip_at(sx, cy - ih / 2, sx + iw, cy + ih / 2) then
				tip_put("pst" .. i, d.title or d.label, "")
			end
		end
	end

	function PN.none(plan, x, y, a, measure)
		local w, h = PX[300], PX[118]
		if measure then
			return w, h
		end
		PN.back(x, y, w, h, a)
		PN.head(plan, x, y, w, a)
		if plan.wait then
			local err = I.error and not I.busy
			text(W.fonts.medium, PX[12], L(err and "cd_ld_error" or "cd_build_loading"), x + PX[12], y + PX[46],
				fade(err and P.WARN or P.TEXT, a))
			text(W.fonts.regular, PX[10], L(err and "cd_p_retry" or "cd_p_wait"), x + PX[12], y + PX[64], fade(P.DIM, a))
			return
		end
		local pl = plan.pos and L("cd_acc" .. plan.pos) or "?"
		text(W.fonts.medium, PX[12], L("cd_build_nopos"):format(pl), x + PX[12], y + PX[46], fade(P.TEXT, a))
		text(W.fonts.regular, PX[10], L("cd_build_nopos2"), x + PX[12], y + PX[64], fade(P.DIM, a))
		PN.roles(plan, x + PX[12], y + h - PX[22], PX[24], a)
	end

	function PN.strip(plan, x, y, a, measure)
		local pad, sw, gap = PX[12], PX[50], PX[6]
		local w = pad * 2 + 6 * sw + 5 * gap
		local rows = math.max(1, math.ceil(#plan.slots / K.STRIP_COLS))
		local cols = math.max(6, math.ceil(#plan.slots / rows))
		local iw = math.min(sw, math.floor((w - pad * 2 - gap * (cols - 1)) / cols))
		local ih = math.floor(iw * 0.74 + 0.5)
		local row_h = ih + PX[10]
		local sh = rows * row_h - PX[10]
		local has_start = plan.start ~= nil
		local wh = plan.warn and PX[20] or 0
		local top = y + PX[34] + wh + (has_start and PX[30] or 0)
		local h = top - y + sh + PX[26] + PX[36]
		if measure then
			return w, h
		end
		PN.back(x, y, w, h, a)
		PN.head(plan, x, y, w, a)
		if plan.warn then
			PN.warn(plan, x + pad, y + PX[42], w - pad * 2, a)
		end
		if has_start then
			PN.start(plan, x + pad, y + PX[48] + wh, w - pad * 2, a)
		end
		local sy = top + PX[4]
		for i, d in ipairs(plan.slots) do
			local sx = x + pad + ((i - 1) % cols) * (iw + gap)
			local iy = sy + ((i - 1) // cols) * row_h
			PN.slot(d, sx, iy, iw, ih, a)
			PN.qbuy(plan, "n" .. i, d.name, sx, iy, sx + iw, iy + ih, a)
			if tip_at(sx, iy, sx + iw, iy + ih) then
				tip_put("pn" .. i, d.label, d.body)
			end
		end
		local ny = sy + sh + PX[15]
		local d = plan.next
		if d then
			local lx = x + pad + text(W.fonts.medium, PX[11], d.label, x + pad, ny, fade(P.TEXT, a)) + PX[10]
			local str, col, k = PN.need(plan, d)
			local rw = tw(W.fonts.regular, PX[11], str)
			text(W.fonts.regular, PX[11], str, x + w - pad - rw, ny, fade(col, a))
			PN.bar(lx, x + w - pad - rw - PX[10], ny, k, a)
		else
			text(W.fonts.medium, PX[11], L("cd_p_all"), x + pad, ny, fade(P.MUTED, a))
		end
		PN.roles(plan, x + pad, y + h - PX[20], PX[24], a)
	end

	function PN.head2(plan, x, y, w, a)
		local hy = y + PX[18]
		local lx = x + PX[12]
		local face = mini(plan.hero)
		if face then
			Render.Image(face, Q.v1:Set(lx, hy - PX[10]), Q.v2:Set(PX[20], PX[20]), fade(P.WHITE, a), PX[3], K.ROUND)
			lx = lx + PX[27]
		end
		local hero = D.by_id[plan.hero]
		lx = lx + text(W.fonts.bold, PX[12], hero and hero.name or L("cd_p_title"), lx, hy, fade(P.TEXT, a)) + PX[8]
		if plan.pos then
			vline(lx, hy, PX[6], a)
			text(W.fonts.regular, PX[11], L("cd_posT" .. plan.pos), lx + PX[8], hy, fade(P.MUTED, a))
		end
		local rx = x + w - PX[12]
		if plan == PN.DEMO or plan == PN.NONE then
			local tag = L("cd_p_preview")
			text(W.fonts.regular, PX[10], tag, rx - tw(W.fonts.regular, PX[10], tag), hy, fade(P.DIM, a))
		elseif plan.solo then
			local four = plan.solo == "4v5"
			local tag = L(four and "cd_state_4v5" or "cd_state_solo")
			local tw0 = tw(W.fonts.bold, PX[11], tag)
			text(W.fonts.bold, PX[11], tag, rx - tw0, hy, fade(P.WARN, a))
			local body = L(four and "cd_tip_state_4v5" or "cd_tip_state_solo")
			if plan.state then
				local amount = ("%.1fk"):format(math.abs(plan.state.diff) / 1000)
				body = body .. "\n" .. L(plan.state.behind and "cd_state_behind" or "cd_state_ahead"):format(amount)
			end
			tip("pstate", rx - tw0 - PX[4], hy - PX[9], rx + PX[4], hy + PX[9], tag, body)
		elseif plan.state then
			local amount = ("%.1fk"):format(math.abs(plan.state.diff) / 1000)
			local tag = (plan.state.behind and "-" or "+") .. amount
			local tw0 = tw(W.fonts.bold, PX[11], tag)
			text(W.fonts.bold, PX[11], tag, rx - tw0, hy, fade(plan.state.behind and P.BAD or P.GOOD, a))
			local lab = L("cd_state_short")
			local lw = tw(W.fonts.regular, PX[10], lab)
			text(W.fonts.regular, PX[10], lab, rx - tw0 - PX[5] - lw, hy, fade(P.DIM, a))
			if tip_at(rx - tw0 - lw - PX[9], hy - PX[9], rx + PX[4], hy + PX[9]) then
				tip_put("pstate", L(plan.state.behind and "cd_state_behind" or "cd_state_ahead"):format(amount), L("cd_state_tip"):format(plan.state.us / 1000, plan.state.them / 1000) .. L(plan.state.behind and "cd_state_tip_behind" or "cd_state_tip_ahead"))
			end
		elseif plan.since or plan.pooled then
			local tag = plan.pooled and I.pool_note(plan.pooled, true) or L("cd_p_since"):format(plan.since)
			text(W.fonts.regular, PX[10], tag, rx - tw(W.fonts.regular, PX[10], tag), hy, fade(P.DIM, a))
		end
		hit(x, y, x + w, y + PX[36], "pdrag")
	end

	function PN.danger(dg, x, y, w, a)
		local hero = D.by_id[dg.e]
		local lx = x
		local face = mini(dg.e)
		if face then
			Render.Image(face, Q.v1:Set(lx, math.floor(y - PX[7])), Q.v2:Set(PX[14], PX[14]), fade(P.WHITE, a))
			lx = lx + PX[19]
		end
		local str = L("cd_danger"):format(hero and hero.name or "?", dg.k or 0, dg.d or 0)
		if dg.kind then
			str = str .. " · " .. L(dg.kind == "phys" and "cd_danger_att" or "cd_danger_spell")
		end
		Render.PushClip(Q.v1:Set(x, y - PX[9]), Q.v2:Set(x + w, y + PX[9]), true)
		text(W.fonts.regular, PX[11], str, lx, y, fade(P.MUTED, a))
		Render.PopClip()
		local dmg = dg.ds and ("%d%%"):format(math.floor(dg.ds * 100 + 0.5)) or "-"
		if tip_at(x, y - PX[9], x + w, y + PX[9]) then
			tip_put("pdanger", L("cd_danger_tip_t"), L("cd_danger_tip"):format(math.floor((dg.ks or 0) * 100 + 0.5), dmg, dg.w or 1))
		end
	end

	function PN.lane(ln, x, y, w, a)
		glyph("\u{f018}", x + PX[7], y, PX[10], fade(P.MUTED, a))
		local names = {}
		for _, id in ipairs(ln.opp) do
			names[#names + 1] = D.by_id[id] and D.by_id[id].name or tostring(id)
		end
		local res = ln.result == "unknown" and L("cd_lane_unknown")
			or ln.result == "lost" and L("cd_lane_lost"):format(ln.diff)
			or (ln.result == "won" and L("cd_lane_won"):format(ln.diff) or L("cd_lane_even"):format(ln.diff))
		local col = ln.result == "lost" and P.BAD or (ln.result == "won" and P.GOOD or P.MUTED)
		Render.PushClip(Q.v1:Set(x, y - PX[9]), Q.v2:Set(x + w, y + PX[9]), true)
		text(W.fonts.regular, PX[11], L("cd_lane_line"):format(table.concat(names, ", "), res), x + PX[19], y, fade(col, a))
		Render.PopClip()
		tip("plane", x, y - PX[9], x + w, y + PX[9], L("cd_lane_tip_t"), L("cd_lane_tip"))
	end

	function PN.foes(fs, x, y, w, a)
		glyph("\u{f3ed}", x + PX[7], y, PX[10], fade(P.MUTED, a))
		local str = L("cd_foe_line"):format(math.floor(fs.phys * 100 + 0.5), math.floor(fs.mag * 100 + 0.5), math.floor(fs.hp + 0.5))
		if fs.eva >= 0.1 and fs.eva_h then
			local hero = D.by_id[fs.eva_h]
			str = str .. L("cd_foe_eva"):format(math.floor(fs.eva * 100 + 0.5), hero and hero.name or "?")
		end
		Render.PushClip(Q.v1:Set(x, y - PX[9]), Q.v2:Set(x + w, y + PX[9]), true)
		text(W.fonts.regular, PX[11], str, x + PX[19], y, fade(P.MUTED, a))
		Render.PopClip()
		tip("pfoes", x, y - PX[9], x + w, y + PX[9], L("cd_foe_tip_t"), L("cd_foe_tip"))
	end

	function PN.replace(rp, x, y, w, a)
		glyph("\u{f362}", x + PX[7], y, PX[10], fade(P.WARN, a))
		local str = L("cd_rep"):format(rp.old.label, rp.new.label)
		Render.PushClip(Q.v1:Set(x, y - PX[9]), Q.v2:Set(x + w, y + PX[9]), true)
		text(W.fonts.medium, PX[11], str, x + PX[19], y, fade(P.TEXT, a))
		Render.PopClip()
		local who = rp.e and D.by_id[rp.e]
		local it = rp.item and I.by_name[rp.item]
		local why
		if rp.team then
			why = L("cd_rep_why_team"):format(who and who.name or "?", it and it.label or rp.old.label)
		elseif rp.mx then
			why = L("cd_rep_why_mx"):format(rp.old.label, rp.mx * 100, rp.mx_why or "-")
		else
			why = L("cd_rep_why_enemy"):format(who and who.name or "?", it and it.label or tostring(rp.item), rp.old.label)
		end
		local body = why .. "\n" .. L("cd_rep_do"):format(rp.old.label, rp.new.label)
		if cfg.autobuy == 1 and cfg.abuy_swap == 1 then
			body = body .. "\n" .. L("cd_rep_auto")
		end
		tip("prep", x, y - PX[9], x + w, y + PX[9], L("cd_rep_tip_t"), body)
	end

	function PN.card(plan, x, y, a, measure)
		local w, pad = PX[300], PX[12]
		local d = plan.next
		local queue, done = {}, {}
		for _, sl in ipairs(plan.slots) do
			if sl.state == "done" then
				done[#done + 1] = sl
			elseif sl ~= d then
				queue[#queue + 1] = sl
			end
		end
		local qw, qh, qg = PX[42], PX[31], PX[6]
		local per = math.max(1, math.floor((w - pad * 2 + qg) / (qw + qg)))
		local qrows = math.ceil(#queue / per)
		local dw, dh, dg = PX[26], PX[19], PX[4]
		local dper = math.max(1, math.floor((w - pad * 2 + dg) / (dw + dg)))
		local drows = math.ceil(#done / dper)
		local start = plan.start and not plan.start.done
		local head_h = PX[36]
		local danger_h = plan.danger and PX[22] or 0
		local rep_h = plan.replace and PX[22] or 0
		local real = plan ~= PN.DEMO and plan ~= PN.NONE and G.live and cfg.live == 1
		local lane = real and G.lane or nil
		local foes = real and G.foe_sum or nil
		local lane_h = lane and PX[22] or 0
		local foe_h = foes and PX[22] or 0
		danger_h = danger_h + lane_h + foe_h
		local warn_h = plan.warn and (plan.warn2 and PX[52] or PX[34]) or 0
		local start_h = start and PX[34] or 0
		local next_h = PX[66]
		local queue_h = #queue > 0 and PX[22] + qrows * (qh + PX[20]) or 0
		local done_h = #done > 0 and PX[22] + drows * (dh + dg) or 0
		local foot_h = PX[40]
		local h = head_h + danger_h + rep_h + warn_h + start_h + next_h + queue_h + done_h + foot_h
		if measure then
			return w, h
		end
		PN.back(x, y, w, h, a)
		PN.head2(plan, x, y, w, a)
		local cy = y + head_h
		if plan.danger then
			PN.danger(plan.danger, x + pad, cy + PX[7], w - pad * 2, a)
			cy = cy + PX[22]
		end
		if lane then
			PN.lane(lane, x + pad, cy + PX[7], w - pad * 2, a)
			cy = cy + lane_h
		end
		if foes then
			PN.foes(foes, x + pad, cy + PX[7], w - pad * 2, a)
			cy = cy + foe_h
		end
		if plan.replace then
			PN.replace(plan.replace, x + pad, cy + PX[7], w - pad * 2, a)
			cy = cy + rep_h
		end
		if plan.warn then
			rect(x + PX[8], cy, x + w - PX[8], cy + warn_h - PX[8], fade(rgba(P.WARN.r, P.WARN.g, P.WARN.b, 26), a), PX[8])
			PN.warn(plan, x + PX[10], cy + PX[13], w - PX[28], a)
			if plan.warn2 then
				PN.warn(plan, x + PX[10], cy + PX[31], w - PX[28], a, plan.warn2)
			end
			cy = cy + warn_h
		end
		if start then
			PN.start(plan, x + pad, cy + PX[14], w - pad * 2, a)
			cy = cy + start_h
		end
		local bx0, by0, bx1, by1 = x + PX[8], cy, x + w - PX[8], cy + next_h - PX[8]
		rect(bx0, by0, bx1, by1, fade(rgba(255, 255, 255, 12), a), PX[10])
		if d then
			PN.qbuy(plan, "cn", d.name, bx0, by0, bx1, by1, a, PX[10])
			local iw, ih = PX[56], PX[41]
			local ix, iy = bx0 + PX[8], math.floor((by0 + by1 - ih) / 2)
			PN.slot(d, ix, iy, iw, ih, a)
			local tx, rx = ix + iw + PX[10], bx1 - PX[10]
			local t1, t2, t3 = by0 + PX[14], by0 + PX[30], by0 + PX[46]
			local when = (d.t and d.t > 0) and L("cd_p_by"):format(math.floor(d.t * (G.tk or 1) / 60 + 0.5)) or ""
			local late = plan ~= PN.DEMO and d.t and G.ptime and G.ptime > d.t + K.LATE_GRACE
			local ww = when ~= "" and tw(W.fonts.regular, PX[11], when) or 0
			if ww > 0 then
				text(W.fonts.regular, PX[11], when, rx - ww, t1, fade(late and P.WARN or P.MUTED, a))
			end
			Render.PushClip(Q.v1:Set(tx, by0), Q.v2:Set(rx - ww - PX[6], by1), true)
			text(W.fonts.bold, PX[13], d.label, tx, t1, fade(P.TEXT, a))
			Render.PopClip()
			local sub
			if d.from then
				sub = L("cd_p_instead"):format(d.from)
			elseif d.base then
				sub = L(d.kind == "up" and "cd_p_up" or "cd_p_dis"):format(d.base.label)
			else
				sub = L("cd_p_have"):format(math.floor(d.have or 0), d.cost or 0)
			end
			if d.mx then
				sub = sub .. " · " .. L("cd_mx_short"):format(d.mx * 100)
			end
			Render.PushClip(Q.v1:Set(tx, by0), Q.v2:Set(rx, by1), true)
			local sw = text(W.fonts.regular, PX[11], sub, tx, t2, fade(P.MUTED, a))
			local face = d.from and d.reason and mini(d.reason)
			if face then
				Render.Image(face, Q.v1:Set(tx + sw + PX[5], math.floor(t2 - PX[7])), Q.v2:Set(PX[14], PX[14]), fade(P.WHITE, a))
			end
			Render.PopClip()
			local str, col, k = PN.need(plan, d)
			local nw = tw(W.fonts.bold, PX[11], str)
			text(W.fonts.bold, PX[11], str, rx - nw, t3, fade(col, a))
			PN.bar(tx, rx - nw - PX[8], t3, k, a)
			tip("cn", bx0, by0, bx1, by1, d.label, d.body or "")
		else
			local face = mini(plan.hero)
			local mid = (by0 + by1) / 2
			if face then
				Render.Image(face, Q.v1:Set(bx0 + PX[10], mid - PX[12]), Q.v2:Set(PX[24], PX[24]), fade(P.WHITE, a), PX[4], K.ROUND)
			end
			text(W.fonts.semi, PX[12], L("cd_p_all"), bx0 + PX[44], mid, fade(P.MUTED, a))
		end
		cy = cy + next_h
		if #queue > 0 then
			SM.caption(L("cd_p_queue"), nil, x + pad, cy + PX[8], a)
			local hint = L("cd_p_rmb")
			text(W.fonts.regular, PX[10], hint, x + w - pad - tw(W.fonts.regular, PX[10], hint), cy + PX[8], fade(P.DIM, a))
			cy = cy + PX[22]
			for i, sl in ipairs(queue) do
				local qx = x + pad + ((i - 1) % per) * (qw + qg)
				local qy = cy + ((i - 1) // per) * (qh + PX[20])
				PN.slot(sl, qx, qy, qw, qh, a)
				PN.qbuy(plan, "cq" .. i, sl.name, qx, qy, qx + qw, qy + qh, a)
				if sl.t and sl.t > 0 then
					local m = L("cd_p_min"):format(math.floor(sl.t * (G.tk or 1) / 60 + 0.5))
					text(W.fonts.regular, PX[10], m, qx + (qw - tw(W.fonts.regular, PX[10], m)) / 2, qy + qh + PX[9], fade(P.MUTED, a))
				end
				if tip_at(qx, qy, qx + qw, qy + qh) then
					tip_put("cq" .. i, sl.label, sl.body or "")
				end
			end
			cy = cy + qrows * (qh + PX[20])
		end
		if #done > 0 then
			SM.caption(L("cd_p_done"), nil, x + pad, cy + PX[8], a)
			cy = cy + PX[22]
			for i, sl in ipairs(done) do
				local qx = x + pad + ((i - 1) % dper) * (dw + dg)
				local qy = cy + ((i - 1) // dper) * (dh + dg)
				PN.slot({ name = sl.name }, qx, qy, dw, dh, a * 0.45)
				if tip_at(qx, qy, qx + dw, qy + dh) then
					tip_put("cd" .. i, sl.label, "")
				end
			end
			cy = cy + drows * (dh + dg)
		end
		local fy = cy + PX[20]
		PN.roles(plan, x + pad, fy, PX[22], a)
		local demo = plan == PN.DEMO
		local gold = demo and PN.DEMO.gold or G.gold
		local tags = {}
		if cfg.autobuy == 1 then
			tags[#tags + 1] = { L("cd_p_auto"), P.GOOD }
		end
		if not demo and cfg.autobuy == 1 and (G.reserve or 0) > 0 then
			tags[#tags + 1] = { L("cd_p_reserve"):format(G.reserve), P.MUTED }
		end
		if gold then
			tags[#tags + 1] = { L("cd_p_gold"):format(math.floor(gold)), P.DIM }
		end
		local min_x = x + pad + PN.roles_w(PX[22]) + PX[10]
		local rx = x + w - pad
		for i, t in ipairs(tags) do
			local tw0 = tw(W.fonts.regular, PX[10], t[1])
			local gap = i > 1 and PX[14] or 0
			if rx - gap - tw0 < min_x then
				break
			end
			if i > 1 then
				vline(rx - PX[7], fy, PX[5], a)
			end
			rx = rx - gap
			text(W.fonts.regular, PX[10], t[1], rx - tw0, fy, fade(t[2], a))
			rx = rx - tw0
		end
	end

	function PN.compact(plan, x, y, a, measure)
		local h = PX[34]
		local d = plan.next
		local queue = {}
		for _, sl in ipairs(plan.slots) do
			if sl.state == "later" and #queue < K.PILL_QUEUE then
				queue[#queue + 1] = sl
			end
		end
		local name = d and d.label or L("cd_p_all")
		local str, col = "", P.MUTED
		if d then
			str, col = PN.need(plan, d)
		end
		local iw, ih = PX[33], PX[24]
		local qw, qh, qg = PX[26], PX[19], PX[4]
		local nw = tw(W.fonts.bold, PX[12], name)
		local sw = str ~= "" and tw(W.fonts.regular, PX[11], str) or 0
		local w = PX[5] + iw + PX[9] + nw + (sw > 0 and PX[17] + sw or 0)
			+ (#queue > 0 and PX[17] + #queue * (qw + qg) - qg or 0) + PX[14]
		if measure then
			return w, h
		end
		PN.back(x, y, w, h, a, h / 2)
		local cy = y + h / 2
		local ix = x + PX[5]
		local img = d and PN.item_img(d.name)
		if img then
			Render.Image(img, Q.v1:Set(ix, math.floor(cy - ih / 2)), Q.v2:Set(iw, ih), fade(P.WHITE, a), PX[5], K.ROUND)
		else
			local face = mini(plan.hero)
			if face then
				Render.Image(face, Q.v1:Set(ix + (iw - ih) / 2, math.floor(cy - ih / 2)), Q.v2:Set(ih, ih), fade(P.WHITE, a), PX[5], K.ROUND)
			end
		end
		local tx = ix + iw + PX[9]
		tx = tx + text(W.fonts.bold, PX[12], name, tx, cy, fade(d and (plan.warn and P.WARN or P.TEXT) or P.MUTED, a))
		if sw > 0 then
			vline(tx + PX[8], cy, PX[6], a)
			tx = tx + PX[17] + text(W.fonts.regular, PX[11], str, tx + PX[17], cy, fade(col, a))
		end
		if #queue > 0 then
			vline(tx + PX[8], cy, PX[6], a)
			local qx = tx + PX[17]
			for _, sl in ipairs(queue) do
				local qimg = PN.item_img(sl.name)
				if qimg then
					Render.Image(qimg, Q.v1:Set(qx, math.floor(cy - qh / 2)), Q.v2:Set(qw, qh), fade(P.WHITE, a * 0.7), PX[3], K.ROUND)
				end
				qx = qx + qw + qg
			end
		end
		hit(x, y, x + w, y + h, "pdrag")
	end

	function W.part(name, f, ...)
		local t0 = os.clock()
		local r1, r2 = f(...)
		W.cost = W.cost or {}
		W.cost[name] = (W.cost[name] or 0) + os.clock() - t0
		return r1, r2
	end

	function draw_panel()
		W.panel_rect = nil
		if not W.open or cfg.panel ~= 1 then
			W.preview = false
		end
		local preview = W.preview and W.open and W.vis > 0 and not G.live
		local plan = preview and PN.demo() or G.plan
		if not plan and not preview and G.live and G.hero and cfg.live == 1 and not I.buys[G.hero] then
			PN.WAIT = PN.WAIT or { none = true, wait = true, slots = {} }
			PN.WAIT.hero, PN.WAIT.pos = G.hero, G.bpos
			plan = PN.WAIT
		end
		local okshop, shop_open = W.part(".pn_shop", pcall, Engine.IsShopOpen)
		shop_open = okshop and shop_open == true and not preview
		local shop = preview or cfg.pshop ~= 1 or shop_open
		local show = cfg.panel == 1 and plan ~= nil
			and (preview or (G.live and shop and not (cfg.phide == 1 and plan.complete)))
		local pa = approach("panel_a", show and 1 or 0, 12)
		if show then
			W.pplan = plan
		end
		plan = W.pplan
		if pa <= 0.01 or not plan then
			W.pdrag = false
			return
		end
		ensure_fonts()
		local menu_scale = Menu.Scale()
		Q.scale(cfg.pzoom / 100 * K.BASE_ZOOM * ((menu_scale >= 50 and menu_scale <= 300) and menu_scale / 100 or 1))
		local draw = plan.none and PN.none or ({ PN.compact, PN.card, PN.strip })[cfg.pview + 1] or PN.compact
		local w, h = W.part(".pn_size", draw, plan, 0, 0, pa, true)
		local screen = Render.ScreenSize()
		if not W.px then
			W.px = Config.ReadInt(K.CONFIG, "px", -1)
			W.py = Config.ReadInt(K.CONFIG, "py", -1)
			if W.px < 0 or W.py < 0 then
				W.px, W.py = screen.x - w - PX[24], math.floor(screen.y * 0.45)
			end
		end
		if W.pdrag then
			if Input.IsKeyDown(K.MOUSE1, true) then
				local cx, cy = Input.GetCursorPos()
				W.px, W.py = cx - W.pdx, cy - W.pdy
			else
				W.pdrag = false
				Config.WriteInt(K.CONFIG, "px", math.floor(W.px))
				Config.WriteInt(K.CONFIG, "py", math.floor(W.py))
			end
		end
		W.px = clamp(W.px, 0, math.max(0, screen.x - w))
		W.py = clamp(W.py, 0, math.max(0, screen.y - h))
		local x, y = math.floor(W.px), math.floor(W.py)
		local r = { x, y, x + w, y + h }
		if draw == PN.compact then
			local cw, ch = W.part(".pn_card_size", PN.card, plan, 0, 0, pa, true)
			local cx0 = x + w / 2 > screen.x / 2 and x + w - cw or x
			cx0 = math.floor(clamp(cx0, 0, math.max(0, screen.x - cw)))
			local cy0 = math.floor(clamp(y, 0, math.max(0, screen.y - ch)))
			local mx, my = Input.GetCursorPos()
			local pad = PX[8]
			local zone = W.pn_open and { cx0 - pad, cy0 - pad, cx0 + cw + pad, cy0 + ch + pad } or r
			if W.pdrag or (show and in_rect(zone, mx, my) and not over_menu(mx, my)) then
				W.pn_hold = os.clock() + K.PN_HOLD
			end
			W.pn_open = show and (shop_open or os.clock() < (W.pn_hold or 0))
			local ek = approach("pn_open", W.pn_open and 1 or 0, 16)
			local nohit = W.nohit
			if ek < 0.99 then
				W.nohit = nohit or W.pn_open
				W.part(".pn_draw", draw, plan, x, y, pa * (1 - ek), false)
			end
			if ek > 0.01 then
				W.nohit = nohit or not W.pn_open
				W.part(".pn_card", PN.card, plan, cx0, cy0 + math.floor((1 - ek) * PX[6] + 0.5), pa * ek, false)
			end
			W.nohit = nohit
			if W.pn_open then
				r = { cx0, cy0, cx0 + cw, cy0 + ch }
			end
		else
			W.part(".pn_draw", draw, plan, x, y, pa, false)
		end
		if show then
			W.panel_rect = r
		end
		W.part(".pn_toast", SM.toast, r[1], r[4], r[3] - r[1], PX[60], pa, "ptoast")
	end

	function draw_tips()
		draw_tip(1)
	end

	function draw_window()
		W.pm_rect, W.gear_block = nil, nil
		if W.slider then
			if Input.IsKeyDown(K.MOUSE1, true) and W.slider_rect then
				local cx = Input.GetCursorPos()
				local k = clamp((cx - W.slider_rect[1]) / math.max(1, W.slider_rect[2] - W.slider_rect[1]), 0, 1)
				cfg.bg = math.floor(50 + 50 * k + 0.5)
			else
				W.slider = false
				set_cfg("bg", cfg.bg)
			end
		end
		local clock = os.clock()
		dt = W.clock and clamp(clock - W.clock, 0, 0.1) or 0
		W.clock = clock
		for k in pairs(Q.ek) do
			Q.ek[k] = nil
		end
		local open = W.open and ui.enable:Get()
		local was = W.vis
		W.vis = open and math.min(1, W.vis + dt / K.FADE) or math.max(0, W.vis - dt / K.FADE)
		W.nhits, Q.nharg = 0, 0
		for key in pairs(W.held) do
			if not Input.IsKeyDown(key, true) then
				W.held[key] = nil
			end
		end
		if W.vis <= 0 then
			W.drag = false
			return
		end
		W.snap = was <= 0
		if W.snap then
			W.list_t0, W.step_t = os.clock() + 0.05, os.clock()
		end
		ensure_fonts()
		if draft.dirty then
			recompute()
		end
		local c = cur_step()
		local key = tostring(c) .. (draft.edit and "e" or "") .. ":" .. draft.filter
		if key ~= W.step_c then
			W.step_c, W.step_t = key, os.clock()
		end
		local menu_scale = Menu.Scale()
		Q.scale(cfg.zoom / 100 * K.BASE_ZOOM * ((menu_scale >= 50 and menu_scale <= 300) and menu_scale / 100 or 1))
		local screen = Render.ScreenSize()
		W.w = PX[K.W]
		W.h = PX[K.WIN_H]
		if not W.x then
			W.x = Config.ReadInt(K.CONFIG, "x", -1)
			W.y = Config.ReadInt(K.CONFIG, "y", -1)
			if W.x < 0 or W.y < 0 then
				W.x, W.y = math.floor((screen.x - W.w) / 2), math.floor((screen.y - W.h) / 2)
			end
		end
		if W.drag then
			if Input.IsKeyDown(K.MOUSE1, true) then
				local cx, cy = Input.GetCursorPos()
				W.x, W.y = cx - W.dx, cy - W.dy
			else
				W.drag = false
				Config.WriteInt(K.CONFIG, "x", math.floor(W.x))
				Config.WriteInt(K.CONFIG, "y", math.floor(W.y))
			end
		end
		W.x = clamp(W.x, 0, math.max(0, screen.x - W.w))
		W.y = clamp(W.y, 0, math.max(0, screen.y - W.h))

		local a = W.vis * W.vis * (3 - 2 * W.vis)
		local slide = open and (1 - ease(W.vis)) or (1 - W.vis)
		local x, y, w, h = math.floor(W.x), math.floor(W.y + slide * PX[K.SLIDE]), W.w, W.h
		W.ox, W.oy = x, y
		local r = PX[K.RADIUS]
		local p0, p1 = Vec2(x, y), Vec2(x + w, y + h)
		if cfg.blur == 1 then
			local strength = clamp((a - 0.5) / 0.5, 0, 1)
			if strength > 0.01 then
				Render.Blur(p0, p1, strength, 1.0, r, K.ROUND)
			end
		end
		local bg = rgba(P.BG.r, P.BG.g, P.BG.b, math.floor(255 * cfg.bg / 100 + 0.5))
		Render.FilledRect(p0, p1, fade(bg, a), r, K.ROUND)

		local rail_w, top_h = PX[K.RAIL_W], PX[K.HEAD_H]
		local line = math.max(1, PX[1])
		local mx0 = x + rail_w
		local cw = x + w - mx0
		local alpha = math.floor(255 * cfg.bg / 100 + 0.5)
		local sm = draft.summary
		W.nav_h = nil
		if sm then
			local mine0 = SM.my_row(sm)
			W.nav_h = (mine0 and mine0.h) or draft.build_h or (sm.rows[1] and sm.rows[1].h)
		end
		draw_rail(x, y, rail_w, h, a, rgba(P.RAIL.r, P.RAIL.g, P.RAIL.b, alpha))
		draw_head(mx0, y, cw, a)
		local cy0 = y + top_h
		rect(mx0, cy0, x + w, cy0 + line, fade(P.LINE, a))
		if W.card and not draft.summary then
			W.card = nil
		end
		local mine = draft.summary and not W.settings and SM.my_row(draft.summary)
		local auto_key = mine and (tostring(draft.match) .. ":" .. mine.h)
		if auto_key and W.card_auto ~= auto_key then
			W.card_auto = auto_key
			W.card, draft.build_h = mine.h, mine.h
			log("card: opened for my hero %d", mine.h)
		end
		if W.card then
			W.card_last = W.card
		end
		local ck = approach("card_k", (W.card and not W.settings) and 1 or 0, 14)
		local sk = approach("set_k", W.settings and 1 or 0, 14)
		local ga = a * (1 - ck) * (1 - sk)
		local body_h = y + h - cy0
		if ga > 0.01 then
			local nohit = W.nohit
			W.nohit = nohit or W.card ~= nil or W.settings
			local arena_h = PX[(draft.mode == 0 and K.ARENA_ORDER_H or K.ARENA_H)]
			draw_arena(mx0 + line, cy0 + line, cw - line, arena_h, ga)
			local by0 = cy0 + line + arena_h
			rect(mx0 + PX[18], by0, x + w - PX[18], by0 + line, fade(P.LINE, ga))
			local side_w = PX[K.SIDE_PREV]
			local sx0 = x + w - PX[14] - side_w
			local sy0, sy1 = by0 + PX[12], y + h - PX[14]
			rect(sx0, sy0, sx0 + side_w, sy1, fade(rgba(P.CARD.r, P.CARD.g, P.CARD.b, math.min(255, alpha + 20)), ga), PX[12])
			Render.Rect(Q.v1:Set(sx0, sy0), Q.v2:Set(sx0 + side_w, sy1), fade(P.LINE, ga), PX[12], K.ROUND, line)
			draw_main(mx0 + line, by0 + line, sx0 - mx0 - line - PX[2], y + h - by0 - line, ga)
			W.nohit = nohit or W.card ~= nil or W.settings
			draw_side(sx0, sy0, side_w, sy1 - sy0, ga)
			W.nohit = nohit
		else
			W.grid_rect, W.list_rect = nil, nil
		end
		if ck > 0.01 then
			local nohit = W.nohit
			W.nohit = nohit or not W.card or W.settings
			SM.card(mx0 + line, cy0 + line + math.floor((1 - ck) * PX[K.SLIDE] + 0.5), cw - line, body_h - line, a * ck)
			W.nohit = nohit
		end
		if sk > 0.01 then
			local nohit = W.nohit
			W.nohit = nohit or not W.settings
			draw_settings_page(mx0 + line, cy0 + line + math.floor((1 - sk) * PX[K.SLIDE] + 0.5), cw - line, body_h - line, a * sk)
			W.nohit = nohit
		end
		draw_pos_menu(a)
		SM.pick(x, y, w, h, a)
		SM.toast(x, y, w, h, a)
		W.snap = false
	end
end

local function check_match()
	if not in_match() then
		return
	end
	local gs = GameRules.GetGameState()
	local id = tostring(GameRules.GetMatchID()) .. ":" .. tostring(GameRules.GetLobbyID())
	if draft.mode_for ~= id then
		local gm = GameRules.GetGameMode()
		if gm and gm ~= Enum.GameMode.DOTA_GAMEMODE_NONE then
			draft.mode_for, draft.gm = id, gm
			set_mode(gm == K.MODE_CM and 0 or 1)
			log("draft mode %s, game mode %s", draft.mode == 0 and "in turns" or "free", tostring(gm))
		end
	end
	if gs == K.HERO_SELECTION then
		if draft.match ~= id then
			draft.match = id
			reset_draft()
			I.bpos, I.shown_pos, W.card = {}, {}, nil
			log("new draft %s", id)
			if cfg.auto == 1 then
				open_window()
				W.auto = true
			end
		end
	elseif W.auto and gs ~= K.STRATEGY then
		W.open, W.auto = false, false
	end
end

local function poll_keys()
	for key in pairs(W.down) do
		if not Input.IsKeyDown(key, true) then
			W.down[key] = nil
		end
	end
	if not W.open or not W.focus or W.vis <= 0 then
		return
	end
	local bind = ui.key:Get()
	for _, code in ipairs(K.TYPE_KEYS) do
		if code ~= bind and Input.IsKeyDownOnce(code) then
			type_key(code)
		end
	end
end

LOGR.esc = { ['"'] = '\\"', ["\\"] = "\\\\", ["\n"] = "\\n", ["\r"] = "\\r", ["\t"] = "\\t" }
LOGR.fly, LOGR.seq = {}, 0

function LOGR.jstr(s)
	return '"' .. s:gsub('[%c"\\]', function(c)
		return LOGR.esc[c] or ("\\u%04x"):format(c:byte())
	end) .. '"'
end

function LOGR.scrub(s)
	s = tostring(s):gsub("%d%d%d%d%d%d%d%d+", "#"):gsub("([Uu]sers[\\/])[^\\/\n]+", "%1*")
	if utf8 and not utf8.len(s) then
		s = s:gsub("[\128-\255]", "?")
	end
	return s
end

function LOGR.cut(s, n)
	local parts, i = {}, 1
	while i <= #s do
		local j = math.min(#s, i + n - 1)
		while j < #s and j > i and s:byte(j + 1) >= 128 and s:byte(j + 1) < 192 do
			j = j - 1
		end
		parts[#parts + 1] = s:sub(i, j)
		i = j + 1
	end
	return parts
end

function LOGR.id()
	if not LOGR.uid then
		local dir = LOGR.dir()
		local path = dir and dir .. "configs\\" .. K.LOG_ID_FILE
		local f = path and io.open(path, "rb")
		local saved = f and f:read("l")
		if f then
			f:close()
		end
		saved = type(saved) == "string" and saved:match("^(%x%x%x%x%x%x)%s*$")
		LOGR.uid = saved or Config.ReadString("draft_helper", "log_id", "")
		if LOGR.uid == "" then
			LOGR.uid = ("%06x"):format((os.time() * 7919 + math.floor(os.clock() * 1000003)) % 0x1000000)
		end
		Config.WriteString("draft_helper", "log_id", LOGR.uid)
		if not saved and path then
			local g = io.open(path, "wb")
			if g then
				g:write(LOGR.uid, "\n")
				g:close()
			end
		end
	end
	return LOGR.uid
end

function LOGR.lines()
	local out = {}
	for _, l in ipairs(LOGR.first) do
		out[#out + 1] = l
	end
	local n = math.min(LOGR.total, LOGR.size)
	if LOGR.total > LOGR.size then
		out[#out + 1] = ("... %d lines skipped ..."):format(LOGR.total - LOGR.size)
	end
	for i = 1, n do
		out[#out + 1] = LOGR.ring[(LOGR.head - n + i - 1) % LOGR.size + 1]
	end
	return out
end

function LOGR.build(reason)
	local function get(f)
		local ok, v = pcall(f)
		return ok and v or nil
	end
	local S = D.sets and D.sets[source()]
	local hero = G.hero and D.by_id[G.hero]
	local set = {}
	for k, v in pairs(cfg) do
		set[#set + 1] = k .. "=" .. tostring(v)
	end
	table.sort(set)
	local head = {
		("### %s, v%s, %s"):format(reason, K.VERSION, LOGR.id()),
		"```",
		("version %s, %s, %s"):format(K.VERSION, _VERSION, os.date("!%Y-%m-%d %H:%M UTC")),
		("game state %s, mode %s, in match %s"):format(tostring(get(GameRules.GetGameState)), tostring(get(GameRules.GetGameMode)),
			tostring(G.live == true)),
		("hero %s, position %s"):format(tostring(hero and hero.name), tostring(G.bpos)),
		("draft stats %s matches, set %s, own %s"):format(tostring(S and S.stats and S.stats.n), tostring(S and S.gh_on),
			tostring(S and S.recs and #S.recs)),
		("data error %s, items error %s, update %s %s"):format(tostring(D.error), tostring(I.error), tostring(U.status),
			tostring(U.error or "")),
		("errors %d"):format(LOGR.nerr),
		"settings " .. table.concat(set, " "),
		"```",
	}
	if #LOGR.errs > 0 then
		head[#head + 1] = "**Errors**"
		head[#head + 1] = "```"
		for _, e in ipairs(LOGR.errs) do
			head[#head + 1] = e
		end
		head[#head + 1] = "```"
	end
	head[#head + 1] = "**Log**"
	head[#head + 1] = "```"
	for i, l in ipairs(head) do
		head[i] = LOGR.scrub(l)
	end
	local top = table.concat(head, "\n")
	local lines = LOGR.lines()
	local kept, size = {}, #top + 8
	for i = #lines, 1, -1 do
		local l = LOGR.scrub(lines[i]):gsub("```", "'''")
		size = size + #l + 1
		if size > K.LOG_MAX then
			kept[#kept + 1] = "... older lines cut ..."
			break
		end
		kept[#kept + 1] = l
	end
	local body = { top }
	for i = #kept, 1, -1 do
		body[#body + 1] = kept[i]
	end
	body[#body + 1] = "```"
	local title = ("[%s] v%s %s: %s"):format(reason, K.VERSION, LOGR.id(), LOGR.scrub(LOGR.errs[1] or "no errors"):sub(1, 100))
	return title, table.concat(body, "\n")
end

function LOGR.dir()
	local dir = Engine.GetCheatDirectory()
	if type(dir) ~= "string" then
		return nil
	end
	return dir:match("[\\/]$") and dir or dir .. "\\"
end

function LOGR.save(title, body)
	local dir = LOGR.dir()
	local f = dir and io.open(dir .. "configs\\draft_helper_log.txt", "wb")
	if not f then
		return false
	end
	f:write(title, "\n\n", body, "\n")
	f:close()
	return true
end

function LOGR.queue(reqs)
	local dir = LOGR.dir()
	local f = dir and io.open(dir .. "configs\\" .. K.LOG_BOX_FILE, "ab")
	if not f then
		return
	end
	local oks, size = pcall(f.seek, f, "end")
	if not oks or (tonumber(size) or 0) < K.LOG_BOX then
		f:write(table.concat(reqs, "\t"), "\n")
	end
	f:close()
end

function LOGR.rid()
	return ("r%s%x"):format(LOGR.id(), os.time())
end

function LOGR.backoff(ok)
	if ok then
		LOGR.fails, LOGR.retry_at = 0, 0
		return
	end
	LOGR.fails = (LOGR.fails or 0) + 1
	LOGR.retry_at = os.clock() + math.min(K.LOG_RETRY_MAX, K.LOG_RETRY_MIN * 2 ^ (LOGR.fails - 1))
end

function LOGR.token()
	if LOGR.tok ~= nil then
		return LOGR.tok
	end
	local dir = LOGR.dir()
	local path = dir and (dir .. "configs\\" .. K.LOG_TOKEN_FILE)
	local saved
	local f = path and io.open(path, "rb")
	if f then
		saved = (f:read("a") or ""):match("[%w_]+")
		f:close()
	end
	if K.LOG_TOKEN ~= "" and saved ~= K.LOG_TOKEN and path then
		local w = io.open(path, "wb")
		if w then
			w:write(K.LOG_TOKEN)
			w:close()
		end
		saved = K.LOG_TOKEN
	end
	LOGR.tok = K.LOG_TOKEN ~= "" and K.LOG_TOKEN or saved or ""
	return LOGR.tok
end

function LOGR.headers()
	return {
		["Authorization"] = "Bearer " .. LOGR.token(),
		["Accept"] = "application/vnd.github+json",
		["Content-Type"] = "application/json",
		["User-Agent"] = "Umbrella/draft_helper",
		["X-GitHub-Api-Version"] = "2022-11-28",
	}
end

function LOGR.find(rid, done)
	local url = K.LOG_URL .. "?state=all&sort=created&direction=desc&per_page=" .. K.LOG_CHECK
	local sent = HTTP.Request("GET", url, { headers = LOGR.headers(), timeout = K.LOG_TIMEOUT }, function(res)
		if tostring(res.code) ~= "200" then
			done(false, res)
			return
		end
		local text = tostring(res.response or "")
		local at = text:find("#" .. rid .. '"', 1, true)
		local num
		if at then
			for n in text:sub(math.max(1, at - 4000), at):gmatch('"number":%s*(%d+)') do
				num = n
			end
		end
		done(true, num)
	end, "cd_log_find")
	if not sent then
		done(false, { code = "not sent" })
	end
end

function LOGR.post(url, json, done)
	local sent = HTTP.Request("POST", url, {
		headers = LOGR.headers(),
		data = json,
		timeout = K.LOG_TIMEOUT,
	}, function(res)
		done(tostring(res.code) == "201", res)
	end, "cd_log")
	if not sent then
		done(false, { code = "not sent" })
	end
end

function LOGR.busy()
	return next(LOGR.fly) ~= nil
end

function LOGR.deliver(reqs, done, queued)
	LOGR.seq = LOGR.seq + 1
	local id = LOGR.seq
	local fl = { t = os.clock() }
	function fl.finish(ok, why, code)
		if LOGR.fly[id] ~= fl then
			return
		end
		LOGR.fly[id] = nil
		if not ok and not queued then
			LOGR.queue(reqs)
		end
		LOGR.backoff(ok)
		done(ok, why, code)
	end
	LOGR.fly[id] = fl
	if LOGR.token() == "" then
		fl.finish(false, "no token")
		return
	end
	local function parts(num)
		fl.num, fl.reqs, fl.i = num, reqs, 1
		local function next_part()
			fl.i = fl.i + 1
			local i = fl.i
			if not reqs[i] then
				fl.finish(true, num)
				return
			end
			fl.t = os.clock()
			LOGR.post(K.LOG_URL .. "/" .. num .. "/comments", reqs[i], function(ok2, res2)
				if LOGR.fly[id] ~= fl then
					return
				end
				local code = tostring(res2.code)
				if not ok2 and code ~= "400" and code ~= "404" and code ~= "410" and code ~= "422" then
					log("log: part %d of report %s not sent: http %s, queued", i, num, code)
					LOGR.queue_rest(num, reqs, i)
					fl.finish(true, num)
					return
				elseif not ok2 then
					log("log: part %d of report %s rejected: http %s", i, num, code)
				end
				next_part()
			end)
		end
		next_part()
	end
	local known = reqs[1]:match("^#(%d+)$")
	if known then
		parts(known)
		return
	end
	local function create()
		fl.t = os.clock()
		LOGR.post(K.LOG_URL, reqs[1], function(ok, res)
		if LOGR.fly[id] ~= fl then
			return
		end
			local text = tostring(res.response or "")
			local num = ok and (text:match('"html_url":"[^"]-/issues/(%d+)"') or text:match('"number":%s*(%d+)'))
			if not num then
				fl.finish(false, ("http %s %s %s"):format(tostring(res.code), tostring(res.error_message or ""), text:sub(1, 160)),
					tostring(res.code))
				return
			end
			parts(num)
		end)
	end
	local rid = queued and reqs[1]:match('^{"title":"[^"]-#(r%x+)"')
	if not rid then
		create()
		return
	end
	LOGR.find(rid, function(ok, num)
		if LOGR.fly[id] ~= fl then
			return
		end
		if not ok then
			fl.finish(false, "check: http " .. tostring(num and num.code))
		elseif num then
			log("log: queued report %s is already issue %s, sending the rest", rid, num)
			parts(num)
		else
			create()
		end
	end)
end

function LOGR.queue_rest(num, reqs, from)
	local rest = { "#" .. num }
	for i = from, #reqs do
		rest[#rest + 1] = reqs[i]
	end
	if #rest > 1 then
		LOGR.queue(rest)
	end
end

function LOGR.watch()
	local now = os.clock()
	for id, fl in pairs(LOGR.fly) do
		if now - fl.t > K.LOG_STUCK then
			log("log: report %d got no answer", id)
			if fl.num then
				LOGR.queue_rest(fl.num, fl.reqs, fl.i)
			end
			fl.finish(fl.num ~= nil, fl.num or "no answer")
		end
	end
end

function LOGR.flush()
	local dir = LOGR.dir()
	local path = dir and dir .. "configs\\" .. K.LOG_BOX_FILE
	local f = path and io.open(path, "rb")
	if not f then
		return
	end
	local first = f:read("l")
	f:close()
	if not first or first == "" then
		os.remove(path)
		return
	end
	local function drop()
		local g = io.open(path, "rb")
		if not g then
			return
		end
		local all = g:read("a")
		g:close()
		if all:sub(1, #first) ~= first then
			return
		end
		local rest = all:sub(#first + 2)
		if rest == "" then
			os.remove(path)
		else
			local h = io.open(path, "wb")
			if h then
				h:write(rest)
				h:close()
			end
		end
	end
	if not first:match('^{"title":.*}$') and not first:match('^#%d+\t{.*}$') then
		drop()
		log("log: dropped a broken queued report, %d bytes", #first)
		return
	end
	local reqs = {}
	for part in first:gmatch("[^\t]+") do
		reqs[#reqs + 1] = part
	end
	LOGR.deliver(reqs, function(ok, why, code)
		if ok then
			drop()
			log("log: queued report sent as %s", tostring(why))
		elseif code == "400" or code == "422" then
			drop()
			log("log: queued report rejected: %s", tostring(why))
		end
	end, true)
end

function LOGR.send(reason)
	local manual = reason == "manual"
	if manual and LOGR.sent_at and os.clock() - LOGR.sent_at < K.LOG_COOLDOWN then
		W.toast = { key = "cd_log_wait", t = os.clock() }
		return
	end
	LOGR.sent_at = os.clock()
	local title, body = LOGR.build(reason)
	if manual then
		LOGR.save(title, body)
	end
	LOGR.deliver({ '{"title":' .. LOGR.jstr(title) .. ',"body":' .. LOGR.jstr(body) .. "}" }, function(ok, why)
		log("log: %s report %s", reason, ok and ("sent as " .. tostring(why)) or ("not sent, queued: " .. tostring(why)))
		if manual then
			W.toast = { key = ok and "cd_log_sent" or "cd_log_saved", t = os.clock() }
		end
	end)
end

function LOGR.match(text, meta)
	if cfg.logauto ~= 1 then
		return
	end
	meta = meta or {}
	if tostring(meta.match or "0") == "0" and cfg.debug ~= 1 then
		log("log: lobby game without a match id, report not sent")
		return
	end
	local set, errs = {}, {}
	for k, v in pairs(cfg) do
		set[#set + 1] = LOGR.jstr(k) .. ":" .. LOGR.jstr(tostring(v))
	end
	table.sort(set)
	for _, e in ipairs(LOGR.errs) do
		errs[#errs + 1] = LOGR.jstr(LOGR.scrub(e))
	end
	local payload = table.concat({ '{"v":1,"uid":', LOGR.jstr(LOGR.id()), ',"version":', LOGR.jstr(K.VERSION), ',"sent":',
		LOGR.jstr(os.date("!%Y-%m-%d %H:%M:%S")), ',"settings":{', table.concat(set, ","), '},"errors":[', table.concat(errs, ","),
		'],"record":', text, "}" })
	local hero = D.by_id[meta.hero or 0]
	local title = ("[match] v%s %s: %s pos %s, %s, %d min%s #%s"):format(K.VERSION, LOGR.id(), hero and hero.name or "?",
		tostring(meta.pos or "?"), meta.win == 1 and "win" or (meta.win == 0 and "loss" or "?"), math.floor(tonumber(meta.minutes) or 0),
		LOGR.nerr > 0 and (", errors " .. LOGR.nerr) or "", LOGR.rid())
	local reqs = {}
	for n, part in ipairs(LOGR.cut(payload, K.LOG_PART)) do
		local md = LOGR.jstr("```json\n" .. part .. "\n```")
		reqs[#reqs + 1] = n == 1 and ('{"title":' .. LOGR.jstr(title) .. ',"body":' .. md .. "}") or ('{"body":' .. md .. "}")
	end
	local lines = LOGR.lines()
	for i, l in ipairs(lines) do
		lines[i] = LOGR.scrub(l):gsub("```", "'''")
	end
	for _, part in ipairs(LOGR.cut(table.concat(lines, "\n"), K.LOG_PART)) do
		reqs[#reqs + 1] = '{"body":' .. LOGR.jstr("```text\n" .. part .. "\n```") .. "}"
	end
	LOGR.pend = nil
	LOGR.deliver(reqs, function(ok, why)
		log("log: match report %s", ok and ("sent as " .. tostring(why)) or ("not sent, queued: " .. tostring(why)))
	end)
end

function LOGR.tick()
	LOGR.watch()
	if not G.live and os.clock() >= (LOGR.park_at or 0) then
		LOGR.park_at = os.clock() + 30
		local okp, perr = pcall(G.rec_flush_parked, false)
		if not okp then
			log("record: %s", tostring(perr))
		end
	end
	if LOGR.busy() or G.live or cfg.logauto ~= 1 then
		return
	end
	local now = os.clock()
	if now >= (LOGR.retry_at or 0) then
		LOGR.retry_at = now + K.LOG_RETRY_MAX
		LOGR.flush()
		return
	end
	if not LOGR.pend or now - LOGR.err_at < K.LOG_CALM then
		return
	end
	if not LOGR.last_t then
		LOGR.last_t = Config.ReadInt("draft_helper", "log_last", 0)
		LOGR.last_sig = Config.ReadString("draft_helper", "log_sig", "")
	end
	local sig = LOGR.scrub(LOGR.pend):sub(1, 120)
	local t = os.time()
	if sig == LOGR.last_sig and t - LOGR.last_t < K.LOG_SAME then
		LOGR.pend = nil
		return
	end
	if t - LOGR.last_t < K.LOG_GAP then
		return
	end
	LOGR.pend, LOGR.last_t, LOGR.last_sig = nil, t, sig
	Config.WriteInt("draft_helper", "log_last", t)
	Config.WriteString("draft_helper", "log_sig", sig)
	LOGR.send("error")
end

local script = {}

function script.OnUpdateEx()
	if cfg.lang ~= 0 and localization.GetLanguage() ~= localization.umb then
		localization.apply_lang()
	end
	if localization.GetLanguage(localization.force) ~= localization.memo_lang then
		localization.memo, localization.memo_lang = {}, localization.GetLanguage(localization.force)
	end
	if D.models_fresh then
		D.models_fresh = nil
		I.models_rebuild()
		I.builds, G.sig = {}, nil
		draft.vs_cache, draft.dirty = {}, true
	end
	if not ui.enable:Get() then
		W.open = false
		return
	end
	local cap = Input.IsInputCaptured()
	if cap ~= W.cap then
		log("input captured: %s, search focus: %s", tostring(cap), tostring(W.focus))
		if cap and W.cap == false then
			W.focus = false
		end
		W.cap = cap
	end
	if ui.key:IsPressed() and (W.focus or not cap) then
		if W.open then
			W.open, W.focus = false, false
		else
			open_window()
		end
		W.auto = false
	end
	local ok, err = W.timed("keys", poll_keys)
	if not ok and tostring(err) ~= W.poll_error then
		W.poll_error = tostring(err)
		LOGR.err("keys", W.poll_error)
	end
	ok, err = W.timed("data", data_tick)
	if not ok and tostring(err) ~= D.tick_error then
		D.tick_error = tostring(err)
		LOGR.err("data", D.tick_error)
	end
	ok, err = W.timed("updater", U.tick)
	if not ok and tostring(err) ~= W.upd_error then
		W.upd_error = tostring(err)
		LOGR.err("updater", W.upd_error)
	end
	ok, err = W.timed("items", I.tick)
	if not ok and tostring(err) ~= I.tick_error then
		I.tick_error = tostring(err)
		LOGR.err("items", I.tick_error)
	end
	ok, err = W.timed("panel", G.tick)
	if not ok and tostring(err) ~= G.tick_error then
		G.tick_error = tostring(err)
		LOGR.err("panel", G.tick_error)
	end
	ok, err = W.timed("orders", W.order_tick)
	if not ok and tostring(err) ~= W.order_error then
		W.order_error = tostring(err)
		LOGR.err("orders", W.order_error)
	end
	ok, err = W.timed("sync", sync_free)
	if not ok and tostring(err) ~= D.sync_error then
		D.sync_error = tostring(err)
		LOGR.err("sync", D.sync_error)
	end
	ok, err = W.timed("match", check_match)
	if not ok and tostring(err) ~= D.match_error then
		D.match_error = tostring(err)
		LOGR.err("match", D.match_error)
	end
	ok, err = W.timed("recompute", function()
		if draft.dirty and D.heroes then
			recompute()
			for _, r in ipairs(draft.summary and draft.summary.rows or {}) do
				if r.pos then
					I.shown_pos[r.h] = I.bpos[r.h] or r.pos
				end
			end
		end
	end)
	if not ok and tostring(err) ~= D.recompute_error then
		D.recompute_error = tostring(err)
		LOGR.err("draft", D.recompute_error)
	end
	pcall(LOGR.tick)
	W.slow("update")
end

function script.OnFrame()
	local ok, err = W.timed("window", draw_window)
	if not ok and tostring(err) ~= W.draw_error then
		W.draw_error = tostring(err)
		LOGR.err("draw", W.draw_error)
	end
	ok, err = W.timed("panel_draw", draw_panel)
	if not ok and tostring(err) ~= W.panel_error then
		W.panel_error = tostring(err)
		LOGR.err("panel draw", W.panel_error)
	end
	ok, err = W.timed("tips", draw_tips)
	if not ok and tostring(err) ~= W.tip_error then
		W.tip_error = tostring(err)
		LOGR.err("tips", W.tip_error)
	end
	W.slow("frame")
end

function script.OnGameEnd()
	if cfg.live == 1 and G.R and not G.R.written then
		local ok, err = pcall(G.record)
		if not ok then
			LOGR.err("record", tostring(err))
		end
	end
end

if cfg.dmgtrack == 1 then
	function script.OnEntityHurt(data)
		if cfg.pdanger ~= 1 or not G.live then
			return
		end
		local ok, err = pcall(G.hurt, data)
		if not ok and tostring(err) ~= G.hurt_error then
			G.hurt_error = tostring(err)
			LOGR.err("hurt", G.hurt_error)
		end
	end
end

function script.OnKeyEvent(data)
	if not data then
		return true
	end
	if data.event == K.KEY_UP then
		W.down[data.key] = nil
	end
	local window_on = W.vis > 0 and W.open
	if not window_on and not W.panel_rect then
		return true
	end
	local key, ev = data.key, data.event
	local scroll = 0
	if ev == K.SCROLL_UP or ev == K.SCROLL_DOWN then
		scroll = ev == K.SCROLL_UP and -1 or 1
	elseif (key == K.WHEEL_UP or key == K.WHEEL_DOWN) and ev == K.KEY_DOWN then
		scroll = key == K.WHEEL_UP and -1 or 1
	end
	if scroll ~= 0 then
		if not cursor_in_window() then
			return true
		end
		local now = os.clock()
		if now - W.scroll_at > 0.004 then
			W.scroll_at = now
			local cx, cy = Input.GetCursorPos()
			local step = math.floor(K.SCROLL * cfg.zoom / 100 * K.BASE_ZOOM + 0.5)
			if W.settings and in_rect(W.set_rect, cx, cy) then
				W.set_scroll = (W.set_scroll or 0) + scroll * step
			elseif in_rect(W.grid_rect, cx, cy) then
				W.grid_scroll = W.grid_scroll + scroll * step
			elseif in_rect(W.list_rect, cx, cy) then
				W.list_scroll = W.list_scroll + scroll * step
			end
		end
		return false
	end
	if key == K.MOUSE1 or key == K.MOUSE2 then
		if ev == K.KEY_DOWN then
			local held = W.held[key]
			W.held[key] = true
			if held then
				return not W.swallow[key]
			end
			if W.grab() then
				W.swallow[key] = true
				W.click_at = os.clock()
				local ok, err = pcall(click, key == K.MOUSE2)
				if not ok then
					LOGR.err("click", tostring(err))
				end
				return false
			end
			W.focus = false
		elseif ev == K.KEY_UP then
			W.held[key] = nil
			if W.swallow[key] then
				W.swallow[key] = nil
				return false
			end
		end
		return true
	end
	if window_on and key == K.ESCAPE and not W.focus and (W.card or W.pick or W.esc_held) then
		if ev == K.KEY_DOWN then
			if W.pick then
				W.pick = nil
			else
				W.card = nil
			end
			W.esc_held = true
		elseif ev == K.KEY_UP then
			W.esc_held = nil
		end
		return false
	end
	if not window_on or not W.focus or key == ui.key:Get() then
		return true
	end
	if (key == K.ENTER or key == K.PAD_ENTER) and #draft.query == 0 then
		return true
	end
	if K.CHARS[key] or key == K.BACKSPACE or key == K.ENTER or key == K.PAD_ENTER or key == K.ESCAPE then
		if ev == K.KEY_DOWN then
			type_key(key)
		end
		return false
	end
	return true
end

function script.OnPrepareUnitOrders(data)
	if not data then
		return true
	end
	if K.CLICK_ORDERS[data.order] and os.clock() - W.click_at < K.CLICK_GUARD and W.grab() then
		return false
	end
	return true
end


do
	local okc, prev = pcall(collectgarbage, K.GC_MODE)
	W.gc_mode = okc and K.GC_MODE or ("default, " .. tostring(prev))
	log("gc mode %s (was %s)", tostring(W.gc_mode), tostring(okc and prev or "-"))
end

return script
