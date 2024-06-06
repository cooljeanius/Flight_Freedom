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

---
-- Get current game zoom level.
--
-- [get_zoom]
--     variable=zoom
-- [/get_zoom]
---
function wesnoth.wml_actions.get_zoom(cfg)
	local varname = cfg.variable or "zoom"
	wml.variables[varname] = wesnoth.interface.zoom(1, true)
end

function wesnoth.wml_actions.fading_message(cfg)
	local message = cfg.message
	local delay_time = tonumber(cfg.time)
	local fade_time = tonumber(cfg.fade_time) or 100
	local matches = wesnoth.units.find_on_map(cfg)
	if matches ~= nil then
		local name = matches[1].name
		local unit_x = matches[1].x
		local unit_y = matches[1].y
		wesnoth.interface.highlight_hex(unit_x, unit_y)
		local options = {}
		options.max_width = "80%"
		options.color = "FFFFFF"
		options.bgcolor = "000000"
		options.duration = delay_time - fade_time
		options.fade_time = fade_time
		options.halign="center"
		options.valign="bottom"
		options.location={0,100}
		local handle = wesnoth.interface.add_overlay_text("<span size='x-large'>" .. name .. "</span>\n<span size='large'>" .. message .. "</span>", options)
		wesnoth.interface.delay(delay_time)
		wesnoth.interface.deselect_hex()
	end
end

---
-- misc functions from EoMA, primarily used to facilitate custom abilities for elementals
---
function wesnoth.wml_actions.remove_array_duplicates(cfg)
	local name = cfg.name
	local attribute = cfg.attribute

	local values = {}
	local inArray = wml.array_access.get(name)
	local outArray = {}
	for _, u in pairs(inArray) do
		if values[u[attribute]] then
			-- skip duplicate
		else
			values[u[attribute]] = true
			table.insert(outArray, u)
		end
	end
	wml.array_access.set(name, outArray)
end

function wesnoth.wml_actions.EoMa_remember_indirectly_damaged_unit(cfg)
	wesnoth.wml_actions.store_unit{
		wml.tag.filter{
			x=cfg.x,
			y=cfg.y
		},
		variable="EoMa_indirectly_damaged_unit",
		mode="append"
	}
end
