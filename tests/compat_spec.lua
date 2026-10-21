--[[
tests/compat_spec.lua — coexistence with the mods MWS ships alongside.

Covers the Task 7 compatibility guarantees without a game:
	* the Black Market hook file captures the previous _setup, show_stats,
	  update_info_text, mouse_pressed, mouse_moved, close and set_info_text, so
	  a wrapper installed before MWS still runs (VanillaHUD Plus/Extra Heist
	  Info load-order chain);
	* loading the two hook files writes no mod globals outside
	  MoreWeaponStats (no Faker/Overrider/SimpleChart/DifficultyPicker, no
	  mws_*); the only new names are SuperBLT's own ModPath/RequiredScript
	  load guards;
	* the crafted skin (SDSS/OSA/HDS cosmetics) reaches
	  core.weapon.new_from_slot, and the path leaves
	  BlackMarketManager.equipped_primary/secondary and
	  Global.game_settings.difficulty untouched;
	* compat.init() is idempotent and touches no manager or global.

The hook file is loaded against stub menu classes; its methods stay on the
returned tables after the globals are restored.
]]

local fixtures = dofile(ModPath .. 'tests/fixtures.lua')

-- Same rule as the other specs: do not re-install a tweak table an earlier spec
-- installed and mutates.
if rawget(_G, 'tweak_data') == nil then
	fixtures.install()
end

local compat = MoreWeaponStats.compat
local weapon = MoreWeaponStats.core.weapon

-- Runs fn with temporary globals, restoring every previous value afterwards.
local function with_globals(stubs, fn)
	local previous = {}

	for name, value in pairs(stubs) do
		previous[name] = rawget(_G, name)
		_G[name] = value
	end

	local ok, err = pcall(fn)

	for name in pairs(stubs) do
		_G[name] = previous[name]
	end

	if not ok then
		error(err, 0)
	end
end

local function global_keys()
	local keys = {}

	for name in pairs(_G) do
		keys[name] = true
	end

	return keys
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

--[[
Loads lua/blackmarketgui.lua once, with a simulated third-party wrapper already
installed on every method MWS wraps. The wrapper counters prove the captured
original still runs. Returns the stub classes/instance table, the counters and
the globals the two hook files created at load time.
]]
local hooks

local function load_hooks()
	if hooks then
		return hooks
	end

	local calls = {
		setup = 0,
		show_stats = 0,
		update_info_text = 0,
		mouse_pressed = 0,
		mouse_moved = 0,
		close = 0,
		set_info_text = 0,
	}

	-- Third-party (VanillaHUD Plus / Extra Heist Info style) wrappers: they
	-- replace the method before MWS loads and would be lost if MWS dropped the
	-- captured original.
	local gui = {}
	local slot_item = {}

	local function wrapper(name)
		return function()
			calls[name] = calls[name] + 1
		end
	end

	gui._setup = wrapper('setup')
	gui.show_stats = wrapper('show_stats')
	gui.update_info_text = wrapper('update_info_text')
	gui.mouse_pressed = wrapper('mouse_pressed')
	gui.mouse_moved = wrapper('mouse_moved')
	gui.close = wrapper('close')
	gui.set_info_text = wrapper('set_info_text')
	gui._update_borders = function() end
	gui.show_btns = function() end
	slot_item.init = function() end
	slot_item.select = function() end
	slot_item.deselect = function() end

	local before = global_keys()

	local ok, err = pcall(function()
		with_globals({
			RequiredScript = 'mws_compat_spec',
			DB = {create_entry = function() end},
			Idstring = function(value)
				return value
			end,
			class = function()
				return {}
			end,
			BlackMarketGui = gui,
			BlackMarketGuiSlotItem = slot_item,
		}, function()
			dofile(ModPath .. 'lua/blackmarketgui.lua')
		end)

		with_globals({
			RequiredScript = 'mws_compat_spec_menumanager',
			Hooks = {Add = function() end},
			DelayedCalls = {Add = function() end},
		}, function()
			dofile(ModPath .. 'lua/menumanager.lua')
		end)
	end)

	if not ok then
		error(err, 0)
	end

	local new_globals = {}

	for name in pairs(_G) do
		if not before[name] then
			new_globals[#new_globals + 1] = name
			-- Keep the runner's global table clean for the following cases.
			_G[name] = nil
		end
	end

	table.sort(new_globals)

	hooks = {
		gui = gui,
		slot_item = slot_item,
		calls = calls,
		new_globals = new_globals,
	}

	return hooks
end

return function(t)
	t.test('a wrapper installed before MWS still runs through every MWS wrapper', function()
		local loaded = load_hooks()
		local gui = loaded.gui
		local calls = loaded.calls

		gui._tabs = {{_data = {identifier = 'inventory'}}}
		gui._selected = 1
		gui._enabled = true
		gui.identifiers = {}

		with_globals({
			alive = function()
				return false
			end,
			Idstring = function(value)
				return value
			end,
		}, function()
			gui:_setup(nil, nil)
			gui:show_stats()
			gui:update_info_text()
			gui:mouse_pressed('0', 0, 0)
			gui:mouse_moved(nil, 0, 0)
			gui:close()
			gui:set_info_text(3, 'text', nil)
		end)

		for _, name in ipairs({
			'setup',
			'show_stats',
			'update_info_text',
			'mouse_pressed',
			'mouse_moved',
			'close',
			'set_info_text',
		}) do
			t.assert_equal(calls[name], 1, name .. ' original called once')
		end
	end)

	t.test('loading the hook files writes no mod globals', function()
		local loaded = load_hooks()
		local guard_prefix = ModPath .. '\t'

		-- SuperBLT itself asks every hook script for this one key; the mod must
		-- not add anything else (no Faker, SimpleChart, DifficultyPicker, mws_*).
		t.assert_equal(#loaded.new_globals, 2, 'one load guard per hook file')

		for _, name in ipairs(loaded.new_globals) do
			t.assert_equal(name:sub(1, #guard_prefix), guard_prefix, 'expected a SuperBLT guard, got ' .. name)
		end

		for _, name in ipairs({'Faker', 'Overrider', 'SimpleChart', 'DifficultyPicker'}) do
			t.assert_nil(rawget(_G, name), name .. ' must not be a global')
		end

		for name in pairs(_G) do
			t.assert_equal(name:match('^mws_') == nil, true, 'unexpected mws_ global ' .. name)
		end

		t.assert_type(rawget(_G, 'MoreWeaponStats'), 'table', 'the mod namespace is the only mod global')
	end)

	t.test('crafted cosmetics reach new_from_slot without manager or difficulty writes', function()
		local loaded = load_hooks()
		local cosmetics = {id = 'new_m4_goldstripes', bonus = 'concealment_p1'}
		local crafted = {weapon_id = 'new_m4', cosmetics = cosmetics}
		local blueprint = {'wpn_fps_m4_lower_reciever'}
		local captured
		local previous_new_from_slot = weapon.new_from_slot
		local crafted_reads = 0

		-- Spy: the slot path must forward the crafted table's skin as options.
		weapon.new_from_slot = function(weapon_id, slot_blueprint, options)
			captured = {
				weapon_id = weapon_id,
				blueprint = slot_blueprint,
				options = options,
			}

			return {marker = true}
		end

		local ok, err = pcall(function()
			with_globals({
				tweak_data = {
					weapon = {new_m4 = {}},
					blackmarket = {melee_weapons = {}},
				},
				deep_clone = deep_copy,
				Global = {game_settings = {difficulty = 'sm_wish'}},
				managers = {
					blackmarket = {
						equipped_primary = 'primary_sentinel',
						equipped_secondary = 'secondary_sentinel',
						equipped_weapon_slot = function()
							return 1
						end,
						equipped_item = function()
							return crafted
						end,
						get_crafted_category_slot = function()
							crafted_reads = crafted_reads + 1
							return crafted
						end,
						get_weapon_blueprint = function()
							return blueprint
						end,
					},
					weapon_factory = {
						get_factory_id_by_weapon_id = function()
							return 'wpn_fps_ass_m4'
						end,
						get_default_blueprint_by_factory_id = function()
							return {}
						end,
					},
				},
			}, function()
				local instance = setmetatable({
					_slot_data = {name = 'new_m4', category = 'primaries', slot = 1},
				}, {__index = loaded.gui})

				local model = instance:mws_get_wbase_from_slot(false)

				t.assert_type(model, 'table', 'model returned')
				t.assert_equal(crafted_reads, 1, 'crafted table read through the manager')
				t.assert_equal(captured.weapon_id, 'new_m4', 'weapon id from the crafted table')
				t.assert_true(rawequal(captured.options.cosmetics, cosmetics), 'cosmetics forwarded unchanged')
				t.assert_equal(captured.blueprint[1], blueprint[1], 'crafted blueprint forwarded')

				local equipped = instance:mws_get_wbase_from_slot(true)
				t.assert_type(equipped, 'table', 'equipped model returned')
				t.assert_true(rawequal(captured.options.cosmetics, cosmetics), 'equipped cosmetics forwarded')

				t.assert_equal(managers.blackmarket.equipped_primary, 'primary_sentinel', 'equipped_primary untouched')
				t.assert_equal(managers.blackmarket.equipped_secondary, 'secondary_sentinel', 'equipped_secondary untouched')
				t.assert_equal(Global.game_settings.difficulty, 'sm_wish', 'difficulty untouched')
			end)
		end)

		weapon.new_from_slot = previous_new_from_slot

		if not ok then
			error(err, 0)
		end
	end)

	t.test('compat.init is idempotent and touches no manager or global', function()
		local before = global_keys()
		local managers_sentinel = {marker = true}
		local previous_managers = rawget(_G, 'managers')
		local previous_global = rawget(_G, 'Global')

		_G.managers = managers_sentinel
		_G.Global = {game_settings = {}}

		local ok, err = pcall(function()
			compat.init()
			compat.init()

			t.assert_true(rawequal(rawget(_G, 'managers'), managers_sentinel), 'managers untouched')
			t.assert_true(rawequal(rawget(_G, 'Global').game_settings, _G.Global.game_settings), 'Global untouched')
			t.assert_nil(rawget(_G, 'Global').game_settings.difficulty, 'no difficulty written')

			for name in pairs(_G) do
				t.assert_equal(before[name] ~= nil or name == 'managers' or name == 'Global', true, 'new global ' .. name)
			end
		end)

		_G.managers = previous_managers
		_G.Global = previous_global

		if not ok then
			error(err, 0)
		end
	end)
end
