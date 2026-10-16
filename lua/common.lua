--- return a replay-safe (by default) random number sampled from specified normal distribution
function random_norm(mean, sd, random_func)
	random_func = random_func or mathx.random
	local u = 1.0 - random_func()
	local v = 1.0 - random_func()
	local n = math.sqrt(-2.0 * math.log(u)) * math.cos(2.0 * math.pi * v)
	local r = (n * sd) + mean
	return r
end

function norm_pdf(x, mean, sd)
	return math.exp(-1.0*((x-mean)^2)/(2.0*sd*sd)) / math.sqrt(2.0 * math.pi * sd * sd)
end

--- randomly generate k integers from 1 to n without replacement
--- integers are returned in sorted order
function random_sample_wor(k, n, random_func)
	random_func = random_func or mathx.random
	local reservoir = {}
	assert(k <= n)
	if k > 0 then
		for i = 1, k do
			table.insert(reservoir, i)
		end
		local w = math.exp(math.log(1.0 - random_func()) / k)
		local i = k
		while i <= n do
			i = i + math.floor(math.log(1.0 - random_func()) / math.log(1 - w)) + 1
			if i <= n then
				reservoir[random_func(1, k)] = i
				w = w * math.exp(math.log(1.0 - random_func()) / k)
			end
		end
		table.sort(reservoir)
	end
	return reservoir
end

function trunc(n)
	if n >= 0.0 then
		return math.floor(n)
	else
		return math.ceil(n)
	end
end

--- adjusts side numbers in the sidebar to 'skip over' listed sides
--- e.g. in 17A (Blockade) used so that depthstalkers appear the same side as the main naga force
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

--- Conditional tag if viewing a replay
--
-- [if]
--     [replay_mode]
--     [/replay_mode]
--     [then]
--         ...
--     [/then]
-- [/if]
---
function wesnoth.wml_conditionals.replay_mode(cfg)
	return wesnoth.current.user_is_replaying
end


--[=[
[has_possible_actions]
Author: MadMax (username on the Battle for Wesnoth forum)

Returns false if all units on a side have both 0 mp and, if next to an enemy, 0 attacks.
Otherwise returns true.

Required keys:
side: side to check (defaults to 1)
]=]
function wesnoth.wml_conditionals.has_possible_actions(cfg)
	local side = cfg.side or 1
	local result = false
	local units = wesnoth.units.find_on_map{side=side}
	for i, u in ipairs(units) do
		if u.moves > 0 then
			result = true
			break
		end
		if u.attacks_left > 0 then
			local adjacent_units = wesnoth.units.find_on_map{x=u.x, y=u.y, wml.tag.filter_adjacent{is_enemy=true}}
			if #adjacent_units > 0 then
				result = true
				break
			end
		end
	end
	return result
end

--[=[
[has_item]
Author: MadMax (username on the Battle for Wesnoth forum)

Test for existence of specific [item]s.

Required keys:
image: string to search for in item's image, halo, or name attribute

Optional keys:
StandardLocationFilter for locations to search for item
]=]
function wesnoth.wml_conditionals.has_item(cfg)
	local found = false
	local image = cfg.image
	cfg = wml.parsed(cfg)
	cfg.image = nil
	local locs = wesnoth.map.find(cfg)
	for i, hex in ipairs(locs) do
		local items_list = wesnoth.interface.get_items(hex[1], hex[2])
		for j, item in ipairs(items_list) do
			if item.name ~= nil and item.name == image then
				found = true
			elseif item.halo ~= nil and item.halo == image then
				found = true
			elseif item.image ~= nil and item.image == image then
				found = true
			end
			if found then
				break
			end
		end
	end
	return found
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

function show_image_dialog(image_path)
	local function pre_show(self)
		self.image.label = image_path
	end
	local dialog_wml = wml.load("~add-ons/Flight_Freedom/gui/image_dialog.cfg")
	gui.show_dialog(wml.get_child(dialog_wml, 'resolution'), pre_show)
end

---
-- Shows a simple dialog with a scrollable image.
--
-- [show_image_dialog]
--     image=path/to/image_file
-- [/show_image_dialog]
---
function wesnoth.wml_actions.show_image_dialog(cfg)
	show_image_dialog(cfg.image)
end

function show_text_box_dialog(text)
	local function pre_show(self)
		self.text.label = text
	end
	local dialog_wml = wml.load("~add-ons/Flight_Freedom/gui/text_box_dialog.cfg")
	gui.show_dialog(wml.get_child(dialog_wml, 'resolution'), pre_show)
end

function show_text_box_borderless_dialog(text)
	local function pre_show(self)
		self.text.label = text
	end
	local dialog_wml = wml.load("~add-ons/Flight_Freedom/gui/text_box_dialog_borderless.cfg")
	gui.show_dialog(wml.get_child(dialog_wml, 'resolution'), pre_show)
end

---
-- Shows a simple dialog with a scrollable text box.
--
-- [show_text_box_dialog]
--     text= ...
-- [/show_text_box_dialog]
---
function wesnoth.wml_actions.show_text_box_dialog(cfg)
	local borderless = cfg.borderless or false
	if borderless then
		show_text_box_borderless_dialog(cfg.text)
	else
		show_text_box_dialog(cfg.text)
	end
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

-- Find the unit which matches provided SUF that is closest to target_x and target_y
-- If multiple units are equidistant, which unit is selected is arbitrary
function wesnoth.wml_actions.get_unit_closest_to(cfg)
	cfg = wml.literal(cfg)
	local varname = "closest_unit"
	if cfg.variable ~= nil then
		varname = cfg.variable
		cfg.variable = nil
	end
	local target_x = tonumber(cfg.target_x)
	local target_y = tonumber(cfg.target_y)
	cfg.target_x = nil
	cfg.target_y = nil
	local units_list = wesnoth.units.find_on_map(cfg)
	local return_unit_x = nil
	local return_unit_y = nil
	local current_dist = nil
	for i,unit in ipairs(units_list) do
		local dist = wesnoth.map.distance_between({unit.x, unit.y}, {target_x, target_y})
		if current_dist == nil or dist < current_dist then
			return_unit_x = unit.x
			return_unit_y = unit.y
			current_dist = dist
		end
	end
	wml.fire("store_unit", {wml.tag.filter{x=return_unit_x, y=return_unit_y}, variable=varname})
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
