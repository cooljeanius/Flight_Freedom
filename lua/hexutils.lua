local hexutils = {}

-- useful reference for cubic grid math: https://www.redblobgames.com/grids/hexagons/
-- wesnoth is even-q

-- since mainline wesnoth.map.from_cubic is broken as of 1.19.13, reimplement it here
-- (c++ backend expects a cubic_location struct which isn't accessible to lua)
function hexutils.from_cubic(q, r, s)
	local x = q
	local y = r + trunc((q + (math.abs(q) % 2)) / 2)
	return({x, y})
end

hexutils.get_cubic = wesnoth.map.get_cubic

-- cartesian space: presume hexes are perfect hexagons
-- screen space: hexes are tiled 54 px apart in x-axis and 72 px apart in y-axis
-- examples:
--  hexutils.find_offset_hex_polar_screen(30,60,10,math.pi/2): 30, 50
--  hexutils.find_offset_hex_polar_screen(30,60,10,0): 43, 60 (new hex is 13 hexes away on X axis)
--  hexutils.find_offset_hex_polar_screen(30,60,10,math.pi/6): 42, 55 (12 hexes away at 60 degree angle on the player's screen)
--  hexutils.find_offset_hex_polar_cartesian(30,60,10,math.pi/2): 30, 50
--  hexutils.find_offset_hex_polar_cartesian(30,60,10,0): 42, 60 (new hex is 12 hexes away on X axis)
--  hexutils.find_offset_hex_polar_cartesian(30,60,10,math.pi/6): 40, 55 (10 hexes away at 60 degree angle in the hex map)

function hexutils.hex_to_cartesian_space(x, y)
	local q, r, s = table.unpack(hexutils.get_cubic({x, y}))
	local x_cartesian = 1.5 * q / math.sqrt(3.0)
	local y_cartesian = ((q / 2.0) + r)
	return x_cartesian, y_cartesian
end

function hexutils.angle_between_hexes_cartesian(x1, y1, x2, y2)
	local x1_cartesian, y1_cartesian = hexutils.hex_to_cartesian_space(x1, y1)
	local x2_cartesian, y2_cartesian = hexutils.hex_to_cartesian_space(x2, y2)
	local theta = math.atan(math.abs(y2_cartesian - y1_cartesian), math.abs(x2_cartesian - x1_cartesian))
	-- y2 reversed here to account for flipped Y axis
	if x1_cartesian >= x2_cartesian and y2_cartesian <= y1_cartesian then -- quadrant II
		theta = math.pi - theta
	elseif x1_cartesian >= x2_cartesian and y2_cartesian > y1_cartesian then -- quadrant III
		theta = math.pi + theta
	elseif x1_cartesian < x2_cartesian and y2_cartesian > y1_cartesian then -- quadrant IV
		theta = (math.pi * 2) - theta
	end
	return theta
end

-- find the distance between two hexes in a straight line between them
function hexutils.distance_between_hexes_cartesian(x1, y1, x2, y2)
	local x1_cartesian, y1_cartesian = hexutils.hex_to_cartesian_space(x1, y1)
	local x2_cartesian, y2_cartesian = hexutils.hex_to_cartesian_space(x2, y2)
	return math.sqrt(((x1_cartesian - x2_cartesian) ^ 2) + ((y1_cartesian - y2_cartesian) ^ 2))
end

function hexutils.find_offset_hex_polar_cartesian(origin_x, origin_y, radius, theta)
	local origin_x_cartesian, origin_y_cartesian = hexutils.hex_to_cartesian_space(origin_x, origin_y)
	theta = theta * -1
	local offset_x = math.cos(theta) * radius
	local offset_y = math.sin(theta) * radius
	local new_x_cartesian = origin_x_cartesian + offset_x
	local new_y_cartesian = origin_y_cartesian + offset_y
	local q = mathx.round(new_x_cartesian * math.sqrt(3.0) / 1.5)
	local r = mathx.round(new_y_cartesian - (q / 2.0))
	local s = (-1 * q) - r
	local hex = hexutils.from_cubic(q,r,s)
	return hex[1], hex[2]
end

function hexutils.calc_image_hex_offset_screen(hex_x, hex_y, x, y)
	-- given a reference hex and an offset in pixels
	-- find the hex closest to the target and adjust the offset to be relative to that hex
	-- returns the new hex coordinates followed by the new pixel offset
	local hex_off_x = math.floor((x + 27) / 54)
	local k = 0
	if math.abs(hex_off_x) % 2 == 1 then
		if math.abs(hex_x) % 2 == 0 then
			k = 36
		else
			y = y - 36
		end
	end
	local hex_off_y = math.floor((y + 36) / 72)
	local new_x = x - hex_off_x * 54
	local new_y = y - (hex_off_y * 72) + k
	if new_y > 36 then
		new_y = new_y - 72
		hex_off_y = hex_off_y+1
	end

	return hex_x+hex_off_x, hex_y+hex_off_y, new_x, new_y
end

--[=[
[find_offset_hex_polar_screen]
Author: MadMax (username on the Battle for Wesnoth forum)

Calculates the closest hex from an origin hex and an offest in polar coordinates.

Required keys:
origin_x, origin_y: the first tile
radius: vector length in tiles along Y-axis
theta: angle in radians; note that this is counterclockwise (i.e. not with reversed Y-axis)

Optional keys:
new_x_variable, new_y_variable: variable names to store new hex coordinates
	If not specified, will default to "new_x" and "new_y" respectively

Example:
[find_offset_hex_polar_screen]
	origin_x=30
	origin_y=10
	radius=9
	theta=$(pi()/4)
[/find_offset_hex_polar_screen]
]=]

function hexutils.find_offset_hex_polar_screen(origin_x, origin_y, radius, theta)
	radius = radius * 72.0
	theta = theta * -1
	local offset_x = math.cos(theta) * radius
	local offset_y = math.sin(theta) * radius
	local new_x,new_y = hexutils.calc_image_hex_offset_screen(origin_x, origin_y, offset_x, offset_y)
	return new_x, new_y
end

function wesnoth.wml_actions.find_offset_hex_polar_screen(cfg)
	local origin_x = tonumber(cfg.origin_x)
	local origin_y = tonumber(cfg.origin_y)
	local radius = tonumber(cfg.radius)
	local theta = tonumber(cfg.theta)
	local new_x, new_y = hexutils.find_offset_hex_polar_screen(origin_x, origin_y, radius, theta)
	local new_x_varname = cfg.new_x_variable or "new_x"
	local new_y_varname = cfg.new_y_variable or "new_y"
	wml.variables[new_x_varname] = new_x
	wml.variables[new_y_varname] = new_y
end

return hexutils
