--[[
core/ammo.lua — ammunition pickup math.

Responsibility:
	Ammo-pickup ranges for a weapon, derived from tweak data and the player's
	pick-up multipliers instead of calling add_ammo on a live weapon.

Public API:
	ammo.ammo_pickup(weapon, context) -> min_amount|nil, max_amount|nil
		Rounds one ammo box can give, the range the row displays. There is no
		random roll: the game lerps between exactly these two values
		(raycastweaponbase.lua:2073), so the row shows the endpoints.

	Returns nil when the weapon has no AMMO_PICKUP data (crew weapons, melee).

Formula sources (PAYDAY 2 248.2):
	lib/units/weapons/raycastweaponbase.lua:2049-2076 add_ammo
		ammo_pickup_min_mul / ammo_pickup_max_mul from _ammo_data
		pick_up_ammo_multiplier, pick_up_ammo_multiplier_2, crew_scavenge
	lib/units/weapons/newraycastweaponbase.lua:1355 _ammo_pickup = weapon AMMO_PICKUP
	lib/units/weapons/weaponammo.lua:51 the same assignment on WeaponAmmo
	lib/tweak_data/weapontweakdata.lua:6392-6490 _pickup_chance
	lib/managers/playermanager.lua:1996-2006 crew_ability_upgrade_value
]]

local ammo = {}

local function raw_global(name)
	return rawget(_G, name)
end

local function weapons_tweak()
	local tweak_data = raw_global('tweak_data')
	return tweak_data and tweak_data.weapon or nil
end

local function ctx_upgrade_value(context, category, upgrade, default)
	if context and type(context.upgrade_value) == 'function' then
		return context:upgrade_value(category, upgrade, default)
	end

	return default
end

-- PlayerManager:crew_ability_upgrade_value (playermanager.lua:1996).
local function ctx_crew_ability_upgrade_value(context, upgrade, default)
	if context and type(context.crew_ability_upgrade_value) == 'function' then
		return context:crew_ability_upgrade_value(upgrade, default)
	end

	return default
end

local function weapon_tweak_data(weapon)
	if type(weapon) ~= 'table' then
		return nil
	end

	if type(weapon.weapon_tweak_data) == 'function' then
		return weapon:weapon_tweak_data()
	end

	local weapons = weapons_tweak()
	return weapons and weapons[weapon._name_id] or nil
end

--[[
RaycastWeaponBase:add_ammo (raycastweaponbase.lua:2049-2076), without the random
lerp: min/max are the lerp endpoints scaled by the pick-up multipliers.
]]
function ammo.ammo_pickup(weapon, context)
	if type(weapon) ~= 'table' then
		return nil, nil
	end

	local pickup = weapon._ammo_pickup

	if pickup == nil then
		local tweak = weapon_tweak_data(weapon)
		pickup = tweak and tweak.AMMO_PICKUP
	end

	if type(pickup) ~= 'table' or (pickup[1] == nil and pickup[2] == nil) then
		return nil, nil
	end

	local min_pickup = pickup[1] or 0
	local max_pickup = pickup[2] or min_pickup
	local ammo_data = weapon._ammo_data

	if ammo_data and (ammo_data.ammo_pickup_min_mul or ammo_data.ammo_pickup_max_mul) then
		min_pickup = min_pickup * (ammo_data.ammo_pickup_min_mul or 1)
		max_pickup = max_pickup * (ammo_data.ammo_pickup_max_mul or 1)
	end

	local multiplier_1 = ctx_upgrade_value(context, 'player', 'pick_up_ammo_multiplier', 1) - 1
	local multiplier_2 = ctx_upgrade_value(context, 'player', 'pick_up_ammo_multiplier_2', 1) - 1
	local crew_multiplier = ctx_crew_ability_upgrade_value(context, 'crew_scavenge', 0)
	local pickup_multiplier = 1 + multiplier_1 + multiplier_2 + crew_multiplier

	return min_pickup * pickup_multiplier, max_pickup * pickup_multiplier
end

return ammo
