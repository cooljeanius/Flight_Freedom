-- Lua code used by scenario 11B (Sol'kan's Lair)

local _ = wesnoth.textdomain "wesnoth-Flight_Freedom"

local functional = wesnoth.require("functional")
wesnoth.dofile('~add-ons/Flight_Freedom/lua/dungeonmapgen.lua')

------------------------
----- dynamic difficulty handling functions
------------------------

-- since it's just Malakar and his loadout's quite variable
-- overall difficulty scales based on Malakar and set difficulty
function calc_difficulty_score()
	local score = 1
	if wesnoth.scenario.difficulty == "NORMAL" then
		score = score + 2
	end
	if wesnoth.scenario.difficulty == "HARD" then
		score = score + 4
	end
	local malakar = wesnoth.units.get("Malakar")
	score = score + malakar.level
	-- from S7B
	-- ignore drain special since player faces undead and automatons
	if malakar.variables["has_elemental_powerup"] and wml.variables["malakar_powerup"] ~= "earth" then
		score = score + 1
	end
	-- from S3A
	if malakar.variation ~= nil and malakar.variation == "weapon" then
		score = score + 1
	end
	wml.variables["difficulty_score"] = score
	return score
end

-- generate a list of numbers of length list_length, summing to level_sum, with no number > max_level
local function get_random_level_list(list_length, level_sum, max_level)
	local levels = {}
	local breakpoints = random_sample_wor(list_length, level_sum)
	local current_floor = 0
	local total_levels = 0
	for i, j in ipairs(breakpoints) do
		local level = j - current_floor
		current_floor = current_floor + level
		if level > max_level then
			level = max_level
		end
		table.insert(levels, level)
		total_levels = total_levels + level
	end
	local extra_levels = level_sum - total_levels
	-- distribute extra levels randomly
	while extra_levels > 0 do
		local random_idx = mathx.random(1, list_length)
		if levels[random_idx] < max_level then
			levels[random_idx] = levels[random_idx] + 1
			extra_levels = extra_levels - 1
		end
	end
	return levels
end

function set_scenario_globals()
	wesnoth.game_config.do_healing = false
	wesnoth.game_config.rest_heal_amount = 0
	wesnoth.game_config.base_income = 0
	wesnoth.game_config.combat_experience = 0
	wesnoth.game_config.kill_experience = 0
end

------------------------
----- ui functions
------------------------

function hide_ui_elements()
	local function null_theme_func()
		return {}
	end

	local old_gold_theme = wesnoth.interface.game_display.gold
	local old_villages_theme = wesnoth.interface.game_display.villages
	local old_num_units_theme = wesnoth.interface.game_display.num_units
	local old_upkeep_theme = wesnoth.interface.game_display.upkeep
	local old_income_theme = wesnoth.interface.game_display.income
	wesnoth.interface.game_display.gold = null_theme_func
	wesnoth.interface.game_display.villages = null_theme_func
	wesnoth.interface.game_display.num_units = null_theme_func
	wesnoth.interface.game_display.upkeep = null_theme_func
	wesnoth.interface.game_display.income = null_theme_func
end

local journal_window_def = wml.load('~add-ons/Flight_Freedom/gui/journal_window.cfg')
gui.add_widget_definition("window", "journal", wml.get_child(journal_window_def, "window_definition"))

local function show_journal_dialog(text, font)
	local text_font = font
	if text_font == nil then
		if wesnoth.current_version() >= wesnoth.version("1.19.15") then
			text_font = "WesScript"
		else
			text_font = "Oldania ADF Std"
		end
	end
	local function pre_show(self)
		self.text.label = "<span font_family='" .. text_font .. "' size='xx-large' color='#000000'>" .. text .. "</span>"
	end
	local dialog_wml = wml.load("~add-ons/Flight_Freedom/gui/journal_dialog.cfg")
	gui.show_dialog(wml.get_child(dialog_wml, 'resolution'), pre_show)
end

function wesnoth.wml_actions.show_journal_dialog(cfg)
	show_journal_dialog(cfg.text, cfg.font)
end

local function add_terrain_overlay(x, y, overlay_code)
	local terrain_code = wesnoth.current.map[{x, y}]
	local base, overlay = wesnoth.map.split_terrain_code(terrain_code)
	wesnoth.current.map[{x, y}] = base .. "^" .. overlay_code
end

-- facilitate persistent location-based events in savegame which can be triggered from wml space
local function hex_list_to_wml_var(hex_list, x_var, y_var)
	local x_string = table.concat(functional.map(hex_list, function(i) return i[1] end), ",")
	local y_string = table.concat(functional.map(hex_list, function(i) return i[2] end), ",")
	wml.variables[x_var] = x_string
	wml.variables[y_var] = y_string
end

local function hex_to_wml_var(hex, x_var, y_var)
	wml.variables[x_var] = hex[1]
	wml.variables[y_var] = hex[2]
end

------------------------
----- room definitions
------------------------

-- keep this separate for name-indexed dictionaries (making them upfront causes wmlxgettext to choke)
local colors_list = {"red", "blue", "green", "white", "black", "yellow"}
local orb_colors_desc_tr = {
	_"Red Orb",
	_"Blue Orb",
	_"Green Orb",
	_"White Orb",
	_"Black Orb",
	_"Yellow Orb",
}
local orb_colors_desc = {}
for i, s in pairs(colors_list) do
	orb_colors_desc[s] = orb_colors_desc_tr[i]
end

StartRoom = Room:new()

function StartRoom:new(o)
	o = o or Room:new()
	setmetatable(o, self)
	self.__index = self
	self:set_dimensions(8, 8)
	return o
end

-- since we need the cave entrance and start variables set before other rooms are instantiated
function StartRoom:initial_setup()
	self:set_inner_terrain("Isa")
	self:set_wall_terrain("Xor")
	-- cave passage in
	wesnoth.wml_actions.terrain_mask({
		mask = filesystem.read_file("~add-ons/Flight_Freedom/masks/11b_cave_entrance.mask"),
		x = self.x1,
		y = self.y1 + 1,
		border = true,
	})
	local malakar_start_x = self.x1 + 6
	local malakar_start_y = self.y1
	wesnoth.units.get("Malakar"):to_map(malakar_start_x, malakar_start_y)
	local q, r, s = table.unpack(get_cubic({malakar_start_x, malakar_start_y}))
	local malakar_run_x, malakar_run_y = table.unpack(from_cubic(q-6, r+6, s))
	wml.variables["malakar_run_x"] = malakar_run_x
	wml.variables["malakar_run_y"] = malakar_run_y
	wml.variables["malakar_start_x"] = malakar_start_x
	wml.variables["malakar_start_y"] = malakar_start_y
	wesnoth.interface.add_item_image(malakar_start_x, malakar_start_y, "scenery/castle-ruins3.png")
end

ControlRoom = Room:new()

function ControlRoom:new(o)
	o = o or Room:new()
	setmetatable(o, self)
	self.__index = self
	self:set_dimensions(11, 9)
	return o
end

function ControlRoom:pre_corridor_setup()
	self:set_inner_terrain("Fypd")
	self:set_wall_terrain("Xoi") -- white wall
	local machine_x, machine_y = table.unpack(self:get_approx_center())
	wml.variables["machine_x"] = machine_x
	wml.variables["machine_y"] = machine_y
	wesnoth.interface.add_item_halo(machine_x - 2, machine_y, "terrain/electrode-thingy-[1,2~9,8,9,8,9,1].png~NO_TOD_SHIFT():[2000,100*8,50*5]")
	wesnoth.interface.add_item_halo(machine_x + 2, machine_y, "terrain/pump-thingy-[1,2~15,1].png~NO_TOD_SHIFT():[2000,100*15]")
	wesnoth.interface.add_item_halo(machine_x, machine_y - 1, "terrain/reactor-thingy-[1~4,3~1,1,1~4,3~1,1,5~11,10~5,1,1].png~NO_TOD_SHIFT():[250*4,250*3,1000,250*4,250*3,2000,50*7,50*6,50,2000]")
	wesnoth.interface.add_item_halo(machine_x, machine_y + 1, "terrain/reactor-thingy-[1~4,3~1,1,1~4,3~1,1,5~11,10~5,1,1].png~NO_TOD_SHIFT():[250*4,250*3,1000,250*4,250*3,2000,50*7,50*6,50,2000]")
	local q, r, s = table.unpack(get_cubic({machine_x, machine_y}))
	local thingy_x, thingy_y = table.unpack(from_cubic(q-1, r+1, s))
	wesnoth.interface.add_item_halo(thingy_x, thingy_y, "terrain/popup-thingy-[1,2~18,18,19,20,19,18,19,20,19,18,19,20,19,18,17~1,1].png~NO_TOD_SHIFT():[2000,100*17,500,250*11,500,75*17,75]")
	wesnoth.interface.add_item_halo(thingy_x, thingy_y - 1, "terrain/popup-thingy-[1,2~18,18,19,20,19,18,19,20,19,18,19,20,19,18,17~1,1].png~NO_TOD_SHIFT():[2000,100*17,500,250*11,500,75*17,75]")
	thingy_x, thingy_y = table.unpack(from_cubic(q+1, r, s-1))
	wesnoth.interface.add_item_halo(thingy_x, thingy_y, "terrain/popup-thingy-[1,2~18,18,19,20,19,18,19,20,19,18,19,20,19,18,17~1,1].png~NO_TOD_SHIFT():[2000,100*17,500,250*11,500,75*17,75]")
	wesnoth.interface.add_item_halo(thingy_x, thingy_y - 1, "terrain/popup-thingy-[1,2~18,18,19,20,19,18,19,20,19,18,19,20,19,18,17~1,1].png~NO_TOD_SHIFT():[2000,100*17,500,250*11,500,75*17,75]")
	--q = q - 1
	--r = r + 1
	wesnoth.interface.add_item_halo(machine_x, machine_y, "scenery/sentinel.png")
	wesnoth.interface.add_item_halo(machine_x, machine_y, "scenery/sentinel-glo.png")
	local console_x = machine_x
	local console_y = machine_y - 3
	add_terrain_overlay(console_x, console_y, "Skyc")
	wml.variables["console_x"] = console_x
	wml.variables["console_y"] = console_y
	local engine_inst_x, engine_inst_y = table.unpack(from_cubic(q - 1, r - 2, s + 3))
	wesnoth.interface.add_item_image(engine_inst_x, engine_inst_y, "items/book1.png")
	wml.variables["engine_inst_x"] = engine_inst_x
	wml.variables["engine_inst_y"] = engine_inst_y
	wesnoth.interface.add_item_halo(machine_x, machine_y, "scenery/engine-shield.png")
	wesnoth.wml_actions.terrain_mask({
		mask = filesystem.read_file("~add-ons/Flight_Freedom/masks/11b_control_room_blocker.mask"),
		x = machine_x - 2,
		y = machine_y - 2,
		border = true,
		wml.tag.rule {
			layer = "overlay",
		},
	})
	hex_list_to_wml_var(self:get_inner_hexes(), "control_room_x", "control_room_y")
end

OrbRoom = Room:new()

function OrbRoom:new(o)
	o = o or Room:new()
	setmetatable(o, self)
	self.__index = self
	o.color = ""
	self:set_dimensions(5, 5)
	return o
end

function OrbRoom:set_color(color)
	self.color = color
end

function OrbRoom:get_orb_hex()
	return {self.x1 + 4, self.y1}
end

function OrbRoom:get_guard_hex()
	return {self.x1 + 4, self.y1 - 1}
end

function OrbRoom:pre_corridor_setup()
	self:set_inner_terrain("Isa")
	local orb_x = self.x1 + 4
	local orb_y = self.y1
	wesnoth.interface.add_item_image(orb_x, orb_y, "items/altar.png")
	local orb_image_path = "items/magic-orb.png~RC(magenta>" .. self.color .. ")"
	wesnoth.interface.add_item_image(orb_x, orb_y, orb_image_path)
	wesnoth.interface.add_item_image(orb_x, orb_y - 1, "units/monsters/automaton-defender.png~RC(magenta>green)~NO_TOD_SHIFT()")
end

LibraryRoom = Room:new()

function LibraryRoom:new(o)
	o = o or Room:new()
	setmetatable(o, self)
	self.__index = self
	self:set_dimensions(12, 7)
	return o
end

function LibraryRoom:pre_corridor_setup()
	self:set_inner_terrain("Iwr") -- wood floor
	self:set_wall_terrain("Xoc") -- clean stone wall
	-- place furniture
	local q, r, s = table.unpack(get_cubic({self.x1 + 6, self.y1}))
	q = q - 1
	r = r + 1
	for i = 1, 8 do
		local hex = from_cubic(q, r, s)
		if i == 1 or i == 3 or i == 6 or i == 8 then
			wesnoth.interface.add_item_image(hex[1], hex[2], "scenery/dinnertable.png")
		end
		q = q + 1
		r = r - 1
	end
	q, r, s = table.unpack(get_cubic({self.x1 + 6, self.y1}))
	q = q - 2
	r = r + 1
	s = s + 1
	for i = 1, 8 do
		local hex = from_cubic(q, r, s)
		if i == 1 or i == 3 or i == 6 or i == 8 then
			wesnoth.interface.add_item_image(hex[1], hex[2], "scenery/chairSE.png")
		end
		q = q + 1
		r = r - 1
	end
	q, r, s = table.unpack(get_cubic({self.x1 + 6, self.y1}))
	r = r + 1
	s = s - 1
	for i = 1, 8 do
		local hex = from_cubic(q, r, s)
		if i == 1 or i == 3 or i == 6 or i == 8 then
			wesnoth.interface.add_item_image(hex[1], hex[2], "scenery/chairNW.png")
		end
		q = q + 1
		r = r - 1
	end
	q, r, s = table.unpack(get_cubic({self.x1 + 2, self.y1}))
	for i = 1, 10 do
		local hex = from_cubic(q, r, s)
		local hex_to_check = from_cubic(q - 1, r, s + 1)
		local full_shelf = mathx.random(1, 2)
		if full_shelf == 1 then
			wesnoth.interface.add_item_image(hex[1], hex[2], "scenery/bookshelf-full.png")
		else
			wesnoth.interface.add_item_image(hex[1], hex[2], "scenery/bookshelf.png")
		end
		q = q + 1
		r = r - 1
	end
	-- randomly place lore/flavor books
	local possible_book_hexes = self:get_inner_hexes()
	mathx.shuffle(possible_book_hexes)
	local num_books_placed = 0
	for i, hex in ipairs(possible_book_hexes) do
		if #wesnoth.interface.get_items(hex[1], hex[2]) == 0 then
			if num_books_placed == 0 then
				wesnoth.interface.add_item_image(hex[1], hex[2], "items/blueprints.png")
				wml.variables["blueprint_x"] = hex[1]
				wml.variables["blueprint_y"] = hex[2]
			elseif num_books_placed == 1 then
				wesnoth.interface.add_item_image(hex[1], hex[2], "items/book3.png")
				wml.variables["isle_book_x"] = hex[1]
				wml.variables["isle_book_y"] = hex[2]
			elseif num_books_placed == 2 then
				wesnoth.interface.add_item_image(hex[1], hex[2], "items/book4.png")
				wml.variables["lab_book_x"] = hex[1]
				wml.variables["lab_book_y"] = hex[2]
			elseif num_books_placed == 3 then
				-- would like to have a factory room if there's suitable graphics
				-- if so, this would be more appropriate going there
				wesnoth.interface.add_item_image(hex[1], hex[2], "items/book6.png")
				wml.variables["automata_book_x"] = hex[1]
				wml.variables["automata_book_y"] = hex[2]
				break
			end
			num_books_placed = num_books_placed + 1
		end
	end
end

function LibraryRoom:post_corridor_setup()
	-- remove any bookshelves that would visually block off a corridor
	local q, r, s = table.unpack(get_cubic({self.x1 + 2, self.y1}))
	for i = 1, 10 do
		local hex = from_cubic(q, r, s)
		local hex_to_check = from_cubic(q - 1, r, s + 1)
		if string.sub(wesnoth.current.map[hex_to_check], 1, 1) ~= "X" then
			wesnoth.interface.remove_item(hex[1], hex[2], "scenery/bookshelf-full.png")
			wesnoth.interface.remove_item(hex[1], hex[2], "scenery/bookshelf.png")
		end
		q = q + 1
		r = r - 1
	end
end

-- Sol'kan's living quarters
BedRoom = Room:new()

function BedRoom:new(o)
	o = o or Room:new()
	setmetatable(o, self)
	self.__index = self
	self:set_dimensions(7, 5)
	return o
end

function BedRoom:pre_corridor_setup()
	self:set_inner_terrain("Iwr")
	wesnoth.wml_actions.terrain_mask({
		mask = filesystem.read_file("~add-ons/Flight_Freedom/masks/11b_bedroom.mask"),
		x = self.x1,
		y = self.y1 - 2,
		border = true,
	})
	local inner_hexes = self:get_inner_hexes()
	for i, hex in ipairs(inner_hexes) do
		if wesnoth.current.map[{hex[1], hex[2]}] == "Iwr" and mathx.random(1, 2) == 1 then
			wesnoth.current.map[{hex[1], hex[2]}] = "Iwo" -- old wood floor
		end
	end
	wesnoth.interface.add_item_image(self.x1 + 6, self.y1 - 1, "scenery/bed-fancy-sw.png")
	local q, r, s = table.unpack(get_cubic({self.x1 + 6, self.y1 - 1}))
	local journal_x, journal_y = table.unpack(from_cubic(q+1, r, s-1))
	wml.variables["journal_x"] = journal_x
	wml.variables["journal_y"] = journal_y
	wesnoth.interface.add_item_image(journal_x, journal_y, "items/book2.png")
	local chair_x, chair_y = table.unpack(from_cubic(q-2, r+2, s))
	wesnoth.interface.add_item_image(chair_x, chair_y, "scenery/chair-2-nw.png~SCALE(100,100)")
	local desk_x, desk_y = table.unpack(from_cubic(q-3, r+2, s-1))
	wesnoth.interface.add_item_image(desk_x, desk_y, "scenery/desk-se.png")
	local wardrobe_x, wardrobe_y = table.unpack(from_cubic(q+1, r-1, s))
	wesnoth.interface.add_item_image(wardrobe_x, wardrobe_y, "scenery/wardrobe-drawer-open.png")
end

PrisonRoom = Room:new()

function PrisonRoom:new(o)
	o = o or Room:new()
	setmetatable(o, self)
	self.__index = self
	self:set_dimensions(12, 9)
	return o
end

function PrisonRoom:place_cell_content(hex, content_type)
	if content_type == 1 then
		-- just a skeleton
		wesnoth.interface.add_item_image(hex[1], hex[2], "items/bones.png")
	elseif content_type == 2 then
		-- magic resist amulet
		wesnoth.interface.add_item_image(hex[1], hex[2], "items/bones.png~FL(horiz)~BLIT(items/ankh-necklace.png, 0, 10)")
		wml.variables["resist_amulet_x"] = hex[1]
		wml.variables["resist_amulet_y"] = hex[2]
	elseif content_type == 3 then
		wesnoth.units.to_map({type="Automaton Reaper", side=3}, hex[1], hex[2])
	end
	-- room type 4 is empty
end

function PrisonRoom:pre_corridor_setup()
	local room_content_ids = {1, 2, 3, 4}
	mathx.shuffle(room_content_ids)
	self:set_inner_terrain("Ur")
	wesnoth.wml_actions.terrain_mask({
		mask = filesystem.read_file("~add-ons/Flight_Freedom/masks/11b_prison.mask"),
		x = self.x1 + 2,
		y = self.y1 - 5,
		border = true,
		wml.tag.rule {
			layer = "overlay",
		},
	})
	local prison_lever_hexes = {}
	local prison_cell_idx = {}
	local q, r, s = table.unpack(get_cubic({self.x1 + 6, self.y1}))
	-- upper left door, cell #1
	q = q - 1
	r = r - 1
	s = s + 2
	local lever_hex = from_cubic(q, r, s)
	wesnoth.interface.add_item_image(lever_hex[1], lever_hex[2], "items/switch-left.png~XBRZ(2)")
	table.insert(prison_lever_hexes, lever_hex)
	table.insert(prison_cell_idx, 1)
	self:place_cell_content(from_cubic(q+1, r+1, s-2), room_content_ids[1])
	-- lower left door, cell #2
	q = q + 6
	s = s - 6
	lever_hex = from_cubic(q, r, s)
	wesnoth.interface.add_item_image(lever_hex[1], lever_hex[2], "items/switch-left.png~XBRZ(2)")
	table.insert(prison_lever_hexes, lever_hex)
	table.insert(prison_cell_idx, 2)
	self:place_cell_content(from_cubic(q-3, r+1, s+2), room_content_ids[2])
	-- lower right door, cell #4
	q = q + 3
	r = r - 3
	lever_hex = from_cubic(q, r, s)
	wesnoth.interface.add_item_image(lever_hex[1], lever_hex[2], "items/switch-left.png~XBRZ(2)")
	table.insert(prison_lever_hexes, lever_hex)
	table.insert(prison_cell_idx, 4)
	self:place_cell_content(from_cubic(q-1, r-1, s+2), room_content_ids[3])
	-- upper right door, cell #3
	q = q - 6
	s = s + 6
	lever_hex = from_cubic(q, r, s)
	wesnoth.interface.add_item_image(lever_hex[1], lever_hex[2], "items/switch-left.png~XBRZ(2)")
	table.insert(prison_lever_hexes, lever_hex)
	table.insert(prison_cell_idx, 3)
	self:place_cell_content(from_cubic(q+3, r-1, s-2), room_content_ids[4])

	hex_list_to_wml_var(prison_lever_hexes, "prison_levers_x", "prison_levers_y")
	wml.variables["prison_cell_idx"] = table.concat(prison_cell_idx, ",")
end

OperatingRoom = Room:new()

function OperatingRoom:new(o)
	o = o or Room:new()
	setmetatable(o, self)
	self.__index = self
	self:set_dimensions(9, 10)
	return o
end

function OperatingRoom:post_corridor_setup()
	wesnoth.wml_actions.terrain_mask({
		mask = filesystem.read_file("~add-ons/Flight_Freedom/masks/11b_operating_room.mask"),
		x = self.x1 + 2,
		y = self.y1 - 4,
		border = true,
	})
	local q, r, s = table.unpack(get_cubic({self.x1, self.y1}))
	q = q + 10
	r = r - 3
	s = s - 7
	local item_x, item_y = table.unpack(from_cubic(q, r, s))
	wesnoth.interface.add_item_image(item_x, item_y, "scenery/sink-metal.png")
	q = q + 2
	r = r - 2
	item_x, item_y = table.unpack(from_cubic(q, r, s))
	wesnoth.interface.add_item_image(item_x, item_y, "scenery/sink-metal.png")
	q = q - 4
	s = s + 4
	item_x, item_y = table.unpack(from_cubic(q, r, s))
	wesnoth.interface.add_item_image(item_x, item_y, "scenery/cabinet-metal.png")
	q = q - 2
	r = r + 2
	item_x, item_y = table.unpack(from_cubic(q, r, s))
	wesnoth.interface.add_item_image(item_x, item_y, "scenery/cabinet-metal.png")
	q = q + 2
	r = r - 1
	s = s - 1
	item_x, item_y = table.unpack(from_cubic(q, r, s))
	wesnoth.interface.add_item_image(item_x, item_y, "scenery/table-metal-1.png")
	q = q - 1
	s = s + 1
	item_x, item_y = table.unpack(from_cubic(q, r, s))
	wesnoth.interface.add_item_image(item_x, item_y, "scenery/surgical.png")
end

WorkshopRoom = Room:new()

function WorkshopRoom:new(o)
	o = o or Room:new()
	setmetatable(o, self)
	self.__index = self
	self:set_dimensions(9, 9)
	return o
end

function WorkshopRoom:pre_corridor_setup()
	self:set_inner_terrain("Isa")
	local q, r, s = table.unpack(get_cubic({self.x1, self.y1}))
	q = q + 4
	r = r - 2
	s = s - 2
	for i = 0, 2 do
		for j = 0, 2 do
			local hex_x, hex_y = table.unpack(from_cubic(q + (i * 2) + (j * 2), r - (i * 2), s - (j * 2)))
			local table_variant = mathx.random(2, 4)
			wesnoth.interface.add_item_image(hex_x, hex_y, "scenery/table-metal-" .. tostring(table_variant) .. ".png")
		end
	end
end

UndeadRoom = Room:new()

function UndeadRoom:new(o)
	o = o or Room:new()
	setmetatable(o, self)
	self.__index = self
	o.undead_levels = {}
	return o
end

function UndeadRoom:set_levels(levels)
	self.undead_levels = levels
end

function UndeadRoom:pre_corridor_setup()
	local malakar_start_x = wml.variables["malakar_start_x"]
	local malakar_start_y = wml.variables["malakar_start_y"]
	local map_size_x = wesnoth.current.map.playable_width
	local map_size_y = wesnoth.current.map.playable_height
	self:set_inner_terrain("Isa")
	self:set_wall_terrain("Xot") -- catacomb wall
	local room_wall_hexes = self:get_edge_hexes()
	for j, hex in ipairs(room_wall_hexes) do
		local rand_decor = mathx.random(1, 6)
		if rand_decor <= 2 then
			add_terrain_overlay(hex[1], hex[2], "Edb") -- remains
		elseif rand_decor == 3 then
			add_terrain_overlay(hex[1], hex[2], "Efs") -- brazier
		end
	end
	local room_inner_hexes = self:get_inner_hexes()
	mathx.shuffle(room_inner_hexes)
	for j, hex in ipairs(room_inner_hexes) do
		local rand_decor = mathx.random(1, 4)
		if rand_decor <= 3 then
			add_terrain_overlay(hex[1], hex[2], "Edb") -- remains
		end
	end
	for j, level in ipairs(self.undead_levels) do
		local hex = room_inner_hexes[j]
		local monster_type = nil
		if level == 1 then
			monster_type = mathx.random_choice{"Ghost", "Skeleton", "Skeleton Archer", "Soulless"}
		-- prevent high-level spirits from spawning near start position
		elseif wesnoth.map.distance_between({malakar_start_x, malakar_start_y}, hex) > math.floor(math.min(map_size_x, map_size_y) / 2) then
			if level == 2 then
				monster_type = mathx.random_choice{"Shadow", "Wraith", "Revenant", "Revenant", "Deathblade", "Bone Shooter"}
			else
				monster_type = mathx.random_choice{"Spectre", "Nightgaunt", "Draug", "Draug", "Banebow"}
			end
		elseif level == 2 then
			monster_type = mathx.random_choice{"Shadow", "Revenant", "Revenant", "Deathblade", "Bone Shooter"}
		else
			monster_type = mathx.random_choice{"Nightgaunt", "Draug", "Draug", "Banebow"}
		end
		wesnoth.units.to_map({type=monster_type, side=2}, hex[1], hex[2])
	end
end

MessHallRoom = Room:new()

function MessHallRoom:pre_corridor_setup()
	self:set_inner_terrain("Isa")
end

function MessHallRoom:post_corridor_setup()
	local q0, r0, s0 = table.unpack(get_cubic({self.x1 + 2, self.y1}))
	-- start at second row along -s axis
	local q1 = q0 + 1
	local r1 = r0
	local s1 = s0 - 1
	for i = 1, self.r_height - 2 do
		local q2 = q1
		local r2 = r1
		local s2 = s1
		-- skip the top row
		for j = 2, self.s_height - 2 do
			-- don't place tables in the middle of the room
			-- also make sure that there are multiples of 2 tables on r axis
			if ((self.r_height - 2) % 4 == 0 or math.abs(i - (self.r_height - 1) / 2) > math.floor((self.r_height - 2) % 4) / 2) and (self.s_height % 2 == 0 or j ~= (self.s_height - 1) / 2) then
				local hex_x, hex_y = table.unpack(from_cubic(q2, r2, s2))
				add_terrain_overlay(hex_x, hex_y, "TabY")
			end
			q2 = q2 + 1
			s2 = s2 - 1
		end
		q1 = q1 + 1
		r1 = r1 - 1
	end
end

SupplyRoom = Room:new()

function SupplyRoom:pre_corridor_setup()
	self:set_inner_terrain("Isa")
	local center_hex = self:get_approx_center()
	local hexes = self:get_inner_hexes()
	for i, hex in ipairs(hexes) do
		local distance = cartesian_distance_between_hexes(center_hex[1], center_hex[2], hex[1], hex[2])
		local thingy_prob = norm_pdf(distance, 0, 4) * 4.0
		if mathx.random() < thingy_prob then
			local item = mathx.random_choice{
				"items/box.png",
				"scenery/brokenbarrel.png",
				"items/barrel.png",
				"scenery/barrel1.png",
				"scenery/barrel2.png",
				"scenery/barrel3.png"
			}
			wesnoth.interface.add_item_image(hex[1], hex[2], item)
		end
	end
end

ClassRoom = Room:new()

function ClassRoom:pre_corridor_setup()
	self:set_inner_terrain("Isa")
	local q0, r0, s0 = table.unpack(get_cubic({self.x1 + 2, self.y1}))
	-- student chairs, skip the rightmost two rows
	for i = 1, self.r_height - 4 do
		local q1 = q0
		local r1 = r0
		local s1 = s0
		for j = 1, self.s_height - 2 do
			local hex_x, hex_y = table.unpack(from_cubic(q1, r1, s1))
			wesnoth.interface.add_item_image(hex_x, hex_y, "scenery/chairNE.png")
			q1 = q1 + 1
			s1 = s1 - 1
		end
		q0 = q0 + 1
		r0 = r0 - 1
	end
	-- teacher chair, midway on rightmost row
	q0 = q0 + math.ceil((self.s_height - 2) / 2)
	r0 = r0 - 1
	s0 = s0 - math.ceil((self.s_height - 2) / 2) + 1
	local hex_x, hex_y = table.unpack(from_cubic(q0, r0, s0))
	wesnoth.interface.add_item_image(hex_x, hex_y, "scenery/chairSW-fancier.png")
end

EmptyRoom = Room:new()

function EmptyRoom:pre_corridor_setup()
	self:set_inner_terrain("Isa")
end

------------------------
----- room setup functions
------------------------

-- keep this separate for name-indexed dictionaries (making them upfront causes wmlxgettext to choke)
local colors_list = {"red", "blue", "green", "white", "black", "yellow"}
local orb_colors_desc_tr = {
	_"Red Orb",
	_"Blue Orb",
	_"Green Orb",
	_"White Orb",
	_"Black Orb",
	_"Yellow Orb",
}
local orb_colors_desc = {}
for i, s in pairs(colors_list) do
	orb_colors_desc[s] = orb_colors_desc_tr[i]
end

local function place_start_room(mapgen)
	local map_size_x = wesnoth.current.map.playable_width
	local map_size_y = wesnoth.current.map.playable_height
	-- start room in bottom left of the map
	local start_room = StartRoom:new()
	start_room.id = "start_room"
	mapgen:find_room_placement(start_room, 1, 1, math.floor(map_size_y * 0.75), map_size_y, true)
	mapgen:register_room(start_room)
	start_room:initial_setup()
end

local function place_control_room(mapgen)
	local map_size_x = wesnoth.current.map.playable_width
	local map_size_y = wesnoth.current.map.playable_height
	-- control room in top right of the map
	local control_room = ControlRoom:new()
	control_room.id = "control_room"
	mapgen:find_room_placement(control_room, math.floor(map_size_x * 0.5), map_size_x, 1, math.floor(map_size_y * 0.25), true)
	mapgen:register_room(control_room)
end

local function place_orb_rooms(mapgen, num_orb_rooms)
	local orb_colors = {}
	local orb_colors_desc = {}
	for i, s in pairs(colors_list) do
		table.insert(orb_colors, s)
		orb_colors_desc[s] = orb_colors_desc_tr[i]
	end
	mathx.shuffle(orb_colors)
	orb_colors = {table.unpack(orb_colors, 1, num_orb_rooms)}
	local orb_hexes = {}
	local orb_guard_hexes = {}
	-- orb rooms
	for i = 1, num_orb_rooms do
		local orb_room = OrbRoom:new()
		orb_room.id = "orb_" .. tostring(i)
		orb_room:set_color(orb_colors[i])
		mapgen:find_placement_anywhere(orb_room, true)
		mapgen:register_room(orb_room)
		table.insert(orb_hexes, orb_room:get_orb_hex())
		table.insert(orb_guard_hexes, orb_room:get_guard_hex())
	end
	hex_list_to_wml_var(orb_hexes, "orbs_x", "orbs_y")
	hex_list_to_wml_var(orb_guard_hexes, "orb_guards_x", "orb_guards_y")
	wml.variables["orb_colors"] = table.concat(orb_colors, ",")
	wml.variables["orig_orb_colors"] = wml.variables["orb_colors"]
end

local function place_library_room(mapgen)
	local library_room = LibraryRoom:new()
	library_room.id = "library_room"
	-- library room in top left of map
	mapgen:find_room_placement(library_room, 1, 10, 1, 15, true)
	mapgen:register_room(library_room)
end

local function place_bedroom(mapgen)
	local map_size_x = wesnoth.current.map.playable_width
	local map_size_y = wesnoth.current.map.playable_height
	local bedroom = BedRoom:new()
	bedroom.id = "bedroom"
	bedroom.max_degree = 1
	-- library room in top left of map
	mapgen:find_room_placement(bedroom, math.floor(map_size_x * 0.75), map_size_x, math.floor(map_size_y * 0.25), math.floor(map_size_y * 0.75), true)
	mapgen:register_room(bedroom)
end

local function place_prison_room(mapgen)
	local map_size_x = wesnoth.current.map.playable_width
	local map_size_y = wesnoth.current.map.playable_height
	local prison_room = PrisonRoom:new()
	prison_room.id = "prison_room"
	prison_room.max_degree = 2
	mapgen:find_room_placement(prison_room, 1, map_size_x, math.floor(map_size_y * 0.75), map_size_y, true)
	mapgen:register_room(prison_room)
end

local function place_operating_room(mapgen)
	local operating_room = OperatingRoom:new()
	operating_room.id = "operating_room"
	-- it can go anywhere
	mapgen:find_placement_anywhere(operating_room, true)
	mapgen:register_room(operating_room)
end

local function place_workshop_room(mapgen)
	local workshop_room = WorkshopRoom:new()
	workshop_room.id = "workshop_room"
	-- it can go anywhere, and it's not essential
	local placed = mapgen:find_placement_anywhere(workshop_room, false)
	if placed then
		mapgen:register_room(workshop_room)
	end
end

-- random rooms include empty rooms, non-unique monsters, etc.
local function place_random_rooms(mapgen, num_random_rooms, num_undead_per_room, num_undead_rooms)
	local malakar_start_x = wml.variables["malakar_start_x"]
	local malakar_start_y = wml.variables["malakar_start_y"]

	-- this includes walls
	local random_room_dim_mean = 12
	local random_room_dim_sd = 5
	local random_room_dim_min = 5
	local random_room_dim_max = 12

	-- difficulty scores range from 3 to 11 (range is 8)
	-- if easiest, all units will be level 2 (average)
	-- if hardest, all units will be level 3
	-- otherwise, random combination of them
	local undead_level_sum = (num_undead_per_room * num_undead_rooms * 2) + math.ceil(((num_undead_per_room * num_undead_rooms) / 8.0) * (wml.variables["difficulty_score"] - 3))
	local undead_levels = get_random_level_list(num_undead_per_room * num_undead_rooms, undead_level_sum, 3)

	local rand_rooms_generated = 0
	while rand_rooms_generated < num_random_rooms do
		local r_height = math.ceil(random_norm(random_room_dim_mean, random_room_dim_sd))
		r_height = math.max(r_height, random_room_dim_min)
		r_height = math.min(r_height, random_room_dim_max)
		local s_height = math.ceil(random_norm(random_room_dim_mean, random_room_dim_sd))
		s_height = math.max(s_height, random_room_dim_min)
		s_height = math.min(s_height, random_room_dim_max)
		local r = nil
		if rand_rooms_generated < num_undead_rooms then
			r = UndeadRoom:new()
			r:set_levels({table.unpack(undead_levels, num_undead_per_room * rand_rooms_generated + 1, num_undead_per_room * (rand_rooms_generated + 1))})
		elseif rand_rooms_generated < num_undead_rooms + 1 then
			r = SupplyRoom:new()
		elseif rand_rooms_generated < num_undead_rooms + 2 then
			r = ClassRoom:new()
			r_height = math.max(r_height, 6)
			s_height = math.min(s_height, 9)
		else
			r = EmptyRoom:new()
		end
		r:set_dimensions(r_height, s_height)
		r.max_degree = 4
		local placed = mapgen:find_placement_anywhere(r, false)
		if placed then
			rand_rooms_generated = rand_rooms_generated + 1
			r.id = "random_" .. tostring(rand_rooms_generated)
			mapgen:register_room(r)
		end
	end
end

local function place_messhall_room(mapgen)
	local messhall_room = MessHallRoom:new()
	local r_height = 3 + mathx.random(1, 2) * 4
	local s_height = math.min(math.ceil(random_norm(9, 5)), 12)
	s_height = math.max(s_height, 7)
	messhall_room:set_dimensions(r_height, s_height)
	messhall_room.id = "messhall_room"
	-- it can go anywhere, and it's not essential
	local placed = mapgen:find_placement_anywhere(messhall_room, false)
	if placed then
		mapgen:register_room(messhall_room)
	end
end


------------------------
----- other map setup functions
------------------------

local function place_healing_glyph_in_room(room)
	local glyph_hex = nil
	local room_inner_hexes = room:get_inner_hexes()
	mathx.shuffle(room_inner_hexes)
	for j, hex in ipairs(room_inner_hexes) do
		if #wesnoth.interface.get_items(hex[1], hex[2]) == 0 then
			wesnoth.interface.add_item_image(hex[1], hex[2], "scenery/rune5.png")
			glyph_hex = hex
			break
		end
	end
	return glyph_hex
end

local function place_healing_glyphs(rooms, num_glyphs)
	local healing_glyph_locs = {}
	local room_iterate_order = {}
	for i = 1, #rooms do
		table.insert(room_iterate_order, i)
		-- one guaranteed healing glyph in start room
		if rooms[i].id == "start_room" then
			table.insert(healing_glyph_locs, place_healing_glyph_in_room(rooms[i]))
		end
	end
	mathx.shuffle(room_iterate_order)
	local glyphs_placed = 1
	while glyphs_placed < num_glyphs do
		for i, k in ipairs(room_iterate_order) do
			local room = rooms[k]
			if string.sub(room.id, 1, 6) == "random" then
				-- 50% chance this room gets a glyph somewhere
				if mathx.random(1, 2) == 1 then
					local hex = place_healing_glyph_in_room(room)
					if hex ~= nil then
						table.insert(healing_glyph_locs, hex)
						glyphs_placed = glyphs_placed + 1
					end
				end
			end
			if glyphs_placed >= num_glyphs then
				break
			end
		end
	end
	return healing_glyph_locs
end

-- scattered randomly, can occur in corridors or rooms
local function place_damage_glyphs(num_glyphs)
	local damage_glyph_locs = {}
	local possible_locs = wesnoth.map.find({terrain="Isa"})
	mathx.shuffle(possible_locs)
	local num_glyphs_placed = 0
	for i, hex in ipairs(possible_locs) do
		if #wesnoth.interface.get_items(hex[1], hex[2]) == 0 then
			wesnoth.interface.add_item_image(hex[1], hex[2], "scenery/rune4-burning.png")
			table.insert(damage_glyph_locs, hex)
			num_glyphs_placed = num_glyphs_placed + 1
			if num_glyphs_placed == num_glyphs then
				break
			end
		end
	end
	return damage_glyph_locs
end

-- scattered randomly, but not near Malakar
local function place_assistant_notes(num_notes)
	local assistant_note_locs = {}
	local possible_locs = wesnoth.map.find({terrain="Isa,Isa^Edb", wml.tag["not"]{radius=10, wml.tag.filter{id="Malakar"}}})
	mathx.shuffle(possible_locs)
	local num_notes_placed = 0
	for i, hex in ipairs(possible_locs) do
		if #wesnoth.interface.get_items(hex[1], hex[2]) == 0 then
			wesnoth.interface.add_item_image(hex[1], hex[2], "help/topic.png")
			table.insert(assistant_note_locs, hex)
			num_notes_placed = num_notes_placed + 1
			if num_notes_placed == num_notes then
				break
			end
		end
	end
	return assistant_note_locs
end

------------------------
----- generate various narrative text
------------------------

-- po: all of these entries must have the name of each entry's color in them
local orb_colors_journal_entries_tr = {
	_"Blood. How fascinating. Such a potent symbol of our life, the red ichor of our vitality. Dark wizards throughout Irdya know of its power and have learned to harness it. By the judicious addition of blood, I can increase by many-fold the potency of the runes and glyphs that shape the void in the heart of the Engine. But I need more blood. Fresh blood. Where, oh where to find it?",
	_"My experiments have borne fruit. After so many experiments and burned apprentices, I have done it! Such a wonderful blue glow, these jars of metal and glass that store lightning in a bottle. With these, the Engine can discharge in a flash the energy needed to breach the final veil between the planes.", -- describing a Leyden jar
	_"Sometimes I consider the toll of my research. I have given so much to the Engine. My fortune, the rarest of resources, the lives of my assistants, and most importantly my own blood, sweat, and tears. Even the few who I once considered to be friends have left me. Oh, how at times I miss the world outside of my laboratory, the green grass, the tall trees, the wind over the rolling hills. But I have come so far. I cannot turn back. I will not turn back. With each passing day the call of the void grows louder.",
	_"So many discordant forces suffuse the Engine. Strands of magic as prolific as the rainbow itself. How fitting, then, that I have made an artificial rainbow. By carefully cutting the purest of crystals into exact shapes, white light can be split into a riot of colors. With the proper enchantments, these crystals can split magic itself.",
	_"The essence of the void. Of nothingness, of that which is not. The purest black, the emptiest nonexistence. Even as I plumb its secrets, I sometimes feel that the void is staring back. But I must press on. Infinity awaits! Through nothing, I shall gain the power of everything. And those Magisters who expelled me from Alduin... they shall be the first to feel my wrath.",
	_"I lost my best apprentice, Goryi, today. While we were concentrating a sphere of pure fire magic, a moment of distraction disrupted our containment charm. The resulting magical flash left Goryi as nothing but a pile of bones, bleached yellow by the fury of the element unchained. Goryi was the apprentice who believed the most in our cause, in the awesome potential of the Engine to be. Perhaps I even would have granted him part of the reward I once promised him. At least his death shall serve the cause of my ascension.",
}
local orb_colors_journal_entries = {}
for i, s in ipairs(colors_list) do
	orb_colors_journal_entries[s] = orb_colors_journal_entries_tr[i]
end

local months_list = {}
table.insert(months_list, _"Whitefire")
table.insert(months_list, _"Bleeding Moon")
table.insert(months_list, _"Scatterseed")
table.insert(months_list, _"Deeproot")
table.insert(months_list, _"Scryer's Bloom")
table.insert(months_list, _"Thorntress")
table.insert(months_list, _"Summit Star")
table.insert(months_list, _"Kindlefire")
table.insert(months_list, _"Stillseed")
table.insert(months_list, _"Reaper's Moon")
table.insert(months_list, _"Verglas Bloom")
table.insert(months_list, _"Blackfire")

-- in case Irdya's months-per-year schedule is defined to be different from Earth's in the future
local days_per_month = {31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31}
local days_per_year = functional.reduce(days_per_month, function(a,b) return a+b end, 0)

local function day_to_month_date(day)
	local month_id = 1
	local remaining_days = ((day - 1) % days_per_year) + 1
	while remaining_days > days_per_month[month_id] do
		remaining_days = remaining_days - days_per_month[month_id]
		month_id = month_id + 1
	end
	local date_str = stringx.vformat(_"$month $day", {month=months_list[month_id], day=remaining_days})
	return date_str
end

-- sets $journal_str to the generated journal string
-- returns the last day in the journal (as some of the assistants' writings must be dated after the last journal entry)
local function generate_journal()
	local orb_colors = stringx.split(wml.variables["orb_colors"], ",")
	local journal_days = random_sample_wor(#orb_colors, days_per_year)
	local journal_entries_by_day = {}
	-- place journal entries with clues first
	for i = 1, #orb_colors do
		journal_entries_by_day[journal_days[i]] = orb_colors_journal_entries[orb_colors[i]]
	end
	local num_distractors = #orb_colors + 1
	-- po: none of these can have any names of a color in them
	local distractor_journal_entries = {
		_"Oh, the wonderful, fabulous workings of the Engine! Countless paths and etchings of magic, to work in such harmony of discord as to sunder the fabric of our world itself! Night after fitful night, I find myself wandering its infinite labyrinth in the eye of my mind. Approaching the void that I so fervently seek.",
		_"In my studies I have become increasingly convinced that the void has a presence. I have contemplated how this may be, how oblivion itself can be made tangible, in hopes that I may find yet more terrible insights for the Engine. Yet understanding eludes me. Always.",
		_"I caught one of my assistants, Yadna, stealing from me. Somehow she had found a way to bypass the inner wards, sneaking precious metals under the cover of spell to a lover down in the valley. Such treachery cannot be tolerated. I am planning a grand experiment, in generating self-perpetuating etheric harmonics using a closed temporal loop to precisely synchronize the automatic redirection of life force. Her life force will do.",
		_"As I seek to fashion new magics from the fundamental firmanent of the universe, I am reminded of my days in the Great Academy of Magic. Even in my youth I was eager to learn. How I would pore over the tomes of the library, in search of every last morsel of knowledge. But my curiosity was too much for those moribund Magisters. They could not stand my intelligence, my growing wisdom, my emerging greatness! Now I have acquired such secrets as to one day become the master of existence itself!",
		_"I slipped on a loose flagstone today. My knee will be sore for a while.",
		_"Throughout my life I have been deemed mad. At first by my own family, who termed me 'touched' after I manifested accidental magic as a toddler. By my classmates in the Academy, whom I could always hear mocking me behind my back. By the Professors and Magisters. By my various illicit patrons as I was forced to make my way in the world after leaving Alduin, criminals who sought to employ a rogue mage to defeat their enemies yet never dared to show their face to me. But it is they who are mad! It is they who deny the pursuit of greatness, the pursuit of all knowledge and power! Work on the Engine proceeds by the day. Soon I shall ascend to mastery of the void, and through nothing I shall attain everything!",
		_"The next phase of the Engine demands much. Eldritch, timeless bindings of pure, youthful vigor, a fusion of life and unlife, a magical contradiction to apply pressure on the local metric tensor. Perhaps the application of a necromantic binding glyph to the beating heart of a virgin will generate the requisite combination of energies.",
		_"At times I imagine how I shall reshape Irdya after the Engine is complete. Not only Irdya but the entire universe! All those who once laughed at me, the multitude of lesser men and women who have wronged me during my life. Oh, how they shall suffer! As for my laboratory assistants, perhaps I shall fulfill my promise of power beyond their imagination. Or perhaps not, their imagination was always limited after all.",
		_"I once again find myself in need of apprentices. The locals are strong in body, hardened from lives of toil on this hostile isle. When approached in secret many of them are eager to join my cause as assistants, if none else but for an escape from the oppression of the orcs. They have proved useful for manual labor and the occasional sacrifice, yet they are weak in mind and ill-served as apprentices. My agents in Wesnoth must redouble their efforts in recruitment. But they report that rogue mages and other magical cast-offs grow ever more difficult to find.",
		_"My agents in Wesnoth report that word has spread about me among the wizarding underworld. 'Bringer of the Void', I have been rather derisively rumored. Short-sighted fools! They comprehend not the scope of my genius! At least this Laboratory and the Engine remain unknown to the wider world. The local orcs have learned to avoid us, though they know not the cause of their fear. But I have no doubt that the Royal Army would hasten to destroy us should they learn of the Engine.",
		_"I have noticed leaps of logic coming more quickly to my brain as of late. Solutions to higher-order nonlinear partial differential equations revealing themselves almost as soon as I put quill to paper, new alchemical brews of just the exact properties needed for the Engine, early prototypes that not only function but exceed my expectations... it is almost as if something is helping me in my labors. Or perhaps this is my intellect continuing to expand, as my mind grows to embrace new heights of genius.",
		_"In my laboratory I have wrought superlative technologies beyond the wildest imagining of the known world. Oh, how even the best minds of the dwarves would envy my grand accomplishments! It has not escaped my reckoning that my artifice could conquer the Great Continent should I so choose. Mass-produced legions of indefatigable Automata that would sweep away even the bravest of warriors. Computing machines by which I could tabulate every hair on each of my subjects' heads should I so desire. Materials of immense strength that would serve as the foundation of the greatest cities to grace Irdya. But the Engine shall grant me power infinitely greater than any king or emperor could ever hope to wield."
	}
	mathx.shuffle(distractor_journal_entries)
	for i = 1, num_distractors do
		local unique_day = false
		local day = nil
		while not unique_day do
			unique_day = true
			day = mathx.random(1, days_per_year)
			for j = 1, #journal_days do
				if journal_days[j] == day then
					unique_day = false
					break
				end
			end
		end
		table.insert(journal_days, day)
		journal_entries_by_day[day] = distractor_journal_entries[i]
	end

	table.sort(journal_days)
	local day_offset = mathx.random(1, days_per_year)
	local journal_str = ""
	for i = 1, #journal_days do
		journal_str = journal_str .. "<span underline='single'>" .. day_to_month_date(journal_days[i] + day_offset) .. ":</span> " .. journal_entries_by_day[journal_days[i]]
		if i ~= #journal_days then
			journal_str = journal_str .. "\n\n"
		end
	end
	wml.variables["journal_str"] = journal_str
	return journal_days[#journal_days] + day_offset
end

------------------------
----- master function for initial scenario setup
------------------------

function randomize_scenario()
	local map_size_x = wesnoth.current.map.playable_width
	local map_size_y = wesnoth.current.map.playable_height
	local mapgen = DungeonMapGen:new()

	local num_orb_rooms = 5
	if wesnoth.scenario.difficulty == "EASY" then
		num_orb_rooms = 4
	elseif wesnoth.scenario.difficulty == "HARD" then
		num_orb_rooms = 6
	end
	local num_healing_glyphs = 6

	-- start out by placing and setting up story-important rooms
	place_start_room(mapgen)
	place_control_room(mapgen)
	place_orb_rooms(mapgen, num_orb_rooms)
	place_library_room(mapgen)
	place_bedroom(mapgen)
	-- now one-off unique rooms
	place_prison_room(mapgen)
	place_operating_room(mapgen)
	place_workshop_room(mapgen)

	-- now make and position some random rooms (not involved in objectives)
	local num_random_rooms = 7
	local num_undead_per_room = 3
	local num_undead_rooms = 4
	place_random_rooms(mapgen, num_random_rooms, num_undead_per_room, num_undead_rooms)
	place_messhall_room(mapgen)

	mapgen:pre_corridor_setup()
	mapgen:place_corridors("Isa")
	mapgen:post_corridor_setup()

	-- scatter healing and damage glyphs
	local healing_glyphs = place_healing_glyphs(mapgen:get_rooms_list(), num_healing_glyphs)
	hex_list_to_wml_var(healing_glyphs, "healing_glyph_x", "healing_glyph_y")

	local damage_glyphs = place_damage_glyphs(15)
	hex_list_to_wml_var(damage_glyphs, "damage_glyph_x", "damage_glyph_y")

	-- generate Sol'kan's journal
	local last_journal_date = generate_journal()
	wml.variables["last_journal_date"] = last_journal_date

	-- notes from his assistants that describe his fall
	local assistant_notes = place_assistant_notes(4)
	hex_list_to_wml_var(assistant_notes, "assistant_note_x", "assistant_note_y")
end

------------------------
----- handle various scenario events
------------------------

local function get_orb_color(x, y)
	local orb_color = nil
	local items_list = wesnoth.interface.get_items(x, y)
	for i, item in ipairs(items_list) do
		local image_path = item.image
		if string.len(image_path) >= 31 and string.sub(image_path, 1, 31) == "items/magic-orb.png~RC(magenta>" then
			local base = nil
			base, orb_color = table.unpack(stringx.split(image_path, ">"))
			orb_color = string.sub(orb_color, 1, #orb_color - 1) -- remove trailing parenthesis
		end
	end
	return orb_color
end

function wesnoth.wml_actions.get_orb_color(cfg)
	local x = cfg.x
	local y = cfg.y
	local orb_color = get_orb_color(x, y)
	local variable = cfg.variable or "orb_color"
	wml.variables[variable] = orb_color
end

function wesnoth.wml_actions.handle_orb(cfg)
	local x = cfg.x
	local y = cfg.y
	local items_list = wesnoth.interface.get_items(x, y)
	local orb_color = get_orb_color(x, y)
	local image_path = "items/magic-orb.png~RC(magenta>" .. orb_color .. ")"
	wesnoth.interface.remove_item(x, y, image_path)
	wesnoth.map.remove_label({x=x, y=y})
	local malakar = wesnoth.units.get("Malakar")
	malakar.moves = 0
	malakar.attacks_left = 0
	local orb_colors = stringx.split(wml.variables["orb_colors"], ",")
	local orbs_x = functional.map(stringx.split(wml.variables["orbs_x"], ","), function(s) return tonumber(s) end)
	local orbs_y = functional.map(stringx.split(wml.variables["orbs_y"], ","), function(s) return tonumber(s) end)
	if orb_colors[1] ~= orb_color then
		-- player smashed orb out of sequence
		wml.variables["alarms_triggered"] = wml.variables["alarms_triggered"] + 1
		wesnoth.audio.play("bells-golden.ogg")
		for i = 1, 3 do
			for j = 1, 5 do
				wesnoth.interface.color_adjust(36*j, -8*j, -8*j)
				wesnoth.interface.delay(100)
			end
			for j = 4, 0, -1 do
				wesnoth.interface.color_adjust(36*j, -8*j, -8*j)
				wesnoth.interface.delay(100)
			end
			wesnoth.interface.delay(1700)
		end
		wesnoth.interface.remove_item(x, y - 1, "units/monsters/automaton-defender.png~RC(magenta>green)~NO_TOD_SHIFT()")
		wesnoth.units.to_map({type="Automaton Defender", side=3, facing="se"}, x, y - 1)
		wesnoth.game_events.remove("guard_description")
	else
		if #orb_colors > 1 then
			for j = 1, 4 do
				wesnoth.interface.color_adjust(-10*j, 45*j, -10*j)
				wesnoth.interface.delay(125)
			end
			for j = 3, 0, -1 do
				wesnoth.interface.color_adjust(-10*j, 45*j, -10*j)
				wesnoth.interface.delay(125)
			end
		end
		if wml.variables["automata_notification_state"] == 1 and #orb_colors > 1 then
			wesnoth.wml_actions.message({x=x,y=y,message=_"This time the machine did not activate.\nThere must be a way to safely break the orbs!"})
			wml.variables["automata_notification_state"] = 2
		end
	end
	for j, color in ipairs(orb_colors) do
		if color == orb_color then
			table.remove(orb_colors, j)
			table.remove(orbs_x, j)
			table.remove(orbs_y, j)
			break
		end
	end
	wml.variables["orb_colors"] = table.concat(orb_colors, ",")
	wml.variables["orbs_x"] = table.concat(orbs_x, ",")
	wml.variables["orbs_y"] = table.concat(orbs_y, ",")
	if #orb_colors == 0 then
		local machine_x = wml.variables["machine_x"]
		local machine_y = wml.variables["machine_y"]
		-- remove their halos since they'll be replaced by terrain overlay
		wesnoth.interface.remove_item(machine_x - 2, machine_y)
		wesnoth.interface.remove_item(machine_x + 2, machine_y)
		wesnoth.interface.remove_item(machine_x, machine_y - 1)
		wesnoth.interface.remove_item(machine_x, machine_y + 1)
		local q, r, s = table.unpack(get_cubic({machine_x, machine_y}))
		local thingy_x, thingy_y = table.unpack(from_cubic(q-1, r+1, s))
		wesnoth.interface.remove_item(thingy_x, thingy_y)
		wesnoth.interface.remove_item(thingy_x, thingy_y - 1)
		thingy_x, thingy_y = table.unpack(from_cubic(q+1, r, s-1))
		wesnoth.interface.remove_item(thingy_x, thingy_y)
		wesnoth.interface.remove_item(thingy_x, thingy_y - 1)
		wesnoth.wml_actions.terrain_mask({
			mask = filesystem.read_file("~add-ons/Flight_Freedom/masks/11b_control_room_unblocker.mask"),
			x = machine_x - 2,
			y = machine_y - 2,
			border = true,
			wml.tag.rule {
				layer = "overlay",
			},
		})
		for i = 1, 3 do
			for j = 1, 5 do
				wesnoth.interface.color_adjust(-2*j, -2*j, 20*j)
				wesnoth.interface.delay(100)
			end
			for j = 4, 0, -1 do
				wesnoth.interface.color_adjust(-2*j, -2*j, 20*j)
				wesnoth.interface.delay(100)
			end
			wesnoth.interface.delay(1000)
		end
		if wml.variables["seen_engine"] then
			wesnoth.interface.scroll_to_hex(machine_x, machine_y)
			wesnoth.interface.delay(500)
			for i = 1, 5 do
				wesnoth.interface.remove_item(machine_x, machine_y, "scenery/engine-shield.png")
				wesnoth.interface.delay(100 * i)
				wesnoth.interface.add_item_halo(machine_x, machine_y, "scenery/engine-shield.png")
				wesnoth.interface.delay(200)
			end
			wesnoth.interface.remove_item(machine_x, machine_y, "scenery/engine-shield.png")
			wesnoth.interface.delay(1000)
			wesnoth.interface.scroll_to_hex(x, y)
		else
			wesnoth.interface.remove_item(machine_x, machine_y, "scenery/engine-shield.png")
		end
	end
end

function wesnoth.wml_actions.handle_prison_lever(cfg)
	local x = cfg.x
	local y = cfg.y
	wesnoth.interface.remove_item(x, y, "items/switch-left.png~XBRZ(2)")
	wesnoth.interface.add_item_image(x, y, "items/switch-right.png~XBRZ(2)")
	local q, r, s = table.unpack(get_cubic({x, y}))
	local prison_levers_x = functional.map(stringx.split(wml.variables["prison_levers_x"], ","), function(s) return tonumber(s) end)
	local prison_levers_y = functional.map(stringx.split(wml.variables["prison_levers_y"], ","), function(s) return tonumber(s) end)
	local prison_cell_idx = functional.map(stringx.split(wml.variables["prison_cell_idx"], ","), function(s) return tonumber(s) end)
	local door_hex = nil
	for j, idx in ipairs(prison_cell_idx) do
		if prison_levers_x[j] == x and prison_levers_y[j] == y then
			-- upper cells are odd-numbered, even cells are even-numbered
			if idx % 2 == 0 then
				door_hex = from_cubic(q - 2, r, s + 2)
			else
				door_hex = from_cubic(q + 2, r, s - 2)
			end
			table.remove(prison_levers_x, j)
			table.remove(prison_levers_y, j)
			table.remove(prison_cell_idx, j)
			break
		end
	end
	add_terrain_overlay(door_hex[1], door_hex[2], "Pr\\o")
	wesnoth.wml_actions.redraw{clear_shroud=true}
	wml.variables["prison_cell_idx"] = table.concat(prison_cell_idx, ",")
	wml.variables["prison_levers_x"] = table.concat(prison_levers_x, ",")
	wml.variables["prison_levers_y"] = table.concat(prison_levers_y, ",")
end

function wesnoth.wml_actions.display_console_screen(cfg)
	local orb_colors = stringx.split(wml.variables["orb_colors"], ",")
	local orig_orb_colors = stringx.split(wml.variables["orig_orb_colors"], ",")
	local alarms_triggered = wml.variables["alarms_triggered"]
	local console_str = "<span font_family='DejaVuSansMono' size='large'>"
	-- po: number of periods should vary so that status entries are aligned
	if #orb_colors > 0 then
		console_str = console_str .. _"VOID ENGINE STATUS............<span color='yellow'>INITIALIZING</span>" .. "\n\n"
		console_str = console_str .. _"INNER CONTAINMENT FIELD.......<span color='yellow'>ENABLED</span>"
	else
		console_str = console_str .. _"VOID ENGINE STATUS............<span color='green'>READY</span>" .. "\n\n"
		console_str = console_str .. _"INNER CONTAINMENT FIELD.......DISABLED"
	end
	console_str = console_str .. "\n"
	console_str = console_str .. _"OUTER CONTAINMENT FIELD.......<span color='red'>OFFLINE</span>"
	console_str = console_str .. "\n\n"
	local function list_contains(list, element)
		local result = false
		for i, list_element in ipairs(list) do
			if list_element == element then
				result = true
				break
			end
		end
		return result
	end
	for i, color in ipairs(orig_orb_colors) do
		console_str = console_str .. stringx.vformat(_"ENERGY SOURCE $i:", {i=i}) .. "\n"
		if list_contains(orb_colors, color) then
			console_str = console_str .. _"   CHARGE.....................<span color='green'>100%</span>" .. "\n"
			console_str = console_str .. _"   TRANSFER...................<span color='yellow'>STANDBY</span>" .. "\n\n"
		else
			console_str = console_str .. _"   CHARGE.....................<span color='red'>0%</span>" .. "\n"
			console_str = console_str .. _"   TRANSFER...................<span color='green'>COMPLETED</span>" .. "\n\n"
		end
	end
	if alarms_triggered > 0 then
		console_str = console_str .. stringx.vformat(_"ALARMS TRIGGERED..............<span color='red'>$i</span>", {i=alarms_triggered}) .. "\n"
	else
		console_str = console_str .. _"ALARMS TRIGGERED..............<span color='green'>0</span>" .. "\n"
	end
	console_str = console_str .. "</span>"
	show_text_box_borderless_dialog(console_str)
end

function wesnoth.wml_actions.engine_activation_sequence(cfg)
	local unit_x = cfg.x
	local unit_y = cfg.y
	local machine_x = wml.variables["machine_x"]
	local machine_y = wml.variables["machine_y"]
	local function tremor(mult)
		mult = mult or 1
		local tremor_coordinates = { {5,0},{-10,0},{-5,5},{0,-10},{0,5} } -- adapted from Wesnoth Lua Pack
		for i, c in ipairs(tremor_coordinates) do
			wesnoth.interface.scroll(c[1] * mult, c[2] * mult)
			wesnoth.interface.delay(50)
		end
	end
	local q, r, s = table.unpack(get_cubic({machine_x, machine_y}))
	wesnoth.interface.lock(true)
	wesnoth.interface.scroll_to_hex(machine_x, machine_y)
	wesnoth.audio.music_list.clear()
	wesnoth.audio.music_list.add("silence.ogg", true)
	wesnoth.interface.remove_item(machine_x, machine_y, "scenery/sentinel-glo.png")
	-- central orb
	for i = 1, 7 do
		local img_path = "halo/evil-star/evil-star-preparation-halo" .. tostring(i) .. ".png"
		wesnoth.interface.add_item_halo(machine_x, machine_y, img_path)
		wesnoth.interface.delay(100)
		wesnoth.wml_actions.redraw{}
		wesnoth.interface.remove_item(machine_x, machine_y, img_path)
	end
	wesnoth.interface.add_item_halo(machine_x, machine_y, "halo/evil-star/evil-star-halo[1~3].png:[100*3]")
	wesnoth.audio.sources["engine_start"] = {id="engine_start", sounds="dark-2.ogg", delay=0, chance=100, loop=-1, range=999, locations={machine_x, machine_y}}
	wesnoth.wml_actions.redraw{}
	wesnoth.interface.delay(1000)
	wesnoth.wml_actions.message({id="Malakar",message=_"The machine is active!\nBy Gar-Alagar... no..."})
	wesnoth.interface.delay(500)
	-- central orb enlarges
	for i = 1, 5 do
		wesnoth.interface.color_adjust(18 * i, 18 * i, 36 * i)
		wesnoth.interface.delay(100)
	end
	for i = 4, 0, -1 do
		wesnoth.interface.color_adjust(18 * i, 18 * i, 36 * i)
		wesnoth.interface.delay(100)
	end
	wesnoth.interface.remove_item(machine_x, machine_y, "halo/evil-star/evil-star-halo[1~3].png:[100*3]")
	wesnoth.interface.add_item_halo(machine_x, machine_y, "halo/evil-star/evil-star-halo[1~3].png~XBRZ(2):[100*3]")
	-- lightning bolts
	local effect_x, effect_y = table.unpack(from_cubic(q-1, r, s+1)) -- NW
	wesnoth.interface.add_item_halo(effect_x, effect_y, "halo/circuit-ne[1~3].png~FL(horiz):[50*3]")
	effect_x, effect_y = table.unpack(from_cubic(q-1, r+1, s)) -- SW
	wesnoth.interface.add_item_halo(effect_x, effect_y, "halo/circuit-ne[1~3].png~FL(horiz)~FL(vert):[50*3]")
	effect_x, effect_y = table.unpack(from_cubic(q+1, r-1, s)) -- NE
	wesnoth.interface.add_item_halo(effect_x, effect_y, "halo/circuit-ne[1~3].png:[50*3]")
	effect_x, effect_y = table.unpack(from_cubic(q+1, r, s-1)) -- SE
	wesnoth.interface.add_item_halo(effect_x, effect_y, "halo/circuit-ne[1~3].png~FL(vert):[50*3]")
	effect_x, effect_y = table.unpack(from_cubic(q, r-1, s+1)) -- N
	wesnoth.interface.add_item_halo(effect_x, effect_y, "halo/circuit-n[1~3].png~FL(vert):[50*3]")
	effect_x, effect_y = table.unpack(from_cubic(q, r+1, s-1)) -- S
	wesnoth.interface.add_item_halo(effect_x, effect_y, "halo/circuit-n[1~3].png:[50*3]")
	wesnoth.wml_actions.redraw{}
	wesnoth.interface.delay(1000)
	wesnoth.audio.sources["engine_start"] = nil
	wesnoth.audio.play("121942__klerrp__implosion_near_cut.wav")
	for i = 1, 10 do
		wesnoth.interface.color_adjust(-18 * i, -18 * i, -18 * i)
		wesnoth.interface.delay(200)
		wesnoth.wml_actions.redraw{}
	end
	wesnoth.interface.delay(500)
	tremor()
	wesnoth.interface.delay(500)
	-- implosion effect
	effect_x, effect_y = table.unpack(from_cubic(q-1, r, s+1)) -- NW
	wesnoth.interface.remove_item(effect_x, effect_y, "halo/circuit-ne[1~3].png~FL(horiz):[50*3]")
	effect_x, effect_y = table.unpack(from_cubic(q-1, r+1, s)) -- SW
	wesnoth.interface.remove_item(effect_x, effect_y, "halo/circuit-ne[1~3].png~FL(horiz)~FL(vert):[50*3]")
	effect_x, effect_y = table.unpack(from_cubic(q+1, r-1, s)) -- NE
	wesnoth.interface.remove_item(effect_x, effect_y, "halo/circuit-ne[1~3].png:[50*3]")
	effect_x, effect_y = table.unpack(from_cubic(q+1, r, s-1)) -- SE
	wesnoth.interface.remove_item(effect_x, effect_y, "halo/circuit-ne[1~3].png~FL(vert):[50*3]")
	effect_x, effect_y = table.unpack(from_cubic(q, r-1, s+1)) -- N
	wesnoth.interface.remove_item(effect_x, effect_y, "halo/circuit-n[1~3].png~FL(vert):[50*3]")
	effect_x, effect_y = table.unpack(from_cubic(q, r+1, s-1)) -- S
	wesnoth.interface.remove_item(effect_x, effect_y, "halo/circuit-n[1~3].png:[50*3]")
	wesnoth.interface.remove_item(machine_x, machine_y, "halo/evil-star/evil-star-halo[1~3].png~XBRZ(2):[100*3]")
	wesnoth.audio.play("490253__anomaex__sci-fi_explosion_cut.wav")
	for i = 1, (10 * 3) do
		local idx = math.ceil(i / 3)
		-- adding on idx * 30 degrees to the rotation accounts for the original frames being 30 degrees rotated in sequence
		local rotation = -1 * (((i % 3) * 120) + (idx * 30) % 360)
		local img_path = "halo/implosion/implosion-1-" .. tostring(idx) .. ".png~ROTATE(" .. tostring(rotation) .. ")"
		wesnoth.interface.add_item_halo(machine_x, machine_y, img_path)
		wesnoth.interface.delay(70)
		wesnoth.wml_actions.redraw{}
		wesnoth.interface.remove_item(machine_x, machine_y, img_path)
	end
	for i = 9, 0, -1 do
		wesnoth.interface.color_adjust(-18 * i, -18 * i, -18 * i)
		wesnoth.interface.delay(200)
		wesnoth.wml_actions.redraw{}
	end
	local theta = find_angle_between_hexes(machine_x, machine_y, unit_x, unit_y)
	local retreat_x = nil
	local retreat_y = nil
	-- in case player debug-teleports to the machine
	if unit_x ~= machine_x or unit_y ~= machine_y then
		for i = 1, 10 do
			local test_x, test_y = find_offset_hex_polar(machine_x, machine_y, i, theta)
			local terrain_code = wesnoth.current.map[{test_x, test_y}]
			if retreat_x == nil and terrain_code == "Fypd" then
				-- first hex outside machine along a line from machine center to unit's position
				retreat_x = test_x
				retreat_y = test_y
				break
			end
		end
	else
		retreat_x = machine_x
		retreat_y = machine_y + 1
	end
	-- small explosion to scare unit back
	local function small_explosion_fx(x, y)
		wesnoth.audio.play("explosion.ogg")
		for i = 1, 8 do
			local img_path = "halo/flame-burst-" .. tostring(i) .. ".png"
			wesnoth.interface.add_item_halo(x, y, img_path)
			wesnoth.interface.delay(100)
			wesnoth.wml_actions.redraw{}
			wesnoth.interface.remove_item(x, y, img_path)
		end
	end
	small_explosion_fx(machine_x, machine_y)
	tremor()
	wesnoth.interface.delay(500)
	-- jump back
	wesnoth.wml_actions.move_unit({x=unit_x, y=unit_y, to_x=retreat_x, to_y=retreat_y, check_passability=false, force_scroll=false, fire_event=false})
	local unit = wesnoth.units.get(retreat_x, retreat_y)
	unit.facing = wesnoth.map.get_relative_dir({retreat_x, retreat_y}, {machine_x, machine_y})
	unit:to_map()
	wesnoth.interface.delay(500)
	-- some more small explosions
	tremor()
	local machine_hexes = wesnoth.map.get_hexes_in_radius({machine_x, machine_y}, 2)
	mathx.shuffle(machine_hexes)
	for i = 1, 5 do
		local explosion_hex = machine_hexes[i]
		small_explosion_fx(explosion_hex[1], explosion_hex[2])
	end
	-- then the big explosion
	tremor(5)
	wesnoth.interface.color_adjust(100, 0, 0)
	wesnoth.audio.play("explosion-big.ogg")
	for i = 1, 8 do
		local img_path = "halo/explosion-big-" .. tostring(i) .. ".png"
		wesnoth.interface.add_item_halo(machine_x, machine_y, img_path)
		wesnoth.interface.delay(100)
		wesnoth.wml_actions.redraw{}
		wesnoth.interface.remove_item(machine_x, machine_y, img_path)
	end
	-- throw unit back
	local unit_img_base = wesnoth.unit_types[unit.type].image
	local unit_img = nil
	if retreat_x > machine_x then
		unit_img = unit_img_base .. "~FL(horiz)~ROTATE(45)"
	else
		unit_img = unit_img_base .. "~ROTATE(-45)"
	end
	local throw_x = nil
	local throw_y = nil
	local throw_steps = nil
	theta = find_angle_between_hexes(machine_x, machine_y, retreat_x, retreat_y)
	for i = 1, 16 do
		local test_x, test_y = find_offset_hex_polar(retreat_x, retreat_y, (i / 2.0), theta)
		local terrain_code = wesnoth.current.map[{test_x, test_y}]
		if string.sub(terrain_code, 1, 1) == "X" then
			break
		else
			-- we want the last hex before the wall
			throw_x = test_x
			throw_y = test_y
			throw_steps = i
		end
	end
	unit.hidden = true
	wesnoth.wml_actions.animate_path({
		hex_x = string.format("%i,%i", retreat_x, throw_x),
		hex_y = string.format("%i,%i", retreat_y, throw_y),
		image=unit_img,
		frames=throw_steps * 3,
		frame_length = 10
	})
	-- in case there's another unit where we're going to throw the player unit to
	local current_unit = nil
	if wesnoth.units.get(throw_x, throw_y) ~= nil then
		if wesnoth.units.get(throw_x, throw_y).id ~= unit.id then
			current_unit = wesnoth.units.get(throw_x, throw_y)
			wesnoth.units.extract(current_unit)
		end
	end
	unit.x = throw_x
	unit.y = throw_y
	unit.hitpoints = 1
	if current_unit ~= nil then
		local current_unit_x, current_unit_y = wesnoth.paths.find_vacant_hex(throw_x, throw_y, current_unit)
		current_unit:to_map(current_unit_x, current_unit_y)
	end
	if retreat_x > machine_x then
		unit_img = unit_img_base .. "~FL(horiz)~ROTATE(90)~NO_TOD_SHIFT()"
	else
		unit_img = unit_img_base .. "~ROTATE(-90)~NO_TOD_SHIFT()"
	end
	wesnoth.interface.add_item_image(throw_x, throw_y, unit_img)
	for i = 1, 6 do
		wesnoth.interface.color_adjust(-40 * i, -40 * i, -40 * i)
		wesnoth.interface.delay(200)
		wesnoth.wml_actions.redraw{}
	end
	-- destroyed engine room
	wesnoth.wml_actions.terrain_mask({
		mask = filesystem.read_file("~add-ons/Flight_Freedom/masks/11b_control_room_blank.mask"),
		x = machine_x - 2,
		y = machine_y - 2,
		border = true,
	})
	local console_x = wml.variables["console_x"]
	local console_y = wml.variables["console_y"]
	wesnoth.interface.delay(5000)
	wesnoth.interface.add_item_image(console_x, console_y, "scenery/sky-console-off.png")
	wesnoth.interface.add_item_image(machine_x - 2, machine_y, "scenery/electrode-thingy-ruined.png")
	wesnoth.interface.add_item_image(machine_x + 2, machine_y, "scenery/pump-thingy-ruined.png")
	wesnoth.interface.add_item_image(machine_x, machine_y - 1, "scenery/reactor-thingy-ruined.png")
	wesnoth.interface.add_item_image(machine_x, machine_y + 1, "scenery/reactor-thingy-ruined.png")
	local thingy_x, thingy_y = table.unpack(from_cubic(q-1, r+1, s))
	wesnoth.interface.add_item_image(thingy_x, thingy_y, "terrain/popup-thingy-3.png")
	wesnoth.interface.add_item_image(thingy_x, thingy_y - 1, "terrain/popup-thingy-3.png")
	thingy_x, thingy_y = table.unpack(from_cubic(q+1, r, s-1))
	wesnoth.interface.add_item_image(thingy_x, thingy_y, "terrain/popup-thingy-3.png")
	wesnoth.interface.add_item_image(thingy_x, thingy_y - 1, "terrain/popup-thingy-3.png")
	for i = 5, 0, -1 do
		wesnoth.interface.color_adjust(-40 * i, -40 * i, -40 * i)
		wesnoth.interface.delay(200)
		wesnoth.wml_actions.redraw{}
	end
	wesnoth.interface.remove_item(throw_x, throw_y, unit_img)
	if retreat_x > machine_x then
		unit_img = unit_img_base .. "~FL(horiz)~ROTATE(45)~NO_TOD_SHIFT()"
	else
		unit_img = unit_img_base .. "~ROTATE(-45)~NO_TOD_SHIFT()"
	end
	wesnoth.interface.add_item_image(throw_x, throw_y, unit_img)
	wesnoth.interface.delay(500)
	wesnoth.wml_actions.redraw{}
	wesnoth.interface.remove_item(throw_x, throw_y, unit_img)
	unit.hidden = false
	wesnoth.interface.lock(false)
end

function wesnoth.wml_actions.display_assistant_note(cfg)
	local x = cfg.x
	local y = cfg.y
	local assistant_note_x = functional.map(stringx.split(wml.variables["assistant_note_x"], ","), function(s) return tonumber(s) end)
	local assistant_note_y = functional.map(stringx.split(wml.variables["assistant_note_y"], ","), function(s) return tonumber(s) end)
	local notes = {
_"I've been stuck down here for months now. I pledged myself to Sol'kan to learn magic after Alduin rejected me. But all I've done is help with insane experiments, each more dangerous than the last. He hasn't taught me even one spell yet. Both of the only real friends I had down here are dead. Leofric died to a malfunctioning Automaton and Perrin was literally turned inside out. Sol'kan does not care. I've fantasized more than once about gutting him with a knife during one of his walks or while he's wrapped up in one of his experiments. And I know I'm not the only one who thinks about it.",
_"That crazy bastard actually did it. The Engine is complete, and Sol'kan is making his final preparations. Already he has activated the containment fields. None of us can get in or out. I know that he promised us all eternal rewards from the void. But I don't believe him anymore. He'll have no need of us, and I think he'll just leave us to rot.\n\nI've talked to my mates and they're with me. He dies tonight. Then we plunder this place and get out of here.",
_"Sol'kan lies dead. Me and my buddies jumped him on the way to the privy and I strangled him with my bare hands. Then we cut his ugly head off to make sure he can't come back. But the containment fields are still up. We hoped that they would fall with his death. We've pored over every book in the library but his magic is far too advanced for us. The apprentices threw every spell they had at the barriers with no luck. We even tried digging under the containment fields but we found the dirt to be as hard as stone.\n\nTempers are running high. Nobody knows how we're going to find more food when the supplies down here run out. Already fights are breaking out, old grudges and spite boiling over. And lots of us have lost hope.",
_"I'm the last one left. We ran out of food a month ago. Everyone else has either starved to death, taken their own life, or was eaten by their fellows. It's been three days since I've had a bite to eat, and I already feel my strength starting to fade. I know my death is coming soon. Gods, I should have never come down here..."
	}
	local note_date = wml.variables["last_journal_date"]
	for i = 1, #assistant_note_x do
		local cur_x = assistant_note_x[i]
		local cur_y = assistant_note_y[i]
		if i == 1 then
			note_date = note_date + 30 + ((cur_x + cur_y) % 30) -- 1-2 months after Sol'kan's last journal entry
		elseif i < 4 then
			note_date = note_date + 2 + ((cur_x + cur_y) % 3) -- engine's finished so things are moving quickly
		else
			note_date = note_date + 90  + ((cur_x + cur_y) % 28) -- a few months after Sol'kan's death
		end
		if x == cur_x and y == cur_y then
			local note_str = "<span underline='single'>" .. day_to_month_date(note_date) .. "</span>\n" .. notes[i]
			show_journal_dialog(note_str)
		end
	end
end

-- for color-blind accessibility
function wesnoth.wml_actions.label_orb_colors(cfg)
	local orbs_x = functional.map(stringx.split(wml.variables["orbs_x"], ","), function(s) return tonumber(s) end)
	local orbs_y = functional.map(stringx.split(wml.variables["orbs_y"], ","), function(s) return tonumber(s) end)
	local orb_colors = stringx.split(wml.variables["orb_colors"], ",")
	for i, color in ipairs(orb_colors) do
		local x = orbs_x[i]
		local y = orbs_y[i]
		wesnoth.map.add_label({x=x, y=y, text=orb_colors_desc[color]})
	end
end
