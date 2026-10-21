--[[
core/ammo.lua — ammunition capacity and pickup math.

Responsibility:
	Magazine/ammo capacity and ammo-pickup ranges for a weapon, derived from tweak
	data and pick-up multipliers instead of calling add_ammo on a live weapon.

Public API (Task 3 fills these in):
	ammo.ammo_pickup(weapon, context) -> near, far
		Rounds picked up per ammo box, the two values the row displays.

	Returns nil until Task 3 lands the formula, so the row stays blank.
]]

local ammo = {}

function ammo.ammo_pickup(weapon, context)
	return nil, nil
end

return ammo
