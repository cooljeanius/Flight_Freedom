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

function Room:set_inner_terrain(terrain, wall_size)
	local x1 = self.x1
	local x2 = self.x1 + (self.r_height - 1) + (self.s_height - 1)
	local y1 = self.y1
	local y2 = self.y1
	for x_cur = x1, x2 do
		local x_dist = x_cur - x1 + 1
		if (x_cur - x1) > (wall_size - 1) and (x2 - x_cur) > (wall_size - 1) then
			for y_cur = y1, y2 do
				if (y_cur - y1) > (wall_size - 1) and (y2 - y_cur) > (wall_size - 1) then
					wesnoth.current.map[{x_cur, y_cur}] = terrain
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
end

function Room:set_wall_terrain(terrain, wall_size)
	local x1 = self.x1
	local x2 = self.x1 + (self.r_height - 1) + (self.s_height - 1)
	local y1 = self.y1
	local y2 = self.y1
	for x_cur = x1, x2 do
		local x_dist = x_cur - x1 + 1
		for y_cur = y1, y2 do
			if (y_cur - y1) <= (wall_size - 1) or (y2 - y_cur) <= (wall_size - 1) then
				wesnoth.current.map[{x_cur, y_cur}] = terrain
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
start_room:set_inner_terrain("Isa", 1)
start_room:set_wall_terrain("Xor", 1)
table.insert(all_rooms, start_room)

-- cave passage in
local start_room_x, start_room_y = table.unpack(start_room:left_corner())
wesnoth.current.map[{start_room_x + 1, start_room_y}] = "Xur"
wesnoth.current.map[{start_room_x, start_room_y + 1}] = "Xur"
wesnoth.current.map[{start_room_x - 1, start_room_y + 1}] = "Xur"
wesnoth.current.map[{start_room_x + 1, start_room_y + 3}] = "Xur"
wesnoth.current.map[{start_room_x, start_room_y + 4}] = "Xur"
wesnoth.current.map[{start_room_x - 1, start_room_y + 4}] = "Xur"
wesnoth.current.map[{start_room_x + 2, start_room_y + 3}] = "Xur"
wesnoth.current.map[{start_room_x + 3, start_room_y + 2}] = "Xur"
wesnoth.current.map[{start_room_x + 1, start_room_y + 1}] = "Uu"
wesnoth.current.map[{start_room_x + 2, start_room_y + 1}] = "Uu"
wesnoth.current.map[{start_room_x + 3, start_room_y + 1}] = "Uu"
wesnoth.current.map[{start_room_x + 2, start_room_y + 2}] = "Uu"
wesnoth.current.map[{start_room_x, start_room_y + 2}] = "Uu"
wesnoth.current.map[{start_room_x + 1, start_room_y + 2}] = "Uu"
wesnoth.current.map[{start_room_x - 1, start_room_y + 2}] = "Uu"
wesnoth.current.map[{start_room_x, start_room_y + 3}] = "Uu"
wesnoth.current.map[{start_room_x - 1, start_room_y + 3}] = "Uu"

local malakar_start_x = start_room_x + 6
local malakar_start_y = start_room_y
wesnoth.units.get("Malakar"):to_map(malakar_start_x, malakar_start_y)

-- control room in top right of the map
local control_room = find_room(12, 9, math.floor(map_size_x * 0.5), map_size_x, 1, math.floor(map_size_y * 0.25), true)
control_room:set_inner_terrain("Isa", 1)
control_room:set_wall_terrain("Xoi", 1)
table.insert(all_rooms, control_room)

random_rooms = {}

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
	local r = find_room(r_height, s_height, 1, map_size_x, 1, map_size_y, false)
	if r ~= nil then
		r:set_inner_terrain("Isa", 1)
		rand_rooms_generated = rand_rooms_generated + 1
		table.insert(all_rooms, r)
		table.insert(random_rooms, r)
	end
end

-- build graph of all rooms
local num_rooms = #all_rooms
graph = Graph:new()
graph:init_unconnected(num_rooms)

-- until graph is fully connected, i.e. all rooms are accessible:
---- pick random room
---- cast a ray at random angle
---- first room that we hit (if any), if no edge between source and destination connect them (both in graph and on map)
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
							local tunnel_tiles = {}
							local max_attempts = 200
							local attempts = 0
							while not corridor_created do
								corridor_created = true
								local corridor_width = 2 -- mathx.random(2, 3)
								local half_corridor_width = math.floor(corridor_width / 2)
								local source_r_offset = mathx.random(-1 * math.floor((origin_room.r_height - 1) / 3), math.floor((origin_room.r_height - 1) / 3))
								local source_s_offset = mathx.random(-1 * math.floor((origin_room.s_height - 1) / 3), math.floor((origin_room.s_height - 1) / 3))
								print(center_x)
								print(center_y)
								local q1, r1, s1 = table.unpack(wesnoth.map.get_cubic({center_x, center_y}))
								-- cubic coordinates of start hex in the origin room
								q1 = q1 + source_r_offset + source_s_offset
								r1 = r1 - source_r_offset
								s1 = s1 - source_s_offset
								-- print(from_cubic(q1, r1, s1)[1])
								-- print(from_cubic(q1, r1, s1)[2])
								-- print("-")
								local dest_center_x, dest_center_y = table.unpack(dest_room:get_approx_center())
								-- print(dest_center_x)
								-- print(dest_center_y)
								local dest_r_offset = mathx.random(-1 * math.floor((dest_room.r_height - 1) / 3), math.floor((dest_room.r_height - 1) / 3))
								local dest_s_offset = mathx.random(-1 * math.floor((dest_room.s_height - 1) / 3), math.floor((dest_room.s_height - 1) / 3))
								local q2, r2, s2 = table.unpack(wesnoth.map.get_cubic({dest_center_x, dest_center_y}))
								-- cubic coordinates of end hex in the destination room
								q2 = q2 + dest_r_offset + dest_s_offset
								r2 = r2 - dest_r_offset
								s2 = s2 - dest_s_offset
								-- print(from_cubic(q2, r2, s2)[1])
								-- print(from_cubic(q2, r2, s2)[2])
								-- print("-")
								-- q, r, and s track the middle of the tunnel
								local q = q1
								local r = r1
								local s = s1
								if mathx.random() > 0.5 then
									-- move in r axis first
									if r1 < r2 then
										while r < r2 do
											-- we're moving along positive r axis, i.e. SW
											-- q_hex, r_hex, and s_hex vary based on corridor width
											local q_hex = q
											local r_hex = r
											local s_hex = s
											-- tunnel width is along s axis, so start by moving halfway along positive s axis (i.e. NW)
											q_hex = q_hex - half_corridor_width
											s_hex = s_hex + half_corridor_width
											for w = 1, corridor_width do
												table.insert(tunnel_tiles, from_cubic(q_hex, r_hex, s_hex))
												-- now sweep along negative s axis (i.e. SE)
												q_hex = q_hex + 1
												s_hex = s_hex - 1
											end
											-- now advance along positive r
											q = q - 1
											r = r + 1
										end
									else
										while r > r2 do
											-- we're moving along negative r axis, i.e. NE
											local q_hex = q
											local r_hex = r
											local s_hex = s
											q_hex = q_hex - half_corridor_width
											s_hex = s_hex + half_corridor_width
											for w = 1, corridor_width do
												table.insert(tunnel_tiles, from_cubic(q_hex, r_hex, s_hex))
												q_hex = q_hex + 1
												s_hex = s_hex - 1
											end
											-- now advance along negative r
											q = q + 1
											r = r - 1
										end
									end
									-- now move in s axis
									if s1 < s2 then
										while s < s2 do
											local q_hex = q
											local r_hex = r
											local s_hex = s
											-- tunnel width is along r axis, so start by moving halfway along positive r axis (i.e. SW)
											q_hex = q_hex - half_corridor_width
											r_hex = r_hex + half_corridor_width
											for w = 1, corridor_width do
												table.insert(tunnel_tiles, from_cubic(q_hex, r_hex, s_hex))
												-- now sweep along negative r axis (i.e. NE)
												q_hex = q_hex + 1
												r_hex = r_hex - 1
											end
											-- now advance along positive s
											q = q - 1
											s = s + 1
										end
									else
										while s > s2 do
											local q_hex = q
											local r_hex = r
											local s_hex = s
											-- tunnel width is along r axis, so start by moving halfway along positive r axis (i.e. SW)
											q_hex = q_hex - half_corridor_width
											r_hex = r_hex + half_corridor_width
											for w = 1, corridor_width do
												table.insert(tunnel_tiles, from_cubic(q_hex, r_hex, s_hex))
												-- now sweep along negative r axis (i.e. NE)
												q_hex = q_hex + 1
												r_hex = r_hex - 1
											end
											-- now advance along negative s
											q = q + 1
											s = s - 1
										end
									end
								else
									-- move in s axis first
									if s1 < s2 then
										while s < s2 do
											local q_hex = q
											local r_hex = r
											local s_hex = s
											-- tunnel width is along r axis, so start by moving halfway along positive r axis (i.e. SW)
											q_hex = q_hex - half_corridor_width
											r_hex = r_hex + half_corridor_width
											for w = 1, corridor_width do
												table.insert(tunnel_tiles, from_cubic(q_hex, r_hex, s_hex))
												-- now sweep along negative r axis (i.e. NE)
												q_hex = q_hex + 1
												r_hex = r_hex - 1
											end
											-- now advance along positive s
											q = q - 1
											s = s + 1
										end
									else
										while s > s2 do
											local q_hex = q
											local r_hex = r
											local s_hex = s
											-- tunnel width is along r axis, so start by moving halfway along positive r axis (i.e. SW)
											q_hex = q_hex - half_corridor_width
											r_hex = r_hex + half_corridor_width
											for w = 1, corridor_width do
												table.insert(tunnel_tiles, from_cubic(q_hex, r_hex, s_hex))
												-- now sweep along negative r axis (i.e. NE)
												q_hex = q_hex + 1
												r_hex = r_hex - 1
											end
											-- now advance along negative s
											q = q + 1
											s = s - 1
										end
									end
									-- now move in r axis
									if r1 < r2 then
										while r < r2 do
											-- we're moving along positive r axis, i.e. SW
											-- q_hex, r_hex, and s_hex vary based on corridor width
											local q_hex = q
											local r_hex = r
											local s_hex = s
											-- tunnel width is along s axis, so start by moving halfway along positive s axis (i.e. NW)
											q_hex = q_hex - half_corridor_width
											s_hex = s_hex + half_corridor_width
											for w = 1, corridor_width do
												table.insert(tunnel_tiles, from_cubic(q_hex, r_hex, s_hex))
												-- now sweep along negative s axis (i.e. SE)
												q_hex = q_hex + 1
												s_hex = s_hex - 1
											end
											-- now advance along positive r
											q = q - 1
											r = r + 1
										end
									else
										while r > r2 do
											-- we're moving along negative r axis, i.e. NE
											local q_hex = q
											local r_hex = r
											local s_hex = s
											q_hex = q_hex - half_corridor_width
											s_hex = s_hex + half_corridor_width
											for w = 1, corridor_width do
												table.insert(tunnel_tiles, from_cubic(q_hex, r_hex, s_hex))
												q_hex = q_hex + 1
												s_hex = s_hex - 1
											end
											-- now advance along negative r
											q = q + 1
											r = r - 1
										end
									end
								end
								for t = 1, #tunnel_tiles do
									local hex_x = tunnel_tiles[t][1]
									local hex_y = tunnel_tiles[t][2]
									if not (hex_x >= 1 and hex_x <= map_size_x and hex_y >=1 and hex_y <= map_size_y) then
										corridor_created = false
										tunnel_tiles = {}
										attempts = attempts + 1
										if attempts > max_attempts then
											-- give up on connecting these rooms
											graph:set_edge(origin_room_num, i, 0)
											graph:set_edge(i, origin_room_num, 0)
										end
										break
									end
								end
							end
							for t = 1, #tunnel_tiles do
								local hex_x = tunnel_tiles[t][1]
								local hex_y = tunnel_tiles[t][2]
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
end
