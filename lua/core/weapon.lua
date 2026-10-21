--[[
core/weapon.lua — pure data model for one weapon plus its blueprint.

Responsibility:
	Turn a weapon id and a factory blueprint into a table that answers the stat
	questions the Black Market UI asks, without spawning a unit or instantiating a
	game weapon class. All values come from tweak data, the crafted blueprint and
	the cosmetics passed in.

Public API:
	weapon.new(weapon_id, blueprint, context, cosmetics) -> WeaponModel|nil
	weapon.new_from_slot(weapon_id, blueprint, options) -> WeaponModel|nil
		options: { npc = boolean, category = string|nil, slot = number|nil }
		`npc` resolves the crew/NPC tweak id the same way the old entry.lua mapping
		did; the player weapon id is kept as the stat source because the NPC
		entries in weapontweakdata are skeletons (usage/sounds only).

	Both return nil when tweak data cannot support a model (unknown weapon id,
	no stats table, no factory data for a non-empty blueprint).

WeaponModel contract (subset of the old weapon-base API the UI relies on):
	weapon_tweak_data(), categories(), is_category(name)
	_name_id, _damage, _ammo_data, _fire_mode_category, _next_fire_allowed
	get_ammo_max_per_clip(), get_ammo_max(), get_ammo_total()
	weapon_fire_rate(), mode_fire_rate(), fire_rate_rpm(), fire_rate_multiplier()
	concealment(), suspicion()
	damage_addend(), damage_multiplier()
	_current_stats, _current_stats_indices
	blueprint, _blueprint, parts, _parts, factory_id/_factory_id
	_spread, _recoil, _spread_moving, _extra_ammo, _total_ammo_mod, _reload,
	_optimal_distance, _optimal_range, _near_falloff, _far_falloff,
	_near_multiplier, _far_multiplier, _damage_near, _damage_far
	can_toggle_firemode(), is_weak_hit(), get_add_head_shot_mul()
	use_shotgun_reload(), clip_empty(), clip_not_empty()

Later tasks fill the rest; the stubs below return nil instead of inventing a
value (core/ballistics, core/timers and core/accuracy own that maths).

Formula sources (PAYDAY 2 248.2):
	lib\units\weapons\newraycastweaponbase.lua:865-1162 _update_stats_values
	lib\units\weapons\newraycastweaponbase.lua:1368-1413 update_damage / ammo
	lib\units\weapons\newraycastweaponbase.lua:223-236, 2799-2828
	lib\units\weapons\raycastweaponbase.lua:173-226, 394-402, 1596-1631
	lib/managers/weaponfactorymanager.lua:389-427, 529-625, 658-856, 1560-1728
	lib/managers/blackmarketmanager.lua:2249-2278, 3018-3044, 10097-10180
	lib/tweak_data/weapontweakdata.lua + weaponfactorytweakdata.lua (data only)
	lib/tweak_data/economytweakdata.lua:1722+ (skin bonus stats)
]]

local weapon = {}

local WeaponModel = {}
WeaponModel.__index = WeaponModel

local function raw_global(name)
	return rawget(_G, name)
end

local function tweak()
	return raw_global('tweak_data')
end

local function weapon_tweak()
	local tweak_data = tweak()
	return tweak_data and tweak_data.weapon or nil
end

local function factory_tweak()
	local weapons = weapon_tweak()
	return weapons and weapons.factory or nil
end

local function log_line(message)
	if type(log) == 'function' then
		log('[More Weapon Stats] ' .. message)
	else
		print('[More Weapon Stats] ' .. message)
	end
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

local function clamp(value, minimum, maximum)
	if value < minimum then
		return minimum
	elseif value > maximum then
		return maximum
	end

	return value
end

local function round(value)
	if math.round then
		return math.round(value)
	end

	return math.floor(value + 0.5)
end

local function contains(list, value)
	for _, entry in ipairs(list) do
		if entry == value then
			return true
		end
	end

	return false
end

--[[
Context shims. The context contract lives in core/context.lua; a plain table
(no methods) is still accepted so callers can pass a hand-built context.
]]
local function ctx_upgrade_value(context, category, upgrade, default)
	if context and type(context.upgrade_value) == 'function' then
		return context:upgrade_value(category, upgrade, default)
	end

	return default
end

local function ctx_has_category_upgrade(context, category, upgrade)
	return context and type(context.has_category_upgrade) == 'function' and context:has_category_upgrade(category, upgrade) or false
end

local function ctx_has_activate_temporary_upgrade(context, category, upgrade)
	return context and type(context.has_activate_temporary_upgrade) == 'function' and context:has_activate_temporary_upgrade(category, upgrade) or false
end

local function ctx_get_property(context, name, default)
	if context and type(context.get_property) == 'function' then
		return context:get_property(name, default)
	end

	return default
end

local function ctx_body_armor_value(context, category, override, default)
	if context and type(context.body_armor_value) == 'function' then
		return context:body_armor_value(category, override, default)
	end

	return default
end

local function is_part_valid(part_id)
	local factory = factory_tweak()
	return not not (factory and factory.parts and factory.parts[part_id])
end

-- WeaponFactoryManager:_part_data (lib/managers/weaponfactorymanager.lua:724).
local function part_data(part_id, factory_id, override)
	local factory = factory_tweak()

	if not is_part_valid(part_id) then
		return nil
	end

	local part = deep_copy(factory.parts[part_id])
	local factory_weapon = factory[factory_id]

	if factory_weapon and factory_weapon.override and factory_weapon.override[part_id] then
		for key, value in pairs(factory_weapon.override[part_id]) do
			part[key] = type(value) == 'table' and deep_copy(value) or value
		end
	end

	if override and override[part_id] then
		for key, value in pairs(override[part_id]) do
			part[key] = type(value) == 'table' and deep_copy(value) or value
		end
	end

	return part
end

-- WeaponFactoryManager:_get_override_parts (lib/managers/weaponfactorymanager.lua:579).
local function get_override_parts(factory_id, blueprint)
	local factory = factory_tweak()
	local overridden = {}
	local override_override = {}
	local factory_weapon = factory and factory[factory_id]

	for _, part_id in ipairs(blueprint) do
		local part = part_data(part_id, factory_id)

		if part and part.override then
			for override_id, override_entry in pairs(part.override) do
				if override_entry.override then
					override_override[override_id] = override_entry
				end
			end
		end
	end

	if factory_weapon and factory_weapon.merge_overrides then
		for _, part_id in ipairs(blueprint) do
			local part = part_data(part_id, factory_id, override_override)

			if part and part.override then
				for override_id, override_entry in pairs(part.override) do
					overridden[override_id] = overridden[override_id] or {}

					for key, value in pairs(override_entry) do
						overridden[override_id][key] = value
					end
				end
			end
		end

		return overridden
	end

	for _, part_id in ipairs(blueprint) do
		local part = part_data(part_id, factory_id, override_override)

		if part and part.override then
			for override_id, override_entry in pairs(part.override) do
				overridden[override_id] = override_entry
			end
		end
	end

	return overridden
end

-- WeaponFactoryManager:_get_forbidden_parts (lib/managers/weaponfactorymanager.lua:529).
local function get_forbidden_parts(factory_id, blueprint, override)
	local forbidden = {}

	for _, part_id in ipairs(blueprint) do
		if is_part_valid(part_id) then
			local part = part_data(part_id, factory_id, override)

			if part.depends_on then
				local part_forbidden = true

				for _, other_part_id in ipairs(blueprint) do
					local other_part = part_data(other_part_id, factory_id, override)

					if other_part and part.depends_on == other_part.type then
						part_forbidden = false

						break
					end
				end

				if part_forbidden then
					forbidden[part_id] = part.depends_on
				end
			end

			if part.forbids then
				for _, forbidden_id in ipairs(part.forbids) do
					forbidden[forbidden_id] = part_id
				end
			end

			if part.adds then
				local add_forbidden = get_forbidden_parts(factory_id, part.adds, get_override_parts(factory_id, part.adds))

				for forbidden_id, source_part_id in pairs(add_forbidden) do
					forbidden[forbidden_id] = source_part_id
				end
			end
		else
			-- The game logs and marks an unknown part as forbidden; keep the same
			-- result so a stale blueprint never contributes stats.
			log_line('unknown part in blueprint: ' .. tostring(part_id) .. ' (factory ' .. tostring(factory_id) .. ')')
			forbidden[part_id] = part_id
		end
	end

	return forbidden
end

-- WeaponFactoryManager:get_assembled_blueprint (lib/managers/weaponfactorymanager.lua:389).
local function get_assembled_blueprint(factory_id, blueprint)
	local factory = factory_tweak()
	local factory_weapon = factory and factory[factory_id]
	local assembled = {}
	local override = get_override_parts(factory_id, blueprint)
	local forbidden = get_forbidden_parts(factory_id, blueprint, override)

	for _, part_id in ipairs(blueprint) do
		if not forbidden[part_id] then
			local part = part_data(part_id, factory_id, override)

			if part then
				local factory_adds = factory_weapon and factory_weapon.adds and factory_weapon.adds[part_id]

				if factory_adds then
					local added_blueprint = get_assembled_blueprint(factory_id, factory_adds) or {}

					for _, added_id in ipairs(added_blueprint) do
						table.insert(assembled, added_id)
					end
				end

				if part.adds_type then
					for _, add_type in ipairs(part.adds_type) do
						local add_id = factory_weapon and factory_weapon[add_type]

						if add_id then
							table.insert(assembled, add_id)
						end
					end
				end

				if part.adds then
					for _, add_id in ipairs(part.adds) do
						table.insert(assembled, add_id)
					end
				end

				table.insert(assembled, part_id)
			end
		end
	end

	return assembled
end

--[[
Data-only equivalent of WeaponFactoryManager:_add_parts/_add_part
(lib/managers/weaponfactorymanager.lua:658-866): the same parts end up in the
result table, but only their tweak data is recorded, never a spawned unit.
]]
local function get_parts_table(factory_id, blueprint, forbidden, override)
	local factory = factory_tweak()
	local factory_weapon = factory and factory[factory_id]
	local parts = {}
	local visiting = {}

	local function add_part(part_id)
		if forbidden[part_id] or parts[part_id] or visiting[part_id] then
			return
		end

		visiting[part_id] = true

		local factory_adds = factory_weapon and factory_weapon.adds and factory_weapon.adds[part_id]

		if factory_adds then
			for _, add_id in ipairs(factory_adds) do
				add_part(add_id)
			end
		end

		local part = part_data(part_id, factory_id, override)

		if not part then
			visiting[part_id] = nil
			return
		end

		if part.adds_type then
			for _, add_type in ipairs(part.adds_type) do
				local add_id = factory_weapon and factory_weapon[add_type]

				if add_id then
					add_part(add_id)
				end
			end
		end

		if part.adds then
			for _, add_id in ipairs(part.adds) do
				add_part(add_id)
			end
		end

		visiting[part_id] = nil
		parts[part_id] = part
	end

	for _, part_id in ipairs(blueprint) do
		add_part(part_id)
	end

	return parts
end

-- WeaponFactoryManager:get_stats (lib/managers/weaponfactorymanager.lua:1560).
local function get_stats(factory_id, blueprint, forbidden)
	local factory = factory_tweak()
	local stats = {}

	for _, part_id in ipairs(blueprint) do
		local source_part = factory and factory.parts and factory.parts[part_id]

		if not forbidden[part_id] and source_part and source_part.stats then
			local part = part_data(part_id, factory_id)

			if part then
				for stat_type, value in pairs(part.stats) do
					if type(value) == 'number' then
						stats[stat_type] = (stats[stat_type] or 0) + value
					elseif type(value) == 'table' then
						stats[stat_type] = stats[stat_type] or {}

						for index = 1, #value do
							stats[stat_type][index] = (stats[stat_type][index] or 0) + value[index]
						end
					end
				end
			end
		end
	end

	return stats
end

-- WeaponFactoryManager:get_custom_stats_from_weapon (lib/managers/weaponfactorymanager.lua:1064).
local function get_custom_stats(factory_id, blueprint)
	local custom_stats = {}

	for _, part_id in ipairs(get_assembled_blueprint(factory_id, blueprint)) do
		local part = part_data(part_id, factory_id)

		if part and part.custom_stats then
			custom_stats[part_id] = deep_copy(part.custom_stats)
		end
	end

	return custom_stats
end

-- WeaponFactoryManager:get_ammo_data_from_weapon (lib/managers/weaponfactorymanager.lua:1079).
local function get_ammo_data(factory_id, blueprint)
	local factory = factory_tweak()
	local ammo_data = {}
	local override = get_override_parts(factory_id, blueprint)

	for _, part_id in ipairs(get_assembled_blueprint(factory_id, blueprint)) do
		local source_part = factory and factory.parts and factory.parts[part_id]

		if source_part and source_part.type == 'ammo' then
			local part = part_data(part_id, factory_id, override)

			if part then
				ammo_data = deep_copy(part.custom_stats or {})
			end
		end
	end

	return ammo_data
end

-- WeaponFactoryManager:get_perks (lib/managers/weaponfactorymanager.lua:1704).
local function get_perks(factory_id, blueprint, forbidden)
	local factory = factory_tweak()
	local perks = {}

	for _, part_id in ipairs(blueprint) do
		local source_part = factory and factory.parts and factory.parts[part_id]

		if not forbidden[part_id] and source_part and source_part.perks then
			for _, perk in ipairs(source_part.perks) do
				perks[perk] = true
			end
		end
	end

	return perks
end

local function has_perk(perk_name, factory_id, blueprint, forbidden)
	return not not get_perks(factory_id, blueprint, forbidden)[perk_name]
end

local function strip_variant_suffix(weapon_id)
	local stripped = weapon_id
	stripped = stripped:gsub('^new_', '')
	stripped = stripped:gsub('_primary$', '')
	stripped = stripped:gsub('_secondary$', '')
	stripped = stripped:gsub('_gold$', '')
	stripped = stripped:gsub('_npc$', '')
	stripped = stripped:gsub('_crew$', '')
	return stripped
end

--[[
special_npc_weapon_id / get_npc_weapon_id (old entry.lua:392-419):
the NPC tweak data names do not always match the player weapon id.
]]
local SPECIAL_NPC_WEAPON_ID = {
	b92fs = 'beretta92',
	benelli = 'beretta92',
	colt_1911 = 'c45',
	glock_17 = 'g17',
	glock_18c = 'glock_18',
}

local function resolve_npc_weapon_id(weapon_id)
	local stripped = strip_variant_suffix(weapon_id)
	local candidate = SPECIAL_NPC_WEAPON_ID[stripped] or stripped
	local weapons = weapon_tweak()

	if weapons and weapons[candidate .. '_crew'] then
		return candidate .. '_crew'
	end

	if weapons and weapons[candidate .. '_npc'] then
		return candidate .. '_npc'
	end

	log_line('npc weapon id not found for ' .. tostring(weapon_id) .. '; using the player id')
	return weapon_id
end

-- WeaponFactoryManager:get_factory_id_by_weapon_id (via UpgradesManager:851).
local function resolve_factory_id(weapon_id)
	local weapons = weapon_tweak()
	local weapon_entry = weapons and weapons[weapon_id]

	if weapon_entry and weapon_entry.factory_id then
		return weapon_entry.factory_id
	end

	local tweak_data = tweak()
	local definitions = tweak_data and tweak_data.upgrades and tweak_data.upgrades.definitions

	if definitions then
		for _, definition in pairs(definitions) do
			if definition.category == 'weapon' and definition.weapon_id == weapon_id and definition.factory_id then
				return definition.factory_id
			end
		end
	end

	local factory = factory_tweak()

	if factory and factory[weapon_id] then
		return weapon_id
	end

	return weapon_id
end

-- BlackMarketManager:is_weapon_modified (lib/managers/blackmarketmanager.lua:2249).
local function is_weapon_modified(factory_id, blueprint)
	local factory = factory_tweak()
	local factory_weapon = factory and factory[factory_id]

	if not factory_weapon then
		return false
	end

	local default_blueprint = factory_weapon.default_blueprint or {}

	for _, part_id in ipairs(blueprint) do
		if not contains(default_blueprint, part_id) then
			return true
		end
	end

	return false
end

-- BlackMarketManager:_convert_add_to_mul (lib/managers/blackmarketmanager.lua:10097).
local function convert_add_to_mul(value)
	if value > 1 then
		return 1 / value
	elseif value < 1 then
		return math.abs(value - 1) + 1
	end

	return 1
end

-- PlayerManager:get_value_from_risk_upgrade (lib/managers/playermanager.lua:2778).
local function risk_upgrade_value(risk_upgrade, detection_risk)
	local risk_value = 0

	if type(risk_upgrade) ~= 'table' then
		return risk_value
	end

	local value = risk_upgrade[1]
	local step = risk_upgrade[2]
	local operator = risk_upgrade[3]
	local threshold = risk_upgrade[4]
	local cap = risk_upgrade[5]
	local num_steps = 0

	if step and step ~= 0 then
		if operator == 'above' then
			num_steps = math.max(math.floor((detection_risk - threshold) / step), 0)
		elseif operator == 'below' then
			num_steps = math.max(math.floor((threshold - detection_risk) / step), 0)
		end
	end

	risk_value = num_steps * (value or 0)

	if cap then
		risk_value = math.min(cap, risk_value)
	end

	return risk_value
end

local function has_stats(weapon_id)
	local weapons = weapon_tweak()
	local entry = weapons and weapons[weapon_id]
	return not not (entry and entry.stats)
end

local function current_context()
	local global = raw_global('MoreWeaponStats')
	local core = global and global.core

	if core and core.context and type(core.context.get) == 'function' then
		return core.context.get()
	end

	return nil
end

--[[
Builds a model. `stat_id` is the player weapon whose stats/factory feed the
model; it differs from `name_id` only for NPC crew entries.
]]
local function build(name_id, blueprint, context, cosmetics, stat_id, npc)
	local weapons = weapon_tweak()

	if not weapons or type(weapons[name_id]) ~= 'table' then
		return nil
	end

	stat_id = stat_id or name_id

	if not has_stats(stat_id) then
		local stripped = strip_variant_suffix(stat_id)

		if has_stats(stripped) then
			stat_id = stripped
		else
			return nil
		end
	end

	local stat_td = weapons[stat_id]
	local factory_id = resolve_factory_id(stat_id)
	local factory = factory_tweak()
	local factory_weapon = factory and factory[factory_id]
	local source_blueprint = blueprint

	if not source_blueprint then
		source_blueprint = factory_weapon and factory_weapon.default_blueprint or {}
	end

	local parts_blueprint = deep_copy(source_blueprint)
	local override = get_override_parts(factory_id, parts_blueprint)
	local forbidden = get_forbidden_parts(factory_id, parts_blueprint, override)
	local assembled = get_assembled_blueprint(factory_id, parts_blueprint)
	local parts = get_parts_table(factory_id, parts_blueprint, forbidden, override)
	local parts_stats = get_stats(factory_id, parts_blueprint, forbidden)
	local custom_stats = get_custom_stats(factory_id, parts_blueprint)
	local ammo_data = get_ammo_data(factory_id, parts_blueprint)
	local perks = get_perks(factory_id, parts_blueprint, forbidden)
	local silencer = has_perk('silencer', factory_id, parts_blueprint, forbidden)

	local base_stats = stat_td.stats
	local stats_tweak_data = weapons.stats or {}
	local modifier_stats = stat_td.stats_modifiers
	local economy = (tweak() or {}).economy
	local bonuses = economy and economy.bonuses
	local bonus_stats = {}
	local competitive = context and context.competitive or false

	if cosmetics and not competitive and not perks.bonus then
		local bonus_id = cosmetics.bonus

		if not bonus_id and cosmetics.id then
			local blackmarket = (tweak() or {}).blackmarket
			local skins = blackmarket and blackmarket.weapon_skins
			local skin = skins and skins[cosmetics.id]

			bonus_id = skin and skin.bonus
		end

		if bonus_id and bonuses and bonuses[bonus_id] then
			bonus_stats = deep_copy(bonuses[bonus_id].stats or {})
		end
	end

	local indices = deep_copy(base_stats)

	for stat in pairs(indices) do
		local column = stats_tweak_data[stat]

		if column then
			if indices[stat] < 1 or indices[stat] > #column then
				log_line(('%s base stat out of bounds: %s = %s, clamping'):format(name_id, tostring(stat), tostring(indices[stat])))
			end

			if parts_stats[stat] then
				indices[stat] = indices[stat] + parts_stats[stat]
			end

			if bonus_stats[stat] then
				indices[stat] = indices[stat] + bonus_stats[stat]
			end

			indices[stat] = clamp(indices[stat], 1, #column)
		end
	end

	local current_stats = {}

	for stat, index in pairs(indices) do
		local column = stats_tweak_data[stat]
		local value = column and column[index] or 1

		if modifier_stats and modifier_stats[stat] then
			value = value * modifier_stats[stat]
		end

		current_stats[stat] = value
	end

	local concealment_column = stats_tweak_data.concealment

	if indices.concealment and concealment_column then
		local suspicion_index = clamp(#concealment_column - base_stats.concealment - (parts_stats.concealment or 0), 1, #concealment_column)

		indices.suspicion = suspicion_index
		current_stats.suspicion = concealment_column[suspicion_index]
	end

	local model = setmetatable({}, WeaponModel)

	model._name_id = name_id
	model._stat_weapon_id = stat_id
	model._npc = npc and true or false
	model._factory_id = factory_id
	model._blueprint = parts_blueprint
	model.blueprint = parts_blueprint
	model._assembled_blueprint = assembled
	model._parts = parts
	model.parts = parts

	model._ammo_data = ammo_data
	model._custom_stats = custom_stats
	model._current_stats_indices = indices
	model._current_stats = current_stats
	model._parts_stats = parts_stats
	model._bonus_stats = bonus_stats
	model._perks = perks
	model._silencer = silencer
	model._cosmetics = cosmetics
	model._context = context

	model._fire_mode_category = model:_resolve_fire_mode_category()
	model._fire_mode = model._fire_mode_category
	model._burst_count = stat_td.BURST_COUNT or 3
	model._movement_penalty = model:_resolve_movement_penalty()
	model._armor_piercing_chance = model:_resolve_armor_piercing_chance()
	model._can_shoot_through_shield = stat_td.can_shoot_through_shield
	model._can_shoot_through_enemy = stat_td.can_shoot_through_enemy
	model._can_shoot_through_wall = stat_td.can_shoot_through_wall

	if ammo_data then
		if ammo_data.can_shoot_through_shield ~= nil then
			model._can_shoot_through_shield = ammo_data.can_shoot_through_shield
		end

		if ammo_data.can_shoot_through_enemy ~= nil then
			model._can_shoot_through_enemy = ammo_data.can_shoot_through_enemy
		end

		if ammo_data.can_shoot_through_wall ~= nil then
			model._can_shoot_through_wall = ammo_data.can_shoot_through_wall
		end
	end

	model._spread = current_stats.spread
	model._spread_moving = current_stats.spread_moving
	model._recoil = current_stats.recoil
	model._suppression = current_stats.suppression
	model._alert_size = current_stats.alert_size
	model._zoom = current_stats.zoom
	model._reload = current_stats.reload
	model._spread_multiplier = current_stats.spread_multi or parts_stats.spread_multi
	model._extra_ammo = current_stats.extra_ammo or 0
	model._total_ammo_mod = current_stats.total_ammo_mod or 0

	if ammo_data and ammo_data.ammo_offset then
		model._extra_ammo = model._extra_ammo + ammo_data.ammo_offset
	end

	model:_apply_damage_falloff()
	model._damage_near = stat_td.damage_near
	model._damage_far = stat_td.damage_far
	model._use_shotgun_reload = stat_td.use_shotgun_reload

	model._fire_rate = model:_resolve_fire_rate()
	model._fire_rate_multiplier = model:_resolve_fire_rate_multiplier()

	if model._fire_rate and model._fire_rate_multiplier and model._fire_rate_multiplier ~= 0 then
		model._next_fire_allowed = model._fire_rate / model._fire_rate_multiplier
	else
		model._next_fire_allowed = nil
	end

	model._ammo_max_per_clip = model:calculate_ammo_max_per_clip()
	model._ammo_max = model:calculate_ammo_max()
	model._ammo_max_per_clip = math.min(model._ammo_max_per_clip, model._ammo_max)
	model._ammo_total = model._ammo_max

	model._damage = ((current_stats.damage or 0) + model:damage_addend()) * model:damage_multiplier()

	return model
end

function weapon.new(weapon_id, blueprint, context, cosmetics)
	if type(weapon_id) ~= 'string' then
		return nil
	end

	return build(weapon_id, blueprint, context, cosmetics, weapon_id, false)
end

function weapon.new_from_slot(weapon_id, blueprint, options)
	if type(weapon_id) ~= 'string' then
		return nil
	end

	-- options.category / options.slot describe the Black Market slot only; the
	-- model derives everything it needs from tweak data and the blueprint.
	options = options or {}

	local npc = options.npc and true or false
	local name_id = npc and resolve_npc_weapon_id(weapon_id) or weapon_id
	local stat_id = weapon_id

	if not has_stats(stat_id) then
		local stripped = strip_variant_suffix(weapon_id)

		if has_stats(stripped) then
			stat_id = stripped
		else
			return nil
		end
	end

	if npc and type(weapon_tweak()[name_id]) ~= 'table' then
		name_id = stat_id
	end

	return build(name_id, blueprint, current_context(), nil, stat_id, npc)
end

-- Metadata ------------------------------------------------------------------

function WeaponModel:weapon_tweak_data()
	local weapons = weapon_tweak()
	return weapons and (weapons[self._name_id] or weapons.amcar) or nil
end

function WeaponModel:stat_tweak_data()
	local weapons = weapon_tweak()
	return weapons and weapons[self._stat_weapon_id] or nil
end

function WeaponModel:categories()
	local stat_td = self:stat_tweak_data()
	return stat_td and stat_td.categories or nil
end

function WeaponModel:is_category(...)
	local categories = self:categories()

	if not categories then
		return false
	end

	for index = 1, select('#', ...) do
		if contains(categories, (select(index, ...))) then
			return true
		end
	end

	return false
end

function WeaponModel:fire_mode_category()
	return self._fire_mode_category
end

function WeaponModel:can_toggle_firemode()
	local stat_td = self:stat_tweak_data()
	return stat_td and stat_td.CAN_TOGGLE_FIREMODE
end

function WeaponModel:_resolve_fire_mode_category()
	if self._perks.fire_mode_auto then
		return 'auto'
	elseif self._perks.fire_mode_single then
		return 'single'
	elseif self._perks.fire_mode_burst then
		return 'burst'
	elseif self._perks.fire_mode_volley then
		return 'volley'
	end

	local stat_td = self:stat_tweak_data()
	return stat_td and (stat_td.FIRE_MODE or 'single') or 'single'
end

function WeaponModel:_resolve_movement_penalty()
	local categories = self:categories()
	local primary_category = categories and categories[1]
	local tweak_data = tweak()
	local upgrade_table = tweak_data and tweak_data.upgrades and tweak_data.upgrades.weapon_movement_penalty
	local penalty = upgrade_table and upgrade_table[primary_category] or 1

	for _, stats in pairs(self._custom_stats) do
		if stats.movement_speed then
			penalty = penalty * stats.movement_speed
		end
	end

	return penalty
end

function WeaponModel:_resolve_armor_piercing_chance()
	local stat_td = self:stat_tweak_data()
	local chance = stat_td and stat_td.armor_piercing_chance or 0

	if self._ammo_data then
		if self._ammo_data.armor_piercing_add then
			chance = clamp(chance + self._ammo_data.armor_piercing_add, 0, 1)
		end

		if self._ammo_data.armor_piercing_mul then
			chance = clamp(chance * self._ammo_data.armor_piercing_mul, 0, 1)
		end
	end

	return chance
end

--[[
NewRaycastWeaponBase:_default_damage_falloff (newraycastweaponbase.lua:223).
The values are pure tweak data; the distance -> multiplier maths belongs to
core/ballistics (Task 3).
]]
function WeaponModel:_apply_damage_falloff()
	local stat_td = self:stat_tweak_data()
	local falloff = stat_td and stat_td.damage_falloff or {}
	local damage_near = stat_td and stat_td.damage_near
	local damage_far = stat_td and stat_td.damage_far

	if not falloff.optimal_range and damage_near then
		falloff = {
			optimal_range = damage_near,
			far_falloff = damage_far,
		}
	end

	self._optimal_distance = falloff.optimal_distance or 0
	self._optimal_range = falloff.optimal_range or 0
	self._near_falloff = falloff.near_falloff or 0
	self._far_falloff = falloff.far_falloff or 0
	self._near_multiplier = falloff.near_multiplier or 0
	self._far_multiplier = falloff.far_multiplier or 0
end

-- Fire rate ----------------------------------------------------------------

--[[
RaycastWeaponBase:weapon_fire_rate (raycastweaponbase.lua:394) returns the
fire_mode_data interval, which is the value the game actually fires with.
Mode-specific tables (td[td.FIRE_MODE].fire_rate) are exposed separately in
mode_fire_rate() because the old henchman row read them directly.
]]
function WeaponModel:_resolve_fire_rate()
	local stat_td = self:stat_tweak_data()

	if not stat_td then
		return nil
	end

	local mode_data = stat_td.fire_mode_data

	if mode_data and mode_data.fire_rate then
		return mode_data.fire_rate
	end

	local mode_fire_rate = self:mode_fire_rate()

	if mode_fire_rate then
		return mode_fire_rate
	end

	return nil
end

function WeaponModel:weapon_fire_rate()
	return self._fire_rate
end

function WeaponModel:mode_fire_rate()
	local stat_td = self:stat_tweak_data()

	if not stat_td then
		return nil
	end

	local fire_mode = stat_td.FIRE_MODE
	local mode = fire_mode and stat_td[fire_mode]

	if mode and mode.fire_rate then
		return mode.fire_rate
	end

	if stat_td.auto and stat_td.auto.fire_rate then
		return stat_td.auto.fire_rate
	end

	-- Akimbo weapons declare FIRE_MODE = "auto" without an auto table; the
	-- interval they fire with is the fire_mode_data value.
	return stat_td.fire_mode_data and stat_td.fire_mode_data.fire_rate or nil
end

function WeaponModel:fire_rate_rpm()
	local rate = self:weapon_fire_rate()

	if not rate or rate == 0 then
		return nil
	end

	return 60 / rate
end

function WeaponModel:_resolve_fire_rate_multiplier()
	-- BlackMarketManager:fire_rate_multiplier (blackmarketmanager.lua:10107).
	local multiplier = 1
	local context = self._context
	local name_id = self._name_id
	local categories = self:categories() or {}

	multiplier = multiplier + (1 - ctx_upgrade_value(context, name_id, 'fire_rate_multiplier', 1))
	multiplier = multiplier + (1 - ctx_upgrade_value(context, 'weapon', 'fire_rate_multiplier', 1))

	for _, category in ipairs(categories) do
		multiplier = multiplier + (1 - ctx_upgrade_value(context, category, 'fire_rate_multiplier', 1))
	end

	multiplier = convert_add_to_mul(multiplier)

	if self._ammo_data and self._ammo_data.fire_rate_multiplier then
		multiplier = multiplier + self._ammo_data.fire_rate_multiplier
	end

	return multiplier
end

function WeaponModel:fire_rate_multiplier()
	return self._fire_rate_multiplier
end

-- Damage -------------------------------------------------------------------

function WeaponModel:_ignore_damage_upgrades()
	-- BlackMarketManager:ignore_damage_upgrades (blackmarketmanager.lua:2267).
	if self._ammo_data and self._ammo_data.ignore_damage_upgrades ~= nil then
		return self._ammo_data.ignore_damage_upgrades
	end

	local stat_td = self:stat_tweak_data()
	return stat_td and stat_td.ignore_damage_upgrades
end

function WeaponModel:damage_addend()
	-- BlackMarketManager:damage_addend (blackmarketmanager.lua:10120).
	if self:_ignore_damage_upgrades() then
		return 0
	end

	local value = 0
	local context = self._context

	value = value + ctx_upgrade_value(context, 'player', 'damage_addend', 0)
	value = value + ctx_upgrade_value(context, 'weapon', 'damage_addend', 0)
	value = value + ctx_upgrade_value(context, self._name_id, 'damage_addend', 0)

	for _, category in ipairs(self:categories() or {}) do
		value = value + ctx_upgrade_value(context, category, 'damage_addend', 0)
	end

	return value
end

function WeaponModel:damage_multiplier()
	-- BlackMarketManager:damage_multiplier (blackmarketmanager.lua:10138).
	if self:_ignore_damage_upgrades() then
		return 1
	end

	local context = self._context
	local categories = self:categories() or {}
	local multiplier = 1

	for _, category in ipairs(categories) do
		multiplier = multiplier + (1 - ctx_upgrade_value(context, category, 'damage_multiplier', 1))
	end

	multiplier = multiplier + (1 - ctx_upgrade_value(context, self._name_id, 'damage_multiplier', 1))
	multiplier = multiplier + (1 - ctx_upgrade_value(context, 'player', 'passive_damage_multiplier', 1))
	multiplier = multiplier + (1 - ctx_upgrade_value(context, 'weapon', 'passive_damage_multiplier', 1))

	if self._silencer then
		multiplier = multiplier + (1 - ctx_upgrade_value(context, 'weapon', 'silencer_damage_multiplier', 1))
	end

	local risk_upgrade = ctx_upgrade_value(context, 'player', 'detection_risk_damage_multiplier', nil)
	local detection_risk = context and context.detection_risk

	if type(risk_upgrade) == 'table' and type(detection_risk) == 'number' then
		multiplier = multiplier - risk_upgrade_value(risk_upgrade, detection_risk)
	end

	if ctx_has_category_upgrade(context, 'player', 'overkill_health_to_damage_multiplier') then
		local damage_ratio = ctx_upgrade_value(context, 'player', 'overkill_health_to_damage_multiplier', 1) - 1

		multiplier = multiplier + damage_ratio
	end

	if context and not context.steelsight then
		for _, category in ipairs(categories) do
			multiplier = multiplier + (1 - ctx_upgrade_value(context, category, 'hip_fire_damage_multiplier', 1))
		end
	end

	if is_weapon_modified(self._factory_id, self._blueprint) then
		multiplier = multiplier + (1 - ctx_upgrade_value(context, 'weapon', 'modded_damage_multiplier', 1))
	end

	multiplier = multiplier + (1 - ctx_get_property(context, 'trigger_happy', 1))

	return convert_add_to_mul(multiplier)
end

-- Ammo ---------------------------------------------------------------------

-- WeaponAmmo:upgrade_blocked (lib\units\weapons\weaponammo.lua:72).
function WeaponModel:upgrade_blocked(category, upgrade)
	local weapon_td = self:weapon_tweak_data()

	if not weapon_td or not weapon_td.upgrade_blocks then
		return false
	end

	if not weapon_td.upgrade_blocks[category] then
		return false
	end

	return contains(weapon_td.upgrade_blocks[category], upgrade)
end

--[[
NewRaycastWeaponBase:calculate_ammo_max_per_clip (newraycastweaponbase.lua:1372).
The game calls upgrade_value(self._name_id, "clip_ammo_increase") without a
default because every weapon has that upgrade; headless runs pass 0 so a
missing player manager cannot turn the sum into an arithmetic error.
]]
function WeaponModel:calculate_ammo_max_per_clip()
	local stat_td = self:stat_tweak_data()

	if not stat_td then
		return 0
	end

	local context = self._context
	local added = 0

	if self:is_category('shotgun') and stat_td.has_magazine then
		added = ctx_upgrade_value(context, 'shotgun', 'magazine_capacity_inc', 0)

		if self:is_category('akimbo') then
			added = added * 2
		end
	elseif self:is_category('pistol') and not self:is_category('revolver') and ctx_has_category_upgrade(context, 'pistol', 'magazine_capacity_inc') then
		added = ctx_upgrade_value(context, 'pistol', 'magazine_capacity_inc', 0)

		if self:is_category('akimbo') then
			added = added * 2
		end
	elseif self:is_category('smg', 'assault_rifle', 'lmg') then
		added = ctx_upgrade_value(context, 'player', 'automatic_mag_increase', 0)

		if self:is_category('akimbo') then
			added = added * 2
		end
	end

	local ammo = stat_td.CLIP_AMMO_MAX + added

	ammo = ammo + ctx_upgrade_value(context, self._name_id, 'clip_ammo_increase', 0)

	if not self:upgrade_blocked('weapon', 'clip_ammo_increase') then
		ammo = ammo + ctx_upgrade_value(context, 'weapon', 'clip_ammo_increase', 0)
	end

	for _, category in ipairs(stat_td.categories or {}) do
		if not self:upgrade_blocked(category, 'clip_ammo_increase') then
			ammo = ammo + ctx_upgrade_value(context, category, 'clip_ammo_increase', 0)
		end
	end

	ammo = ammo + (self._extra_ammo or 0)

	return ammo
end

-- NewRaycastWeaponBase:replenish (newraycastweaponbase.lua:1330), ammo part only.
function WeaponModel:ammo_max_multiplier()
	local context = self._context
	local multiplier = ctx_upgrade_value(context, 'player', 'extra_ammo_multiplier', 1)

	for _, category in ipairs(self:categories() or {}) do
		multiplier = multiplier * ctx_upgrade_value(context, category, 'extra_ammo_multiplier', 1)
	end

	multiplier = multiplier + multiplier * (self._total_ammo_mod or 0)

	if ctx_has_category_upgrade(context, 'player', 'add_armor_stat_skill_ammo_mul') then
		multiplier = multiplier * ctx_body_armor_value(context, 'skill_ammo_mul', nil, 1)
	end

	return multiplier
end

function WeaponModel:calculate_ammo_max()
	local stat_td = self:stat_tweak_data()

	if not stat_td then
		return 0
	end

	local ammo_max = stat_td.AMMO_MAX or 0
	local amount_increase = ctx_upgrade_value(self._context, self._name_id, 'clip_amount_increase', 0)

	return round((ammo_max + amount_increase * self._ammo_max_per_clip) * self:ammo_max_multiplier())
end

function WeaponModel:get_ammo_max_per_clip()
	return self._ammo_max_per_clip
end

function WeaponModel:get_ammo_max()
	return self._ammo_max
end

function WeaponModel:get_ammo_total()
	return self._ammo_total
end

-- Concealment --------------------------------------------------------------

-- BlackMarketManager:_calculate_weapon_concealment (blackmarketmanager.lua:3018).
function WeaponModel:concealment()
	local stat_td = self:stat_tweak_data()
	local base_stats = stat_td and stat_td.stats

	if not base_stats or not base_stats.concealment then
		return 0
	end

	local bonus = 0
	local parts_stats = self._parts_stats or {}
	local modifier_stats = stat_td.stats_modifiers

	return (base_stats.concealment + bonus + (parts_stats.concealment or 0) + (self._bonus_stats.concealment or 0))
		* (modifier_stats and modifier_stats.concealment or 1)
end

-- NewRaycastWeaponBase:_update_stats_values (newraycastweaponbase.lua:1116).
function WeaponModel:suspicion()
	return self._current_stats.suspicion
end

-- Later-task seams ---------------------------------------------------------

function WeaponModel:is_weak_hit()
	-- Called without a distance/user unit the game returns 1
	-- (newraycastweaponbase.lua:1207); real falloff lives in core/ballistics.
	return 1
end

function WeaponModel:get_damage_falloff()
	-- Task 3: core/ballistics.get_damage_falloff.
	return nil
end

function WeaponModel:_get_spread()
	-- Task 3: core/accuracy.
	return nil
end

function WeaponModel:reload_speed_multiplier()
	-- Task 3: core/timers.
	return nil
end

function WeaponModel:reload_expire_t()
	return nil
end

function WeaponModel:reload_enter_expire_t()
	return nil
end

function WeaponModel:reload_exit_expire_t()
	return nil
end

function WeaponModel:started_reload_empty()
	return nil
end

function WeaponModel:use_shotgun_reload()
	return self._use_shotgun_reload
end

function WeaponModel:clip_empty()
	return false
end

function WeaponModel:clip_not_empty()
	return true
end

function WeaponModel:get_add_head_shot_mul()
	-- NewRaycastWeaponBase:get_add_head_shot_mul (newraycastweaponbase.lua:1233).
	if (self:is_category('smg', 'lmg', 'assault_rifle', 'minigun') and (self._fire_mode == 'auto' or self._fire_mode == 'burst'))
		or self:is_category('bow', 'saw') then
		return ctx_upgrade_value(self._context, 'weapon', 'automatic_head_shot_add', nil)
	end

	return nil
end

return weapon
