--[=[
[new_side]
Author: MadMax (username on the Battle for Wesnoth forum)

Creates a new side (next available side number) with stated parameters. Accepts side parameters available to [modify_side]. Will not create a leader unit; need to do this yourself with [unit] and canrecruit=yes.

NOTE: manipulating the side's flag crashes Wesnoth as of 1.17.24 (vanilla bug also part of [modify_side]).

Optional keys:
variable: variable side number is saved to (default: new_side_number)
]=]

function wesnoth.wml_actions.new_side(cfg)
	local side_num_var = cfg.variable or "new_side_number"
	local side_num = wesnoth.sides.create()
	wml.variables[side_num_var] = side_num
	local new_cfg = wml.patch(cfg, {
		wml.tag.insert {
			side = side_num
		},
		wml.tag.delete {
			variable = "x"
		},
	})
	wesnoth.wml_actions.modify_side(new_cfg)
end
