---
-- from After the Storm, by shadowm
---

function safe_random(arg)
	wesnoth.fire("set_variable", {
		name = "temp_ats_lua_random",
		rand = arg,
	})

	local r = wesnoth.get_variable("temp_ats_lua_random")
	wesnoth.set_variable("temp_ats_lua_random")

	return r
end

---
-- Counts the amount of matching units.
--
-- [count_units]
--     ... SUF ...
--     variable=unit_count
-- [/count_units]
---

function wesnoth.wml_actions.count_units(cfg)
	local units = wesnoth.get_units(cfg)
	local varname = cfg.variable or "unit_count"

	if units == nil then
		wesnoth.set_variable(varname, 0)
	else
		wesnoth.set_variable(varname, #units)
	end
end

