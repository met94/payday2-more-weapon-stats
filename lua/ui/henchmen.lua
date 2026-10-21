--[[
ui/henchmen.lua — henchman/NPC weapon stat rows.

Responsibility:
	Own the NPC rows (damage/hit chance per distance, ROF, reload, aim delay,
	falloff) that Task 6 moves out of blackmarketgui.lua. Values come from
	tweak_data.character[*].weapon and tweak_data.weapon, never from an NPC unit.

Public API (Task 6 fills these in):
	henchmen.init(gui)
	henchmen.refresh(gui, context)

	Both are no-ops until Task 6.
]]

local henchmen = {}

function henchmen.init(gui)
end

function henchmen.refresh(gui, context)
end

return henchmen
