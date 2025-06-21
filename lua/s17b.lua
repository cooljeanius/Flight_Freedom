-- Lua code used by scenario 17B (Parched Sands)

local _ = wesnoth.textdomain "wesnoth-Flight_Freedom"

--spaces need to be converted to underscores to serialize properly
local food_value_by_type = {
	["Sheep"] = 10,
	["Desert_Lion"] = 6,
	["Cow"] = 15,
	["Crow"] = 3,
	["Raven"] = 3,
	["Falcon"] = 3,
	["Roc"] = 30,
	["Wild_Wyvern"] = 30,
	["Cave_Bear"] = 25,
	["Work_Horse"] = 10,
}

local human_food_value = 3

local food_needed = 130
if wesnoth.scenario.difficulty == "EASY" then food_needed = 110
elseif wesnoth.scenario.difficulty == "HARD" then food_needed = 150
end
wml.variables["food_needed"] = food_needed

local food_kills = {}
if wml.variables["food_kills"] ~= nil then
	food_kills = wml.variables["food_kills"]
end

local function get_total_food()
	local total_food = 0
	for unit_type,kill_count in pairs(food_kills) do
		local food = kill_count * food_value_by_type[unit_type]
		total_food = total_food + food
	end
	if wml.variables["turned_cannibal"] == true then
		total_food = total_food + wml.variables["humans_eaten"] * human_food_value
	end
	return total_food
end

function wesnoth.wml_actions.get_total_food(cfg)
	local varname = cfg.variable or "total_food"
	wml.variables[varname] = get_total_food()
end

function wesnoth.wml_actions.show_food_table(cfg)
	function pre_show(self)
		local total_food = get_total_food()
		local total_food_label = ""
		if total_food >= food_needed then
			total_food_label = stringx.vformat(_"Food acquired: <b><span color='green'>$value</span></b>", {value=total_food})
		else
			total_food_label = stringx.vformat(_"Food acquired: <b><span color='red'>$value</span></b>", {value=total_food})
		end
		self.total_food.label = total_food_label
		local food_needed_label = stringx.vformat(_"Food needed: <b>$value</b>", {value=food_needed})
		self.food_needed.label = food_needed_label

		local listbox = self.kills
		for raw_unit_type,kill_count in pairs(food_kills) do
			local unit_type = string.gsub(raw_unit_type, "_", " ")
			local new_item = listbox:add_item()
			new_item.image.label = wesnoth.unit_types[unit_type].image
			new_item.unit_type_string.label = wesnoth.unit_types[unit_type].name
			new_item.food_value.label = tostring(food_value_by_type[raw_unit_type])
			new_item.count.label = tostring(kill_count)
			new_item.food.label = tostring(kill_count * food_value_by_type[raw_unit_type])
		end
		if wml.variables["turned_cannibal"] == true then
			local new_item = listbox:add_item()
			new_item.image.label = "units/human-peasants/peasant-defend.png"
			new_item.unit_type_string.label = _"Human"
			new_item.food_value.label = tostring(human_food_value)
			new_item.count.label = tostring(wml.variables["humans_eaten"])
			new_item.food.label = tostring(wml.variables["humans_eaten"] * human_food_value)
		end
	end

	local dialog_wml = wml.load("~add-ons/Flight_Freedom/gui/food_table.cfg")
	gui.show_dialog(wml.get_child(dialog_wml, 'resolution'), pre_show)
end

local function float_food_label(x, y, value)
	local float_label = stringx.vformat(_"<span color='green'>+$value food</span>", {value=value})
	wesnoth.interface.float_label(x, y, float_label)
end

function wesnoth.wml_actions.add_food(cfg)
	local unit = wesnoth.units.get(cfg.x, cfg.y)
	local unit_race = unit.race
	if (wml.variables["turned_cannibal"] == true) and (unit_race == "human" or unit_race == "dunefolk") then
		wml.variables["humans_eaten"] = wml.variables["humans_eaten"] + 1
		float_food_label(cfg.x, cfg.y, human_food_value)
	else
		local unit_type = unit.type
		local raw_unit_type = string.gsub(unit_type, " ", "_")
		if food_value_by_type[raw_unit_type] ~= nil then
			food_kills[raw_unit_type] = (food_kills[raw_unit_type] or 0) + 1
			wml.variables["food_kills"] = food_kills
			float_food_label(cfg.x, cfg.y, food_value_by_type[raw_unit_type])
		end
	end
end
