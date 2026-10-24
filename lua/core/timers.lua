--[[
core/timers.lua — reload, equip and unequip duration math.

Responsibility:
	Answer "how long does this take" questions from weapon data and the player
	context, instead of advancing a simulated player state machine. Every value
	is the duration the game's timer would end up with, never a running clock.

Public API:
	timers.reload_speed_multiplier(weapon, context) -> multiplier|nil
		NewRaycastWeaponBase:reload_speed_multiplier (newraycastweaponbase.lua:2903).
	timers.swap_speed_multiplier(weapon, context) -> multiplier|nil
		PlayerStandard:_get_swap_speed_multiplier (playerstandard.lua:5571).
	timers.reload_full(weapon, ammo_remaining, context) -> seconds|nil
		Full reload: the empty-clip reload when `ammo_remaining` is 0. A nil
		`ammo_remaining` falls back to the weapon's own clip accessor
		(get_ammo_remaining_in_clip); when that is unset too the reload is
		reported as an empty-clip reload.
	timers.reload_partial(weapon, rounds_missing, context) -> partial|nil, shell|nil
		The "one round short" reload the row shows next to the single-shell time.
		`rounds_missing` defaults to 1 and mirrors the v76 row, which called
		mws_reload_x_ammo(wbase, 1) — one round missing, not one round left.
		Single-shell weapons (clip max == 1) return nil so the row blanks, like
		the old mws_reload_partial did.
		The single-shell time uses the tactical (`not_empty`) shell timer. v76
		called reload_shell_expire_t() without that flag, i.e. the empty variant;
		for weapons with an explicit timers.shotgun_reload table (ultima,
		weapontweakdata.lua:28262-28304) that showed the empty-path fallback
		(0.5667 s) instead of ultima's tactical reload_shell (1.0 s).
	timers.equip_delay(weapon, context) -> equip|nil, unequip|nil
		PlayerStandard:_start_action_equip_weapon / _start_action_unequip_weapon.

	timers.reload_expire_t(weapon, ammo_remaining, is_not_empty)
	timers.reload_enter_expire_t(weapon, is_not_empty)
	timers.reload_exit_expire_t(weapon, is_not_empty)
	timers.reload_shell_expire_t(weapon, is_not_empty)
	timers.first_shell_reload_expire_t(weapon, is_not_empty)
	timers.started_reload_empty(weapon, ammo_remaining)
	timers.use_shotgun_reload(weapon)
	timers.clip_empty(weapon, ammo_remaining)
	timers.clip_not_empty(weapon, ammo_remaining)
		The weapon-side half of the same contract, so core/weapon can answer the
		same questions the game's weapon base answers.

	Every function returns nil when the tweak data does not support the answer
	(no stats, no timer, a multiplier of zero, an unknown clip state) so the UI
	leaves the row blank rather than printing a made-up duration.

Formula sources (PAYDAY 2 248.2):
	lib/units/weapons/newraycastweaponbase.lua:2903-3101
	lib/units/weapons/raycastweaponbase.lua:1787-1803, 1945-1951, 2025-2027
	lib/units/beings/player/states/playerstandard.lua:5424-5517, 5571-5721
	lib/managers/playermanager.lua:1974-2006, 2119-2195
Engine state the stat snapshot cannot carry (documented, not invented):
	* movement ext morale_boost()/next_reload_speed_multiplier() — transient
	  crew buffs that live on the player's movement state;
	* managers.modifiers:modify_value("WeaponBase:GetReloadSpeedMultiplier")
	  and ("PlayerStandard:GetSwapSpeedMultiplier") — mutator overrides.
	The v76 fake player unit produced none of these either.
]]

local timers = {}

local function raw_global(name)
	return rawget(_G, name)
end

local function weapon_tweak()
	local tweak_data = raw_global('tweak_data')
	return tweak_data and tweak_data.weapon or nil
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

local function ctx_temporary_upgrade_value(context, category, upgrade, default)
	if context and type(context.temporary_upgrade_value) == 'function' then
		return context:temporary_upgrade_value(category, upgrade, default)
	end

	return default
end

local function ctx_has_activate_temporary_upgrade(context, category, upgrade)
	return context and type(context.has_activate_temporary_upgrade) == 'function'
		and context:has_activate_temporary_upgrade(category, upgrade)
		or false
end

local function ctx_get_property(context, name, default)
	if context and type(context.get_property) == 'function' then
		return context:get_property(name, default)
	end

	return default
end

local function ctx_get_temporary_property(context, name, default)
	if context and type(context.get_temporary_property) == 'function' then
		return context:get_temporary_property(name, default)
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

	local weapons = weapon_tweak()
	return weapons and weapons[weapon._name_id] or nil
end

local function weapon_categories(weapon)
	if type(weapon) == 'table' and type(weapon.categories) == 'function' then
		return weapon:categories() or {}
	end

	local tweak = weapon_tweak_data(weapon)
	return tweak and tweak.categories or {}
end

local function weapon_timers(weapon)
	local tweak = weapon_tweak_data(weapon)
	return tweak and tweak.timers or nil
end

local function ammo_max_per_clip(weapon)
	if type(weapon) ~= 'table' then
		return nil
	end

	if type(weapon.get_ammo_max_per_clip) == 'function' then
		return weapon:get_ammo_max_per_clip()
	end

	return weapon._ammo_max_per_clip
end

local function ammo_total(weapon)
	if type(weapon) ~= 'table' then
		return nil
	end

	if type(weapon.get_ammo_total) == 'function' then
		return weapon:get_ammo_total()
	end

	return weapon._ammo_total
end

local function ammo_remaining_in_clip(weapon)
	if type(weapon) ~= 'table' then
		return nil
	end

	if type(weapon.get_ammo_remaining_in_clip) == 'function' then
		return weapon:get_ammo_remaining_in_clip()
	end

	return weapon._ammo_remaining_in_clip
end

-- RaycastWeaponBase:use_shotgun_reload (raycastweaponbase.lua:2961).
function timers.use_shotgun_reload(weapon)
	if type(weapon) ~= 'table' then
		return false
	end

	local value = weapon._use_shotgun_reload

	if value == nil then
		local tweak = weapon_tweak_data(weapon)
		value = tweak and tweak.use_shotgun_reload
	end

	return value and true or false
end

-- RaycastWeaponBase:clip_empty / clip_not_empty (raycastweaponbase.lua:1945-1951).
function timers.clip_empty(weapon, ammo_remaining)
	local remaining = ammo_remaining

	if remaining == nil then
		remaining = ammo_remaining_in_clip(weapon)
	end

	if remaining == nil then
		return nil
	end

	return remaining <= 0
end

function timers.clip_not_empty(weapon, ammo_remaining)
	local empty = timers.clip_empty(weapon, ammo_remaining)

	if empty == nil then
		return nil
	end

	return not empty
end

-- NewRaycastWeaponBase:started_reload_empty (newraycastweaponbase.lua:3095).
-- The game caches the flag in start_reload(); for a stat query the flag is the
-- clip state the reload starts from.
function timers.started_reload_empty(weapon, ammo_remaining)
	if not timers.use_shotgun_reload(weapon) then
		return nil
	end

	return timers.clip_empty(weapon, ammo_remaining)
end

-- NewRaycastWeaponBase:_get_shotgun_reload_tweak_data (newraycastweaponbase.lua:3055).
local function shotgun_reload_tweak(weapon, is_not_empty)
	local timer_data = weapon_timers(weapon)
	local shotgun_reload = timer_data and timer_data.shotgun_reload

	if not shotgun_reload then
		return nil
	end

	return is_not_empty and shotgun_reload.not_empty or shotgun_reload.empty
end

-- NewRaycastWeaponBase:reload_shell_expire_t (newraycastweaponbase.lua:3034).
function timers.reload_shell_expire_t(weapon, is_not_empty)
	if not timers.use_shotgun_reload(weapon) then
		return nil
	end

	local shotgun_tweak = shotgun_reload_tweak(weapon, is_not_empty)

	if shotgun_tweak and shotgun_tweak.reload_shell then
		return shotgun_tweak.reload_shell
	end

	local timer_data = weapon_timers(weapon)
	return timer_data and timer_data.shotgun_reload_shell or 0.5666666666666667
end

-- NewRaycastWeaponBase:_first_shell_reload_expire_t (newraycastweaponbase.lua:3044).
function timers.first_shell_reload_expire_t(weapon, is_not_empty)
	if not timers.use_shotgun_reload(weapon) then
		return nil
	end

	local shotgun_tweak = shotgun_reload_tweak(weapon, is_not_empty)
	local offset

	if shotgun_tweak and shotgun_tweak.reload_first_shell_offset then
		offset = shotgun_tweak.reload_first_shell_offset
	else
		local timer_data = weapon_timers(weapon)
		offset = timer_data and timer_data.shotgun_reload_first_shell_offset or 0.33
	end

	return timers.reload_shell_expire_t(weapon, is_not_empty) - offset
end

-- NewRaycastWeaponBase:reload_enter_expire_t (newraycastweaponbase.lua:3006).
function timers.reload_enter_expire_t(weapon, is_not_empty)
	if not timers.use_shotgun_reload(weapon) then
		return nil
	end

	local shotgun_tweak = shotgun_reload_tweak(weapon, is_not_empty)

	if shotgun_tweak and shotgun_tweak.reload_enter then
		return shotgun_tweak.reload_enter
	end

	local timer_data = weapon_timers(weapon)
	return timer_data and timer_data.shotgun_reload_enter or 0.3
end

-- NewRaycastWeaponBase:reload_exit_expire_t (newraycastweaponbase.lua:3016).
function timers.reload_exit_expire_t(weapon, is_not_empty)
	if not timers.use_shotgun_reload(weapon) then
		return nil
	end

	local shotgun_tweak = shotgun_reload_tweak(weapon, is_not_empty)

	if shotgun_tweak then
		return shotgun_tweak.reload_exit
	end

	local timer_data = weapon_timers(weapon) or {}

	if is_not_empty then
		return timer_data.shotgun_reload_exit_not_empty or 0.3
	end

	return timer_data.shotgun_reload_exit_empty or 0.7
end

-- NewRaycastWeaponBase:reload_expire_t (newraycastweaponbase.lua:2969).
-- `ammo_remaining` is the clip content before the reload starts; it decides how
-- many shells a shell-by-shell weapon has to load.
function timers.reload_expire_t(weapon, ammo_remaining, is_not_empty)
	if not timers.use_shotgun_reload(weapon) then
		return nil
	end

	local clip_max = ammo_max_per_clip(weapon) or 0
	local total = ammo_total(weapon) or 0
	local remaining = ammo_remaining

	if remaining == nil then
		remaining = ammo_remaining_in_clip(weapon)
	end

	remaining = remaining or 0

	local ammo_to_reload = math.min(total - remaining, clip_max - remaining)
	local shotgun_tweak = shotgun_reload_tweak(weapon, is_not_empty)

	if shotgun_tweak and shotgun_tweak.reload_queue then
		local queue = shotgun_tweak.reload_queue
		local queue_num = #queue

		if queue_num == 0 then
			return 0
		end

		local reload_expire_t = 0
		local queue_index = 0
		local guard = 0

		while ammo_to_reload > 0 and guard < 1000 do
			guard = guard + 1

			if queue_index == queue_num then
				reload_expire_t = reload_expire_t + (shotgun_tweak.reload_queue_wrap or 0)
			end

			queue_index = queue_index % queue_num + 1

			local queue_data = queue[queue_index]
			reload_expire_t = reload_expire_t + queue_data.expire_t
			ammo_to_reload = ammo_to_reload - (queue_data.reload_num or 1)
		end

		return reload_expire_t
	end

	local shell_expire_t = timers.reload_shell_expire_t(weapon, is_not_empty)
	local reload_num = shotgun_tweak and shotgun_tweak.reload_num or 1

	return math.ceil(ammo_to_reload / reload_num) * shell_expire_t
end

--[[
NewRaycastWeaponBase:reload_speed_multiplier (newraycastweaponbase.lua:2903).
Additive upgrade terms converted with _convert_add_to_mul, then scaled by
reload_speed_stat() = self._reload (the resolved stats.reload value).
]]
function timers.reload_speed_multiplier(weapon, context)
	if type(weapon) ~= 'table' then
		return nil
	end

	local categories = weapon_categories(weapon)
	local name_id = weapon._name_id
	local multiplier = 1

	for _, category in ipairs(categories) do
		multiplier = multiplier + (1 - ctx_upgrade_value(context, category, 'reload_speed_multiplier', 1))
	end

	multiplier = multiplier + (1 - ctx_upgrade_value(context, 'weapon', 'passive_reload_speed_multiplier', 1))
	multiplier = multiplier + (1 - ctx_upgrade_value(context, name_id, 'reload_speed_multiplier', 1))

	if ctx_has_activate_temporary_upgrade(context, 'temporary', 'reload_weapon_faster') then
		multiplier = multiplier + (1 - ctx_temporary_upgrade_value(context, 'temporary', 'reload_weapon_faster', 1))
	end

	if ctx_has_activate_temporary_upgrade(context, 'temporary', 'single_shot_fast_reload') then
		multiplier = multiplier + (1 - ctx_temporary_upgrade_value(context, 'temporary', 'single_shot_fast_reload', 1))
	end

	multiplier = multiplier + (1 - ctx_get_property(context, 'shock_and_awe_reload_multiplier', 1))
	multiplier = multiplier + (1 - ctx_get_temporary_property(context, 'bloodthirst_reload_speed', 1))
	multiplier = multiplier + (1 - ctx_upgrade_value(context, 'team', 'crew_faster_reload', 1))

	multiplier = convert_add_to_mul(multiplier)

	local reload_speed_stat = weapon._reload

	if type(reload_speed_stat) ~= 'number' then
		return nil
	end

	multiplier = multiplier * reload_speed_stat

	if multiplier <= 0 then
		return nil
	end

	return multiplier
end

--[[
PlayerStandard:_get_swap_speed_multiplier (playerstandard.lua:5571): every term
is a plain multiplication, over the equipped weapon's tweak categories.
]]
function timers.swap_speed_multiplier(weapon, context)
	if type(weapon) ~= 'table' then
		return nil
	end

	local tweak = weapon_tweak_data(weapon)
	local categories = tweak and tweak.categories or weapon_categories(weapon)
	local multiplier = 1

	multiplier = multiplier * ctx_upgrade_value(context, 'weapon', 'swap_speed_multiplier', 1)
	multiplier = multiplier * ctx_upgrade_value(context, 'weapon', 'passive_swap_speed_multiplier', 1)

	for _, category in ipairs(categories or {}) do
		multiplier = multiplier * ctx_upgrade_value(context, category, 'swap_speed_multiplier', 1)
	end

	multiplier = multiplier * ctx_upgrade_value(context, 'team', 'crew_faster_swap', 1)

	if ctx_has_activate_temporary_upgrade(context, 'temporary', 'swap_weapon_faster') then
		multiplier = multiplier * ctx_temporary_upgrade_value(context, 'temporary', 'swap_weapon_faster', 1)
	end

	multiplier = multiplier * ctx_upgrade_value(context, 'weapon', 'mrwi_swap_speed_multiplier', 1)

	if multiplier <= 0 then
		return nil
	end

	return multiplier
end

local function reload_default_expire_t(is_not_empty)
	-- PlayerStandard:_start_action_reload (playerstandard.lua:5486-5494).
	return is_not_empty and 2.2 or 2.6
end

--[[
Full reload duration: PlayerStandard:_start_action_reload_enter followed by
_start_action_reload, plus the reload_exit timer shell-by-shell weapons get.

	enter = reload_enter_expire_t(is_not_empty)     -- shotguns only
	base  = timers.reload_empty|reload_not_empty
	        or reload_expire_t(is_not_empty)        -- shotguns only
	        or 2.6|2.2
	exit  = reload_exit_expire_t(is_not_empty)      -- shotguns only

Everything is divided by the reload speed multiplier, exactly like
playerstandard.lua:5456, 5502 and 3163.
]]
function timers.reload_full(weapon, ammo_remaining, context)
	local speed_multiplier = timers.reload_speed_multiplier(weapon, context)

	if not speed_multiplier then
		return nil
	end

	local is_not_empty = timers.clip_not_empty(weapon, ammo_remaining)

	if is_not_empty == nil then
		is_not_empty = false
	end

	local timer_data = weapon_timers(weapon) or {}
	local reload_tweak

	if is_not_empty then
		reload_tweak = timer_data.reload_not_empty
	else
		reload_tweak = timer_data.reload_empty
	end

	local base = reload_tweak
		or timers.reload_expire_t(weapon, ammo_remaining, is_not_empty)
		or reload_default_expire_t(is_not_empty)
	local enter = timers.reload_enter_expire_t(weapon, is_not_empty) or 0
	local exit = timers.reload_exit_expire_t(weapon, is_not_empty) or 0

	return (enter + base + exit) / speed_multiplier
end

--[[
Partial reload: the v76 row (mws_reload_partial) showed the reload from one
round short and, separately, the single-shell time.

	partial = reload_full(weapon, clip_max - rounds_missing)
	shell   = (timers.reload_not_empty or reload_shell_expire_t or 2.2) / speed

Both are nil for single-shell weapons (clip max == 1): the old row blanked them.
]]
function timers.reload_partial(weapon, rounds_missing, context)
	local clip_max = ammo_max_per_clip(weapon)

	if clip_max == 1 then
		return nil, nil
	end

	local speed_multiplier = timers.reload_speed_multiplier(weapon, context)

	if not speed_multiplier then
		return nil, nil
	end

	if not rounds_missing or rounds_missing <= 0 or (clip_max and rounds_missing >= clip_max) then
		rounds_missing = 1
	end

	local ammo_remaining

	if clip_max then
		ammo_remaining = clip_max - rounds_missing
	end

	local partial_seconds = timers.reload_full(weapon, ammo_remaining, context)
	local timer_data = weapon_timers(weapon) or {}
	local shell_seconds = (
		timer_data.reload_not_empty
			or timers.reload_shell_expire_t(weapon, true)
			or 2.2
	) / speed_multiplier

	if partial_seconds == 0 then
		partial_seconds = shell_seconds
	end

	return partial_seconds, shell_seconds
end

--[[
PlayerStandard:_start_action_equip_weapon (playerstandard.lua:5667-5721) and
_start_action_unequip_weapon (playerstandard.lua:5594-5665):

	equip   = (weapon.timers.equip or 0.7)   / swap_speed_multiplier
	unequip = (weapon.timers.unequip or 0.5) / swap_speed_multiplier
]]
function timers.equip_delay(weapon, context)
	-- The game always swaps a real equipped unit; without weapon tweak data
	-- there is no equip timer to report.
	if not weapon_tweak_data(weapon) then
		return nil, nil
	end

	local speed_multiplier = timers.swap_speed_multiplier(weapon, context)

	if not speed_multiplier then
		return nil, nil
	end

	local timer_data = weapon_timers(weapon) or {}

	return (timer_data.equip or 0.7) / speed_multiplier, (timer_data.unequip or 0.5) / speed_multiplier
end

return timers
