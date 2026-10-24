--[[
core/accuracy.lua — spread and recoil math.

Responsibility:
	Read the weapon's spread/recoil tweaks and the current stance from the context
	and return the numbers the stats rows display. The formulas are ported from
	the game's weapon and player-state code, but evaluated as plain math: the
	stance comes from the context instead of a player unit.

Public API:
	accuracy.spread_horizontal(weapon, context) -> standing, moving
	accuracy.spread_vertical(weapon, context) -> standing, moving
		Horizontal/vertical spread in degrees for the standing and the moving
		pose (crouching follows context.ducking, aiming follows
		context.steelsight, a deployed bipod counts as crouching).
	accuracy.recoil_horizontal(weapon, context) -> left, right
	accuracy.recoil_vertical(weapon, context) -> up, down
		Kick angles in degrees, matching the old "recoil" rows.
	accuracy.spread(weapon, context) -> x, y
	accuracy.recoil(weapon, context) -> {up=, down=, left=, right=}
		The full pair for the context's own stance (what weapon:_get_spread and
		weapon:recoil answer in the game).

	Every function returns nil when the tweak data has no stance table for the
	weapon (the row stays blank), never a placeholder angle.

Formula sources (PAYDAY 2 248.2):
	lib/units/weapons/newraycastweaponbase.lua:2649-2797 _get_spread and its index
	lib/managers/blackmarketmanager.lua:10192-10396 accuracy_*/recoil_*
	lib/units/weapons/raycastweaponbase.lua:1779-1832 recoil/spread accessors
	lib/units/beings/player/states/playerstandard.lua:5249-5265 recoil kick
	lib/units/beings/player/states/playerbipod.lua:79-81 bipod stance
	lib/tweak_data/weapontweakdata.lua stats.spread / stats.recoil columns
Engine-only terms (documented, not invented):
	* NewRaycastWeaponBase:recoil_multiplier divides by _shooting_count + 1 for
	  shots after the first; a stat row describes the first bullet.
	* alt-fire spread/recoil multipliers (_alt_fire_active) are not modelled.
]]

local accuracy = {}

local function raw_global(name)
	return rawget(_G, name)
end

local function weapons_tweak()
	local tweak_data = raw_global('tweak_data')
	return tweak_data and tweak_data.weapon or nil
end

local function stats_tweak(name)
	local weapons = weapons_tweak()
	return weapons and weapons.stats and weapons.stats[name] or nil
end

local function clamp(value, minimum, maximum)
	if value < minimum then
		return minimum
	elseif value > maximum then
		return maximum
	end

	return value
end

-- NewRaycastWeaponBase:_convert_add_to_mul (newraycastweaponbase.lua:2639).
local function convert_add_to_mul(value)
	if value > 1 then
		return 1 / value
	elseif value < 1 then
		return math.abs(value - 1) + 1
	end

	return 1
end

local function ctx_upgrade_value(context, category, upgrade, default)
	if context and type(context.upgrade_value) == 'function' then
		return context:upgrade_value(category, upgrade, default)
	end

	return default
end

local function ctx_get_property(context, name, default)
	if context and type(context.get_property) == 'function' then
		return context:get_property(name, default)
	end

	return default
end

local function ctx_has_team_category_upgrade(context, category, upgrade)
	return context and type(context.has_team_category_upgrade) == 'function'
		and context:has_team_category_upgrade(category, upgrade)
		or false
end

local function ctx_team_upgrade_value(context, category, upgrade, default)
	if context and type(context.team_upgrade_value) == 'function' then
		return context:team_upgrade_value(category, upgrade, default)
	end

	return default
end

local function ctx_flag(context, name)
	return context and not not context[name] or false
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

local function weapon_categories(weapon)
	if type(weapon) == 'table' and type(weapon.categories) == 'function' then
		return weapon:categories() or {}
	end

	local tweak = weapon_tweak_data(weapon)
	return tweak and tweak.categories or {}
end

-- NewRaycastWeaponBase:fire_mode (newraycastweaponbase.lua:1848).
local function fire_mode(weapon)
	if type(weapon) ~= 'table' then
		return 'single'
	end

	if type(weapon.fire_mode_category) == 'function' then
		return weapon:fire_mode_category() or 'single'
	end

	return weapon._fire_mode or weapon._fire_mode_category or 'single'
end

-- NewRaycastWeaponBase:is_single_shot (newraycastweaponbase.lua:3258).
local function is_single_shot(weapon)
	return fire_mode(weapon) == 'single'
end

local function has_category(weapon, list)
	for _, category in ipairs(weapon_categories(weapon)) do
		for _, entry in ipairs(list or {}) do
			if entry == category then
				return true
			end
		end
	end

	return false
end

-- BlackMarketManager:is_weapon_modified (blackmarketmanager.lua:2249), answered
-- by the model because it owns the blueprint.
local function is_weapon_modified(weapon)
	return type(weapon) == 'table' and type(weapon.is_weapon_modified) == 'function' and weapon:is_weapon_modified() or false
end

local function is_silenced(weapon)
	return type(weapon) == 'table' and not not weapon._silencer
end

--[[
PlayerStandard:get_movement_state (playerstandard.lua:5824) /
PlayerBipod:get_movement_state (playerbipod.lua:79).

`moving` overrides context.moving: the spread rows show the standing value and
the moving value side by side.
]]
local function movement_state(context, moving)
	local ducking = ctx_flag(context, 'ducking') or ctx_flag(context, 'deployed')

	if moving == nil then
		moving = ctx_flag(context, 'moving')
	end

	if ducking then
		return moving and 'moving_crouching' or 'crouching'
	end

	return moving and 'moving_standing' or 'standing'
end

--[[
BlackMarketManager:accuracy_index_addend (blackmarketmanager.lua:10237).
]]
local function accuracy_index_addend(weapon, context, moving)
	local categories = weapon_categories(weapon)
	local index = 0

	index = index + ctx_upgrade_value(context, 'player', 'weapon_accuracy_increase', 0)

	for _, category in ipairs(categories) do
		index = index + ctx_upgrade_value(context, category, 'spread_index_addend', 0)

		if moving then
			index = index + ctx_upgrade_value(context, category, 'move_spread_index_addend', 0)
		end
	end

	if is_silenced(weapon) then
		index = index + ctx_upgrade_value(context, 'weapon', 'silencer_spread_index_addend', 0)

		for _, category in ipairs(categories) do
			index = index + ctx_upgrade_value(context, category, 'silencer_spread_index_addend', 0)
		end
	end

	-- 248.2: lib/tweak_data/upgradestweakdata.lua:713 sharpshooter_categories.
	local upgrades = raw_global('tweak_data') and raw_global('tweak_data').upgrades
	local sharpshooter_categories = upgrades and upgrades.sharpshooter_categories

	if fire_mode(weapon) == 'single' and sharpshooter_categories and has_category(weapon, sharpshooter_categories) then
		index = index + ctx_upgrade_value(context, 'weapon', 'single_spread_index_addend', 0)
	elseif fire_mode(weapon) == 'auto' or fire_mode(weapon) == 'burst' then
		index = index + ctx_upgrade_value(context, 'weapon', 'auto_spread_index_addend', 0)
	end

	return index
end

--[[
NewRaycastWeaponBase:conditional_accuracy_addend (newraycastweaponbase.lua:2739).
]]
local function conditional_accuracy_addend(weapon, context, moving)
	local index = 0

	if not ctx_flag(context, 'steelsight') then
		index = index + ctx_upgrade_value(context, 'player', 'hip_fire_accuracy_inc', 0)
	end

	if is_single_shot(weapon) and has_category(weapon, {'assault_rifle', 'smg', 'snp'}) then
		index = index + ctx_upgrade_value(context, 'weapon', 'single_spread_index_addend', 0)
	elseif not is_single_shot(weapon) then
		index = index + ctx_upgrade_value(context, 'weapon', 'auto_spread_index_addend', 0)
	end

	if not moving then
		index = index + ctx_upgrade_value(context, 'player', 'not_moving_accuracy_increase', 0)
	end

	if moving then
		for _, category in ipairs(weapon_categories(weapon)) do
			index = index + ctx_upgrade_value(context, category, 'move_spread_index_addend', 0)
		end
	end

	return index
end

--[[
NewRaycastWeaponBase:conditional_accuracy_multiplier (newraycastweaponbase.lua:2771).
]]
local function conditional_accuracy_multiplier(weapon, context, moving)
	local multiplier = 1

	if ctx_flag(context, 'steelsight') and is_single_shot(weapon) then
		multiplier = multiplier + (1 - ctx_upgrade_value(context, 'player', 'single_shot_accuracy_inc', 1))
	end

	if ctx_flag(context, 'steelsight') then
		for _, category in ipairs(weapon_categories(weapon)) do
			multiplier = multiplier + (1 - ctx_upgrade_value(context, category, 'steelsight_accuracy_inc', 1))
		end
	end

	if moving then
		multiplier = multiplier + (1 - ctx_upgrade_value(context, 'player', 'weapon_movement_stability', 1))
	end

	multiplier = multiplier + (1 - ctx_get_property(context, 'desperado', 1))

	return convert_add_to_mul(multiplier)
end

--[[
BlackMarketManager:accuracy_multiplier (blackmarketmanager.lua:10267). This is
what NewRaycastWeaponBase:spread_multiplier(current_state) returns; do not
confuse it with RaycastWeaponBase:spread_multiplier() (plain category terms,
unused by the spread formula in 248.2).
]]
local function accuracy_multiplier(weapon, context)
	local categories = weapon_categories(weapon)
	local multiplier = 1

	if is_silenced(weapon) then
		multiplier = multiplier + (1 - ctx_upgrade_value(context, 'weapon', 'silencer_spread_multiplier', 1))

		for _, category in ipairs(categories) do
			multiplier = multiplier + (1 - ctx_upgrade_value(context, category, 'silencer_spread_multiplier', 1))
		end
	end

	if is_weapon_modified(weapon) then
		multiplier = multiplier + (1 - ctx_upgrade_value(context, 'weapon', 'modded_spread_multiplier', 1))
	end

	return convert_add_to_mul(multiplier)
end

--[[
NewRaycastWeaponBase:_get_spread_index (newraycastweaponbase.lua:2723): resolve
the stat index into the stats.spread value after every accuracy upgrade.
]]
local function spread_index_value(weapon, context, spread_index, moving)
	local spread_multiplier = 1
	local spread_column = stats_tweak('spread')

	spread_multiplier = spread_multiplier - (1 - accuracy_multiplier(weapon, context))
	spread_multiplier = spread_multiplier - (1 - conditional_accuracy_multiplier(weapon, context, moving))
	spread_multiplier = convert_add_to_mul(spread_multiplier)

	local spread_addend = accuracy_index_addend(weapon, context, moving)
		+ conditional_accuracy_addend(weapon, context, moving)

	local index = math.ceil((spread_index + spread_addend) * spread_multiplier)

	if spread_column then
		index = clamp(index, 1, #spread_column)
		return spread_column[index]
	end

	return nil
end

--[[
NewRaycastWeaponBase:_get_spread_indices (newraycastweaponbase.lua:2708): the
spread stat may be a single index or an {x, y} pair.
]]
local function spread_indices(weapon, context, moving)
	local stats = type(weapon) == 'table' and weapon._current_stats_indices or nil
	local spread_index = stats and stats.spread

	if type(spread_index) == 'table' then
		return spread_index_value(weapon, context, spread_index[1], moving),
			spread_index_value(weapon, context, spread_index[2], moving)
	end

	local value = spread_index_value(weapon, context, spread_index or 1, moving)

	return value, value
end

--[[
NewRaycastWeaponBase:_get_spread (newraycastweaponbase.lua:2649).
Returns the horizontal and vertical spread of one pose.
]]
function accuracy.spread(weapon, context, moving)
	local tweak = weapon_tweak_data(weapon)
	local spread_values = tweak and tweak.spread

	if type(spread_values) ~= 'table' then
		return nil, nil
	end

	local is_moving = moving

	if is_moving == nil then
		is_moving = ctx_flag(context, 'moving')
	end

	local state = movement_state(context, is_moving)
	local current_spread_value = spread_values[state]

	if current_spread_value == nil then
		return nil, nil
	end

	local index_x, index_y = spread_indices(weapon, context, is_moving)
	local spread_x, spread_y

	if type(current_spread_value) == 'number' then
		spread_x = math.max(index_x * current_spread_value, 0)
		spread_y = spread_x
	else
		spread_x = math.max(index_x * current_spread_value[1], 0)
		spread_y = math.max(index_y * current_spread_value[2], 0)
	end

	if ctx_flag(context, 'steelsight') then
		local steelsight_tweak = spread_values.steelsight

		if type(steelsight_tweak) == 'number' then
			local multi = 1 + (1 - steelsight_tweak)
			spread_x = spread_x * multi
			spread_y = spread_y * multi
		elseif type(steelsight_tweak) == 'table' then
			spread_x = spread_x * (1 + (1 - steelsight_tweak[1]))
			spread_y = spread_y * (1 + (1 - steelsight_tweak[2]))
		end
	end

	if type(weapon._spread_multiplier) == 'table' then
		spread_x = spread_x * (weapon._spread_multiplier[1] or 1)
		spread_y = spread_y * (weapon._spread_multiplier[2] or 1)
	end

	return spread_x, spread_y
end

function accuracy.spread_horizontal(weapon, context)
	local standing = accuracy.spread(weapon, context, false)

	if standing == nil then
		return nil, nil
	end

	return standing, (accuracy.spread(weapon, context, true))
end

function accuracy.spread_vertical(weapon, context)
	local _, standing = accuracy.spread(weapon, context, false)

	if standing == nil then
		return nil, nil
	end

	local _, moving = accuracy.spread(weapon, context, true)

	return standing, moving
end

--[[
BlackMarketManager:recoil_addend (blackmarketmanager.lua:10285). The team branch
follows the not-suppressed path: context.suppressed is false unless the snapshot
captured a suppressed player.
]]
local function recoil_addend(weapon, context)
	local stats = type(weapon) == 'table' and weapon._current_stats_indices or nil
	local recoil_index = stats and stats.recoil

	if not recoil_index then
		return 0
	end

	local categories = weapon_categories(weapon)
	local name_id = weapon and weapon._name_id
	local index = recoil_index

	index = index + ctx_upgrade_value(context, 'weapon', 'recoil_index_addend', 0)
	index = index + ctx_upgrade_value(context, 'player', 'stability_increase_bonus_1', 0)
	index = index + ctx_upgrade_value(context, 'player', 'stability_increase_bonus_2', 0)
	index = index + ctx_upgrade_value(context, name_id, 'recoil_index_addend', 0)

	for _, category in ipairs(categories) do
		index = index + ctx_upgrade_value(context, category, 'recoil_index_addend', 0)
	end

	if ctx_flag(context, 'suppressed') then
		for _, category in ipairs(categories) do
			if ctx_has_team_category_upgrade(context, category, 'suppression_recoil_index_addend') then
				index = index + ctx_team_upgrade_value(context, category, 'suppression_recoil_index_addend', 0)
			end
		end

		if ctx_has_team_category_upgrade(context, 'weapon', 'suppression_recoil_index_addend') then
			index = index + ctx_team_upgrade_value(context, 'weapon', 'suppression_recoil_index_addend', 0)
		end
	else
		for _, category in ipairs(categories) do
			if ctx_has_team_category_upgrade(context, category, 'recoil_index_addend') then
				index = index + ctx_team_upgrade_value(context, category, 'recoil_index_addend', 0)
			end
		end

		if ctx_has_team_category_upgrade(context, 'weapon', 'recoil_index_addend') then
			index = index + ctx_team_upgrade_value(context, 'weapon', 'recoil_index_addend', 0)
		end
	end

	if is_silenced(weapon) then
		index = index + ctx_upgrade_value(context, 'weapon', 'silencer_recoil_index_addend', 0)

		for _, category in ipairs(categories) do
			index = index + ctx_upgrade_value(context, category, 'silencer_recoil_index_addend', 0)
		end
	end

	if is_weapon_modified(weapon) then
		index = index + ctx_upgrade_value(context, 'weapon', 'modded_recoil_index_addend', 0)
	end

	local recoil_column = stats_tweak('recoil')

	if not recoil_column then
		return 0
	end

	index = clamp(index, 1, #recoil_column)
	recoil_index = clamp(recoil_index, 1, #recoil_column)

	if index ~= recoil_index then
		return recoil_column[index] - recoil_column[recoil_index]
	end

	return 0
end

--[[
BlackMarketManager:recoil_multiplier (blackmarketmanager.lua:10349).
]]
local function recoil_multiplier(weapon, context)
	local categories = weapon_categories(weapon)
	local multiplier = 1

	for _, category in ipairs(categories) do
		multiplier = multiplier + (1 - ctx_upgrade_value(context, category, 'recoil_multiplier', 1))
		multiplier = multiplier + (1 - ctx_upgrade_value(context, category, 'passive_recoil_multiplier', 1))
	end

	if ctx_flag(context, 'suppressed') then
		for _, category in ipairs(categories) do
			if ctx_has_team_category_upgrade(context, category, 'suppression_recoil_multiplier') then
				multiplier = multiplier + (1 - ctx_team_upgrade_value(context, category, 'suppression_recoil_multiplier', 1))
			end
		end

		if ctx_has_team_category_upgrade(context, 'weapon', 'suppression_recoil_multiplier') then
			multiplier = multiplier + (1 - ctx_team_upgrade_value(context, 'weapon', 'suppression_recoil_multiplier', 1))
		end
	else
		for _, category in ipairs(categories) do
			if ctx_has_team_category_upgrade(context, category, 'recoil_multiplier') then
				multiplier = multiplier + (1 - ctx_team_upgrade_value(context, category, 'recoil_multiplier', 1))
			end
		end

		if ctx_has_team_category_upgrade(context, 'weapon', 'recoil_multiplier') then
			multiplier = multiplier + (1 - ctx_team_upgrade_value(context, 'weapon', 'recoil_multiplier', 1))
		end
	end

	multiplier = multiplier + (1 - ctx_upgrade_value(context, weapon and weapon._name_id, 'recoil_multiplier', 1))
	multiplier = multiplier + (1 - ctx_upgrade_value(context, 'weapon', 'passive_recoil_multiplier', 1))
	multiplier = multiplier + (1 - ctx_upgrade_value(context, 'player', 'recoil_multiplier', 1))

	if is_silenced(weapon) then
		multiplier = multiplier + (1 - ctx_upgrade_value(context, 'weapon', 'silencer_recoil_multiplier', 1))

		for _, category in ipairs(categories) do
			multiplier = multiplier + (1 - ctx_upgrade_value(context, category, 'silencer_recoil_multiplier', 1))
		end
	end

	if is_weapon_modified(weapon) then
		multiplier = multiplier + (1 - ctx_upgrade_value(context, 'weapon', 'modded_recoil_multiplier', 1))
	end

	return convert_add_to_mul(multiplier)
end

--[[
PlayerStandard:_check_action_primary_attack (playerstandard.lua:5249-5265):

	recoil_multiplier = (weapon:recoil() + weapon:recoil_addend()) * weapon:recoil_multiplier()
	kick              = weap_tweak_data.kick[fire_mode] or weap_tweak_data.kick
	up, down, left, right = unpack(kick[steelsight|crouching|standing])
]]
function accuracy.recoil(weapon, context)
	local tweak = weapon_tweak_data(weapon)
	local kick = tweak and tweak.kick

	if type(kick) ~= 'table' then
		return nil
	end

	local mode_kick = kick[fire_mode(weapon)]

	if type(mode_kick) == 'table' then
		kick = mode_kick
	end

	local pose

	if ctx_flag(context, 'steelsight') then
		pose = 'steelsight'
	elseif ctx_flag(context, 'ducking') then
		pose = 'crouching'
	else
		pose = 'standing'
	end

	local values = kick[pose]

	if type(values) ~= 'table' or values[1] == nil then
		return nil
	end

	local recoil = type(weapon._recoil) == 'number' and weapon._recoil or 0
	local multiplier = (recoil + recoil_addend(weapon, context)) * recoil_multiplier(weapon, context)

	return {
		up = values[1] * multiplier,
		down = values[2] * multiplier,
		left = values[3] * multiplier,
		right = values[4] * multiplier,
	}
end

function accuracy.recoil_horizontal(weapon, context)
	local recoil = accuracy.recoil(weapon, context)

	if not recoil then
		return nil, nil
	end

	return recoil.left, recoil.right
end

function accuracy.recoil_vertical(weapon, context)
	local recoil = accuracy.recoil(weapon, context)

	if not recoil then
		return nil, nil
	end

	return recoil.up, recoil.down
end

return accuracy
