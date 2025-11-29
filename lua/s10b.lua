-- Lua code used by scenario 10B (Freezing Foothills)

local _ = wesnoth.textdomain "wesnoth-Flight_Freedom"

-- add fire damage reduction to UI
local old_unit_weapons_theme = wesnoth.interface.game_display.unit_weapons
function wesnoth.interface.game_display.unit_weapons()
	local new_unit_weapons_theme = old_unit_weapons_theme()
	local u = wesnoth.interface.get_displayed_unit()
	if u then
		local attack = wesnoth.units.find_attack(u, {range="ranged", type="fire"})
		if attack and u.race=="drake" then
			local fire_reduction = wml.variables["fire_reduction"]
			if fire_reduction ~= "-0%" then
				local fire_reduction_num = string.sub(fire_reduction, 2, -2)
				local table_text = stringx.vformat(_"<span color='red'>CHILL: -$value%</span>", {value=fire_reduction_num})
				local tooltip_text = stringx.vformat(_"The freezing cold is chilling your drakes' fire breath! Fire attacks do $value% less damage.", {value=fire_reduction_num})
				table.insert(new_unit_weapons_theme, wml.tag.element {
					text=table_text,
					tooltip=tooltip_text
				})
			end
		end
	end
	return new_unit_weapons_theme
end

-- places where recall list units can spawn
local recall_spawn_locs = {}
table.insert(recall_spawn_locs,{1,7})
table.insert(recall_spawn_locs,{2,5})
table.insert(recall_spawn_locs,{3,6})
table.insert(recall_spawn_locs,{4,6})
table.insert(recall_spawn_locs,{5,6})
table.insert(recall_spawn_locs,{6,5})
table.insert(recall_spawn_locs,{7,6})
table.insert(recall_spawn_locs,{8,6})
table.insert(recall_spawn_locs,{9,7})
table.insert(recall_spawn_locs,{10,6})
table.insert(recall_spawn_locs,{12,6})
table.insert(recall_spawn_locs,{13,7})
table.insert(recall_spawn_locs,{14,7})
table.insert(recall_spawn_locs,{15,8})
table.insert(recall_spawn_locs,{16,6})
table.insert(recall_spawn_locs,{17,7})
table.insert(recall_spawn_locs,{18,6})
table.insert(recall_spawn_locs,{19,7})
table.insert(recall_spawn_locs,{20,6})
table.insert(recall_spawn_locs,{21,5})
table.insert(recall_spawn_locs,{22,4})
table.insert(recall_spawn_locs,{23,5})

function wesnoth.wml_actions.get_recall_spawn_loc(cfg)
	local recall_spawn_loc = recall_spawn_locs[mathx.random(1, #recall_spawn_locs)]
	wml.variables["recall_x"] = recall_spawn_loc[1]
	wml.variables["recall_y"] = recall_spawn_loc[2]
end

-- probability of a tile getting snowed with each check (based on base terrain only)
local terrain_snow_prob = {}
terrain_snow_prob["Gd"] = 0.2
terrain_snow_prob["Gll"] = 0.2
terrain_snow_prob["Gg"] = 0.2
terrain_snow_prob["Gs"] = 0.2
terrain_snow_prob["Rb"] = 0.2
terrain_snow_prob["Re"] = 0.2
terrain_snow_prob["Ww"] = 0.1
terrain_snow_prob["Hhd"] = 0.3
terrain_snow_prob["Md"] = 0.4
terrain_snow_prob["Ce"] = 0.1
terrain_snow_prob["Ke"] = 0.1
terrain_snow_prob["Co"] = 0.1
terrain_snow_prob["Ko"] = 0.1

-- if tile to get snowed, table of base terrain codes to convert
local terrain_to_snow = {}
terrain_to_snow["Gd"] = "Aa"
terrain_to_snow["Gll"] = "Aa"
terrain_to_snow["Gg"] = "Aa"
terrain_to_snow["Gs"] = "Aa"
terrain_to_snow["Rb"] = "Aa"
terrain_to_snow["Re"] = "Aa"
terrain_to_snow["Ww"] = "Ai"
terrain_to_snow["Hhd"] = "Ha"
terrain_to_snow["Md"] = "Ms"
terrain_to_snow["Ce"] = "Cea"
terrain_to_snow["Ke"] = "Kea"
terrain_to_snow["Co"] = "Coa"
terrain_to_snow["Ko"] = "Koa"

-- if tile to get snowed, table of overlay terrain codes to convert
local overlay_to_snow = {}
overlay_to_snow["Fp"] = "Fpa"
overlay_to_snow["Fmw"] = "Fma"
overlay_to_snow["Vh"] = "Vha"
overlay_to_snow["Vhh"] = "Vhha"
overlay_to_snow["Fet"] = "Feta"

function wesnoth.wml_actions.snow_loc(cfg)
	local loc_x = tonumber(cfg.x)
	local loc_y = tonumber(cfg.y)
	-- if guarantee, skip probability check and convert the tile
	local guarantee = cfg.guarantee or false
	local terrain_code = wesnoth.current.map[{loc_x, loc_y}]
	local new_terrain = terrain_code
	local base, overlay = wesnoth.map.split_terrain_code(terrain_code)
	if terrain_snow_prob[base] ~= nil then
		if guarantee or mathx.random() < terrain_snow_prob[base] then
			new_terrain = terrain_to_snow[base]
			if overlay ~= nil then
				if overlay_to_snow[overlay] ~= nil then
					overlay = overlay_to_snow[overlay]
				end
				new_terrain = new_terrain .. "^" .. overlay
			end
			wesnoth.current.map[{loc_x, loc_y}] = new_terrain
		end
	end
end
