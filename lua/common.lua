---
-- from After the Storm, by shadowm
---

function safe_random(arg)
	wml.fire("set_variable", {
		name = "temp_ats_lua_random",
		rand = arg,
	})

	local r = wml.variables["temp_ats_lua_random"]
	wml.variables["temp_ats_lua_random"] = nil

	return r
end

--- return a replay-safe random number sampled from specified normal distribution
function random_norm(mean, sd)
	local u = mathx.random()
	local v = mathx.random()
	local n = math.sqrt(-2.0 * math.log(u)) * math.cos(2.0 * math.pi * v)
	local r = (n * sd) + mean
	return r
end

function trunc(n)
	if n >= 0.0 then
		return math.floor(n)
	else
		return math.ceil(n)
	end
end

-- since mainline wesnoth.map.from_cubic is broken as of 1.19.13, reimplement it here
-- (c++ backend expects a cubic_location struct which isn't accessible to lua)
function from_cubic(q, r, s)
	local x = q
	local y = r + trunc((q + (math.abs(q) % 2)) / 2)
	return({x, y})
end

get_cubic = nil
if wesnoth.current_version() >= wesnoth.version("1.19.4") then
	get_cubic = wesnoth.map.get_cubic
else
	-- even-q -> cubic conversion prior to 1.19.4
	get_cubic = function(loc)
		local parity = math.abs(loc[1]) % 2
		local q = loc[1]
		local r = loc[2] - trunc((loc[1] + parity) / 2)
		local s = -1 * (q+r)
		return({q, r, s})
	end
end

--- adjusts side numbers in the sidebar to 'skip over' listed sides
--- used in 17A (Blockade) so that depthstalkers appear the same side as the main naga force
function conceal_sides_sidebar(side_list)
	local side_num_map = {}
	for side in wesnoth.sides.iter() do
		local new_side_num = side.side
		for i, v in ipairs(side_list) do
			if side.side >= v then
				new_side_num = new_side_num - 1
			end
		end
		side_num_map[side.side] = new_side_num
	end
	local old_unit_side_ui = wesnoth.interface.game_display.unit_side
	function wesnoth.interface.game_display.unit_side()
		local info = old_unit_side_ui()
		if #info >= 2 then
			local orig_side_num = info[2][2]["text"]
			info[2][2]["text"] = side_num_map[tonumber(orig_side_num)]
		end
		return info
	end
end

---
-- Counts the amount of matching units.
--
-- [count_units]
--     ... SUF ...
--     variable=unit_count
-- [/count_units]
---
function wesnoth.wml_actions.count_units(cfg)
	local units = wesnoth.units.find_on_map(cfg)
	local varname = cfg.variable or "unit_count"

	if units == nil then
		wml.variables[varname] = 0
	else
		wml.variables[varname] = #units
	end
end

---
-- Sum cost in gold of units matching a filter.
--
-- [total_unit_cost]
--     ... SUF ...
--     variable=unit_count
-- [/total_unit_cost]
---
function wesnoth.wml_actions.total_unit_cost(cfg)
	local units = wesnoth.units.find_on_map(cfg)
	local varname = cfg.variable or "total_cost"

	local functional = wesnoth.require("functional")
	if units == nil then
		wml.variables[varname] = 0
	else
		wml.variables[varname] = functional.reduce(units, function(a,b) return a + b.cost end, 0)
	end
end

---
-- Clears the chat log.
--
-- [clear_chat]
-- [/clear_chat]
---
function wesnoth.wml_actions.clear_chat(cfg)
	wesnoth.interface.clear_chat_messages()
end

---
-- Get current game zoom level.
--
-- [store_zoom]
--     variable=zoom
-- [/store_zoom]
---
function wesnoth.wml_actions.store_zoom(cfg)
	wml.variables[cfg.variable or "zoom"] = wesnoth.interface.zoom(1, true)
end

--- Conditional tag if player has debug mode set
--
-- [if]
--     [debug_mode]
--     [/debug_mode]
--     [then]
--         ...
--     [/then]
-- [/if]
---
function wesnoth.wml_conditionals.debug_mode(cfg)
	return (wesnoth.game_config.debug or wesnoth.game_config.debug_lua or wesnoth.game_config.mp_debug)
end

--[=[
[shuffle_list]
Author: MadMax (username on the Battle for Wesnoth forum)

Shuffles a WML variable list.

Required keys:
variable: the variable name of the list to be shuffled.

Optional keys:
to_variable: if present, this variable will be set to the new list. If not present, the variable in variable= will be overwritten.

Example:
[shuffle_list]
	variable=my_list
	to_variable=my_list_shuffled
[/shuffle_list]
]=]
function wesnoth.wml_actions.shuffle_list(cfg)
	local varname = cfg.variable or wml.error("Missing required variable= attribute in [shuffle_list]")
	local dest_varname = cfg.to_variable or varname
	local temp = wml.array_access.get(varname)
	mathx.shuffle(temp)
	wml.array_access.set(dest_varname, temp)
end

--[=[
[fading_message]
Author: MadMax (username on the Battle for Wesnoth forum)

Displays timed messages at bottom of the screen. Intended for cutscenes, active dialogue, etc.

Required keys:
message: text of the message to display
time: total of how long (milliseconds) message remains on the screen
SUF: do not include a [filter] subtag. If multiple units match the filter, the message will be displayed for the first unit only.

Optional keys:
fade_time: how long (milliseconds) message takes to fade out. Cannot be greater than time=.
caption: similar to [message], override the name displayed for the speaker
skippable: if yes, then do not show if messages are currently being skipped (e.g. if player has skipped replay)
[time_lang]:
	Override time= for specific languages. Accepts both two-letter (ISO 639-1) and longer language codes, with longer overriding two-letter.
	Example:
	time=4000
	[time_lang]
		es=6000
		es_PE=8000
	[/time_lang]
	If Wesnoth language is Spanish (Paraguay), message will be displayed for 8 seconds, else if other Spanish 6 seconds, else 4 seconds.
]=]
function wesnoth.wml_actions.fading_message(cfg)
	local skippable = cfg.skippable or false
	if (not skippable) or (not wesnoth.interface.is_skipping_messages()) then
		local message = cfg.message
		local delay_time = tonumber(cfg.time)
		local fade_time = tonumber(cfg.fade_time) or 100
		local matches = wesnoth.units.find_on_map(cfg)
		local time_lang = wml.get_child(cfg, "time_lang")
		if time_lang ~= nil then
			local system_lang = wesnoth.get_language()
			for k,v in pairs(time_lang) do
				if string.len(k) == 2 then
					local lang = k
					if lang == string.sub(system_lang, 1, 2) then
						delay_time = tonumber(v)
					end
				end
			end
			for k,v in pairs(time_lang) do
				if string.len(k) > 2 then
					local lang = k
					if lang == system_lang then
						delay_time = tonumber(v)
					end
				end
			end
		end
		if fade_time > delay_time then
			delay_time = fade_time
		end
		if matches ~= nil then
			local caption = cfg.caption or matches[1].name
			local unit_x = matches[1].x
			local unit_y = matches[1].y
			wesnoth.interface.highlight_hex(unit_x, unit_y)
			local options = {}
			options.max_width = "80%"
			options.color = "FFFFFF"
			options.bgcolor = "000000"
			options.duration = delay_time - fade_time
			options.fade_time = fade_time
			options.halign="center"
			options.valign="bottom"
			options.location={0,100}
			local handle = wesnoth.interface.add_overlay_text("<span size='x-large'>" .. caption .. "</span>\n<span size='large'>" .. message .. "</span>", options)
			wesnoth.interface.delay(delay_time)
			wesnoth.interface.deselect_hex()
		end
	end
end

---
-- Shows a simple dialog with a scrollable image.
--
-- [show_image_dialog]
--     image=path/to/image_file
-- [/show_image_dialog]
---
function wesnoth.wml_actions.show_image_dialog(cfg)
	local image_path = cfg.image
	function pre_show(self)
		self.image.label = image_path
	end
	local dialog_wml = wml.load("~add-ons/Flight_Freedom/gui/image_dialog.cfg")
	gui.show_dialog(wml.get_child(dialog_wml, 'resolution'), pre_show)
end

function wesnoth.wml_actions.skip_messages(cfg)
	wesnoth.interface.skip_messages(true)
end

function wesnoth.wml_actions.unskip_messages(cfg)
	wesnoth.interface.skip_messages(false)
end

-- CAUTION: This disables end turn during unit selection and afterwards enables it.
-- If you wish for end turn to be disabled afterward, you should call allow_end_turn(false) afterward.
-- Logic inspired in part by God Game Magic Mod
function select_tile(caption, validator_func, action_func, cancel_func)
	wesnoth.interface.allow_end_turn(false)
	local width = math.floor(wesnoth.current.map.width / 2)
	local height = math.floor(wesnoth.current.map.height / 2)
	local step_guide = wesnoth.interface.add_overlay_text("")
	local old_on_mouse_move = wesnoth.game_events.on_mouse_move or (function() end)
	wesnoth.game_events.on_mouse_move = function(x, y)
		step_guide:remove(0)
		step_guide = wesnoth.interface.add_overlay_text(caption, {location = {(x-width)*5,(-y+height)*5+190}, duration = "unlimited", valign = "bottom", halign = "center", size = 20, bgcolor={0,0,0}, color={255,255,100}, bgalpha=80})
	end
	local old_on_mouse_button = wesnoth.game_events.on_mouse_button or (function() end)
	wesnoth.game_events.on_mouse_button = function(x, y, button, event)
		if button == "left" and event == "up" then
			wesnoth.interface.select_unit()
			if validator_func(x, y) then
				wesnoth.game_events.on_mouse_move = old_on_mouse_move
				wesnoth.game_events.on_mouse_button = old_on_mouse_button
				step_guide:remove(0)
				action_func(x, y)
				wesnoth.interface.allow_end_turn(true)
			end
		elseif button == "right" and event == "click" then
			wesnoth.game_events.on_mouse_move = old_on_mouse_move
			wesnoth.game_events.on_mouse_button = old_on_mouse_button
			step_guide:remove(0)
			wesnoth.interface.allow_end_turn(true)
			if cancel_func then cancel_func() end
			return true
		end
	end
end

---
-- misc functions from EoMA, primarily used to facilitate custom abilities for elementals
---
function wesnoth.wml_actions.remove_array_duplicates(cfg)
	local name = cfg.name
	local attribute = cfg.attribute

	local values = {}
	local inArray = wml.array_access.get(name)
	local outArray = {}
	for _, u in pairs(inArray) do
		if values[u[attribute]] == nil then
			values[u[attribute]] = true
			table.insert(outArray, u)
		end
	end
	wml.array_access.set(name, outArray)
end

function wesnoth.wml_actions.EoMa_remember_indirectly_damaged_unit(cfg)
	wesnoth.wml_actions.store_unit{
		wml.tag.filter{
			x=cfg.x,
			y=cfg.y
		},
		variable="EoMa_indirectly_damaged_unit",
		mode="append"
	}
end
