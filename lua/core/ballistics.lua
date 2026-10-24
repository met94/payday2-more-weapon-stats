--[[
core/ballistics.lua — damage and damage-falloff math.

Responsibility:
	Pure formulas for the damage a weapon still deals over distance, shared by
	the stats panel, the range chart and the breakpoint table. No unit, no
	raycast, no manager stubbing.

Public API:
	ballistics.get_damage(weapon, context) -> number|nil
		The weapon's resolved damage (the model already folds the upgrades in).
	ballistics.get_damage_falloff(weapon, distance, context) -> multiplier|nil
		Damage multiplier at `distance` (centimetres, game units), following
		NewRaycastWeaponBase:get_damage_falloff. 1 inside the optimal range,
		the near/far multipliers outside it, interpolated across the falloff
		bands. The multiplier is returned instead of a damage value because the
		range chart needs the ratio.
	ballistics.is_weak_hit(weapon, distance, context) -> number
		Damage scale NewRaycastWeaponBase:is_weak_hit returns: 1 inside the
		bands, 1.2 beyond a multiplier above 1, 0.5 beyond a multiplier below 1.
	ballistics.modify_falloff(falloff, custom_stats) -> table
		BlackMarketManager:modify_damage_falloff: the part custom stats
		(falloff_override, *_mul) applied to the default falloff table. Pure, so
		core/weapon can build the falloff fields without the manager.

	Falloff functions return nil when the weapon table has no falloff data at
	all; a weapon whose optimal_distance + optimal_range is 0 has no falloff and
	answers the full multiplier, exactly like the game.

Formula sources (PAYDAY 2 248.2):
	lib/units/weapons/newraycastweaponbase.lua:223-236 _default_damage_falloff
	lib/units/weapons/newraycastweaponbase.lua:1164-1231 get_damage_falloff /
		is_weak_hit
	lib/managers/blackmarketmanager.lua:3209-3266 modify_damage_falloff
	core/lib/utils/coremath.lua:275-281 math.map_range_clamped
	lib/tweak_data/WeaponFalloffTweakData.lua (falloff templates)
Engine-only terms (documented, not invented):
	* the far end of the optimal range is scaled by
	  upgrade_value(primary_category, "steelsight_range_inc", 1) while aiming,
	  which the context supplies;
	* a gadget/underbarrel reskin of the falloff table is not modelled (no
	  underbarrel state in the model).
]]

local ballistics = {}

local function ctx_upgrade_value(context, category, upgrade, default)
	if context and type(context.upgrade_value) == 'function' then
		return context:upgrade_value(category, upgrade, default)
	end

	return default
end

local function clamp(value, minimum, maximum)
	if value < minimum then
		return minimum
	elseif value > maximum then
		return maximum
	end

	return value
end

-- core/lib/utils/coremath.lua:275-281
local function map_range_clamped(value, from_a, from_b, to_a, to_b)
	local ratio = 0

	if from_b ~= from_a then
		ratio = clamp((value - from_a) / (from_b - from_a), 0, 1)
	end

	return to_a + (to_b - to_a) * ratio
end

local function weapon_categories(weapon)
	if type(weapon) ~= 'table' then
		return {}
	end

	if type(weapon.categories) == 'function' then
		return weapon:categories() or {}
	end

	local tweak_data = rawget(_G, 'tweak_data')
	local weapons = tweak_data and tweak_data.weapon
	local tweak = weapons and weapons[weapon._name_id]

	return tweak and tweak.categories or {}
end

local function has_falloff(weapon)
	return type(weapon) == 'table'
		and type(weapon._optimal_distance) == 'number'
		and type(weapon._optimal_range) == 'number'
end

function ballistics.get_damage(weapon, context)
	if type(weapon) ~= 'table' then
		return nil
	end

	if type(weapon._damage) == 'number' then
		return weapon._damage
	end

	return nil
end

--[[
NewRaycastWeaponBase:get_damage_falloff (newraycastweaponbase.lua:1164).

	near_dist     = optimal_distance - near_falloff
	optimal_start = optimal_distance
	optimal_end   = optimal_distance + optimal_range
	far_dist      = optimal_end + far_falloff

	distance < optimal_start:
		near_falloff > 0 -> map(distance, near_dist, optimal_start, near_mul, 1)
		else             -> near_mul
	distance < optimal_end  -> 1
	far_falloff > 0         -> map(distance, optimal_end, far_dist, 1, far_mul)
	else                    -> far_mul
]]
function ballistics.get_damage_falloff(weapon, distance, context)
	if not has_falloff(weapon) then
		return nil
	end

	if type(distance) ~= 'number' then
		return nil
	end

	local optimal_distance = weapon._optimal_distance or 0
	local optimal_range = weapon._optimal_range or 0

	if optimal_distance + optimal_range == 0 then
		return 1
	end

	local near_falloff = weapon._near_falloff or 0
	local far_falloff = weapon._far_falloff or 0
	local near_mul = weapon._near_multiplier or 0
	local far_mul = weapon._far_multiplier or 0
	local optimal_end = optimal_distance + optimal_range
	local far_dist = optimal_end + far_falloff
	local near_dist = optimal_distance - near_falloff

	if context and context.steelsight then
		local primary_category = weapon_categories(weapon)[1]
		local range_multiplier = ctx_upgrade_value(context, primary_category, 'steelsight_range_inc', 1)

		optimal_end = optimal_end * range_multiplier
		far_dist = far_dist * range_multiplier
	end

	if distance < optimal_distance then
		if near_falloff > 0 then
			return map_range_clamped(distance, near_dist, optimal_distance, near_mul, 1)
		end

		return near_mul
	elseif distance < optimal_end then
		return 1
	elseif far_falloff > 0 then
		return map_range_clamped(distance, optimal_end, far_dist, 1, far_mul)
	end

	return far_mul
end

--[[
NewRaycastWeaponBase:is_weak_hit (newraycastweaponbase.lua:1206). The game's
nested and/or expression yields false for multipliers exactly 1; return the
neutral 1 instead so callers always get a number.
]]
function ballistics.is_weak_hit(weapon, distance, context)
	if not has_falloff(weapon) or type(distance) ~= 'number' then
		return 1
	end

	local optimal_distance = weapon._optimal_distance or 0
	local optimal_range = weapon._optimal_range or 0

	if optimal_distance + optimal_range == 0 then
		return 1
	end

	local near_distance = optimal_distance - (weapon._near_falloff or 0)
	local far_distance = optimal_distance + optimal_range + (weapon._far_falloff or 0)

	if context and context.steelsight then
		local primary_category = weapon_categories(weapon)[1]
		far_distance = far_distance * ctx_upgrade_value(context, primary_category, 'steelsight_range_inc', 1)
	end

	if distance < near_distance then
		local near_mul = weapon._near_multiplier or 0

		if near_mul < 1 then
			return 0.5
		elseif near_mul > 1 then
			return 1.2
		end

		return 1
	end

	if far_distance < distance then
		local far_mul = weapon._far_multiplier or 0

		if far_mul < 1 then
			return 0.5
		elseif far_mul > 1 then
			return 1.2
		end
	end

	return 1
end

--[[
BlackMarketManager:modify_damage_falloff (blackmarketmanager.lua:3209): each
part's custom_stats may override or scale the falloff table, in the order the
game applies them. Returns a new table; the input is not mutated.
]]
function ballistics.modify_falloff(falloff, custom_stats)
	local result = {
		optimal_distance = falloff and falloff.optimal_distance or 0,
		optimal_range = falloff and falloff.optimal_range or 0,
		near_falloff = falloff and falloff.near_falloff or 0,
		far_falloff = falloff and falloff.far_falloff or 0,
		near_multiplier = falloff and falloff.near_multiplier or 0,
		far_multiplier = falloff and falloff.far_multiplier or 0,
	}

	for _, stats in pairs(custom_stats or {}) do
		local override = stats.falloff_override

		if override then
			result.optimal_distance = override.optimal_distance or result.optimal_distance
			result.optimal_range = override.optimal_range or result.optimal_range
			result.near_falloff = override.near_falloff or result.near_falloff
			result.far_falloff = override.far_falloff or result.far_falloff
			result.near_multiplier = override.near_multiplier or result.near_multiplier
			result.far_multiplier = override.far_multiplier or result.far_multiplier
		end

		if stats.optimal_distance_mul ~= nil then
			result.optimal_distance = result.optimal_distance * stats.optimal_distance_mul
		end

		if stats.optimal_range_mul ~= nil then
			result.optimal_range = result.optimal_range * stats.optimal_range_mul
		end

		if stats.near_falloff_mul ~= nil then
			result.near_falloff = result.near_falloff * stats.near_falloff_mul
		end

		if stats.far_falloff_mul ~= nil then
			result.far_falloff = result.far_falloff * stats.far_falloff_mul
		end

		if stats.falloff_mul ~= nil then
			result.optimal_distance = result.optimal_distance * stats.falloff_mul
			result.optimal_range = result.optimal_range * stats.falloff_mul
			result.near_falloff = result.near_falloff * stats.falloff_mul
			result.far_falloff = result.far_falloff * stats.falloff_mul
		end

		if stats.near_damage_mul ~= nil then
			result.near_multiplier = result.near_multiplier * stats.near_damage_mul
		end

		if stats.far_damage_mul ~= nil then
			result.far_multiplier = result.far_multiplier * stats.far_damage_mul
		end

		if stats.falloff_damage_mul ~= nil then
			result.near_multiplier = result.near_multiplier * stats.falloff_damage_mul
			result.far_multiplier = result.far_multiplier * stats.falloff_damage_mul
		end

		if stats.damage_near_mul ~= nil then
			result.optimal_range = result.optimal_range * stats.damage_near_mul
		end

		if stats.damage_far_mul ~= nil then
			result.far_falloff = result.far_falloff * stats.damage_far_mul
		end
	end

	return result
end

return ballistics
