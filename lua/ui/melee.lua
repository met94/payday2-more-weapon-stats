--[[
ui/melee.lua — melee weapon stat rows.

Responsibility:
	Own the melee stats (attack delay, cooldown, unequip delay, special, DoT
	length) that Task 6 moves out of blackmarketgui.lua. Values come from
	tweak_data.blackmarket.melee_weapons and tweak_data.melee, compared between
	the selected and the equipped melee weapon.

Public API (Task 6 fills these in):
	melee.init(gui)
	melee.refresh(gui, context)

	Both are no-ops until Task 6.
]]

local melee = {}

function melee.init(gui)
end

function melee.refresh(gui, context)
end

return melee
