--[[
tests/stats_panel_spec.lua — the Black Market extended stat rows.

Covers the adapter seam introduced in Task 5:
	* rows() returns the nine v76 rows in display order;
	* settings.display still hides a row (stats_panel.visible);
	* refresh() formats every row from two real fixture models (CAR-4 equipped,
	  Judge selected), so a swapped left/right mapping fails;
	* a shell-by-shell model (Supernova) keeps both the one-round-short reload
	  and the single-shell time;
	* every two-value row keeps both ends of its range (ammo pickup min/max,
	  moving spread, equip/unequip, recoil left/right and up/down);
	* refresh() blanks cells instead of throwing when a model is nil;
	* a second refresh clears the cells a previous selected/equipped pair left;
	* one context table is passed to every row;
	* mws_get_wbase_from_slot forwards the crafted table's skin bonus.

Expected strings are the formatted values the v76 panel produced, recalculated
from the real 248.2 tweak data in tests/fixtures.lua (CAR-4 and Judge).
]]

local fixtures = dofile(ModPath .. 'tests/fixtures.lua')

-- The specs each load their own fixtures copy; keep the tweak data an earlier
-- spec installed so a character-table case in breakpoints_spec still reads the
-- table it mutates. Install only when running this spec on its own.
if rawget(_G, 'tweak_data') == nil then
	fixtures.install()
end

local stats_panel = MoreWeaponStats.ui.stats_panel
local context = MoreWeaponStats.core.context
local weapon = MoreWeaponStats.core.weapon
local settings = MoreWeaponStats.settings

local ROW_NAMES = {
	'mws_reload_partial',
	'mws_reload_full',
	'mws_equip_delay',
	'mws_ammo_pickup',
	'mws_recoil_horiz',
	'mws_recoil_vert',
	'mws_spread',
	'mws_spread_vert',
	'mws_falloff',
}

local CELL_NAMES = { 'a1', 'b1', 'a2', 'b2' }

local function new_cell()
	return {
		text = nil,
		set_text = function(self, value)
			self.text = value
		end,
	}
end

local function fake_gui()
	local gui = { mws_stats_texts = {} }

	for _, name in ipairs(ROW_NAMES) do
		local cells = {}

		for _, cell_name in ipairs(CELL_NAMES) do
			cells[cell_name] = new_cell()
		end

		gui.mws_stats_texts[name] = cells
	end

	gui.mws_stats_shown = stats_panel.rows()

	return gui
end

local function cell_text(gui, stat_name, cell_name)
	return gui.mws_stats_texts[stat_name][cell_name].text
end

local function assert_row(t, gui, stat_name, a1, b1)
	t.assert_equal(cell_text(gui, stat_name, 'a1'), a1, stat_name .. ' a1')
	t.assert_equal(cell_text(gui, stat_name, 'b1'), b1, stat_name .. ' b1')
	t.assert_equal(cell_text(gui, stat_name, 'a2'), a1, stat_name .. ' a2 (same model)')
	t.assert_equal(cell_text(gui, stat_name, 'b2'), b1, stat_name .. ' b2 (same model)')
end

-- Distinct left/right expectations: a swapped selected/equipped mapping fails.
local function assert_columns(t, gui, stat_name, a1, b1, a2, b2)
	t.assert_equal(cell_text(gui, stat_name, 'a1'), a1, stat_name .. ' a1 (equipped)')
	t.assert_equal(cell_text(gui, stat_name, 'b1'), b1, stat_name .. ' b1 (equipped)')
	t.assert_equal(cell_text(gui, stat_name, 'a2'), a2, stat_name .. ' a2 (selected)')
	t.assert_equal(cell_text(gui, stat_name, 'b2'), b2, stat_name .. ' b2 (selected)')
end

-- Deep copy for the black market hook test; the game provides this global.
local function deep_clone(value)
	if type(value) ~= 'table' then
		return value
	end

	local copy = {}

	for key, entry in pairs(value) do
		copy[key] = deep_clone(entry)
	end

	return copy
end

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

--[[
Loads lua/blackmarketgui.lua against stub menu classes so its real
mws_get_wbase_from_slot can be exercised without a game. The hook file only
defines methods and patches the stubbed class tables at load time; the returned
table keeps them after the globals are restored.
]]
local black_market_gui

local function load_black_market_hook()
	if black_market_gui then
		return black_market_gui
	end

	local gui = {
		close = function() end,
		_setup = function() end,
		_update_borders = function() end,
		set_info_text = function() end,
		update_info_text = function() end,
		show_btns = function() end,
		show_stats = function() end,
		mouse_pressed = function() end,
		mouse_moved = function() end,
	}

	local slot_item = {
		init = function() end,
		select = function() end,
		deselect = function() end,
	}

	with_globals({
		RequiredScript = 'mws_stats_panel_spec',
		DB = { create_entry = function() end },
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

	black_market_gui = gui

	return gui
end

return function(t)
	t.test('stats_panel.rows returns the nine v76 rows in order', function()
		local rows = stats_panel.rows()

		t.assert_equal(#rows, #ROW_NAMES, 'row count')

		for index, name in ipairs(ROW_NAMES) do
			t.assert_equal(rows[index].name, name, 'row ' .. index)
			t.assert_type(rows[index].fct, 'function', name .. ' renderer')
		end
	end)

	t.test('settings.display hides a row through stats_panel.visible', function()
		local previous = settings.display.spread_vert

		settings.display.spread_vert = false
		t.assert_equal(stats_panel.visible({ name = 'mws_spread_vert' }), false, 'hidden row')
		t.assert_equal(stats_panel.visible({ name = 'mws_spread' }), true, 'visible row')
		t.assert_equal(stats_panel.visible({ name = 'mws_not_in_display' }), true, 'unset key stays visible')

		settings.display.spread_vert = true
		t.assert_equal(stats_panel.visible({ name = 'mws_spread_vert' }), true, 'row shown again')

		settings.display.spread_vert = previous
	end)

	t.test('refresh formats every row from a real fixture model', function()
		local previous = settings.display.spread_vert
		settings.display.spread_vert = true

		local ok, err = pcall(function()
			context.invalidate()

			local gui = fake_gui()
			local ctx = context.get()
			local model = weapon.new_from_slot('new_m4', nil, { npc = false })
			local judge = weapon.new_from_slot('judge', nil, { npc = false })

			-- CAR-4 is the equipped (left) model and Judge the selected (right)
			-- one, so a swapped mapping cannot pass on equal columns.
			stats_panel.refresh(gui, judge, model, ctx)

			-- CAR-4 timers reload_not_empty/empty 2.665/3.43, equip 0.6;
			-- AMMO_PICKUP 4.5/8.25; kick 0.6/0.8/-1/1. Judge timers 2.25/2.25,
			-- equip 0.45/unequip 0.5; AMMO_PICKUP 0.175/0.525; kick
			-- 2.9/3/-0.5/0.5.
			assert_columns(t, gui, 'mws_reload_partial', '2.67s', '', '2.25s', '')
			assert_columns(t, gui, 'mws_reload_full', '3.43s', '', '2.25s', '')
			assert_columns(t, gui, 'mws_equip_delay', '0.60s', ' | 0.60s', '0.45s', ' | 0.50s')
			assert_columns(t, gui, 'mws_ammo_pickup', '4.50', ' | 8.25', '0.17', ' | 0.53')
			assert_columns(t, gui, 'mws_recoil_horiz', "-1.50'", " | 1.50'", "-1.15'", " | 1.15'")
			assert_columns(t, gui, 'mws_recoil_vert', "0.90'", " | 1.20'", "6.67'", " | 6.90'")
			assert_columns(t, gui, 'mws_spread', "3.36'", " | 3.36'", "2.88'", " | 2.88'")
			assert_columns(t, gui, 'mws_spread_vert', "3.36'", " | 3.36'", "2.88'", " | 2.88'")
			assert_columns(t, gui, 'mws_falloff', '', '', '1.0', ' | 0.7')
		end)

		settings.display.spread_vert = previous
		context.invalidate()

		if not ok then
			error(err, 0)
		end
	end)

	t.test('shell-by-shell reload keeps the partial and the single-shell time', function()
		-- Supernova uses use_shotgun_reload: the one-round-short reload and the
		-- single-shell timer differ, which is the case the old truncating
		-- `model and timers.reload_partial(...)` chain blanked.
		context.invalidate()

		local gui = fake_gui()
		local ctx = context.get()
		local equipped = weapon.new_from_slot('supernova', nil, { npc = false })
		local selected = weapon.new_from_slot('new_m4', nil, { npc = false })

		stats_panel.refresh(gui, selected, equipped, ctx)

		assert_columns(t, gui, 'mws_reload_partial', '1.97s', ' | 0.60s', '2.67s', '')
		assert_columns(t, gui, 'mws_reload_full', '4.77s', '', '3.43s', '')

		context.invalidate()
	end)

	t.test('refresh with nil models blanks the cells and never throws', function()
		local gui = fake_gui()

		for _, name in ipairs(ROW_NAMES) do
			for _, cell_name in ipairs(CELL_NAMES) do
				gui.mws_stats_texts[name][cell_name]:set_text('sentinel')
			end
		end

		stats_panel.refresh(gui, nil, nil, context.get())

		for _, name in ipairs(ROW_NAMES) do
			for _, cell_name in ipairs(CELL_NAMES) do
				t.assert_equal(cell_text(gui, name, cell_name), '', name .. ' ' .. cell_name)
			end
		end

		stats_panel.refresh(nil, nil, nil, nil)
		stats_panel.refresh({}, nil, nil, nil)
	end)

	t.test('a second refresh clears the previous selected/equipped values', function()
		context.invalidate()

		local gui = fake_gui()
		local ctx = context.get()
		local model = weapon.new_from_slot('new_m4', nil, { npc = false })

		stats_panel.refresh(gui, model, model, ctx)
		t.assert_equal(cell_text(gui, 'mws_reload_full', 'a1'), '3.43s', 'populated before the second refresh')
		t.assert_equal(cell_text(gui, 'mws_falloff', 'b2'), '', 'CAR-4 has no falloff row')

		gui.mws_stats_texts.mws_reload_full.a1:set_text('stale')
		gui.mws_stats_texts.mws_reload_full.b2:set_text('stale')
		gui.mws_stats_texts.mws_falloff.a1:set_text('stale')

		stats_panel.refresh(gui, nil, nil, ctx)

		for _, name in ipairs(ROW_NAMES) do
			for _, cell_name in ipairs(CELL_NAMES) do
				t.assert_equal(cell_text(gui, name, cell_name), '', 'stale ' .. name .. ' ' .. cell_name)
			end
		end
	end)

	t.test('one context table reaches every row', function()
		local gui = { mws_stats_texts = {} }
		local seen = {}

		for _, name in ipairs({ 'mws_reload_full', 'mws_recoil_horiz' }) do
			gui.mws_stats_texts[name] = {
				a1 = new_cell(),
				b1 = new_cell(),
				a2 = new_cell(),
				b2 = new_cell(),
			}
		end

		gui.mws_stats_shown = {
			{
				name = 'mws_reload_full',
				fct = function(model, index, txts, ctx)
					seen[#seen + 1] = ctx
					txts['a' .. index]:set_text('reload')
				end,
			},
			{
				name = 'mws_recoil_horiz',
				fct = function(model, index, txts, ctx)
					seen[#seen + 1] = ctx
					txts['a' .. index]:set_text('recoil')
				end,
			},
		}

		local ctx = { marker = {}, steelsight = false }
		local model = { name = 'fixture' }

		stats_panel.refresh(gui, model, model, ctx)

		t.assert_equal(#seen, 4, 'two rows x two columns')

		for index, value in ipairs(seen) do
			t.assert_true(rawequal(value, ctx), 'row ' .. index .. ' received the render context')
		end
	end)

	t.test('mws_get_wbase_from_slot forwards the crafted table cosmetics', function()
		local hook = load_black_market_hook()
		local crafted = { weapon_id = 'new_m4', cosmetics = nil }
		local previous_managers = rawget(_G, 'managers')
		local previous_deep_clone = rawget(_G, 'deep_clone')

		_G.deep_clone = deep_clone
		_G.managers = {
			blackmarket = {
				equipped_weapon_slot = function()
					return 1
				end,
				equipped_item = function()
					return crafted
				end,
				get_crafted_category_slot = function()
					return crafted
				end,
				get_weapon_blueprint = function()
					return nil
				end,
			},
			weapon_factory = {
				get_factory_id_by_weapon_id = function(_, weapon_id)
					t.assert_equal(weapon_id, 'new_m4', 'factory lookup weapon id')
					return 'wpn_fps_ass_m4'
				end,
				get_default_blueprint_by_factory_id = function()
					return {}
				end,
			},
		}

		local ok, err = pcall(function()
			context.invalidate()

			local instance = setmetatable({
				_slot_data = { name = 'new_m4', category = 'primaries', slot = 1 },
			}, { __index = hook })

			local plain = instance:mws_get_wbase_from_slot(false)
			t.assert_type(plain, 'table', 'plain model')
			t.assert_equal(plain:concealment(), 20, 'CAR-4 base concealment')

			crafted.cosmetics = { bonus = 'concealment_p1' }

			local skinned = instance:mws_get_wbase_from_slot(false)
			t.assert_type(skinned, 'table', 'skinned model')
			t.assert_equal(skinned:concealment(), 21, 'ok skin bonus reaches the model')

			local equipped = instance:mws_get_wbase_from_slot(true)
			t.assert_equal(equipped:concealment(), 21, 'equipped column carries the skin too')
		end)

		_G.managers = previous_managers
		_G.deep_clone = previous_deep_clone
		context.invalidate()

		if not ok then
			error(err, 0)
		end
	end)
end
