-- implements a graph class and functions
-- so far used in S11A and S11B

Graph = {adjacency_mat = {}}

function Graph:new(o)
	o = o or {}
	setmetatable(o, self)
	self.__index = self
	return o
end

function Graph:init_adjacency_mat(adjacency_mat)
	self.adjacency_mat = adjacency_mat
end

function Graph:init_unconnected(num_nodes)
	self.adjacency_mat = {}
	for x = 1, num_nodes do
		self.adjacency_mat[x] = {}
		for y = 1, num_nodes do
			self.adjacency_mat[x][y] = 0
		end
	end
end

function Graph:set_edge(node1, node2, value)
	self.adjacency_mat[node1][node2] = value
end

function Graph:get_edge(node1, node2)
	return self.adjacency_mat[node1][node2]
end

local function is_in_list(e, list1)
	local result = false
	for x = 1, #list1 do
		if list1[x] == e then
			result = true
			break
		end
	end
	return result
end

local function concat_list(list1, list2)
	for x = 1, #list2 do
		table.insert(list1, list2[x])
	end
	return list1
end

local function list_shallow_copy(list1)
	local new_list = {}
	for x = 1, #list1 do
		table.insert(new_list, list1[x])
	end
	return new_list
end

function Graph:get_connections(node)
	local row = self.adjacency_mat[node]
	local connections = {}
	for x = 1, #row do
		if row[x] > 0 then
			table.insert(connections, x)
		end
	end
	return connections
end

-- randomly traverse graph until a path (not necessarily an optimal one) is found from cur_node to dest_node
function Graph:find_guaranteed_path(cur_node, cur_path, dest_node, max_guaranteed_path_length)
	local path = nil
	if #cur_path < max_guaranteed_path_length then
		local connections = self:get_connections(cur_node)
		mathx.shuffle(connections)
		for x = 1, #connections do
			local possible_connection = connections[x]
			if not is_in_list(possible_connection, cur_path) then
				local new_cur_path = list_shallow_copy(cur_path)
				table.insert(new_cur_path, possible_connection)
				if possible_connection == dest_node then
					path = new_cur_path
				else
					path = self:find_guaranteed_path(possible_connection, new_cur_path, dest_node, max_guaranteed_path_length)
					if path ~= nil then
						break
					end
				end
			end
		end
	end
	return path
end

-- test if graph is connected
function Graph:enumerate_connected_nodes(cur_node, visited_nodes)
	local connections = self:get_connections(cur_node)
	local nodes_to_visit = {}
	for x = 1, #connections do
		local possible_connection = connections[x]
		if visited_nodes[possible_connection] == nil then
			visited_nodes[possible_connection] = true
			table.insert(nodes_to_visit, possible_connection)
		end
	end
	for x = 1, #nodes_to_visit do
		self:enumerate_connected_nodes(nodes_to_visit[x], visited_nodes)
	end
	return visited_nodes
end

function Graph:is_connected()
	-- BFS from arbitrary node
	local connected_nodes = self:enumerate_connected_nodes(1, {})
	local result = false
	local num_nodes_connected = 0
	local num_nodes = #self.adjacency_mat
	for x = 1, num_nodes do
		if connected_nodes[x] ~= nil then
			num_nodes_connected = num_nodes_connected + 1
		end
	end
	if num_nodes_connected == num_nodes then
		result = true
	end
	return result
end

function Graph:degree(node)
	local connections = 0
	local row = self.adjacency_mat[node]
	for x = 1, #row do
		if row[x] > 0 then
			connections = connections + 1
		end
	end
	return connections
end
