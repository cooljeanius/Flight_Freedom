---
-- from After the Storm, by shadowm
---

function safe_random(arg)
	wml.fire("set_variable", {
		name = "temp_ats_lua_random",
		rand = arg,
	})

	local r = wml.variables["temp_ats_lua_random"]
	wml.variables["temp_ats_lua_random"] = nil

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
	local units = wesnoth.units.find_on_map(cfg)
	local varname = cfg.variable or "unit_count"

	if units == nil then
		wml.variables[varname] = 0
	else
		wml.variables[varname] = #units
	end
end

---
-- Clears the chat log.
-- [clear_chat]
-- [/clear_chat]
---
function wesnoth.wml_actions.clear_chat(cfg)
	wesnoth.interface.clear_chat_messages()
end
