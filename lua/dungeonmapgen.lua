wesnoth.dofile('~add-ons/Flight_Freedom/lua/graph_utils.lua')

------------------------
----- Room base class that implements room tracking, collision checking, and basic terrain painting
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

---Set dimensions of this Room
---@param r_height integer #Dimension of the room in r axis (NE to SW)
---@param s_height integer #Dimension of the room in s axis (NW to SE)
function Room:set_dimensions(r_height, s_height)
	self.r_height = r_height
	self.s_height = s_height
end

---Move a Room by its left corner (which will be part of its wall)
---@param x integer #x-coordinate of left corner
---@param y integer #y-coordinate of left corner
function Room:set_left_corner(x, y)
	self.x1 = x
	self.y1 = y
end

---Get coordinates of this Room's left corner
---@return location
function Room:left_corner()
	return {self.x1, self.y1}
end

---Get coordinates of this Room's top corner
---@return location
function Room:top_corner()
	local q, r, s = table.unpack(get_cubic({self.x1, self.y1}))
	q = q + (self.r_height - 1)
	r = r - (self.r_height - 1)
	return from_cubic(q, r, s)
end

---Get coordinates of this Room's bottom corner
---@return location
function Room:bottom_corner()
	local q, r, s = table.unpack(get_cubic({self.x1, self.y1}))
	q = q + (self.s_height - 1)
	s = s - (self.s_height - 1)
	return from_cubic(q, r, s)
end

---Get coordinates of this Room's right corner
---@return location
function Room:right_corner()
	local q, r, s = table.unpack(get_cubic({self.x1, self.y1}))
	q = q + (self.r_height - 1) + (self.s_height - 1)
	r = r - (self.r_height - 1)
	s = s - (self.s_height - 1)
	return from_cubic(q, r, s)
end

---Get coordinates of this Room's approximate center tile
---If the Room's center would fall in between tiles, return one of the tiles that would border its center
---@return location
function Room:get_approx_center()
	local q, r, s = table.unpack(get_cubic({self.x1, self.y1}))
	local half_r_height = math.ceil(self.r_height / 2)
	local half_s_height = math.ceil(self.s_height / 2)
	q = q + (half_r_height - 1) + (half_s_height - 1)
	r = r - (half_r_height - 1)
	s = s - (half_s_height - 1)
	return from_cubic(q, r, s)
end

---Test if this Room would fit within the bounds of the map
---@return boolean
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

---Test if the provided hex is within the Room, including its walls
---@param x integer
---@param y integer
---@return boolean
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

---Obtain list of the wall/edge hexes of this Room
---@return location[]
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

---Obtain lists of the wall/edge hexes of this Room, separated by direction
---@return location[] #Hexes along the NW edge
---@return location[] #Hexes along the NE edge
---@return location[] #Hexes along the SW edge
---@return location[] #Hexes along the SE edge
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

---Paint the Room's wall hexes with the specified terrain
---@param terrain string #The terrain code to paint
function Room:set_wall_terrain(terrain)
	local edge_hexes = self:get_edge_hexes()
	for i, hex in ipairs(edge_hexes) do
		local x1 = hex[1]
		local y1 = hex[2]
		wesnoth.current.map[{x1, y1}] = terrain
	end
end

---Obtain list of the inner hexes (i.e. not part of the walls) of this Room
---@return location[]
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

---Paint the Room's inner hexes with the specified terrain
---@param terrain string #The terrain code to paint
function Room:set_inner_terrain(terrain)
	local inner_hexes = self:get_inner_hexes()
	for i, hex in ipairs(inner_hexes) do
		local x1 = hex[1]
		local y1 = hex[2]
		wesnoth.current.map[{x1, y1}] = terrain
	end
end

---Check if any of the border tiles of Room r1 are in Room r2
---@param r1 Room
---@param r2 Room
---@return boolean
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

---Check if this Room intersects with another
---@param r2 Room
---@return boolean
function Room:intersects_with(r2)
	local intersects = false
	return (Room.half_intersect(self, r2) or Room.half_intersect(r2, self))
end

---Obtain the approximate direction of Room r2 from this Room
---@param r2 Room
---@alias presenting_side
---| se #r2 is to the SE of this Room
---| sw #r2 is to the SW of this Room
---| ne #r2 is to the NE of this Room
---| nw #r2 is to the NW of this Room
---@return presenting_side string #The direction to Room r2
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

---Find the shortest distance between any wall tile of this Room to any wall tile of Room r2
---@param r2 Room
---@return integer
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

---Code to set up room before corridors are plotted
---Intended to be overriden by user-defined derived classes
function Room:pre_corridor_setup()
end

---Code to set up room after corridors are plotted
---Intended to be overriden by user-defined derived classes
function Room:post_corridor_setup()
end

------------------------
----- DungeonMapGen class for main map generator functions
------------------------

DungeonMapGen = {
	rooms_list = {}
	}

function DungeonMapGen:new(o)
	o = o or {}
	setmetatable(o, self)
	self.__index = self
	return o
end

---Make this DungeonMapGen aware of a new Room
---@param room Room
function DungeonMapGen:register_room(room)
	table.insert(self.rooms_list, room)
end

---Obtain the list of currently registered Rooms
---@return Room[]
function DungeonMapGen:get_rooms_list()
	return self.rooms_list
end

---Attempt to place a Room on the map within desired parameters
---Note that this does NOT register the room
---@param room Room #The Room (or more likely an instance of a Room subclass) to be placed
---@param min_x integer #Minimum x coordinate for Room's left corner
---@param min_y integer #Minimum y coordinate for Room's left corner
---@param max_x integer #Maximum x coordinate for Room's left corner
---@param max_y integer #Maximum y coordinate for Room's left corner
---@param essential boolean #If false, then give up after 200 attempts to find a suitable positioning
---@return boolean #true if room placed, otherwise returns false
function DungeonMapGen:find_room_placement(room, min_x, max_x, min_y, max_y, essential)
	local attempts = 0
	local max_attempts = 200
	local placed = false
	while not placed do
		local x1 = mathx.random(min_x, max_x)
		local y1 = mathx.random(min_y, max_y)
		room:set_left_corner(x1, y1)
		if room:fits_in_map() then
			local intersects = false
			for i, r2 in ipairs(self.rooms_list) do
				if room:intersects_with(r2) then
					intersects = true
					break
				end
			end
			if not intersects then
				placed = true
			end
		end
		attempts = attempts + 1
		if (not essential) and (attempts > max_attempts) then
			break
		end
	end
	return placed
end

---Attempt to place a room anywhere on the map
---Note that this does NOT register the room
---@param room Room #The Room (or more likely an instance of a Room subclass) to be placed
---@param essential boolean #If false, then give up after 200 attempts to find a suitable positioning
---@return boolean #true if room placed, otherwise returns false
function DungeonMapGen:find_placement_anywhere(room, essential)
	local map_size_x = wesnoth.current.map.playable_width
	local map_size_y = wesnoth.current.map.playable_height
	return self:find_room_placement(room, 1, map_size_x, 1, map_size_y, essential)
end

---Identify hexes along a specified corridor
---@param q integer #q coordinate of starting hex (in cubic coordinates)
---@param r integer #r coordinate of starting hex (in cubic coordinates)
---@param s integer #s coordinate of starting hex (in cubic coordinates)
---@param corridor_width integer #Width of corridor in hexes
---@alias instruction
---| nw #Extend the corridor NW
---| ne #Extend the corridor NE
---| sw #Extend the corridor SW
---| se #Extend the corridor SE
---@param inst_list instruction[] #List of instructions to extend the tunnel
---@return location[]
function DungeonMapGen:plot_corridor(q, r, s, corridor_width, inst_list)
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

---Calculate and paint corridors between all registered Rooms
---Any Room with max_degree set will have no more than that number of connecting corridors
---Note: corridors will only paint over wall terrain (i.e. terrain codes that begin with 'X')
---@param terrain_type string #The terrain code to paint
---@return graph #Graph object containing connections between Rooms. Node indices correspond to the order of registered Rooms in the DungeonMapGen object.
---@return boolean #true if algorithm was able to connect all rooms, otherwise false
function DungeonMapGen:place_corridors(terrain_type)
	local map_size_x = wesnoth.current.map.playable_width
	local map_size_y = wesnoth.current.map.playable_height
	local current_rooms = self.rooms_list
	-- build graph of all rooms
	local num_rooms = #current_rooms
	local graph = Graph:new()
	graph:init_unconnected(num_rooms)
	-- until graph is fully connected, i.e. all rooms are accessible:
	--   pick random room
	--   cast a ray at random angle
	--   first room that we hit (if any), if no edge between source and destination try to connect them (both in graph and on map)
	local max_connect_attempts = 1000 -- avoid infinte loop in case there's a room that can't be connected anywhere
	local connect_attempts = 0 -- tracks number of failed connections (resets if successful connection made)
	local rays_failed = 0
	local starting_max_ray_length = 15 -- restrict maximum distance algorithm will try to connect rooms
	local successful = true
	while not graph:is_connected() do
		local origin_room_selected = false
		local origin_room_num = nil
		local origin_room = nil
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
									corridor_tiles = self:plot_corridor(q1, r1, s1, corridor_width, inst)
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
												-- left and right corners don't permit unit movement into rooms so don't count them as graph connections
												local k_left_corner_x, k_left_corner_y = table.unpack(current_rooms[k]:left_corner())
												local k_right_corner_x, k_right_corner_y = table.unpack(current_rooms[k]:right_corner())
												if (k_left_corner_x ~= hex_x or k_left_corner_y ~= hex_y) and (k_right_corner_x ~= hex_x or k_right_corner_y ~= hex_y) then
													if graph:get_edge(current_origin_room_num, k) == 0 then
														--print("Connecting room " .. current_rooms[current_origin_room_num].id .. " to room " .. current_rooms[k].id)
														graph:set_edge(current_origin_room_num, k, 1)
														graph:set_edge(k, current_origin_room_num, 1)
													end
													-- if corridor from A -> C goes through B, then link A:B and B:C (but not A:C) in graph
													current_origin_room_num = k
												end
											end
										end
									end
									-- only overwrite wall terrains
									if string.sub(wesnoth.current.map[{hex_x, hex_y}], 1, 1) == "X" then
										wesnoth.current.map[{hex_x, hex_y}] = terrain_type
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
		if connect_attempts > max_connect_attempts then
			successful = false
			break
		end
	end
	return {graph, successful}
end

---Execute the pre_corridor_setup of all registered Rooms
function DungeonMapGen:pre_corridor_setup()
	for i, r in ipairs(self.rooms_list) do
		r:pre_corridor_setup()
	end
end

---Execute the post_corridor_setup of all registered Rooms
function DungeonMapGen:post_corridor_setup()
	for i, r in ipairs(self.rooms_list) do
		r:post_corridor_setup()
	end
end

---For debug purposes, label rooms in map
---Requires room.id to be set for every Room
function DungeonMapGen:label_rooms()
	for i, room in ipairs(self.rooms_list) do
		local center_x, center_y = table.unpack(room:get_approx_center())
		wesnoth.map.add_label({x=center_x, y=center_y, text=room.id})
	end
end
