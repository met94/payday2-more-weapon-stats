--[[
core/context.lua — player state snapshot used by every stat calculation.

Responsibility:
	Describe the conditions a stat is computed under: difficulty, stance and the
	player's skills/perks/upgrades. Callers pass a context into core.weapon,
	core.timers, core.accuracy, core.ballistics and core.ammo instead of asking
	the engine themselves.

Public API:
	context.get(overrides) -> table
		Returns a new context table. Fields:
			difficulty      string  e.g. 'overkill_290'
			difficulty_rank number  1-based index into tweak_data.difficulties
			moving          boolean player is moving
			ducking         boolean player is crouched
			steelsight      boolean player is aiming down sights
			deployed        boolean bipod deployed
			skills          table   skill_id -> unlocked level (managers.skilltree)
			perks           table   perk deck (specialization index) -> points spent
			upgrades        table   resolved upgrade values, category -> upgrade -> value
			detection_risk  number|nil  player suspicion offset * 100, when a loadout exists
			competitive     boolean the current job is competitive (skin bonuses are off)
			suppressed      boolean the local player is currently suppressed
		Methods:
			ctx:upgrade_value(category, upgrade, default)
			ctx:temporary_upgrade_value(category, upgrade, default)
			ctx:has_category_upgrade(category, upgrade)
			ctx:has_activate_temporary_upgrade(category, upgrade)
			ctx:has_category(category)
			ctx:get_property(name, default)
			ctx:get_temporary_property(name, default)
			ctx:body_armor_value(category, override, default)
			ctx:crew_ability_upgrade_value(upgrade, default)
			ctx:has_team_category_upgrade(category, upgrade)
			ctx:team_upgrade_value(category, upgrade, default)
			ctx:critical_hit_chance() -> number
			ctx:get_damage_health_ratio(health_ratio, category) -> number
			ctx:skill_level(skill_id) -> number

	context.invalidate() -> nil
		Forgets the cached snapshot. Call at the start of a Black Market render.

	context.capture() -> table
		Reads the live managers, stores the snapshot and returns a copy of it.

The base snapshot is captured lazily, once, and reused by every get() until
invalidate() is called. get() deep-copies the snapshot and every override, so a
caller can never mutate the cached base or another caller's context.

Manager reads (PAYDAY 2 248.2):
	PlayerManager:upgrade_value (lib/managers/playermanager.lua:1974),
	:has_category_upgrade (:2351), :get_property (:242), :body_armor_value (:2363).
	248.2 has no PlayerManager:get_difficulty(), so the difficulty comes from
	Global.game_settings.difficulty (the value the game itself persists) with
	PlayerManager:get_difficulty() used only if a future build/mutator adds it.
	Skill levels come from SkillTreeManager._global.skills
	(lib/managers/skilltreemanager.lua:64,323-332) and the perk deck from
	SkillTreeManager._global.specializations (:129-162, points_spent per deck).
	There is no PlayerManager skill/perk enumeration in 248.2.
	detection_risk mirrors PlayerManager:_cached_detection_risk (:2778-2788):
	round(blackmarket:get_suspicion_offset_of_local(SUSPICION_OFFSET_LERP) * 100);
	competitive mirrors JobManager:is_current_job_competitive (:1685).
	suppressed mirrors the local player's
	character_damage:is_suppressed() (:10300), the branch the recoil formulas take.
]]

local context = {}

local DIFFICULTY_DEFAULT = 'overkill_290'
-- tweak_data.difficulties (lib/tweak_data/tweakdata.lua:373-382), used when
-- tweak_data is not loaded (headless tests).
local DIFFICULTY_ORDER = {
	'easy',
	'normal',
	'hard',
	'overkill',
	'overkill_145',
	'easy_wish',
	'overkill_290',
	'sm_wish',
}

-- Marks a cached nil so a repeated query does not hit the manager again.
local NIL_VALUE = {}

local snapshot

local function raw_global(name)
	return rawget(_G, name)
end

local function player_manager()
	local managers = raw_global('managers')
	return managers and managers.player or nil
end

local function deep_copy(value)
	if type(value) ~= 'table' then
		return value
	end

	local copy = {}

	for key, entry in pairs(value) do
		copy[key] = deep_copy(entry)
	end

	return copy
end

local function difficulty_rank(difficulty)
	local tweak = raw_global('tweak_data')
	local difficulties = tweak and tweak.difficulties or DIFFICULTY_ORDER

	for index, name in ipairs(difficulties) do
		if name == difficulty then
			return index
		end
	end

	return 0
end

local function read_difficulty()
	local player = player_manager()

	if player and type(player.get_difficulty) == 'function' then
		local ok, value = pcall(player.get_difficulty, player)

		if ok and type(value) == 'string' then
			return value
		end
	end

	local global = raw_global('Global')
	local settings = global and global.game_settings

	if settings and type(settings.difficulty) == 'string' then
		return settings.difficulty
	end

	return DIFFICULTY_DEFAULT
end

local function manager(name)
	local managers = raw_global('managers')
	return managers and managers[name] or nil
end

local function round(value)
	if math.round then
		return math.round(value)
	end

	return math.floor(value + 0.5)
end

local function numeric(value)
	local number = tonumber(value)
	return number or value
end

-- SkillTreeManager._global.skills (lib/managers/skilltreemanager.lua:64): each
-- entry is { unlocked = level, total = max_level }.
local function read_skills()
	local skilltree = manager('skilltree')
	local stored = skilltree and skilltree._global and skilltree._global.skills
	local skills = {}

	if type(stored) == 'table' then
		for skill_id, entry in pairs(stored) do
			if type(entry) == 'table' then
				skills[skill_id] = numeric(entry.unlocked)
			elseif type(entry) == 'number' then
				skills[skill_id] = entry
			end
		end
	end

	return skills
end

-- SkillTreeManager._global.specializations (lib/managers/skilltreemanager.lua:129-162):
-- the perk decks are the specialization trees, keyed by their 1-based index.
local function read_perks()
	local skilltree = manager('skilltree')
	local stored = skilltree and skilltree._global and skilltree._global.specializations
	local perks = {}

	if type(stored) == 'table' then
		for deck, entry in pairs(stored) do
			if type(deck) == 'number' and type(entry) == 'table' then
				local points = tonumber(entry.points_spent)

				if points then
					perks[deck] = points
				end
			end
		end
	end

	return perks
end

-- PlayerManager:_cached_detection_risk (lib/managers/playermanager.lua:2778-2788).
local function read_detection_risk()
	local blackmarket = manager('blackmarket')

	if not blackmarket or type(blackmarket.get_suspicion_offset_of_local) ~= 'function' then
		return nil
	end

	local tweak_data = raw_global('tweak_data')
	local lerp = tweak_data and tweak_data.player and tweak_data.player.SUSPICION_OFFSET_LERP or 0.75
	local ok, offset = pcall(blackmarket.get_suspicion_offset_of_local, blackmarket, lerp)

	if ok and type(offset) == 'number' then
		return round(offset * 100)
	end

	return nil
end

-- JobManager:is_current_job_competitive (lib/managers/jobmanager.lua:1685).
local function read_competitive()
	local job = manager('job')

	if not job or type(job.is_current_job_competitive) ~= 'function' then
		return false
	end

	local ok, value = pcall(job.is_current_job_competitive, job)
	return ok and not not value or false
end

--[[
Local player suppression, the branch BlackMarketManager:recoil_addend and
:recoil_multiplier take (blackmarketmanager.lua:10300, :10357). There is no
player unit in the main menu, so the snapshot captures false.
]]
local function read_suppressed()
	local player = player_manager()

	if not player or type(player.player_unit) ~= 'function' then
		return false
	end

	local ok, unit = pcall(player.player_unit, player)

	if not ok or not unit then
		return false
	end

	local ok_damage, damage = pcall(function()
		return unit:character_damage()
	end)

	if not ok_damage or not damage or type(damage.is_suppressed) ~= 'function' then
		return false
	end

	local ok_value, value = pcall(damage.is_suppressed, damage)

	return ok_value and not not value or false
end

--[[
Builds a context from a base snapshot. The methods write through to the
snapshot's private caches so repeated queries inside one render are answered
once, while the returned field tables are copies.
]]
local function make_context(base)
	local result = {
		difficulty = base.difficulty,
		difficulty_rank = base.difficulty_rank,
		moving = base.moving,
		ducking = base.ducking,
		steelsight = base.steelsight,
		deployed = base.deployed,
		skills = deep_copy(base.skills),
		perks = deep_copy(base.perks),
		upgrades = deep_copy(base.upgrades),
		detection_risk = base.detection_risk,
		competitive = base.competitive,
		suppressed = base.suppressed,
	}

	local upgrade_cache = base.upgrade_cache
	local property_cache = base.property_cache

	local function query(method, ...)
		local player = player_manager()

		if not player or type(player[method]) ~= 'function' then
			return nil
		end

		local ok, value = pcall(player[method], player, ...)

		if ok then
			return value
		end

		return nil
	end

	function result:upgrade_value(category, upgrade, default)
		-- PlayerManager:upgrade_value returns `default or 0`, so the same
		-- category/upgrade with a different default resolves differently; the
		-- default is part of the cache key.
		local key = tostring(category) .. '\0' .. tostring(upgrade) .. '\0' .. tostring(default)
		local cached = upgrade_cache[key]

		if cached ~= nil then
			if cached == NIL_VALUE then
				return nil
			end

			return cached
		end

		local value = query('upgrade_value', category, upgrade, default)

		if value == nil then
			value = default
		end

		upgrade_cache[key] = value == nil and NIL_VALUE or value
		result.upgrades[category] = result.upgrades[category] or {}

		if value ~= nil then
			result.upgrades[category][upgrade] = value
		end

		return value
	end

	function result:temporary_upgrade_value(category, upgrade, default)
		local value = query('temporary_upgrade_value', category, upgrade, default)

		if value == nil then
			value = default
		end

		return value
	end

	function result:has_category_upgrade(category, upgrade)
		return query('has_category_upgrade', category, upgrade) and true or false
	end

	function result:has_activate_temporary_upgrade(category, upgrade)
		return query('has_activate_temporary_upgrade', category, upgrade) and true or false
	end

	function result:has_category(category)
		-- 248.2 PlayerManager has no has_category(); honour it if a mutator adds it.
		return query('has_category', category) and true or false
	end

	function result:get_property(name, default)
		local key = tostring(name)
		local cached = property_cache[key]

		if cached ~= nil then
			if cached == NIL_VALUE then
				return nil
			end

			return cached
		end

		local value = query('get_property', name, default)

		if value == nil then
			value = default
		end

		property_cache[key] = value == nil and NIL_VALUE or value

		return value
	end

	function result:body_armor_value(category, override, default)
		local value = query('body_armor_value', category, override, default)

		if value == nil then
			value = default
		end

		return value
	end

	-- PlayerManager:get_temporary_property (playermanager.lua:594).
	function result:get_temporary_property(name, default)
		local value = query('get_temporary_property', name, default)

		if value == nil then
			value = default
		end

		return value
	end

	-- PlayerManager:crew_ability_upgrade_value (playermanager.lua:1996).
	function result:crew_ability_upgrade_value(upgrade, default)
		local value = query('crew_ability_upgrade_value', upgrade, default)

		if value == nil then
			value = default
		end

		return value
	end

	-- PlayerManager:has_team_category_upgrade (playermanager.lua:3496).
	function result:has_team_category_upgrade(category, upgrade)
		return query('has_team_category_upgrade', category, upgrade) and true or false
	end

	-- PlayerManager:team_upgrade_value (playermanager.lua:3473).
	function result:team_upgrade_value(category, upgrade, default)
		local value = query('team_upgrade_value', category, upgrade, default)

		if value == nil then
			value = default
		end

		return value
	end

	--[[
	PlayerManager:critical_hit_chance (playermanager.lua:2742). It reads the
	skill/perk upgrades and the cached detection risk, and answers 0 when no
	player manager exists (headless, or a main menu without a loadout).
	]]
	function result:critical_hit_chance(detection_risk)
		local value = query('critical_hit_chance', detection_risk or result.detection_risk)

		if type(value) == 'number' then
			return value
		end

		return 0
	end

	--[[
	PlayerManager:get_damage_health_ratio (playermanager.lua:5409): the 0..1
	"how hurt am I" scale the berserker/health-ratio skills multiply by. A
	missing manager answers 0, the value the game returns at full health.
	]]
	function result:get_damage_health_ratio(health_ratio, category)
		local value = query('get_damage_health_ratio', health_ratio, category)

		if type(value) == 'number' then
			return value
		end

		return 0
	end

	-- SkillTreeManager unlock level (see read_skills): 0 when the skill is not in
	-- the snapshot, which is also the level an unowned skill reports.
	function result:skill_level(skill_id)
		local level = result.skills[skill_id]

		if type(level) == 'number' then
			return level
		end

		return 0
	end

	return result
end

local function ensure_snapshot()
	if snapshot then
		return snapshot
	end

	local difficulty = read_difficulty()

	snapshot = {
		difficulty = difficulty,
		difficulty_rank = difficulty_rank(difficulty),
		moving = false,
		ducking = false,
		steelsight = false,
		deployed = false,
		skills = read_skills(),
		perks = read_perks(),
		upgrades = {},
		detection_risk = read_detection_risk(),
		competitive = read_competitive(),
		suppressed = read_suppressed(),
		upgrade_cache = {},
		property_cache = {},
	}

	return snapshot
end

function context.capture()
	local copy = deep_copy(ensure_snapshot())

	copy.upgrade_cache = nil
	copy.property_cache = nil

	return copy
end

function context.invalidate()
	snapshot = nil
end

function context.get(overrides)
	local result = make_context(ensure_snapshot())

	if overrides then
		for key, value in pairs(overrides) do
			result[key] = deep_copy(value)
		end

		if overrides.difficulty and not overrides.difficulty_rank then
			result.difficulty_rank = difficulty_rank(overrides.difficulty)
		end
	end

	return result
end

return context
