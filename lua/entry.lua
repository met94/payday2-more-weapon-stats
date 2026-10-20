_G.MoreWeaponStats = _G.MoreWeaponStats or {}
MoreWeaponStats._path = ModPath
MoreWeaponStats._data_path = SavePath .. 'more_weapon_stats.txt'
MoreWeaponStats.stance_color = Color(0.114, 0.736, 0.517)
MoreWeaponStats.settings = {
	display = {
		ammo_pickup = true,
		equip_delay = true,
		falloff = true,
		recoil_horiz = true,
		recoil_vert = true,
		reload_full = true,
		reload_partial = true,
		spread = true,
		spread_vert = false,
	},
	show_dlc_info = true,
	last_used_difficulty = 'overkill_290',
	fill_breakpoints = true,
	use_preview_to_switch_breakpoints = true,
	clicks_per_second = 5,
	enable_trigger_happy_for_first_bullet = true
}

function MoreWeaponStats:load()
	local file = io.open(self._data_path, 'r')
	if file then
		for k, v in pairs(json.decode(file:read('*all')) or {}) do
			self.settings[k] = v
		end
		file:close()
	end
end

function MoreWeaponStats:save()
	local file = io.open(self._data_path, 'w+')
	if file then
		file:write(json.encode(self.settings))
		file:close()
	end
end

local function function_empty()
end

local function function_empty_table()
	return {}
end

local function function_zero()
	return 0
end

local function make_function_returns_params_x(x)
	return function(...)
		local params = {...}
		return params[x]
	end
end

_G.Overrider = _G.Overrider or class()

function Overrider:init()
	self.things = {}
end

function Overrider:remember(obj, id)
	table.insert(self.things, { obj, id, obj[id] })
end

function Overrider:replace(obj, id, v)
	table.insert(self.things, { obj, id, obj[id] })
	obj[id] = v
end

function Overrider:replace_once(obj, id, v)
	for _, thing in ipairs(self.things) do
		if thing[1] == obj and thing[2] == id then
			return
		end
	end
	self:replace(obj, id, v)
end

function Overrider:revert_all()
	local thing = table.remove(self.things)
	while thing do
		thing[1][thing[2]] = thing[3]
		thing = table.remove(self.things)
	end
end

-- Fake weapon base classes are cached here, never in _G.
local fake_weapon_base_classes = {}

_G.Faker = _G.Faker or {
	classes = {},
	overrider = Overrider:new(),
	_sandbox_active = false,
}

function Faker:redo_class(name, parent_name)
	if not _G[name] then
		log('[Faker] class not redone: ' .. name)
		return
	end
	local parent = self.classes[parent_name]
	local result = class(parent)
	for k, v in pairs(_G[name]) do
		if type(v) == 'function' then
			result[k] = v
		end
	end
	self.classes[name] = result
end

-- Deprecated. Kept as no-ops so that any external caller still resolves, but
-- swapping _G weapon classes is gone for good: it leaked fake classes into the
-- real game whenever an error happened between the swap and the unswap.
function Faker:use_game_classes()
	return false
end

-- Deprecated no-op, see Faker:use_game_classes().
function Faker:use_normal_classes()
	return false
end

-- Runs fn with stubbed managers and restores every replaced field afterwards,
-- even if fn errors. Safe to nest (each call restores what it replaced).
-- Returns ok, result_or_error.
function Faker:sandbox(fn)
	if type(fn) ~= 'function' then
		return false, 'sandbox: expected a function, got ' .. type(fn)
	end

	if self._sandbox_active then
		-- The outer sandbox already installed the stubs and will restore them;
		-- do not rebuild (or re-restore) them here.
		local ok, result = pcall(fn)
		if not ok then
			log('[MWS] statistics sandbox failed: ' .. tostring(result))
			return false, result
		end
		return true, result
	end

	if not managers then
		-- Too early for managers (we are a pre-hook on lib/entry).
		local ok, result = pcall(fn)
		if not ok then
			log('[MWS] statistics sandbox failed: ' .. tostring(result))
			return false, result
		end
		return true, result
	end

	local restores = {}

	local function remember(obj, key, replacement)
		if not obj then
			return
		end
		restores[#restores + 1] = { obj = obj, key = key, old = obj[key] }
		if replacement ~= nil then
			obj[key] = replacement
		end
	end

	local function remember_manager(name, class_name, extra_key, extra_value)
		local class_table = _G[class_name]
		if not class_table then
			log('[MWS] sandbox: manager class not loaded: ' .. tostring(class_name))
			return
		end
		local stubbed, stub = pcall(self.fill_with_empty_methods, class_table)
		if not stubbed then
			error(('[MWS] sandbox: could not stub manager class %s: %s'):format(tostring(class_name), tostring(stub)), 0)
		end
		if extra_key then
			stub[extra_key] = extra_value
		end
		remember(managers, name, stub)
	end

	-- Installing the stubs is fallible too (fill_with_empty_methods walks class
	-- tables). Protect it with pcall so a mid-install error still reaches the
	-- restore loop below instead of leaking the stubs installed so far.
	local installed, install_err = pcall(function()
		remember(managers.player, 'remove_property', function_empty)
		remember(managers.player, 'send_message_now', function_empty)
		remember_manager('achievment', 'AchievmentManager')
		remember_manager('challenge', 'ChallengeManager', 'get_all_active_challenges', function_empty_table)
		remember_manager('enemy', 'EnemyManager')
		remember_manager('hud', 'HUDManager')
		remember_manager('job', 'JobManager')
		remember_manager('mission', 'MissionManager')
		remember_manager('statistics', 'StatisticsManager')
	end)

	local ok, result
	if installed then
		self._sandbox_active = true
		ok, result = pcall(fn)
	else
		-- Do not run fn against a half-installed sandbox.
		ok, result = false, install_err
	end

	for i = #restores, 1, -1 do
		local saved = restores[i]
		local restored, restore_err = pcall(function()
			saved.obj[saved.key] = saved.old
		end)
		if not restored then
			log(('[MWS] sandbox: could not restore managers field "%s": %s'):format(tostring(saved.key), tostring(restore_err)))
		end
	end

	self._sandbox_active = false

	if not ok then
		log('[MWS] statistics sandbox failed: ' .. tostring(result))
		return false, result
	end

	return true, result
end

function Faker.spy(tbl, name, recursive, verbose, processed)
	if verbose then log('[Faker] spy ' .. tostring(name) .. '	-> ' .. tostring(tbl)) end
	if recursive then
		processed = processed or {}
		processed[tbl] = true
		for k, v in pairs(tbl) do
			if k ~= 'faker_model' and type(v) == 'table' and not processed[v] and not getmetatable(v) then
				tbl[k] = Faker.spy(v, k, recursive, verbose, processed)
			end
		end
	end

	if getmetatable(tbl) then
		return tbl
	end

	return setmetatable({}, {
		__index = function (t, k)
			if verbose then log(('[Faker] > accessed %s.%s'):format(tostring(name), tostring(k))) end
			if not tbl[k] and tbl.faker_model and type(tbl.faker_model[k]) == 'function' then
				return function(...)
					if verbose then log(('[Faker] > called "%s.%s" with %i parameters'):format(tostring(name), tostring(k), table.size({...}))) end
				end
			end
			return tbl[k]
		end
	})
end

function Faker.fill_with_empty_methods(source, result)
	result = result or {}

	if type(source.super) == 'table' then
		result = Faker.fill_with_empty_methods(source.super, result)
	end

	local holder = source
	if type(source) == 'userdata' then
		holder = getmetatable(source)
	end

	for k, v in pairs(holder) do
		if type(v) == 'function' and not result[k] then
			result[k] = function_empty
		end
	end

	return result
end

function Faker.make_playerstate(player_unit, weapon_base, st_moving, st_ducking, st_deploy, st_steelsight)
	local result = {
		faker_model = PlayerStandard,
		_unit = player_unit,
		_change_weapon_data = {},
		_equipped_unit = weapon_base._unit,
		_ext_camera = Faker.fill_with_empty_methods(PlayerCamera),
		_ext_inventory = player_unit and player_unit:inventory(),
		_ext_network = Faker.fill_with_empty_methods(NetworkBaseExtension),
		_ext_movement = player_unit and player_unit:movement(),
		_moving = st_moving,
		_state_data = {
			using_bipod = st_deploy,
			ducking = st_ducking,
			in_steelsight = st_steelsight,
		},
	}
	result = Faker.fill_with_empty_methods(PlayerStandard, result)

	result._get_swap_speed_multiplier = PlayerStandard._get_swap_speed_multiplier
	result._start_action_equip_weapon = PlayerStandard._start_action_equip_weapon
	result._start_action_unequip_weapon = PlayerStandard._start_action_unequip_weapon
	result._start_action_reload_enter = PlayerStandard._start_action_reload_enter
	result._start_action_reload = PlayerStandard._start_action_reload
	result._update_reload_timers = PlayerStandard._update_reload_timers
	result.get_movement_state = PlayerStandard.get_movement_state
	result.in_steelsight = PlayerStandard.in_steelsight

	return result
end

function Faker.make_unit()
	local result = Faker.fill_with_empty_methods(Unit)
	result.faker_model = Unit

	local id = math.random(1000000000)
	result.id = function()
		return id
	end

	result.key = function()
		return 'key ' .. id
	end

	return result
end

function Faker.make_player_unit(weapon_base, st_moving, st_ducking, st_deploy, st_steelsight)
	local result = Faker.make_unit()

	result.m_head_pos = function()
		return Vector3()
	end

	-- A fake inventory with empty methods. Building a real inventory and
	-- registering the fake weapon unit on it leaked engine units into the game.
	local inventory = PlayerInventory and Faker.fill_with_empty_methods(PlayerInventory) or {}
	inventory.add_unit = function_empty
	inventory.remove_unit = function_empty
	inventory._link_weapon = function_empty
	result._inventory = inventory
	result.inventory = function(self)
		return self._inventory
	end

	result._movement = {
		_moving = st_moving
	}
	result.movement = function(self)
		return self._movement
	end

	result._network = Faker.fill_with_empty_methods(NetworkBaseExtension)
	result.network = function(self)
		return self._network
	end

	result._character_damage = Faker.fill_with_empty_methods(PlayerDamage)
	result.character_damage = function(self)
		return self._character_damage
	end

	result._unit_data = {}
	result.unit_data = function(self)
		return self._unit_data
	end

	result._movement._current_state = Faker.make_playerstate(result, weapon_base, st_moving, st_ducking, st_deploy, st_steelsight)

	return result
end

function Faker.make_sounddevice()
	local result = {
		create_source = function()
			return {
				link = function_empty,
				post_event = function_empty,
				set_switch = function_empty,
			}
		end,
	}
	result = Faker.fill_with_empty_methods(SoundDevice, result)
	return result
end

function Faker.get_weapon_base_class_name(name_id, npc)
	local result

	local td = tweak_data.weapon[name_id]
	local categories = td.categories and table.list_to_set(td.categories)
	if not categories then
		result = npc and 'NewNPCRaycastWeaponBase' or 'NewRaycastWeaponBase'
	elseif categories.shotgun then
		if npc then
			result = 'NewNPCRaycastWeaponBase'
		elseif categories.akimbo then
			result = 'AkimboShotgunBase'
		elseif td.timers and td.timers.reload_not_empty then
			result = 'SaigaShotgun'
		else
			result = 'ShotgunBase'
		end
	elseif categories.flamethrower then
		result = npc and 'NewNPCFlamethrowerBase' or 'NewFlamethrowerBase'
	elseif categories.grenade_launcher then
		if td.timers and td.timers.shotgun_reload_enter then
			result = not npc and 'GrenadeLauncherContinousReloadBase'
		else
			result = npc and 'NPCGrenadeLauncherBase' or 'GrenadeLauncherBase'
		end
	elseif categories.bow then
		result = npc and 'NPCBowWeaponBase' or 'BowWeaponBase'
	elseif categories.crossbow then
		result = npc and 'NPCCrossBowWeaponBase' or 'CrossbowWeaponBase'
	elseif categories.akimbo then
		result = npc and 'NPCAkimboWeaponBase' or 'AkimboWeaponBase'
	elseif categories.saw then
		result = npc and 'NPCSawWeaponBase' or 'SawWeaponBase'
	end

	if not result then
		result = npc and 'NewNPCRaycastWeaponBase' or 'NewRaycastWeaponBase'
	end

	return result
end

function Faker:craft_weapon_base_class(class_name, factory_id, blueprint, name_id)
	local cached = fake_weapon_base_classes[class_name]
	if cached then
		return cached
	end

	-- Gameplay class snapshot first: self.classes holds the classes taken before
	-- other mods (and before the menu globals) could touch them.
	local cls = self.classes[class_name] or _G[class_name]
	if not cls then
		log('[Faker] weapon base class not found: ' .. tostring(class_name))
		return nil
	end

	local FakeWeaponBase = class(cls)
	fake_weapon_base_classes[class_name] = FakeWeaponBase

	function FakeWeaponBase:init(unit, factory_id, blueprint, name_id)
		self._blueprint = blueprint
		self._factory_id = factory_id
		self.name_id = name_id

		local original_sounddevice = SoundDevice
		SoundDevice = Faker.make_sounddevice()
		local ok, err = pcall(function()
			FakeWeaponBase.super.init(self, unit)
		end)
		SoundDevice = original_sounddevice
		if not ok then
			error(err, 0)
		end
	end

	function FakeWeaponBase:setup_default()
		self._ammo_data = self._ammo_data or managers.weapon_factory:get_ammo_data_from_weapon(self._factory_id, self._blueprint) or {}
		FakeWeaponBase.super.setup_default(self)
	end

	return FakeWeaponBase
end

Faker.special_npc_weapon_id = {
	b92fs = 'beretta92',
	benelli = 'beretta92',
	colt_1911 = 'c45',
	glock_17 = 'g17',
	glock_18c = 'glock_18',
}

function Faker.get_npc_weapon_id(weapon_id)
	weapon_id = weapon_id:gsub('^new_', '')
	weapon_id = weapon_id:gsub('_primary$', '')
	weapon_id = weapon_id:gsub('_secondary$', '')
	weapon_id = weapon_id:gsub('_gold$', '')

	weapon_id = Faker.special_npc_weapon_id[weapon_id] or weapon_id

	local result = weapon_id .. '_crew'
	if tweak_data.weapon[result] then
		return result
	end
	result = weapon_id .. '_npc'
	if tweak_data.weapon[result] then
		return result
	end

	log('[Faker] npc weapon id not found for ' .. weapon_id)
	return weapon_id
end

function Faker:make_weapon_base(factory_id, blueprint, name_id, npc)
	local non_npc_name_id = name_id
	if npc then
		name_id = self.get_npc_weapon_id(name_id)
	end

	local wbase

	local ok, err = self:sandbox(function()
		local class_name = self.get_weapon_base_class_name(non_npc_name_id, npc)
		local FakeClass = self:craft_weapon_base_class(class_name, factory_id, blueprint, name_id)
		if not FakeClass then
			error('no fake weapon base class for ' .. tostring(class_name), 0)
		end

		local fake_unit = self.make_unit()
		local base = FakeClass:new(fake_unit, factory_id, blueprint, name_id)

		fake_unit.base = function()
			return base
		end

		base.name_id = name_id
		base.fkr_non_npc_name_id = non_npc_name_id
		base._assembly_complete = true
		base._parts = {}
		base._gadgets = {}
		base.add_destroy_listener = function_empty
		base.on_reload = function_empty

		if npc then
			base:set_factory_data(factory_id .. '_npc')
			local setup_data = {
				expend_ammo = false,
				autoaim = false,
				alert_AI = false
			}
			base:setup(setup_data)
		end

		base:_update_stats_values()

		if not npc then
			base._next_fire_allowed = 0
			base:update_next_shooting_time()
			base:update_damage()
		end

		wbase = base
	end)

	if not ok or not wbase then
		log(('[MWS] fake weapon base failed for "%s": %s'):format(tostring(name_id), tostring(err)))
		return nil
	end

	return wbase
end
