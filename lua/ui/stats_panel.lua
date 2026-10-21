--[[
ui/stats_panel.lua — extended stat rows in the Black Market weapon panel.

Responsibility:
	Own the extra stat rows (reload, equip delay, ammo pickup, spread, recoil,
	falloff) that Task 5 moves out of blackmarketgui.lua. It renders values but
	never computes them: values come from MoreWeaponStats.core.

Public API (Task 5 fills these in):
	stats_panel.init(gui)
		Called once per Black Market setup, after the row panels exist.
	stats_panel.refresh(gui, context)
		Called on every stats refresh; re-reads the rows from the weapon model.

	Both are no-ops until Task 5.
]]

local stats_panel = {}

function stats_panel.init(gui)
end

function stats_panel.refresh(gui, context)
end

return stats_panel
