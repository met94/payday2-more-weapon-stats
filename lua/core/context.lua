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
			skills          table   skill_name -> level
			perks           table   perk deck -> points/level
			upgrades        table   resolved upgrade values, category -> upgrade -> value
		Methods:
			ctx:upgrade_value(category, upgrade, default)
			ctx:temporary_upgrade_value(category, upgrade, default)
			ctx:has_category_upgrade(category, upgrade)
			ctx:has_activate_temporary_upgrade(category, upgrade)
			ctx:has_category(category)
			ctx:get_property(name, default)
			ctx:body_armor_value(category, override, default)

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
	Skill and perk levels are folded into PlayerManager._global.upgrades in 248.2;
	they are copied here when present, otherwise skills/perks stay empty and all
	skill queries go through upgrade_value.
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

local function read_player_table(player, key)
	if player and type(player._global) == 'table' and type(player._global[key]) == 'table' then
		return deep_copy(player._global[key])
	end

	return {}
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
		local key = tostring(category) .. '\0' .. tostring(upgrade)
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

	return result
end

local function ensure_snapshot()
	if snapshot then
		return snapshot
	end

	local player = player_manager()
	local difficulty = read_difficulty()

	snapshot = {
		difficulty = difficulty,
		difficulty_rank = difficulty_rank(difficulty),
		moving = false,
		ducking = false,
		steelsight = false,
		deployed = false,
		skills = read_player_table(player, 'skills'),
		perks = read_player_table(player, 'perks'),
		upgrades = {},
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
