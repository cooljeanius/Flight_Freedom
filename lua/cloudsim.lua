-- Implements a simplex noise-based cloud simulation
-- This keeps a matrix of cloud intensity over the specified bounds (by
-- default, the whole map). Methods permit acccess to flagged hexes, or
-- the entire cloud matrix. Default parameters look sensible for weather (at
-- least to me subjectively), however your use cases and needs likely vary.
-- Cloud intensity will have range [0, 1] with mean 0.5, unless a transform
-- function is specified
--
-- intended usage:
--    In preload context:
--    * Create a CloudSim object
--    * as desired, configure it. Any desired config_* method calls MUST occur before object is used
--       (set_* methods can be called on-demand now or later)
--    * Call its post_config() method immediately after: this is mandatory for saveload safety
--    In prestart:
--    * Call initial_scenario_setup()
--    Subsequent usage:
--    * Call update_cloud_map() when you need it updated (probably want to do so in a new_turn or turn_end event)
-- CAUTION: loading this file and creating all CloudSim objects you want MUST happen in preload context!

local hexutils = wesnoth.require("hexutils")
local simplex = wesnoth.require("simplex")
local cloudsim = {}

---@class CloudSim
---@field flag_threshold number #hexes with cloud intensity above this threshold are flagged
---@field cloud_scale_x number #scale factor for cloud width; larger number yields wider clouds
---@field cloud_scale_y number #scale factor for cloud height; larger number yields taller clouds
---@field time_scale number #scale factor for cloud change over time; larger number yields faster changing clouds
---@field wind_speed_x integer #how many hexes clouds move east to west per turn
---@field wind_speed_y integer #how many hexes clouds move south to north per turn
---@field cloud_matrix number[][] #per-hex matrix of cloud intensity
---@field built_turn integer #which scenario turn cloud_matrix currently reflects
---@field x_offset integer #starting offset in x-dimension in simplex noise field
---@field y_offset integer #starting offset in y-dimension in simplex noise field
---@field z_offset integer #starting offset in z-dimension in simplex noise field
---@field cloud_transform_func function(number, integer, integer) #an optional user-specified function to transform intensity values
---@field cloud_min_x integer #lower x-bound of cloud map (default: 1)
---@field cloud_max_x integer #upper x-bound of cloud map (default: map width)
---@field cloud_min_y integer #lower y-bound of cloud map (default: 1)
---@field cloud_max_y integer #upper y-bound of cloud map (default: map height)
---@field id integer #internal unique id per instance
cloudsim.CloudSim = {}
cloudsim.CloudSim.__index = cloudsim.CloudSim

local next_id = 1

function cloudsim.CloudSim:new()
	local o = {}
	setmetatable(o, self)
	-- lower threshold corresponds to more flagged hexes
	o.flag_threshold = 0.56
	o.cloud_scale_x = 5.0
	o.cloud_scale_y = 5.0
	o.time_scale = 0.05
	o.wind_speed_x = 1
	o.wind_speed_y = 0
	o.cloud_matrix = {}
	o.built_turn = 0
	o.x_offset = nil
	o.y_offset = nil
	o.z_offset = nil
	o.cloud_transform_func = nil
	o.cloud_min_x = 1
	o.cloud_max_x = wesnoth.current.map.playable_width
	o.cloud_min_y = 1
	o.cloud_max_y = wesnoth.current.map.playable_height
	o.id = next_id
	local local_id = tostring(next_id)
	-- inject victory event to cleanup the WML variables we create
	wesnoth.game_events.add{
		name = "scenario_end",
		id = "CloudSim_variable_cleanup_" .. tostring(next_id),
		action = function()
			local variable_stems = {
				"initial_setup",
				"x_offset",
				"y_offset",
				"z_offset",
				"flag_threshold",
				"cloud_scale_x",
				"cloud_scale_y",
				"time_scale",
				"wind_speed_x",
				"wind_speed_y"
			}
			for i, stem in ipairs(variable_stems) do
				local varname = "CloudSim_" .. stem .. "_" .. local_id
				wml.variables[varname] = nil
			end
		end
	}
	next_id = next_id + 1
	return o
end

---For saveload safety, you MUST call this method after you've created and configured a CloudSim object!
---Note: this will restore mid-scenario changes from set_* methods, but will NOT overturn any set_* calls prior to this
function cloudsim.CloudSim:post_config()
	-- regenerate the cloud map on save load (when called by preload event)
	if wml.variables["CloudSim_initial_setup_" .. tostring(self.id)] == 1 then
		if wml.variables["CloudSim_flag_threshold_" .. tostring(self.id)] ~= nil then
			self.flag_threshold = wml.variables["CloudSim_flag_threshold_" .. tostring(self.id)]
		end
		if wml.variables["CloudSim_cloud_scale_x_" .. tostring(self.id)] ~= nil then
			self.cloud_scale_x = wml.variables["CloudSim_cloud_scale_x_" .. tostring(self.id)]
			self.cloud_scale_y = wml.variables["CloudSim_cloud_scale_y_" .. tostring(self.id)]
			self.time_scale = wml.variables["CloudSim_time_scale_" .. tostring(self.id)]
		end
		if wml.variables["CloudSim_wind_speed_x_" .. tostring(self.id)] ~= nil then
			self.wind_speed_x = wml.variables["CloudSim_wind_speed_x_" .. tostring(self.id)]
			self.wind_speed_y = wml.variables["CloudSim_wind_speed_y_" .. tostring(self.id)]
		end
		self:_reload_offsets()
		self:update_cloud_map(wesnoth.current.turn)
	end
end

---This must be called in a prestart event; NOT a preload event
function cloudsim.CloudSim:initial_scenario_setup()
	if self.x_offset == nil then
		self:_init_random_offsets()
	end
	self:update_cloud_map(1)
	wml.variables["CloudSim_initial_setup_" .. tostring(self.id)] = 1
end

---Manually set initial offsets for simplex clouds; by default they will be randomly set
---@param x_offset integer #Starting offset in x-dimension in simplex noise field
---@param y_offset integer #Starting offset in y-dimension in simplex noise field
---@param z_offset integer #Starting offset in z-dimension in simplex noise field
function cloudsim.CloudSim:config_set_offsets(x_offset, y_offset, z_offset)
	self.x_offset = x_offset
	wml.variables["CloudSim_x_offset_" .. tostring(self.id)] = x_offset
	self.y_offset = y_offset
	wml.variables["CloudSim_y_offset_" .. tostring(self.id)] = y_offset
	self.z_offset = z_offset
	wml.variables["CloudSim_z_offset_" .. tostring(self.id)] = z_offset
end

---Constrain the CloudSim to the specified hexes
---By default, CloudSim will include the entire map
---@param min_x integer #Minimum x coordinate for the CloudSim
---@param max_x integer #Maximum x coordinate for the CloudSim
---@param min_y integer #Minimum y coordinate for the CloudSim
---@param max_y integer #Maximum y coordinate for the CloudSim
function cloudsim.CloudSim:config_set_boundaries(min_x, max_x, min_y, max_y)
	self.cloud_min_x = min_x
	self.cloud_max_x = max_x
	self.cloud_min_y = min_y
	self.cloud_max_y = max_y
end

---Provide a transformation function that it is run on every generated cloud intensity
---Must fit the prototype transform_func(cloud_intensity, x, y)
---@param transform_func function(number, integer, integer) #The specified transformation function
function cloudsim.CloudSim:config_transform_func(transform_func)
	self.cloud_transform_func = transform_func
end

---Set cloud sizes and time scale
---@param cloud_scale_x number #Scale factor for cloud width; larger number yields wider clouds
---@param cloud_scale_y number #Scale factor for cloud height; larger number yields taller clouds
---@param time_scale number #Scale factor for cloud change over time; larger number yields faster changing clouds
function cloudsim.CloudSim:set_scale_factors(cloud_scale_x, cloud_scale_y, time_scale)
	self.cloud_scale_x = cloud_scale_x
	self.cloud_scale_y = cloud_scale_y
	self.time_scale = time_scale
	wml.variables["CloudSim_cloud_scale_x_" .. tostring(self.id)] = cloud_scale_x
	wml.variables["CloudSim_cloud_scale_y_" .. tostring(self.id)] = cloud_scale_y
	wml.variables["CloudSim_time_scale_" .. tostring(self.id)] = time_scale
end

---Set wind speed
---CAUTION: this will affect all future calls to update_cloud_map, which will 
---start updating *as if this has been the wind speed the entire scenario*
---@param wind_speed_x integer #how many hexes clouds move east to west per turn
---@param wind_speed_y integer #how many hexes clouds move south to north per turn
function cloudsim.CloudSim:set_wind_speed(wind_speed_x, wind_speed_y)
	self.wind_speed_x = wind_speed_x
	self.wind_speed_y = wind_speed_y
	wml.variables["CloudSim_wind_speed_x_" .. tostring(self.id)] = wind_speed_x
	wml.variables["CloudSim_wind_speed_y_" .. tostring(self.id)] = wind_speed_y
end

---Set the intensity threshold that a hex must meet to be flagged
---Note: if you supply a transformation function (with config_transform_func),
---your threshold will need to account for it
---@param flag_threshold number #Minimum cloud intensity to flag a hex
function cloudsim.CloudSim:set_flag_threshold(flag_threshold)
	self.flag_threshold = flag_threshold
	wml.variables["CloudSim_flag_threshold_" .. tostring(self.id)] = flag_threshold
end

---@private
function cloudsim.CloudSim:_init_random_offsets()
	local x_offset = mathx.random(0,9999)
	local y_offset = mathx.random(0,9999)
	local z_offset = mathx.random(0,9999)
	self:config_set_offsets(x_offset, y_offset, z_offset)
end

---@private
function cloudsim.CloudSim:_reload_offsets()
	self.x_offset = wml.variables["CloudSim_x_offset_" .. tostring(self.id)]
	self.y_offset = wml.variables["CloudSim_y_offset_" .. tostring(self.id)]
	self.z_offset = wml.variables["CloudSim_z_offset_" .. tostring(self.id)]
end

-- x: input
-- k: depth
function cloudsim.exponential_adjust(x, k)
	local y = x
	if k ~= 0.0 then
		y = (1.0 - math.exp(-1.0 * k * x)) / (1.0 - math.exp(-1.0 * k))
	end
	return y
end

function cloudsim.rational_sigmoid(x, k)
	return (x ^ k) / ((x ^ k) + ((1.0 - x) ^ k))
end

-- by moving linearly down the z-axis can simulate cloud shifts
---@private
function cloudsim.CloudSim:_noise_3d(hex_x, hex_y, time_z)
	local x_pixel, y_pixel = hexutils.hex_to_cartesian_space(hex_x, hex_y)
	local x = (x_pixel / self.cloud_scale_x) + self.x_offset
	local y = (y_pixel / self.cloud_scale_y) + self.y_offset
	local z = (time_z * self.time_scale) + self.z_offset
	local r = (simplex.Noise3D(x, y, z) + 1.0) / 2.0
	return r
end

---Update the cloud matrix
---@param turn_number? integer #The turn to calculate the cloud matrix for (default: current turn)
function cloudsim.CloudSim:update_cloud_map(turn_number)
	turn_number = turn_number or wesnoth.current.turn
	self.cloud_matrix = {}
	for x = self.cloud_min_x, self.cloud_max_x do
		self.cloud_matrix[x] = self.cloud_matrix[x] or {}
		for y = self.cloud_min_y, self.cloud_max_y do
			local i = x + turn_number * (self.wind_speed_x)
			local j = y + turn_number * (self.wind_speed_y)
			local noise = self:_noise_3d(i, j, turn_number)
			if self.cloud_transform_func ~= nil then
				noise = self.cloud_transform_func(noise, x, y)
			end
			self.cloud_matrix[x][y] = noise
		end
	end
	self.built_turn = turn_number
end

---Return the current cloud intensity matrix
---@treturn number[][] #Matrix (indexes in X and Y coordinaters) of cloud intensity
function cloudsim.CloudSim:get_cloud_matrix()
	return self.cloud_matrix
end

---Return cloud intensity of a specific hex
---@param hex_x integer #X-coordinate of hex
---@param hex_y integer #Y-coordinate of hex
---@return number
function cloudsim.CloudSim:get_intensity(hex_x, hex_y)
	assert(hex_x >= self.cloud_min_x and hex_x <= self.cloud_max_x)
	assert(hex_y >= self.cloud_min_y and hex_y <= self.cloud_max_y)
	return self.cloud_matrix[hex_x][hex_y]
end

---For a particular cloud map, compute the specified quantile
---This returns a threshold number, that is highter than proportion q of cloud intensities
---One possible use: calibrate a flag threshold to an approximate proportion of hexes
---Note: calling set_flag_threshold with this result will approximately flag (1 - q) percentage of hexes
---@param q number #The desired proportion
---@return number
function cloudsim.CloudSim:quantile(q)
	local vals_flat = {}
	for x = self.cloud_min_x, self.cloud_max_x do
		for y = self.cloud_min_y, self.cloud_max_y do
			table.insert(vals_flat, self.cloud_matrix[x][y])
		end
	end
	table.sort(vals_flat)
	local n = math.floor(q * #vals_flat)
	local res = nil
	if n <= 0 then
		res = -math.huge
	elseif n >= #vals_flat then
		res = math.huge
	else
		res = (vals_flat[n] + vals_flat[n+1]) / 2.0
	end
	return res
end

---Check if a specific hex if flagged
---@param hex_x integer #X-coordinate of hex
---@param hex_y integer #Y-coordinate of hex
---@return boolean
function cloudsim.CloudSim:is_flagged(hex_x, hex_y)
	assert(hex_x >= self.cloud_min_x and hex_x <= self.cloud_max_x)
	assert(hex_y >= self.cloud_min_y and hex_y <= self.cloud_max_y)
	return self.cloud_matrix[hex_x][hex_y] > self.flag_threshold
end

---Get the list of all flagged hexes
---@treturn {integer, integer}[] #The list of flagged hexes
function cloudsim.CloudSim:get_flagged_hexes()
	local flagged_locs = {}
	for x = self.cloud_min_x, self.cloud_max_x do
		for y = self.cloud_min_y, self.cloud_max_y do
			if self.cloud_matrix[x][y] > self.flag_threshold then
				local hex = {x, y}
				table.insert(flagged_locs, hex)
			end
		end
	end
	return flagged_locs
end

---Convenience method to run the desired function on all flagged hexes
---Must fit the prototype action_func(hex, intensity), where hex is a 2-element list {x, y}
---@param action_func function({integer, integer}, number) #The specified function
---@param shuffle? boolean #If true, then run over hexes in shuffled order (default order is arbitrary)
function cloudsim.CloudSim:execute_per_flagged_hex(action_func, shuffle)
	local flagged_hexes = self:get_flagged_hexes()
	if shuffle then
		mathx.shuffle(flagged_hexes)
	end
	for i, hex in ipairs(flagged_hexes) do
		action_func(hex, self.cloud_matrix[hex[1]][hex[2]])
	end
end

---Label each hex covered by the CloudSim with the current cloud intensity
function cloudsim.CloudSim:debug_show_cloud_map()
	for x = self.cloud_min_x, self.cloud_max_x do
		for y = self.cloud_min_y, self.cloud_max_y do
			wesnoth.map.remove_label{x=x, y=y}
			wesnoth.map.add_label{x=x, y=y, text=string.format("%.3f",self.cloud_matrix[x][y])}
		end
	end
end

---Get the turn that this CloudSim was last updated with
---@return integer
function cloudsim.CloudSim:get_built_turn()
	return self.built_turn
end

return cloudsim
