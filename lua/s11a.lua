-- Lua code used by scenario 11A (River of Skulls)

wesnoth.dofile('~add-ons/Flight_Freedom/lua/graph_utils.lua')

local start_node = 1
local dest_node = 23
local num_nodes = 23

--terrain coordinates that need to be changed to close a graph edge
--see extras/s11_regions.jpg
local terrains_to_close = {}
terrains_to_close[1] =
{
	[2] = {{18, 10}},
	[3] = {{17, 13}, {18, 13}, {22, 16}, {23, 17}},
	[4] = {{24, 16}, {25, 16}},
	[5] = {{28, 14}, {29, 14}},
}
terrains_to_close[2] =
{
	[3] = {{14, 15}, {15, 15}},
	[6] = {{7, 15}, {8, 15}, {9, 16}, {9, 17}},
}
terrains_to_close[3] =
{
	[7] = {{12, 17}},
	[8] = {{14, 17}, {15, 17}},
}
terrains_to_close[4] =
{
	[5] = {{33, 20}, {33, 21}, {34, 20}},
	[11] = {{31, 21}, {32, 21}, {33, 21}},
}
terrains_to_close[5] =
{
	[12] = {{35, 21}, {36, 20}},
}
terrains_to_close[6] =
{
	[7] = {{5, 28}, {5, 29}},
}
terrains_to_close[7] =
{
	[8] = {{13, 25}},
	[13] = {{8, 31}},
}
terrains_to_close[8] =
{
	[9] = {{15, 25}, {16, 24}},
}
terrains_to_close[9] =
{
	[10] = {{24, 24}, {24, 25}},
	[14] = {{22, 27}},
}
terrains_to_close[10] =
{
	[11] = {{30, 21}, {30, 22}},
	[14] = {{23, 29}, {24, 29}},
	[15] = {{31, 31}, {31, 32}},
	[16] = {{26, 31}},
}
terrains_to_close[11] =
{
	[15] = {{31, 28}, {32, 28}},
}
terrains_to_close[12] =
{
	[15] = {{35, 29}, {36, 29}},
}
terrains_to_close[13] =
{
	[14] = {{13, 31}, {14, 31}},
	[17] = {{12, 35}, {12, 36}},
	[18] = {{6, 42}, {7, 42}, {8, 41}},
}
terrains_to_close[14] =
{
	[16] = {{22, 31}, {22, 32}},
	[17] = {{15, 32}, {17, 33}},
}
terrains_to_close[15] =
{
	[16] = {{31, 35}, {31, 36}},
	[21] = {{33, 37}, {34, 36}},
	[22] = {{36, 33}, {36, 34}, {37, 34}},
}
terrains_to_close[16] =
{
	[19] = {{25, 37}},
}
terrains_to_close[17] =
{
	[18] = {{12, 43}, {13, 43}, {14, 42}, {15, 42}},
	[19] = {{18, 38}, {19, 37}, {19, 38}},
}
terrains_to_close[18] =
{
	[23] = {{15, 45}, {15, 43}, {15, 44}},
}
terrains_to_close[19] =
{
	[20] = {{24, 42}, {26, 43}, {28, 43}, {29, 44}},
	[21] = {{31, 41}},
}
terrains_to_close[20] =
{
	[21] = {{31, 45}},
	[23] = {{20, 43}, {20, 44}, {20, 45}},
}
terrains_to_close[21] =
{
	[22] = {{37, 43}},
}

-- adjacency matrix of areas in the map
-- 1: open edge
-- 2: protected edge
-- 0: closed edge
local initial_adjacency_mat = {}
for x = 1, num_nodes do
	initial_adjacency_mat[x] = {}
	for y = 1, num_nodes do
		local edge_x = math.min(x, y)
		local edge_y = math.max(x, y)
		if terrains_to_close[edge_x] == nil or terrains_to_close[edge_x][edge_y] == nil then
			initial_adjacency_mat[x][y] = 0
		else
			initial_adjacency_mat[x][y] = 1
		end
	end
end

graph = Graph:new()
graph:init_adjacency_mat(initial_adjacency_mat)

local function get_image_coords_from_hex(hex_x, hex_y)
	-- obtained from measurements of the map jpg (pixels / map tiles) after borders cropped
	local hex_size_x = 37.35
	local hex_size_y = 49.8
	local hex_offset_y = hex_size_y / 2
	-- overlay imaging is 60x60 (instead of 50x50) so they overlap
	local global_offset_x = -5
	-- extra -15 makes it fit better on the map, probably because cave wall terrain graphics has its own offset
	local global_offset_y = -15 - 5
	local hex_coord_x = math.floor((hex_x - 1) * hex_size_x + global_offset_x + 0.5)
	local hex_coord_y = (hex_y - 1) * hex_size_y
	if hex_x % 2 == 0 then
		hex_coord_y = hex_coord_y + hex_offset_y
	end
	hex_coord_y = math.floor(hex_coord_y + global_offset_y + 0.5)
	return {hex_coord_x, hex_coord_y}
end

function hide_map_coords_ui()
	local old_interface_position = wesnoth.interface.game_display.position
	function wesnoth.interface.game_display.position()
		local info = old_interface_position()
		if not wml.variables["has_map"] then
			if #info >= 1 then
				local info_text = info[1][2].text
				info_text = string.gsub(info_text, "^(%d+),(%d+)", "??,??")
				info[1][2].text = info_text
			end
		end
		return info
	end
end

function randomize_map(max_guaranteed_path_length, closure_prop, chasm_prop)
	local map_image_overlay = ""
	local guaranteed_path = graph:find_guaranteed_path(start_node, {start_node}, dest_node, max_guaranteed_path_length)
	-- now protect these edges
	for x = 1, (#guaranteed_path - 1) do
		local node1 = guaranteed_path[x]
		local node2 = guaranteed_path[x+1]
		graph:set_edge(node1, node2, 2)
		graph:set_edge(node2, node1, 2)
	end

	-- get edges not in guaranteed path
	local candidate_closable_edges = {}
	for x = 1, num_nodes do
		for y = x, num_nodes do
			if graph:get_edge(x, y) == 1 then
				table.insert(candidate_closable_edges, {x, y})
			end
		end
	end
	mathx.shuffle(candidate_closable_edges)
	local num_edges_to_close = math.floor(closure_prop * #candidate_closable_edges)
	local num_edges_to_chasm = math.floor(chasm_prop * num_edges_to_close)
	local edges_closed = 0
	for x = 1, #candidate_closable_edges do
		local node1 = candidate_closable_edges[x][1]
		local node2 = candidate_closable_edges[x][2]
		if (node1 > node2) then
			local temp = node1
			node1 = node2
			node2 = temp
		end
		graph:set_edge(node1, node2, 0)
		graph:set_edge(node2, node1, 0)
		-- only close edge if graph remains fully connected
		-- i.e. closing this edge wouldn't lock any of the map away
		if graph:is_connected() then
			local terrain_list = terrains_to_close[node1][node2]
			for i = 1, #terrain_list do
				local terrain_x = terrain_list[i][1]
				local terrain_y = terrain_list[i][2]
				if edges_closed <= num_edges_to_chasm then
					wesnoth.current.map[{terrain_x, terrain_y}] = "Qxu"
				else
					wesnoth.current.map[{terrain_x, terrain_y}] = "Xu"
				end
				-- extend the overlay that will be applied to the map image
				local hex_coords = get_image_coords_from_hex(terrain_x, terrain_y)
				local blit_string = "~BLIT(storyline/blackout_hex.png," .. hex_coords[1] .. "," .. hex_coords[2] .. ")"
				map_image_overlay = map_image_overlay .. blit_string
			end
			edges_closed = edges_closed + 1
			if edges_closed > num_edges_to_close then
				break
			end
		else
			graph:set_edge(node1, node2, 1)
			graph:set_edge(node2, node1, 1)
		end
	end
	return map_image_overlay
end
