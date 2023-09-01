--[=[
[distance_between]
Author: MadMax (username on the Battle for Wesnoth forum)

distance_between is a WML wrapper around the Lua function wesnoth.map.distance_between, and returns the distance between two tiles.

Required keys:
x, y: the first tile
to_x, to_y: the second tile
variable: the variable to write the distance to (default: distance)

Example:
[distance_between]
	x=1
	y=1
	to_x=8
	to_y=7
[/distance_between]
[message]
	speaker=narrator
	#outputs 10
	message="$distance"
[/message]
]=]

function wesnoth.wml_actions.distance_between(cfg)
	local dist = wesnoth.map.distance_between({cfg.x, cfg.y}, {cfg.to_x, cfg.to_y})
	local variable_name = cfg.variable or "distance"
	wml.variables[variable_name] = dist
end
