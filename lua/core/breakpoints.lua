--[[
core/breakpoints.lua — breakpoint table math (damage needed for N hits).

Responsibility:
	Answer "how much damage do I need to kill <enemy> in N hits", for the six
	unit types the breakpoint table shows, under a difficulty and a set of
	optional damage bonuses. Pure data: no unit, no manager mutation, no
	difficulty re-initialisation.

	The table is `{ [hit_nr] = damage }` over 512 health steps, exactly like
	`CopDamage` measures health (_HEALTH_GRANULARITY), because the game rounds
	incoming damage down to those steps before subtracting it.

Public API:
	breakpoints.unit_types
		The six enemy types the table shows, in display order.
	breakpoints.bonuses
		The eight bonus toggles: index, required_level, checked_by_default.
	breakpoints.bonus_availability(context, previous) -> table
		bonus name -> { index, required_level, checked_by_default, level,
		available, checked }. Reads the skill unlock levels; never writes them.
		`previous` (optional) is the previous result, so a toggle the player set
		survives a refresh instead of snapping back to its default.
	breakpoints.skill_level(context, skill) -> number
		SkillTreeManager unlock level, from the context snapshot when present.
	breakpoints.can_be_critical(weapon, damage_type) -> boolean
		CopDamage:can_be_critical, data-only: the weapon tweak data's
		categories[1] / ignore_crit_damage against
		tweak_data.weapon_disable_crit_for_damage.
	breakpoints.prepare_params(weapon, context, bonuses, options) -> table|nil
		Everything get_for_unit needs about the weapon and the toggles, derived
		from the WeaponModel and the player context. `options` may override
		clicks_per_second and enable_trigger_happy_for_first_bullet (the mod
		settings are the default).
	breakpoints.get_for_unit(unit_type, params, difficulty) -> { [hit_nr] = damage }
		`difficulty` is optional: nil means "the difficulty the params were
		captured under" (params.context.difficulty), then neutral multipliers.
	breakpoints.get_all(params, difficulty) -> unit_type -> breakpoint table
	breakpoints.consolidate(data, damage, amount_wanted, fill) -> ref_damage, list
		Merges the per-unit tables into the table the UI draws; `fill` is the
		fill_breakpoints setting.
	breakpoints.difficulty_snapshot(difficulty) -> table
		Pure difficulty multipliers (health, headshot, revive step).
	breakpoints.character_data(unit_type, difficulty) -> table|nil
		The enemy snapshot the maths reads: base health/headshot scaled by the
		difficulty, plus the difficulty-independent fields from
		tweak_data.character.
	breakpoints.current_damage(weapon) -> number
		The selected weapon's damage in breakpoint units (weapon damage * 10).

Difficulty is never applied by mutating Global.game_settings.difficulty,
tweak_data.character or tweak_data.player (what v76's picker did): the
multipliers below are the same numbers `CharacterTweakData:_set_*` applies, so
the table can show any difficulty while the game keeps the difficulty it is
actually running.

Engine-only terms (documented, not modelled):
	* explosion damage disabled by a mutator (`managers.modifiers` zeroing
	  CopDamage:DamageExplosion) arrives as `options.explosion_blocked` and
	  makes the explosion table empty;
	* a weapon with no fire interval (crew/NPC models) cannot place the
	  trigger-happy stacks and simply skips that bonus;
	* crime-spree health modifiers are not applied: they are runtime state, and
	  v76 only initialised them for the manager's own bookkeeping.

Formula sources (PAYDAY 2 248.2):
	lib/units/enemies/cop/copdamage.lua:55 _HEALTH_GRANULARITY, :176
		_HEALTH_INIT_PRECENT, :657-658 bullet clamp, :717-731 headshot /
		body-expertise, :744-745 damage -> health-percent rounding, :2091-2095
		explosion clamp and explosion_damage_mul, :2437-2512 crit roll and
		can_be_critical
	lib/tweak_data/charactertweakdata.lua — base HEALTH_INIT / headshot_dmg_mul
		per unit, _multiply_all_hp (:13742-13900) and the per-difficulty
		_set_easy.._set_sm_wish bodies (line cites next to the table below)
	lib/tweak_data/playertweakdata.lua:36-67, :128-130 REVIVE_HEALTH_STEPS
	lib/managers/playermanager.lua:2742 critical_hit_chance, :5409-5423
		get_damage_health_ratio
	lib/tweak_data/upgradestweakdata.lua:229, :402-413, :508-513, :598-600,
		:609-614, :646-649, :1702-1707 (bonus values)
	lib/managers/blackmarketmanager.lua:10120-10180 damage_addend/multiplier
		(the model already folded those in)
]]

local breakpoints = {}

-- CopDamage._HEALTH_GRANULARITY (copdamage.lua:55).
local HEALTH_GRANULARITY = 512

-- The `i > 1 and bp < 10` stop in v76's loop: below a tenth of the weapon's
-- damage unit the row is noise, and the game rounds such hits to one step.
local MIN_BREAKPOINT_DAMAGE = 10

local DEFAULT_DAMAGE_CLICK_RATE = 5

breakpoints.unit_types = {
	'swat',
	'heavy_swat',
	'sniper',
	'taser',
	'spooc',
	'tank',
}

--[[
The bonus toggles of the table, in v76 order. `index` is the UI column,
`required_level` the skill unlock that enables the toggle and
`checked_by_default` the state the toggle starts in. The layout offsets and
colours stay in the UI layer (Task 6).
]]
breakpoints.bonuses = {
	prison_wife = {index = 1, required_level = 0, checked_by_default = true}, -- headshot damage
	hitman = {index = 2, required_level = 1, checked_by_default = false},
	underdog = {index = 3, required_level = 1, checked_by_default = false},
	overkill = {index = 4, required_level = 1, checked_by_default = false},
	body_expertise = {index = 5, required_level = 1, checked_by_default = true},
	backstab = {index = 6, required_level = 1, checked_by_default = true}, -- crits
	trigger_happy = {index = 7, required_level = 1, checked_by_default = true},
	wolverine = {index = 8, required_level = 1, checked_by_default = true}, -- berserker
}

--[[
Base CHARACTER health in CopDamage units (HEALTH_INIT) and the un-scaled
headshot multiplier. These are the values CharacterTweakData builds in
`_init_*` before any difficulty runs; the live tweak_data.character entries
already carry the running difficulty's multipliers, so they must not be read
as a base or the difficulty would be applied twice.
]]
local CHARACTER_BASE = {
	-- charactertweakdata.lua:433-434
	swat = {health_init = 8, headshot_dmg_mul = 2},
	-- :472-473
	heavy_swat = {health_init = 16, headshot_dmg_mul = 2},
	-- :627-628
	sniper = {health_init = 4, headshot_dmg_mul = 2},
	-- :3517-3518
	taser = {health_init = 30, headshot_dmg_mul = 2},
	-- :2955-2956
	spooc = {health_init = 60, headshot_dmg_mul = 6},
	-- :2731-2732
	tank = {health_init = 200, headshot_dmg_mul = 5},
}

--[[
Difficulty multipliers, from the `_multiply_all_hp(hp_mul, hs_mul)` call at the
top of each CharacterTweakData:_set_<difficulty>:

	easy          (1, 1)    charactertweakdata.lua:11014
	normal        (1, 1)    :11033
	hard          (1, 1)    :11959
	overkill      (2, 2)    :12207
	overkill_145  (3, 3)    :12456   (Mayhem)
	easy_wish     (6, 2)    :12649   (Death Wish)
	overkill_290  (6, 1.5)  :12815   (Death Sentence)
	sm_wish       (6, 1.5)  :13273

`revive_health_step` is PlayerTweakData.damage.REVIVE_HEALTH_STEPS[1], which the
difficulty also rewrites (playertweakdata.lua:36-38, :50-52, :64-66 set it to
0.1 for easy_wish/overkill_290/sm_wish; playertweakdata.lua:128-130 keeps the
0.4 base everywhere else). The berserker multiplier is computed from it, so it
belongs to the difficulty snapshot instead of being read off tweak_data.player.

`health_override` holds the absolute health values the difficulty sets *after*
the multiply: sm_wish overwrites tank with 2400 (:13291) — tank_medic (:13292)
and tank_mini (:13293) are not one of the six. overkill_290 only overrides
tank_mini (:12833), which is likewise not in the table.
]]
local DIFFICULTIES = {
	easy = {health_mul = 1, headshot_mul = 1, revive_health_step = 0.4},
	normal = {health_mul = 1, headshot_mul = 1, revive_health_step = 0.4},
	hard = {health_mul = 1, headshot_mul = 1, revive_health_step = 0.4},
	overkill = {health_mul = 2, headshot_mul = 2, revive_health_step = 0.4},
	overkill_145 = {health_mul = 3, headshot_mul = 3, revive_health_step = 0.4},
	easy_wish = {health_mul = 6, headshot_mul = 2, revive_health_step = 0.1},
	overkill_290 = {health_mul = 6, headshot_mul = 1.5, revive_health_step = 0.1},
	sm_wish = {
		health_mul = 6,
		headshot_mul = 1.5,
		revive_health_step = 0.1,
		health_override = {tank = 2400},
	},
}

-- Neutral multipliers for an unknown/nil difficulty: no scaling, and the base
-- revive step. Used instead of guessing the player's live difficulty.
local NEUTRAL_DIFFICULTY = {health_mul = 1, headshot_mul = 1, revive_health_step = 0.4}

local function raw_global(name)
	return rawget(_G, name)
end

local function manager(name)
	local managers = raw_global('managers')
	return managers and managers[name] or nil
end

local function tweak()
	return raw_global('tweak_data')
end

local function contains(list, value)
	if type(list) ~= 'table' then
		return false
	end

	for _, entry in ipairs(list) do
		if entry == value then
			return true
		end
	end

	return false
end

local function clamp(value, minimum, maximum)
	if value < minimum then
		return minimum
	elseif value > maximum then
		return maximum
	end

	return value
end

local function copy_table(source)
	local copy = {}

	for key, value in pairs(source or {}) do
		copy[key] = value
	end

	return copy
end

local function settings()
	local global = raw_global('MoreWeaponStats')
	return global and global.settings or {}
end

-- Player state ---------------------------------------------------------------

local function ctx_upgrade_value(context, category, upgrade, default)
	if context and type(context.upgrade_value) == 'function' then
		return context:upgrade_value(category, upgrade, default)
	end

	return default
end

-- PlayerManager:critical_hit_chance (playermanager.lua:2742). The context owns
-- the manager query; a hand-built context or a headless run answers 0.
local function ctx_critical_hit_chance(context)
	if context and type(context.critical_hit_chance) == 'function' then
		local value = context:critical_hit_chance()

		if type(value) == 'number' then
			return value
		end
	end

	return 0
end

--[[
PlayerManager:get_damage_health_ratio (playermanager.lua:5409-5423):

	damage_ratio = 1 - health_ratio / max(0.01, threshold)
	threshold    = tweak_data.upgrades.player_damage_health_ratio_threshold
	               * (category and upgrade_value("player",
	                 category .. "_damage_health_ratio_threshold_multiplier", 1))

The context answers it when it can (it talks to the manager); the formula is
kept here as the pure fallback because every term is either tweak data or an
upgrade value.
]]
local function ctx_damage_health_ratio(context, health_ratio, category)
	if context and type(context.get_damage_health_ratio) == 'function' then
		local value = context:get_damage_health_ratio(health_ratio, category)

		if type(value) == 'number' then
			return value
		end
	end

	local upgrade_data = tweak() and tweak().upgrades
	local threshold = upgrade_data and upgrade_data.player_damage_health_ratio_threshold or 0.5

	if category then
		threshold = threshold * ctx_upgrade_value(context, 'player', category .. '_damage_health_ratio_threshold_multiplier', 1)
	end

	return math.max(1 - health_ratio / math.max(0.01, threshold), 0)
end

local function upgrade_values()
	local upgrade_data = tweak() and tweak().upgrades
	return upgrade_data and upgrade_data.values or {}
end

-- Upgrade values that are `{ {value, duration} }` lists (upgradestweakdata.lua
-- :508-513, :609-614): the first entry's first field is the multiplier.
local function temporary_multiplier(name, default)
	local values = upgrade_values()
	local list = values.temporary and values.temporary[name]
	local first = type(list) == 'table' and list[1]

	if type(first) == 'table' then
		return first[1] or default
	end

	return default
end

-- The mark multipliers: `marked_enemy_damage_mul` and the second column of
-- marked_inc_dmg_distance (upgradestweakdata.lua:229, :1702-1707).
local function marked_enemy_damage_mul()
	local values = upgrade_values()
	local player = values.player or {}

	return player.marked_enemy_damage_mul or 1
end

local function marked_inc_dmg_distance_mul()
	local values = upgrade_values()
	local player = values.player or {}
	local entry = player.marked_inc_dmg_distance and player.marked_inc_dmg_distance[1]

	if type(entry) == 'table' then
		return entry[2] or 1
	end

	return 1
end

--[[
Skill unlock levels ----------------------------------------------------------

SkillTreeManager._global.skills entries are `{ unlocked = level, total = max }`
(lib/managers/skilltreemanager.lua:64); the context snapshot flattens them to
skill id -> unlocked level. The context answers first (it owns the manager read),
a hand-built context table falls back to its `skills` field, and a headless run
falls back to the manager itself. Read-only: nothing is written back.
]]
function breakpoints.skill_level(context, skill_name)
	if context and type(context.skill_level) == 'function' then
		local level = context:skill_level(skill_name)

		if type(level) == 'number' then
			return level
		end
	end

	local skills = context and context.skills
	local level = type(skills) == 'table' and skills[skill_name] or nil

	if type(level) == 'number' then
		return level
	end

	local skilltree = manager('skilltree')
	local stored = skilltree and skilltree._global and skilltree._global.skills
	local entry = type(stored) == 'table' and stored[skill_name] or nil

	if type(entry) == 'table' then
		return tonumber(entry.unlocked) or 0
	elseif type(entry) == 'number' then
		return entry
	end

	return 0
end

--[[
BlackMarketGui:mws_set_bonus_availability, without the in-place mutation of the
bonus table: `available` follows the unlocked skill level, `checked` keeps the
player's choice while the toggle is available and is forced off otherwise.
]]
function breakpoints.bonus_availability(context, previous)
	local result = {}

	for name, bonus in pairs(breakpoints.bonuses) do
		local level = breakpoints.skill_level(context, name)
		local available = level >= bonus.required_level
		local checked

		if available then
			local previous_bonus = previous and previous[name]

			if previous_bonus and previous_bonus.checked ~= nil then
				checked = previous_bonus.checked
			else
				checked = bonus.checked_by_default
			end
		else
			checked = false
		end

		result[name] = {
			index = bonus.index,
			required_level = bonus.required_level,
			checked_by_default = bonus.checked_by_default,
			level = level,
			available = available,
			checked = checked,
		}
	end

	return result
end

-- Weapon ---------------------------------------------------------------------

local function weapon_categories(weapon)
	if type(weapon) ~= 'table' then
		return {}
	end

	if type(weapon.categories) == 'function' then
		return weapon:categories() or {}
	end

	return weapon._categories or {}
end

local function is_category(weapon, category)
	if type(weapon) ~= 'table' then
		return false
	end

	if type(weapon.is_category) == 'function' then
		return weapon:is_category(category) and true or false
	end

	return contains(weapon_categories(weapon), category)
end

-- CopDamage:can_be_critical (copdamage.lua:2465-2512), data-only. The projectile
-- (thrower_unit) branch is only reachable from a spawned projectile unit, which
-- the model never is; a model answers through its weapon tweak data, and a nil
-- weapon means "no attacking weapon" like the game.
function breakpoints.can_be_critical(weapon, damage_type)
	if weapon == nil then
		return true
	end

	local weapon_type
	local weapon_td

	if type(weapon) == 'table' then
		if type(weapon.weapon_tweak_data) == 'function' then
			weapon_td = weapon:weapon_tweak_data()
		elseif type(weapon.weapon_tweak_data) == 'table' then
			weapon_td = weapon.weapon_tweak_data
		end

		if type(weapon_td) == 'table' and weapon_td.ignore_crit_damage then
			return false
		end

		if type(weapon_td) == 'table' and weapon_td.categories then
			weapon_type = weapon_td.categories[1]
		end

		if not weapon_type and type(weapon.get_name_id) == 'function' then
			weapon_type = weapon:get_name_id()
		end

		if not weapon_type then
			weapon_type = weapon_categories(weapon)[1]
		end
	end

	local tweak_data = tweak()
	local disable_table = tweak_data and tweak_data.weapon_disable_crit_for_damage
	local damage_crit_data = weapon_type and disable_table and disable_table[weapon_type]

	if not damage_crit_data then
		return true
	end

	return damage_crit_data[damage_type] and true or false
end

--[[
NewRaycastWeaponBase:get_add_head_shot_mul (newraycastweaponbase.lua:1233): body
expertise only applies to automatic weapons (and bows/saws).
]]
local function add_head_shot_mul(weapon)
	if type(weapon) == 'table' and type(weapon.get_add_head_shot_mul) == 'function' then
		return weapon:get_add_head_shot_mul()
	end

	return nil
end

--[[
BlackMarketGui:mws_prepare_breakpoints_params: the weapon and the toggles folded
into the parameter table the maths reads.

	explosion / fire / headshot / hitman / underdog / overkill / body_expertise
	crits / trigger_happy / berserker / shoot_interval / primary_category
	context / trigger_happy_first_bullet

`explosion_blocked` carries the "explosion damage disabled for this unit"
mutator state (v76 asked `managers.modifiers:modify_value(
"CopDamage:DamageExplosion", ...)`); the caller sets it through `options`.
]]
function breakpoints.prepare_params(weapon, context, bonuses, options)
	if type(weapon) ~= 'table' then
		return nil
	end

	bonuses = bonuses or {}
	options = options or {}

	local function checked(name)
		local bonus = bonuses[name]
		return bonus and bonus.checked or false
	end

	local function level(name)
		local bonus = bonuses[name]
		local value = bonus and bonus.level
		return type(value) == 'number' and value or 0
	end

	local ammo_data = weapon._ammo_data
	local ammo_type = type(ammo_data) == 'table' and ammo_data.bullet_class or nil
	local explosion = ammo_type == 'InstantExplosiveBulletBase'
	local fire = ammo_type == 'FlameBulletBase' or is_category(weapon, 'flamethrower')
	local damage_type = explosion and 'explosion' or fire and 'fire' or 'bullet'

	local can_full_auto = weapon._fire_mode_category == 'auto'
		or (type(weapon.can_toggle_firemode) == 'function' and weapon:can_toggle_firemode())

	local shoot_interval = weapon._next_fire_allowed

	if not can_full_auto then
		local is_akimbo = is_category(weapon, 'akimbo')
		local manual_rate_modifier = is_akimbo and 2 or 1
		local clicks_per_second = options.clicks_per_second or settings().clicks_per_second or DEFAULT_DAMAGE_CLICK_RATE

		if type(clicks_per_second) ~= 'number' or clicks_per_second <= 0 then
			clicks_per_second = DEFAULT_DAMAGE_CLICK_RATE
		end

		local manual_interval = 1 / (manual_rate_modifier * clicks_per_second)

		if type(shoot_interval) ~= 'number' then
			shoot_interval = manual_interval
		else
			shoot_interval = math.max(shoot_interval, manual_interval)
		end
	end

	local berserker
	if checked('wolverine') then
		-- Bloodthirst is the melee variant of the same skill family
		-- (newraycastweaponbase/PlayerStandard pick the saw category).
		berserker = is_category(weapon, 'saw') and 'melee_damage_health_ratio_multiplier' or 'damage_health_ratio_multiplier'
	end

	local bemul = add_head_shot_mul(weapon)
	local body_expertise = checked('body_expertise') and type(bemul) == 'number' and bemul > 0 or false
	local crits = checked('backstab') and breakpoints.can_be_critical(weapon, damage_type)
	local overkill = checked('overkill') and (level('overkill') == 2 or is_category(weapon, 'shotgun'))
	local trigger_happy = checked('trigger_happy') and is_category(weapon, 'pistol')

	local first_bullet = options.enable_trigger_happy_for_first_bullet

	if first_bullet == nil then
		first_bullet = settings().enable_trigger_happy_for_first_bullet
	end

	local params = {
		explosion = explosion,
		fire = fire,
		headshot = checked('prison_wife'),
		hitman = checked('hitman') and level('hitman') or 0,
		underdog = checked('underdog') and true or false,
		overkill = overkill and true or false,
		body_expertise = body_expertise,
		crits = crits and true or false,
		trigger_happy = trigger_happy and level('trigger_happy') or nil,
		berserker = berserker or false,
		shoot_interval = shoot_interval,
		primary_category = weapon_categories(weapon)[1],
		context = context,
		-- v76 read this setting inside the maths; passing it through the params
		-- keeps the module free of globals and lets a caller preview both modes.
		trigger_happy_first_bullet = first_bullet ~= false,
		-- v76 asked managers.modifiers per unit; the caller supplies the flag.
		explosion_blocked = options.explosion_blocked and true or false,
	}

	if explosion then
		params.headshot = false
		params.hitman = math.min(1, params.hitman)
	elseif fire then
		params.headshot = false
		params.hitman = 0
	end

	return params
end

function breakpoints.current_damage(weapon)
	if type(weapon) ~= 'table' then
		return 0
	end

	return (tonumber(weapon._damage) or 0) * 10
end

-- Difficulty -----------------------------------------------------------------

function breakpoints.difficulty_snapshot(difficulty)
	local name = type(difficulty) == 'string' and difficulty or nil
	local entry = name and DIFFICULTIES[name] or NEUTRAL_DIFFICULTY

	return {
		name = name,
		health_mul = entry.health_mul,
		headshot_mul = entry.headshot_mul,
		revive_health_step = entry.revive_health_step,
		health_override = entry.health_override and copy_table(entry.health_override) or nil,
	}
end

--[[
The per-unit snapshot the maths reads. Health and headshot come from the base
constants scaled by the difficulty; tags, critical_hits, ignore_headshot,
damage.explosion_damage_mul and the damage clamps are not difficulty-scaled, so
they are read from tweak_data.character at call time.

A unit the module has no base for, or one the running tweak data does not
define, produces nil — get_for_unit turns that into an empty table instead of
throwing.
]]
function breakpoints.character_data(unit_type, difficulty)
	local base = CHARACTER_BASE[unit_type]
	local tweak_data = tweak()
	local character = tweak_data and tweak_data.character
	local live = type(character) == 'table' and character[unit_type] or nil

	if not base or type(live) ~= 'table' then
		return nil
	end

	local snapshot = breakpoints.difficulty_snapshot(difficulty)
	local health_init = base.health_init * snapshot.health_mul

	if snapshot.health_override and snapshot.health_override[unit_type] then
		health_init = snapshot.health_override[unit_type]
	end

	return {
		unit_type = unit_type,
		difficulty = snapshot.name,
		health_init = health_init,
		headshot_dmg_mul = base.headshot_dmg_mul * snapshot.headshot_mul,
		revive_health_step = snapshot.revive_health_step,
		tags = live.tags,
		critical_hits = live.critical_hits,
		ignore_headshot = live.ignore_headshot,
		explosion_damage_mul = type(live.damage) == 'table' and live.damage.explosion_damage_mul or nil,
		damage_clamp_bullet = live.DAMAGE_CLAMP_BULLET,
		damage_clamp_explosion = live.DAMAGE_CLAMP_EXPLOSION,
	}
end

-- Breakpoints ----------------------------------------------------------------

--[[
BlackMarketGui:mws_get_breakpoints, with the enemy and difficulty supplied
instead of read from mutated tweak data.

	health        = HEALTH_INIT * 10 (CopDamage counts damage in health units)
	health_step   = health / 512
	bonus_mul     = headshot * hitman * underdog * overkill * berserker
	crit_chance   = critical_hits.base_chance
	                + PlayerManager:critical_hit_chance()
	                  * critical_hits.player_chance_multiplier
	crit_mul      = critical_hits.damage_mul or headshot_dmg_mul

For each hit count i the effective hit count is the real i plus the extra
damage of the crit/trigger-happy stacks; the breakpoint is the largest damage
that still leaves the target alive, rounded down to a health step and capped at
the unit's damage clamp.

Trigger happy (PlayerAction.TriggerHappy / playermanager.lua:417-428) rewrites
the first `th_nr` shots of every `1 + th_nr` as unboosted; `first_bullet`
decides whether the very first shot of a burst already carries the stack (the
enable_trigger_happy_for_first_bullet setting).
]]
function breakpoints.get_for_unit(unit_type, params, difficulty)
	local result = {}

	if type(params) ~= 'table' then
		return result
	end

	--[[
	The UI selects a difficulty explicitly; when it does not, the context's own
	difficulty is the honest answer. Falling straight through to the neutral
	1x/1x snapshot would render normal-difficulty numbers while the player is
	on Death Sentence.
	]]
	if difficulty == nil and type(params.context) == 'table' then
		difficulty = params.context.difficulty
	end

	local data = breakpoints.character_data(unit_type, difficulty)

	if not data or type(data.health_init) ~= 'number' or data.health_init <= 0 then
		return result
	end

	-- Explosion damage disabled by a mutator: the unit cannot be damaged by
	-- this weapon at all, so there is no breakpoint to draw.
	if params.explosion and params.explosion_blocked then
		return result
	end

	local health = data.health_init * 10
	local health_step = health / HEALTH_GRANULARITY
	local damage_clamp

	if params.explosion then
		damage_clamp = data.damage_clamp_explosion
	elseif not params.fire then
		-- CopDamage:damage_fire applies no clamp; bullets and explosions do.
		damage_clamp = data.damage_clamp_bullet
	end

	local headshot_mul = 1

	if params.explosion then
		headshot_mul = data.explosion_damage_mul or 1
	elseif params.headshot then
		if not data.ignore_headshot then
			local player_headshot_mul = ctx_upgrade_value(params.context, 'weapon', 'passive_headshot_damage_multiplier', 1)

			headshot_mul = player_headshot_mul * (data.headshot_dmg_mul or 1)
		end
	elseif params.body_expertise then
		-- Body expertise does nothing against the bulldozer's helmet.
		if not contains(data.tags, 'tank') then
			local add_head_shot = ctx_upgrade_value(params.context, 'weapon', 'automatic_head_shot_add', nil)

			if type(add_head_shot) == 'number' then
				headshot_mul = 1 + add_head_shot * math.max(0, (data.headshot_dmg_mul or 1) - 1)
			end
		end
	end

	local crit_mul = 0
	local crit_chance = 0

	if params.crits then
		local crits = data.critical_hits or {}

		crit_chance = (crits.base_chance or 0) + ctx_critical_hit_chance(params.context) * (crits.player_chance_multiplier or 1)

		if crit_chance > 0 then
			crit_mul = crits.damage_mul or data.headshot_dmg_mul

			if not crit_mul then
				crit_chance = 0
			end
		end
	end

	local hitman_level = type(params.hitman) == 'number' and params.hitman or 0
	local hitman_mul = 1

	if contains(data.tags, 'special') then
		if hitman_level >= 1 then
			hitman_mul = marked_enemy_damage_mul()
		end

		if hitman_level >= 2 then
			hitman_mul = hitman_mul * marked_inc_dmg_distance_mul()
		end
	end

	local underdog_mul = params.underdog and temporary_multiplier('dmg_multiplier_outnumbered', 1) or 1
	local overkill_mul = params.overkill and temporary_multiplier('overkill_damage_multiplier', 1) or 1
	local berserker_mul = 1

	if params.berserker then
		local health_ratio = data.revive_health_step * ctx_upgrade_value(params.context, 'player', 'revived_health_regain', 1)
		local damage_health_ratio = ctx_damage_health_ratio(params.context, health_ratio, params.primary_category)

		berserker_mul = 1 + ctx_upgrade_value(params.context, 'player', params.berserker, 0) * damage_health_ratio
	end

	local th_mul
	local th_nr

	if params.trigger_happy then
		local values = upgrade_values()
		local pistol = values.pistol or {}
		local stacking = pistol.stacking_hit_damage_multiplier
		local entry = type(stacking) == 'table' and stacking[params.trigger_happy] or nil
		local shoot_interval = params.shoot_interval

		if type(entry) == 'table' and type(entry.damage_bonus) == 'number' and type(shoot_interval) == 'number' and shoot_interval > 0 then
			th_mul = entry.damage_bonus
			th_nr = math.floor((entry.max_time or 0) / shoot_interval)
		end
	end

	local all_mul = headshot_mul * hitman_mul * underdog_mul * overkill_mul * berserker_mul

	if all_mul <= 0 then
		return result
	end

	local previous_bp

	for i = 1, HEALTH_GRANULARITY do
		local crit_nr = math.ceil(i * crit_chance)
		local final_i = i

		if th_mul then
			local th_initiator_nr

			if params.trigger_happy_first_bullet then
				th_initiator_nr = math.floor(i / (1 + th_nr))
			else
				th_initiator_nr = math.ceil(i / (1 + th_nr))
			end

			local th_boosted_nr = math.max(0, i - th_initiator_nr)
			-- Crits and trigger happy stack additively on the boosted shots; the
			-- crit term never drops below one extra hit's worth of damage.
			final_i = final_i + th_boosted_nr * (th_mul - 1) * math.max(1, (crit_mul - 1) * crit_nr)
		elseif crit_nr > 0 then
			final_i = final_i + (crit_mul - 1) * crit_nr
		end

		if final_i <= 0 then
			final_i = 1
		end

		local damage = health / final_i
		local bp = math.ceil(clamp(damage / health_step, 1, HEALTH_GRANULARITY)) * health_step

		if final_i == i then
			-- No bonus damage: the previous step is already fatal, so the
			-- breakpoint is one step lower.
			bp = bp - health_step
		end

		bp = bp / all_mul

		if previous_bp == bp then
			-- Same value as the previous hit count: the row would repeat, skip.
		elseif damage_clamp and bp > damage_clamp then
			break
		else
			if i > 1 and bp < MIN_BREAKPOINT_DAMAGE then
				break
			end

			result[i] = math.ceil(bp * 100) / 100
		end

		previous_bp = bp
	end

	return result
end

function breakpoints.get_all(params, difficulty)
	local result = {}

	for _, unit_type in ipairs(breakpoints.unit_types) do
		result[unit_type] = breakpoints.get_for_unit(unit_type, params, difficulty)
	end

	return result
end

--[[
BlackMarketGui:mws_consolidate_breakpoints: one entry per distinct breakpoint
value across all units, sorted ascending, with the hit count each unit needs
(`hits_nr`) and, when `fill` is on, the hit count carried over from the previous
lower breakpoint (`herited_hits_nr`) so a unit that gains nothing from extra
damage still shows a number.

`ref_damage` is the highest breakpoint the weapon already reaches, which the UI
highlights; -1 when no breakpoint is within reach.

v76 also had a `value >= 20` block that removed low breakpoints. It was inert:
the guard required the smallest value to be >= 20, so the loop beneath it could
never remove anything. It is not reproduced (it would hide real rows such as a
sniper's third hit), but no v76 output changes because the branch never ran.
]]
function breakpoints.consolidate(data, damage, amount_wanted, fill)
	local all_bp = {}
	local ref_bp = -1

	for unit_type, bps in pairs(data or {}) do
		for hit_nr, value in pairs(bps) do
			if value <= damage and value > ref_bp then
				ref_bp = value
			end

			local bp = all_bp[value]

			if not bp then
				bp = {
					value = value,
					hits_nr = {},
					herited_hits_nr = {},
				}
				all_bp[value] = bp
			end

			bp.hits_nr[unit_type] = hit_nr
		end
	end

	local sorted = {}
	local nr = 0

	for _, bp in pairs(all_bp) do
		nr = nr + 1
		sorted[nr] = bp
	end

	table.sort(sorted, function(a, b)
		return a.value < b.value
	end)

	if nr == 0 then
		return ref_bp, {}
	end

	if fill then
		local last_hit_nr = {}

		for i = 1, nr do
			local bp = sorted[i]

			for _, unit_type in ipairs(breakpoints.unit_types) do
				local hit_nr = bp.hits_nr[unit_type]

				if hit_nr then
					last_hit_nr[unit_type] = hit_nr
				else
					bp.herited_hits_nr[unit_type] = last_hit_nr[unit_type]
				end
			end
		end
	end

	if not amount_wanted or amount_wanted >= nr then
		return ref_bp, sorted
	end

	local result = {}

	for i = 1, nr do
		local bp = sorted[i]

		if bp.value == ref_bp then
			local to_add = amount_wanted - 1
			local half_m = (to_add - (to_add % 2)) / 2
			local half_p = half_m + (to_add % 2)

			if half_m >= i then
				local diff = half_m - i + 1

				half_p = half_p + diff
				half_m = half_m - diff
			end

			if half_p > nr - i then
				local diff = half_p - (nr - i)

				half_p = half_p - diff
				half_m = half_m + diff
			end

			local index = 1

			for j = i - half_m, i + half_p do
				result[index] = sorted[j]
				index = index + 1
			end

			break
		end
	end

	return ref_bp, result
end

return breakpoints
