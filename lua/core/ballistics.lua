--[[
core/ballistics.lua — damage and falloff math.

Responsibility:
	Pure formulas for base damage, damage falloff and headshot/crit multipliers,
	shared by the stats panel, the range chart and the breakpoint table. No unit,
	no raycast, no manager stubbing.

Public API (Task 3 fills these in):
	ballistics.get_damage(weapon, context) -> number|nil
	ballistics.get_damage_falloff(weapon, distance, context) -> number|nil
		Damage multiplier at `distance` (centimetres, game units) for `weapon`.

	Both return nil until Task 3 lands the formulas.
]]

local ballistics = {}

function ballistics.get_damage(weapon, context)
	return nil
end

function ballistics.get_damage_falloff(weapon, distance, context)
	return nil
end

return ballistics
