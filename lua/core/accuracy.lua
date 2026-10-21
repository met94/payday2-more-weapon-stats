--[[
core/accuracy.lua — spread and recoil math.

Responsibility:
	Read the weapon's spread/recoil tweaks and the current stance from the context
	and return the numbers the stats rows display. The formulas are ported from
	the game's weapon and player-state code, but evaluated as plain math.

Public API (Task 3 fills these in):
	accuracy.spread_horizontal(weapon, context) -> standing, moving
	accuracy.spread_vertical(weapon, context) -> standing, moving
		Both values are in degrees.
	accuracy.recoil_horizontal(weapon, context) -> left, right
	accuracy.recoil_vertical(weapon, context) -> up, down
		Values are in degrees, matching the old "recoil" rows.

	Every function returns nil until Task 3 lands the formulas, so the UI leaves
	the row blank instead of printing a made-up angle.
]]

local accuracy = {}

function accuracy.spread_horizontal(weapon, context)
	return nil, nil
end

function accuracy.spread_vertical(weapon, context)
	return nil, nil
end

function accuracy.recoil_horizontal(weapon, context)
	return nil, nil
end

function accuracy.recoil_vertical(weapon, context)
	return nil, nil
end

return accuracy
