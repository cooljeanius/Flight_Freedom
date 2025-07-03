-- Lua code used by scenario 11B (Sol'Kan's Lair)

wesnoth.dofile('~add-ons/Flight_Freedom/lua/graph_utils.lua')

local function trunc(n)
	if n >= 0.0 then
		return math.floor(n)
	else
		return math.ceil(n)
	end
end

-- since mainline wesnoth.map.from_cubic is broken as of 1.19.13, reimplement it here
-- (c++ backend expects a cubic_location struct which isn't accessble to lua)
local function from_cubic(q, r, s)
	local x = q
	local y = r + trunc((q + (math.abs(q) % 2)) / 2)
	return({x, y})
end

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
	local q, r, s = table.unpack(wesnoth.map.get_cubic({self.x1, self.y1}))
	q = q + (self.r_height - 1)
	r = r - (self.r_height - 1)
	return from_cubic(q, r, s)
end

function Room:bottom_corner()
	local q, r, s = table.unpack(wesnoth.map.get_cubic({self.x1, self.y1}))
	q = q + (self.s_height - 1)
	s = s - (self.s_height - 1)
	return from_cubic(q, r, s)
end

function Room:right_corner()
	local q, r, s = table.unpack(wesnoth.map.get_cubic({self.x1, self.y1}))
	q = q + (self.r_height - 1) + (self.s_height - 1)
	r = r - (self.r_height - 1)
	s = s - (self.s_height - 1)
	return from_cubic(q, r, s)
end

function Room:get_approx_center()
	local q, r, s = table.unpack(wesnoth.map.get_cubic({self.x1, self.y1}))
	local half_r_height = math.floor(self.r_height / 2)
	local half_s_height = math.floor(self.s_height / 2)
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
	local x2, y2 = table.unpack(self:bottom_corner())
	if (x2 < 1) or (y2 < 1) or (x2 > map_size_x) or (y2 > map_size_y) then
		fits = false
	end
	local x2, y2 = table.unpack(self:right_corner())
	if (x2 < 1) or (y2 < 1) or (x2 > map_size_x) or (y2 > map_size_y) then
		fits = false
	end
	return fits
end

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

------------------------
----- now set up the map
------------------------

local map_size_x = wesnoth.current.map.playable_width
local map_size_y = wesnoth.current.map.playable_height

all_rooms = {}

-- essential=true used for story rooms
local function find_room(r_height, s_height, min_x, max_x, min_y, max_y, essential)
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
				for i, r2 in ipairs(all_rooms) do
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

-- start out by placing story-important rooms

-- start room in bottom left of the map
local start_room = find_room(8, 8, 1, 1, math.floor(map_size_y * 0.75), map_size_y, true)
start_room.id = "start_room"
start_room:set_inner_terrain("Isa")
start_room:set_wall_terrain("Xor")
table.insert(all_rooms, start_room)

-- cave passage in
local start_room_x, start_room_y = table.unpack(start_room:left_corner())
wesnoth.wml_actions.terrain_mask({
	mask = filesystem.read_file("~add-ons/Flight_Freedom/masks/13b_cave_entrance.mask"),
	x = start_room_x,
	y = start_room_y + 1,
	border = true,
})

local malakar_start_x = start_room_x + 6
local malakar_start_y = start_room_y
wesnoth.units.get("Malakar"):to_map(malakar_start_x, malakar_start_y)

-- control room in top right of the map
local control_room = find_room(12, 9, math.floor(map_size_x * 0.5), map_size_x, 1, math.floor(map_size_y * 0.25), true)
control_room.id = "control_room"
control_room:set_inner_terrain("Isa")
control_room:set_wall_terrain("Xoi")
table.insert(all_rooms, control_room)

-- now make and position some random rooms (not involved in objectives)
random_rooms = {}

local num_random_rooms = 12
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
	local r = find_room(r_height, s_height, 1, map_size_x, 1, map_size_y, false)
	if r ~= nil then
		r.id = "random_" .. tostring(rand_rooms_generated)
		r:set_inner_terrain("Isa")
		rand_rooms_generated = rand_rooms_generated + 1
		table.insert(all_rooms, r)
		table.insert(random_rooms, r)
	end
end

-- populate random rooms
for i = 1, rand_rooms_generated do
	-- undead
	if i >= 1 and i <= 4 then
		random_rooms[i]:set_wall_terrain("Xot") -- catacombs
	end
end

-- build graph of all rooms
local num_rooms = #all_rooms
graph = Graph:new()
graph:init_unconnected(num_rooms)

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

-- until graph is fully connected, i.e. all rooms are accessible:
---- pick random room
---- cast a ray at random angle
---- first room that we hit (if any), if no edge between source and destination connect them (both in graph and on map)
local max_connect_attempts = 1000 -- avoid infinte loop in case there's a room that can't be connected anywhere
local connect_attempts = 0 -- tracks number of failed connections (resets if successful connection made)
--local corridor_created = false
--while not corridor_created do
while not graph:is_connected() do
	local origin_room_num = mathx.random(1, num_rooms)
	local origin_room = all_rooms[origin_room_num]
	local center_x, center_y = table.unpack(origin_room:get_approx_center())
	local theta = mathx.random() * math.pi * 2.0
	local radius = 1
	local casting_ray = true
	while casting_ray do
		local test_x, test_y = find_offset_hex_polar(center_x, center_y, radius, theta)
		if test_x >= 1 and test_x <= map_size_x and test_y >= 1 and test_y <= map_size_y then
			for i = 1, num_rooms do
				if i ~= origin_room_num then
					if all_rooms[i]:contains_hex(test_x, test_y) then
						local dest_room = all_rooms[i]
						-- don't make duplicate tunnels between rooms
						if graph:get_edge(origin_room_num, i) == 0 then
							-- update connection in rooms graph
							graph:set_edge(origin_room_num, i, 1)
							graph:set_edge(i, origin_room_num, 1)
							-- create corridor on map
							local corridor_created = false
							local corridor_tiles = {}
							local max_corridor_attempts = 200
							local corridor_attempts = 0
							while not corridor_created do
								corridor_created = true
								local corridor_width = 2 -- mathx.random(2, 3)
								local half_corridor_width = math.floor(corridor_width / 2)
								local dest_center_x, dest_center_y = table.unpack(dest_room:get_approx_center())
								local source_hex_list = nil
								local dest_hex_list = nil
								if center_x < dest_center_x and center_y < dest_center_y then
									-- SE of origin to NW of destination
									source_hex_list = origin_room:get_specific_edge_hexes()[4]
									dest_hex_list = dest_room:get_specific_edge_hexes()[1]
								elseif center_x >= dest_center_x and center_y < dest_center_y then
									-- SW of origin to NE of destination
									source_hex_list = origin_room:get_specific_edge_hexes()[3]
									dest_hex_list = dest_room:get_specific_edge_hexes()[2]
								elseif center_x < dest_center_x and center_y >= dest_center_y then
									-- NE of origin to SW of destination
									source_hex_list = origin_room:get_specific_edge_hexes()[2]
									dest_hex_list = dest_room:get_specific_edge_hexes()[3]
								elseif center_x >= dest_center_x and center_y >= dest_center_y then
									-- NW of origin to SE of destination
									source_hex_list = origin_room:get_specific_edge_hexes()[1]
									dest_hex_list = dest_room:get_specific_edge_hexes()[4]
								end
								-- exclude left and right corners as possible connection points
								local source_hex = source_hex_list[mathx.random(2, (#source_hex_list - 1))]
								local dest_hex = dest_hex_list[mathx.random(2, (#dest_hex_list - 1))]
								local q1, r1, s1 = table.unpack(wesnoth.map.get_cubic(source_hex))
								local q2, r2, s2 = table.unpack(wesnoth.map.get_cubic(dest_hex))
								local r_dist = r2 - r1
								local s_dist = s2 - s1
								local inst = {}
								-- middle direction occurs anywhere from 25% to 75% of the way down corridor
								local first_prop = mathx.random() * 0.5 + 0.25
								if (center_x < dest_center_x and center_y >= dest_center_y) or (center_x >= dest_center_x and center_y < dest_center_y) then
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
								corridor_tiles = plot_corridor(q1, r1, s1, corridor_width, inst)
								for t = 1, #corridor_tiles do
									local hex_x = corridor_tiles[t][1]
									local hex_y = corridor_tiles[t][2]
									if not (hex_x >= 1 and hex_x <= map_size_x and hex_y >=1 and hex_y <= map_size_y) then
										corridor_created = false
										corridor_tiles = {}
										corridor_attempts = corridor_attempts + 1
										if corridor_attempts > max_corridor_attempts then
											-- give up on connecting these rooms
											graph:set_edge(origin_room_num, i, 0)
											graph:set_edge(i, origin_room_num, 0)
											connect_attempts = connect_attempts + 1
											corridor_created = true
										end
										break
									end
								end
							end
							for t = 1, #corridor_tiles do
								local hex_x = corridor_tiles[t][1]
								local hex_y = corridor_tiles[t][2]
								-- check if we've made any additional connections along the way
								for k = 1, num_rooms do
									if k ~= origin_room_num then
										if all_rooms[k]:contains_hex(hex_x, hex_y) then
											graph:set_edge(origin_room_num, k, 1)
											graph:set_edge(k, origin_room_num, 1)
										end
									end
								end
								wesnoth.current.map[{hex_x, hex_y}] = "Isa" -- "Gg"
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
		end
	end
--	if connect_attempts > max_connect_attempts then
--		break
--	end
end
