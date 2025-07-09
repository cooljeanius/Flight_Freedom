-- Lua code used by scenario 11B (Sol'kan's Lair)

local _ = wesnoth.textdomain "wesnoth-Flight_Freedom"

local functional = wesnoth.require("functional")
wesnoth.dofile('~add-ons/Flight_Freedom/lua/graph_utils.lua')

------------------------
----- Room class to handle creation, initial terrain painting, and collision checking
------------------------

-- x1 and y1 refer to left corner on Wesnoth map
-- r and s refer to room size in cubic coordinates, inclusive of corners
Room = {x1 = 0, y1 = 0, r_height = 0, s_height = 0}

function Room:new(o)
	o = o or {}
	setmetatable(o, self)
	self.__index = self
	return o
end

function Room:set_dimensions(r_height, s_height)
	self.r_height = r_height
	self.s_height = s_height
end

function Room:set_left_corner(x1, y1)
	self.x1 = x1
	self.y1 = y1
end

function Room:left_corner()
	return {self.x1, self.y1}
end

function Room:top_corner()
	local q, r, s = table.unpack(get_cubic({self.x1, self.y1}))
	q = q + (self.r_height - 1)
	r = r - (self.r_height - 1)
	return from_cubic(q, r, s)
end

function Room:bottom_corner()
	local q, r, s = table.unpack(get_cubic({self.x1, self.y1}))
	q = q + (self.s_height - 1)
	s = s - (self.s_height - 1)
	return from_cubic(q, r, s)
end

function Room:right_corner()
	local q, r, s = table.unpack(get_cubic({self.x1, self.y1}))
	q = q + (self.r_height - 1) + (self.s_height - 1)
	r = r - (self.r_height - 1)
	s = s - (self.s_height - 1)
	return from_cubic(q, r, s)
end

function Room:get_approx_center()
	local q, r, s = table.unpack(get_cubic({self.x1, self.y1}))
	local half_r_height = math.ceil(self.r_height / 2)
	local half_s_height = math.ceil(self.s_height / 2)
	q = q + (half_r_height - 1) + (half_s_height - 1)
	r = r - (half_r_height - 1)
	s = s - (half_s_height - 1)
	return from_cubic(q, r, s)
end

function Room:fits_in_map()
	local map_size_x = wesnoth.current.map.playable_width
	local map_size_y = wesnoth.current.map.playable_height
	local fits = true
	if (self.x1 < 1) or (self.y1 < 1) or (self.x1 > map_size_x) or (self.y1 > map_size_y) then
		fits = false
	end
	local x2, y2 = table.unpack(self:top_corner())
	if (x2 < 1) or (y2 < 1) or (x2 > map_size_x) or (y2 > map_size_y) then
		fits = false
	end
	x2, y2 = table.unpack(self:bottom_corner())
	if (x2 < 1) or (y2 < 1) or (x2 > map_size_x) or (y2 > map_size_y) then
		fits = false
	end
	x2, y2 = table.unpack(self:right_corner())
	if (x2 < 1) or (y2 < 1) or (x2 > map_size_x) or (y2 > map_size_y) then
		fits = false
	end
	return fits
end

-- includes walls
function Room:contains_hex(x, y)
-- start at left corner, iterate across width of room (in x-coordinate), and check y coordinates
	local in_room = false
	local x1 = self.x1
	local x2 = self.x1 + (self.r_height - 1) + (self.s_height - 1)
	local y1 = self.y1
	local y2 = self.y1
	for x_cur = x1, x2 do
		local x_dist = x_cur - x1 + 1
		if x_cur == x and y >= y1 and y <= y2 then
			in_room = true
			break
		end
		if x_dist < self.r_height then
			-- y1 moves up
			y1 = y1 - (x_cur % 2)
		else
			-- y1 moves down
			y1 = y1 + ((x_cur - 1) % 2)
		end
		if x_dist < self.s_height then
			-- y2 moves down
			y2 = y2 + ((x_cur - 1) % 2)
		else
			-- y2 moves up
			y2 = y2 - (x_cur % 2)
		end
	end
	return in_room
end

function Room:get_edge_hexes()
	local edge_hexes = {}
	local x1 = self.x1
	local x2 = self.x1 + (self.r_height - 1) + (self.s_height - 1)
	local y1 = self.y1
	local y2 = self.y1
	for x_cur = x1, x2 do
		local x_dist = x_cur - x1 + 1
		local hex1 = {x_cur, y1}
		table.insert(edge_hexes, hex1)
		if y1 ~= y2 then
			local hex2 = {x_cur, y2}
			table.insert(edge_hexes, hex2)
		end
		if x_dist < self.r_height then
			-- y1 moves up
			y1 = y1 - (x_cur % 2)
		else
			-- y1 moves down
			y1 = y1 + ((x_cur - 1) % 2)
		end
		if x_dist < self.s_height then
			-- y2 moves down
			y2 = y2 + ((x_cur - 1) % 2)
		else
			-- y2 moves up
			y2 = y2 - (x_cur % 2)
		end
	end
	return edge_hexes
end

function Room:get_specific_edge_hexes()
	local nw_edge_hexes = {}
	local ne_edge_hexes = {}
	local sw_edge_hexes = {}
	local se_edge_hexes = {}
	local x1 = self.x1
	local x2 = self.x1 + (self.r_height - 1) + (self.s_height - 1)
	local y1 = self.y1
	local y2 = self.y1
	for x_cur = x1, x2 do
		local x_dist = x_cur - x1 + 1
		local hex1 = {x_cur, y1}
		local hex2 = {x_cur, y2}
		if x_dist < self.r_height then
			-- traversing NW edge; y1 moves up
			y1 = y1 - (x_cur % 2)
			table.insert(nw_edge_hexes, hex1)
		else
			-- traversing NE edge; y1 moves down
			if x_dist == self.r_height then
				-- top corner so it's part of NW and NE edges
				table.insert(nw_edge_hexes, hex1)
			end
			table.insert(ne_edge_hexes, hex1)
			y1 = y1 + ((x_cur - 1) % 2)
		end
		if x_dist < self.s_height then
			-- traversing SW edge; y2 moves down
			table.insert(sw_edge_hexes, hex2)
			y2 = y2 + ((x_cur - 1) % 2)
		else
			-- traversing SE edge; y2 moves up
			if x_dist == self.s_height then
				-- bottom corner so it's part of SW and SE edges
				table.insert(sw_edge_hexes, hex2)
			end
			table.insert(se_edge_hexes, hex2)
			y2 = y2 - (x_cur % 2)
		end
	end
	return {nw_edge_hexes, ne_edge_hexes, sw_edge_hexes, se_edge_hexes}
end

function Room:set_wall_terrain(terrain)
	local edge_hexes = self:get_edge_hexes()
	for i, hex in ipairs(edge_hexes) do
		local x1 = hex[1]
		local y1 = hex[2]
		wesnoth.current.map[{x1, y1}] = terrain
	end
end

function Room:get_inner_hexes()
	local inner_hexes = {}
	local x1 = self.x1
	local x2 = self.x1 + (self.r_height - 1) + (self.s_height - 1)
	local y1 = self.y1
	local y2 = self.y1
	for x_cur = x1, x2 do
		local x_dist = x_cur - x1 + 1
		if x_cur > x1 and x_cur < x2 then
			for y_cur = y1, y2 do
				if y_cur > y1 and y_cur < y2 then
					local hex1 = {x_cur, y_cur}
					table.insert(inner_hexes, hex1)
				end
			end
		end
		if x_dist < self.r_height then
			-- y1 moves up
			y1 = y1 - (x_cur % 2)
		else
			-- y1 moves down
			y1 = y1 + ((x_cur - 1) % 2)
		end
		if x_dist < self.s_height then
			-- y2 moves down
			y2 = y2 + ((x_cur - 1) % 2)
		else
			-- y2 moves up
			y2 = y2 - (x_cur % 2)
		end
	end
	return inner_hexes
end

function Room:set_inner_terrain(terrain)
	local inner_hexes = self:get_inner_hexes()
	for i, hex in ipairs(inner_hexes) do
		local x1 = hex[1]
		local y1 = hex[2]
		wesnoth.current.map[{x1, y1}] = terrain
	end
end

--check if any of the border tiles of r1 are in r2
Room.half_intersect = function(r1, r2)
	local intersects = false
	local edge_hexes = r1:get_edge_hexes()
	for i, hex in ipairs(edge_hexes) do
		local x1 = hex[1]
		local y1 = hex[2]
		intersects = r2:contains_hex(x1, y1)
		if intersects then
			break
		end
	end
	return intersects
end

function Room:intersects_with(r2)
	local intersects = false
	return (Room.half_intersect(self, r2) or Room.half_intersect(r2, self))
end

function Room:presenting_side_to(r2)
	-- find sides closest to each other
	local center_x, center_y = table.unpack(self:get_approx_center())
	local r2_center_x, r2_center_y = table.unpack(r2:get_approx_center())
	local side = ""
	if center_x < r2_center_x and center_y < r2_center_y then
		side = "se"
	elseif center_x >= r2_center_x and center_y < r2_center_y then
		side = "sw"
	elseif center_x < r2_center_x and center_y >= r2_center_y then
		side = "ne"
	elseif center_x >= r2_center_x and center_y >= r2_center_y then
		side = "nw"
	end
	return side
end

function Room:minimum_wall_distance(r2)
	local presenting_side = self:presenting_side_to(r2)
	local source_hex_list = nil
	local dest_hex_list = nil
	if presenting_side == "se" then
		source_hex_list = self:get_specific_edge_hexes()[4] -- SE wall
		dest_hex_list = r2:get_specific_edge_hexes()[1] -- NW wall
	elseif presenting_side == "sw" then
		source_hex_list = self:get_specific_edge_hexes()[3] -- SW wall
		dest_hex_list = r2:get_specific_edge_hexes()[2] -- NE wall
	elseif presenting_side == "ne" then
		source_hex_list = self:get_specific_edge_hexes()[2] -- NE wall
		dest_hex_list = r2:get_specific_edge_hexes()[3] -- SW wall
	elseif presenting_side == "nw" then
		source_hex_list = self:get_specific_edge_hexes()[1] -- NW wall
		dest_hex_list = r2:get_specific_edge_hexes()[4] -- SE wall
	end
	local min_dist = nil
	for i, hex1 in ipairs(source_hex_list) do
		for j, hex2 in ipairs(dest_hex_list) do
			local dist = wesnoth.map.distance_between(hex1, hex2)
			if min_dist == nil or dist < min_dist then
				min_dist = dist
			end
		end
	end
	return min_dist
end

------------------------
----- now set up the map
------------------------

local map_size_x = wesnoth.current.map.playable_width
local map_size_y = wesnoth.current.map.playable_height

-- essential=true used for story rooms
local function find_room(r_height, s_height, min_x, max_x, min_y, max_y, existing_rooms, essential)
	local attempts = 0
	local max_attempts = 200
	local placed = false
	local room = nil
	while not placed do
		room = Room:new()
		local x1 = mathx.random(min_x, max_x)
		local y1 = mathx.random(min_y, max_y)
		room:set_left_corner(x1, y1)
		room:set_dimensions(r_height, s_height)
		if room:fits_in_map() then
			if room:fits_in_map() then
				local intersects = false
				for i, r2 in ipairs(existing_rooms) do
					if room:intersects_with(r2) then
						intersects = true
						break
					end
				end
				if not intersects then
					placed = true
				end
			end
		end
		attempts = attempts + 1
		if (not essential) and (attempts > max_attempts) then
			room = nil
			break
		end
	end
	return room
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

-- q, r, s: starting cubic coordinates
-- inst: list of instructions ("nw", "ne", "sw", "se") to extend the tunnel
local function plot_corridor(q, r, s, corridor_width, inst_list)
	local corridor_tiles = {}
	local half_corridor_width = math.floor(corridor_width / 2)
	-- q, r, s track center of coordinate and vary along its length
	for i, inst in ipairs(inst_list) do
		-- q_hex, r_hex, and s_hex vary along corridor width
		local q_hex = q
		local r_hex = r
		local s_hex = s
		if inst == "nw" then -- +s
			-- start adding tiles halfway along positive r axis
			q_hex = q_hex - half_corridor_width
			r_hex = r_hex + half_corridor_width
			for w = 1, corridor_width do
				table.insert(corridor_tiles, from_cubic(q_hex, r_hex, s_hex))
				-- now sweep along negative r axis
				q_hex = q_hex + 1
				r_hex = r_hex - 1
			end
			-- now advance corridor center along positive s axis
			q = q - 1
			s = s + 1
		elseif inst == "ne" then -- -r
			-- start adding tiles halfway along positive s axis
			q_hex = q_hex - half_corridor_width
			s_hex = s_hex + half_corridor_width
			for w = 1, corridor_width do
				table.insert(corridor_tiles, from_cubic(q_hex, r_hex, s_hex))
				-- now sweep along negative s axis
				q_hex = q_hex + 1
				s_hex = s_hex - 1
			end
			-- now advance corridor center along negative r axis
			q = q + 1
			r = r - 1
		elseif inst == "sw" then -- +r
			-- start adding tiles halfway along negative s axis
			q_hex = q_hex + half_corridor_width
			s_hex = s_hex - half_corridor_width
			for w = 1, corridor_width do
				table.insert(corridor_tiles, from_cubic(q_hex, r_hex, s_hex))
				-- now sweep along positive s axis
				q_hex = q_hex - 1
				s_hex = s_hex + 1
			end
			-- now advance corridor center along positive r axis
			q = q - 1
			r = r + 1
		elseif inst == "se" then -- -s
			-- start adding tiles halfway along negative r axis
			q_hex = q_hex + half_corridor_width
			r_hex = r_hex - half_corridor_width
			for w = 1, corridor_width do
				table.insert(corridor_tiles, from_cubic(q_hex, r_hex, s_hex))
				-- now sweep along positive r axis
				q_hex = q_hex - 1
				r_hex = r_hex + 1
			end
			-- now advance corridor center along negative s axis
			q = q + 1
			s = s - 1
		end
	end
	return corridor_tiles
end

local function place_story_rooms(current_rooms, num_orb_rooms)
	-- all rooms made by this function should be "ready to go"
	-- including item graphics, units, and WML variables for events

	-- start room in bottom left of the map
	local start_room = find_room(8, 8, 1, 1, math.floor(map_size_y * 0.75), map_size_y, current_rooms, true)
	start_room.id = "start_room"
	start_room:set_inner_terrain("Isa")
	start_room:set_wall_terrain("Xor")
	table.insert(current_rooms, start_room)

	-- cave passage in
	local start_room_x, start_room_y = table.unpack(start_room:left_corner())
	wesnoth.wml_actions.terrain_mask({
		mask = filesystem.read_file("~add-ons/Flight_Freedom/masks/11b_cave_entrance.mask"),
		x = start_room_x,
		y = start_room_y + 1,
		border = true,
	})

	local malakar_start_x = start_room_x + 6
	local malakar_start_y = start_room_y
	wesnoth.units.get("Malakar"):to_map(malakar_start_x, malakar_start_y)

	-- control room in top right of the map
	local control_room = find_room(12, 9, math.floor(map_size_x * 0.5), map_size_x, 1, math.floor(map_size_y * 0.25), current_rooms, true)
	control_room.id = "control_room"
	control_room:set_inner_terrain("Isr")
	control_room:set_wall_terrain("Xoi") -- white wall
	table.insert(current_rooms, control_room)

	local orb_colors = {"red", "blue", "green", "white", "black", "yellow"}
	mathx.shuffle(orb_colors)
	orb_colors = {table.unpack(orb_colors, 1, num_orb_rooms)}
	local orb_hexes = {}
	-- orb rooms
	for i = 1, num_orb_rooms do
		local orb_room = find_room(5, 5, 1, map_size_x, 1, map_size_y, current_rooms, true)
		orb_room.id = "orb_" .. tostring(i)
		orb_room:set_inner_terrain("Isa")
		local orb_room_x, orb_room_y = table.unpack(orb_room:left_corner())
		local orb_x = orb_room_x + 4
		local orb_y = orb_room_y
		wesnoth.interface.add_item_image(orb_x, orb_y, "items/altar.png")
		local orb_image_path = "items/magic-orb.png~RC(magenta>" .. orb_colors[i] .. ")"
		wesnoth.interface.add_item_image(orb_x, orb_y, orb_image_path)
		table.insert(orb_hexes, {orb_x, orb_y})
		table.insert(current_rooms, orb_room)
	end
	hex_list_to_wml_var(orb_hexes, "orbs_x", "orbs_y")
	wml.variables["orb_colors"] = table.concat(orb_colors, ",")
	wml.variables["num_orbs"] = num_orb_rooms

	-- library room in top left of map
	local library_room = find_room(12, 7, 1, 10, 1, 15, current_rooms, true)
	library_room.id = "library_room"
	library_room:set_inner_terrain("Iwr") -- wood floor
	library_room:set_wall_terrain("Xoc") -- clean stone wall
	table.insert(current_rooms, library_room)

	-- todo: Sol'kan's living quarters
	local bedroom = find_room(7, 5, math.floor(map_size_x * 0.75), map_size_x, math.floor(map_size_y * 0.25), math.floor(map_size_y * 0.75), current_rooms, true)
	bedroom.id = "bedroom"
	bedroom:set_inner_terrain("Iwr")
	local bedroom_x, bedroom_y = table.unpack(bedroom:left_corner())
	wesnoth.wml_actions.terrain_mask({
		mask = filesystem.read_file("~add-ons/Flight_Freedom/masks/11b_bedroom.mask"),
		x = bedroom_x,
		y = bedroom_y - 2,
		border = true,
	})
	local inner_hexes = bedroom:get_inner_hexes()
	for i, hex in ipairs(inner_hexes) do
		if wesnoth.current.map[{hex[1], hex[2]}] == "Iwr" and mathx.random(1, 2) == 1 then
			wesnoth.current.map[{hex[1], hex[2]}] = "Iwo" -- old wood floor
		end
	end
	wesnoth.interface.add_item_image(bedroom_x + 6, bedroom_y - 1, "scenery/bed-fancy-sw.png")
	local journal_x = bedroom_x + 7
	local journal_y = bedroom_y - (bedroom_x % 2)
	wml.variables["journal_x"] = journal_x
	wml.variables["journal_y"] = journal_y
	wesnoth.interface.add_item_image(journal_x, journal_y, "items/book2.png")
	bedroom.max_degree = 1
	table.insert(current_rooms, bedroom)

	return current_rooms
end

local function place_random_rooms(current_rooms)
	local random_rooms = {}

	local num_random_rooms = 10
	-- this includes walls
	local random_room_dim_mean = 12
	local random_room_dim_sd = 5
	local random_room_dim_min = 5
	local random_room_dim_max = 12

	local rand_rooms_generated = 0

	while rand_rooms_generated < num_random_rooms do
		local r_height = math.ceil(random_norm(random_room_dim_mean, random_room_dim_sd))
		r_height = math.max(r_height, random_room_dim_min)
		r_height = math.min(r_height, random_room_dim_max)
		local s_height = math.ceil(random_norm(random_room_dim_mean, random_room_dim_sd))
		s_height = math.max(s_height, random_room_dim_min)
		s_height = math.min(s_height, random_room_dim_max)
		local r = find_room(r_height, s_height, 1, map_size_x, 1, map_size_y, current_rooms, false)
		if r ~= nil then
			rand_rooms_generated = rand_rooms_generated + 1
			r.id = "random_" .. tostring(rand_rooms_generated)
			r:set_inner_terrain("Isa")
			table.insert(current_rooms, r)
			table.insert(random_rooms, r)
		end
	end

	-- populate random rooms
	for i = 1, rand_rooms_generated do
		-- undead catacombs
		if i >= 1 and i <= 4 then
			random_rooms[i]:set_wall_terrain("Xot") -- catacomb wall
			--random_rooms[i]:set_inner_terrain("Rb") -- dark dirt
			local room_wall_hexes = random_rooms[i]:get_edge_hexes()
			for j, hex in ipairs(room_wall_hexes) do
				local rand_decor = mathx.random(1, 6)
				if rand_decor <= 2 then
					add_terrain_overlay(hex[1], hex[2], "Edb") -- remains
				elseif rand_decor == 3 then
					add_terrain_overlay(hex[1], hex[2], "Efs") -- brazier
				end
			end
			local room_inner_hexes = random_rooms[i]:get_inner_hexes()
			mathx.shuffle(room_inner_hexes)
			for j, hex in ipairs(room_inner_hexes) do
				local rand_decor = mathx.random(1, 4)
				if rand_decor <= 3 then
					add_terrain_overlay(hex[1], hex[2], "Edb") -- remains
				end
			end
			local num_undead_per_catacomb = 3
			for j = 1, num_undead_per_catacomb do
				local hex = room_inner_hexes[j]
				local rand_monster = mathx.random(1, 4)
				if rand_monster == 1 then
					wesnoth.units.to_map({type="Spectre", side=2}, hex[1], hex[2])
				end
				if rand_monster == 2 then
					wesnoth.units.to_map({type="Nightgaunt", side=2}, hex[1], hex[2])
				end
				if rand_monster == 3 then
					wesnoth.units.to_map({type="Draug", side=2}, hex[1], hex[2])
				end
				if rand_monster == 4 then
					wesnoth.units.to_map({type="Banebow", side=2}, hex[1], hex[2])
				end
			end
		end
		-- todo: other monster room
		-- todo: prison room (use window wall terrain)
		-- todo: kitchen room
		-- todo: servant or guard quarters
		-- todo: creepy lab room
		-- todo: maybe a treasure room?
	end
	return current_rooms
end

local function place_corridors(current_rooms)
	-- build graph of all rooms
	local num_rooms = #current_rooms
	graph = Graph:new()
	graph:init_unconnected(num_rooms)
	-- until graph is fully connected, i.e. all rooms are accessible:
	---- pick random room
	---- cast a ray at random angle
	---- first room that we hit (if any), if no edge between source and destination connect them (both in graph and on map)
	local max_connect_attempts = 1000 -- avoid infinte loop in case there's a room that can't be connected anywhere
	local connect_attempts = 0 -- tracks number of failed connections (resets if successful connection made)
	local rays_failed = 0
	local starting_max_ray_length = 15 -- restrict maximum distance algorithm will try to connect rooms
	--local corridor_created = false
	--while not corridor_created do
	while not graph:is_connected() do
		local origin_room_selected = false
		local origin_room_num = nil
		local oriign_room = nil
		while not origin_room_selected do
			origin_room_num = mathx.random(1, num_rooms)
			origin_room = current_rooms[origin_room_num]
			if origin_room.max_degree == nil or graph:degree(origin_room_num) < origin_room.max_degree then
				origin_room_selected = true
			end
		end
		local center_x, center_y = table.unpack(origin_room:get_approx_center())
		--print("Source hex: " .. tostring(center_x) .. ", " .. tostring(center_y))
		local theta = mathx.random() * math.pi * 2.0
		--print("Theta: " .. (theta * 180.0 / math.pi))
		local radius = 1
		local casting_ray = true
		-- start with trying to make shorter connections, but gradually extend the reach
		-- so that far-away rooms eventually do get connected
		local max_ray_length = starting_max_ray_length + math.floor(rays_failed / 100)
		while casting_ray do
			local test_x, test_y = find_offset_hex_polar(center_x, center_y, radius, theta)
			if test_x >= 1 and test_x <= map_size_x and test_y >= 1 and test_y <= map_size_y and radius <= max_ray_length then
				--print("Eval hex: " .. tostring(test_x) .. ", " .. tostring(test_y))
				for i = 1, num_rooms do
					if i ~= origin_room_num then
						if current_rooms[i]:contains_hex(test_x, test_y) then
							--print("Found target: " .. tostring(test_x) .. ", " .. tostring(test_y))
							local dest_room = current_rooms[i]
							-- don't make duplicate tunnels between rooms
							-- also fail corridor if it would exceed a room's max_degree
							if graph:get_edge(origin_room_num, i) == 0 and (dest_room.max_degree == nil or graph:degree(i) < dest_room.max_degree) then
								-- create corridor on map
								local corridor_created = false
								local corridor_tiles = {}
								local max_corridor_attempts = 200
								local corridor_attempts = 0
								while not corridor_created do
									corridor_created = true
									local corridor_width = 2 -- mathx.random(2, 3)
									local half_corridor_width = math.floor(corridor_width / 2)
									local presenting_side = origin_room:presenting_side_to(dest_room)
									local source_hex_list = nil
									local dest_hex_list = nil
									if presenting_side == "se" then
										-- SE of origin to NW of destination
										source_hex_list = origin_room:get_specific_edge_hexes()[4]
										dest_hex_list = dest_room:get_specific_edge_hexes()[1]
									elseif presenting_side == "sw" then
										-- SW of origin to NE of destination
										source_hex_list = origin_room:get_specific_edge_hexes()[3]
										dest_hex_list = dest_room:get_specific_edge_hexes()[2]
									elseif presenting_side == "ne" then
										-- NE of origin to SW of destination
										source_hex_list = origin_room:get_specific_edge_hexes()[2]
										dest_hex_list = dest_room:get_specific_edge_hexes()[3]
									elseif presenting_side == "nw" then
										-- NW of origin to SE of destination
										source_hex_list = origin_room:get_specific_edge_hexes()[1]
										dest_hex_list = dest_room:get_specific_edge_hexes()[4]
									end
									-- exclude left and right corners as possible connection points
									table.remove(source_hex_list)
									table.remove(source_hex_list, 1)
									table.remove(dest_hex_list)
									table.remove(dest_hex_list, 1)
									mathx.shuffle(source_hex_list)
									mathx.shuffle(dest_hex_list)
									local source_hex = nil
									local dest_hex = nil
									-- if rooms are sufficiently close try to find a straight path
									local min_wall_dist = origin_room:minimum_wall_distance(dest_room)
									if min_wall_dist <= 6 then
										for j, hex1 in ipairs(source_hex_list) do
											local q1, r1, s1 = table.unpack(get_cubic(hex1))
											for k = 1, min_wall_dist do
												if source_hex == nil then
													if presenting_side == "se" then
														q1 = q1 + 1
														s1 = s1 - 1
													elseif presenting_side == "sw" then
														q1 = q1 - 1
														r1 = r1 + 1
													elseif presenting_side == "ne" then
														q1 = q1 + 1
														r1 = r1 - 1
													elseif presenting_side == "nw" then
														q1 = q1 - 1
														s1 = s1 + 1
													end
													local hex2 = from_cubic(q1, r1, s1)
													for l, poss_dest_hex in ipairs(dest_hex_list) do
														if hex2[1] == poss_dest_hex[1] and hex2[2] == poss_dest_hex[2] then
															source_hex = hex1
															dest_hex = hex2
														end
													end
												end
											end
											if source_hex ~= nil then
												break
											end
										end
									end
									if source_hex == nil then
										source_hex = source_hex_list[1]
										dest_hex = dest_hex_list[1]
									end
									local q1, r1, s1 = table.unpack(get_cubic(source_hex))
									local q2, r2, s2 = table.unpack(get_cubic(dest_hex))
									local r_dist = r2 - r1
									local s_dist = s2 - s1
									local inst = {}
									-- middle direction occurs anywhere from 25% to 75% of the way down corridor
									local first_prop = mathx.random() * 0.5 + 0.25
									if presenting_side == "sw" or presenting_side == "ne" then
										-- connecting SW:NE, so move in r, then s, then r
										local r1 = math.floor(r_dist * first_prop)
										local r2 = r_dist - r1
										for k = 1, math.abs(r1) do
											if r_dist < 0 then
												table.insert(inst, "ne")
											else
												table.insert(inst, "sw")
											end
										end
										for k = 1, math.abs(s_dist) do
											if s_dist < 0 then
												table.insert(inst, "se")
											else
												table.insert(inst, "nw")
											end
										end
										for k = 1, math.abs(r2) + 1 do
											if r_dist < 0 then
												table.insert(inst, "ne")
											else
												table.insert(inst, "sw")
											end
										end
									else
										-- connecting SE:NW, so move in s, then r, then s
										local s1 = math.floor(s_dist * first_prop)
										local s2 = s_dist - s1
										for k = 1, math.abs(s1) do
											if s_dist < 0 then
												table.insert(inst, "se")
											else
												table.insert(inst, "nw")
											end
										end
										for k = 1, math.abs(r_dist) do
											if r_dist < 0 then
												table.insert(inst, "ne")
											else
												table.insert(inst, "sw")
											end
										end
										for k = 1, math.abs(s2) + 1 do
											if s_dist < 0 then
												table.insert(inst, "se")
											else
												table.insert(inst, "nw")
											end
										end
									end
									-- make sure that side direction is at least slightly offset from room wall
									if #inst > 1 and (inst[1] ~= inst[2] or inst[#inst] ~= inst[#inst - 1]) then
										corridor_created = false
										corridor_tiles = {}
										corridor_attempts = corridor_attempts + 1
										break
									end
									corridor_tiles = plot_corridor(q1, r1, s1, corridor_width, inst)
									for t = 1, #corridor_tiles do
										local hex_x = corridor_tiles[t][1]
										local hex_y = corridor_tiles[t][2]
										-- make sure corridor doesn't go off edge of map
										if not (hex_x >= 1 and hex_x <= map_size_x and hex_y >=1 and hex_y <= map_size_y) then
												corridor_created = false
												break
										end
										-- make sure we won't exceed max_degree of a room
										for k = 1, num_rooms do
											if current_rooms[k]:contains_hex(hex_x, hex_y) and current_rooms[k].max_degree ~= nil and graph:degree(k) >= current_rooms[k].max_degree then
												corridor_created = false
												break
											end
										end
									end
									if not corridor_created then
										corridor_tiles = {}
										corridor_attempts = corridor_attempts + 1
										if corridor_attempts > max_corridor_attempts then
											-- give up on connecting these rooms
											connect_attempts = connect_attempts + 1
											corridor_created = true
										end
										break
									end
								end
								local current_origin_room_num = origin_room_num
								for t = 1, #corridor_tiles do
									local hex_x = corridor_tiles[t][1]
									local hex_y = corridor_tiles[t][2]
									-- check what connections we've made along the way (including but not limited to dest_room)
									for k = 1, num_rooms do
										if k ~= current_origin_room_num then
											if current_rooms[k]:contains_hex(hex_x, hex_y) then
												if graph:get_edge(current_origin_room_num, k) == 0 then
													print("Connecting room " .. origin_room.id .. " to room " .. dest_room.id)
													graph:set_edge(current_origin_room_num, k, 1)
													graph:set_edge(k, current_origin_room_num, 1)
												end
												-- if corridor from A -> C goes through B, then link A:B and B:C (but not A:C) in graph
												current_origin_room_num = k
											end
										end
									end
									-- only overwrite wall terrains
									if string.sub(wesnoth.current.map[{hex_x, hex_y}], 1, 1) == "X" then
										wesnoth.current.map[{hex_x, hex_y}] = "Isa" -- "Gg"
									end
									connect_attempts = 0
								end
							end
							casting_ray = false
							break
						end
					end
				end
				radius = radius + 1
			else
				casting_ray = false
				rays_failed = rays_failed + 1
			end
		end
	--	if connect_attempts > max_connect_attempts then
	--		break
	--	end
	end
end

local function place_healing_glyphs(rooms)
	local healing_glyph_locs = {}
	for i, room in ipairs(rooms) do
		if string.sub(room.id, 1, 6) == "random" then
			-- 50% of random rooms get a healing glyph
			if (i % 2) == 0 then
				local room_inner_hexes = room:get_inner_hexes()
				local hex = room_inner_hexes[mathx.random(1, #room_inner_hexes)]
				wesnoth.interface.add_item_image(hex[1], hex[2], "scenery/rune5.png")
				table.insert(healing_glyph_locs, hex)
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

-- since it's just Malakar and his loadout's quite variable
-- overall difficulty scales based on Malakar and set difficulty
function calc_difficulty_score()
	local score = 1
	if wesnoth.scenario.difficulty == "NORMAL" then
		score = score + 2
	end
	if wesnoth.scenario.difficulty == "HARD" then
		score = score + 2
	end
	local malakar = wesnoth.units.get("Malakar")
	score = score + malakar.level
	-- from S7B
	if malakar.variables["has_elemental_powerup"] then
		score = score + 1
	end
	-- from S3A
	if malakar.variation ~= nil and malakar.variation == "weapon" then
		score = score + 1
	end
	wml.variables["difficulty_score"] = score
	return score
end

function randomize_map()
	local all_rooms = {}

	local num_orb_rooms = 5
	if wesnoth.scenario.difficulty == "EASY" then
		num_orb_rooms = 4
	elseif wesnoth.scenario.difficulty == "HARD" then
		num_orb_rooms = 6
	end
	-- start out by placing and setting up story-important rooms
	all_rooms = place_story_rooms(all_rooms, num_orb_rooms)

	-- now make and position some random rooms (not involved in objectives)
	all_rooms = place_random_rooms(all_rooms)

	-- for debug purposes, label all rooms in map
	for i, room in ipairs(all_rooms) do
		local center_x, center_y = table.unpack(room:get_approx_center())
		wesnoth.map.add_label({x=center_x, y=center_y, text=room.id})
	end

	place_corridors(all_rooms)

	-- scatter healing and damage glyphs
	local healing_glyphs = place_healing_glyphs(all_rooms)
	hex_list_to_wml_var(healing_glyphs, "healing_glyph_x", "healing_glyph_y")

	local damage_glyphs = place_damage_glyphs(15)
	hex_list_to_wml_var(damage_glyphs, "damage_glyph_x", "damage_glyph_y")
end

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

function wesnoth.wml_actions.handle_orb(cfg)
	local orb_destroyed = false
	local x = cfg.x
	local y = cfg.y
	local items_list = wesnoth.interface.get_items(x, y)
	for i, item in ipairs(items_list) do
		local image_path = item.image
		if string.len(image_path) >= 31 and string.sub(image_path, 1, 31) == "items/magic-orb.png~RC(magenta>" then
			-- todo: give player choice whether or not to destroy orb
			-- todo: some sort of animation with orb destruction
			orb_destroyed = true
			local base, orb_color = table.unpack(stringx.split(image_path, ">"))
			orb_color = string.sub(orb_color, 1, #orb_color - 1)
			wesnoth.interface.remove_item(x, y, image_path)
			local orb_colors = stringx.split(wml.variables["orb_colors"], ",")
			local orbs_x = functional.map(stringx.split(wml.variables["orbs_x"], ","), function(s) return tonumber(s) end)
			local orbs_y = functional.map(stringx.split(wml.variables["orbs_y"], ","), function(s) return tonumber(s) end)
			-- if orb_colors[1] ~= orb_color then
				-- player smashed orb out of sequence, do something bad
			-- end
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
			wml.variables["num_orbs"] = #orb_colors
			-- todo: use up Malakar's attacks and moves
		end
	end
	if not orb_destroyed then
		wesnoth.wml_actions.allow_undo()
	end
end
