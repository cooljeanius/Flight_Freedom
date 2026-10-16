-- Lua code used by scenario 7A (The Open Ocean)

local cloudsim = wesnoth.require("cloudsim")

local storm_handler = cloudsim.CloudSim:new()
storm_handler:post_config()

-- adjust threshold for difficulty
if wesnoth.scenario.difficulty == "EASY" then storm_handler:set_flag_threshold(0.57)
elseif wesnoth.scenario.difficulty == "HARD" then storm_handler:set_flag_threshold(0.55)
else storm_handler:set_flag_threshold(0.56)
end

local function add_hex_highlight(hex, intensity)
	wesnoth.interface.add_item_image(hex[1], hex[2], "halo/highlight-hex.png")
end

local function remove_hex_highlight(hex, intensity)
	wesnoth.interface.remove_item(hex[1], hex[2], "halo/highlight-hex.png")
end

local function lightning_strike_damage(hex, intensity)
	local unit = wesnoth.units.get(hex[1], hex[2])
	if unit ~= nil and unit.side == 1 then
		wesnoth.audio.play("lightning.ogg")
		local bolt_var = math.random(1,3)
		for j = 1, 4 do
			local image_path = "halo/lightning-bolt-" .. tostring(bolt_var) .. "-" .. tostring(j) .. ".png~PAD(b=250)"
			wesnoth.interface.add_hex_overlay(hex[1], hex[2], {halo = image_path})
			wesnoth.interface.delay(100)
			wesnoth.interface.remove_hex_overlay(hex[1], hex[2], image_path)
		end
		wesnoth.wml_actions.harm_unit{wml.tag.filter{x=hex[1], y=hex[2]}, amount=12, animate=true, kill=true, fire_event=true}
		wesnoth.interface.delay(500)
	end
end

-- must be done in prestart instead of preload for replay safety
local function storm_initial_setup()
	storm_handler:initial_scenario_setup()
	storm_handler:execute_per_flagged_hex(add_hex_highlight)
end

local function storm_turn_update()
	storm_handler:execute_per_flagged_hex(lightning_strike_damage, true)
	storm_handler:execute_per_flagged_hex(remove_hex_highlight)
	storm_handler:update_cloud_map(wesnoth.current.turn + 1)
	storm_handler:execute_per_flagged_hex(add_hex_highlight)
end

function wesnoth.wml_actions.storm_initial_setup(cfg)
	storm_initial_setup()
end

function wesnoth.wml_actions.storm_turn_update(cfg)
	storm_turn_update()
end

-- debug functions for testing from lua console
function debug_show_cloud_map()
	storm_handler:debug_show_cloud_map()
end

function debug_quantile(q)
	return storm_handler:quantile(q)
end
