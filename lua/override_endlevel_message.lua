---
-- Override the title and report in endlevel dialog. Must be called
-- immediately before [endlevel] to work reliably.
--
-- [override_endlevel_message]
--     title= _ "Custom Title"
--     report= _ "Scenario is over!"
-- [/override_endlevel_message]
---

function wesnoth.wml_actions.override_endlevel_message(cfg)
	wesnoth.game_events.remove("carryover_gold")
	local custom_carryover = wesnoth.require("carryover_gold.lua")
	local title = cfg.title
	local report = cfg.report
	custom_carryover.get_popup_text_basic = function()
		return title, report
	end
	wesnoth.game_events.add {
		name = "scenario_end",
		id = "carryover_gold",
		first_time_only = false,
		priority = -1000,
		action = function()
			custom_carryover.do_carryover_gold()
			-- avoids warning that this event can't be serialized
			-- since it's registered after preload
			wesnoth.game_events.remove("carryover_gold")
		end
	}
end
