--[[
tests/henchmen_spec.lua — the henchman/NPC stat rows (Task 6b).

Covers the adapter seam that moved out of blackmarketgui.lua:
	* rows() returns the five v76 base rows in order, then one
	  mws_damage_hitchance row per unique FALLOFF distance of
	  tweak_data.character.russian.weapon (ascending, with text_name and the
	  DIS macro);
	* refresh() fills the equipped (left) and selected (right) columns from the
	  NPC models: spread, ROF, autofire rounds, reload and aim delay;
	* automatic crew weapons use the auto interval and the autofire rounds,
	  single-fire ones use the CopActionShoot cadence at 1500cm and '-';
	* damage/hit chance follow the v76 falloff lookup at two distances;
	* a model without a weapon usage entry shows the '?' fallback;
	* a nil model blanks every cell instead of raising;
	* a second refresh clears the previous values.

Expected strings are the v76 panel output, calculated from the real 248.2 tweak
data copied into tests/fixtures.lua: the crew weapons m4_crew and m95_crew
(weapontweakdata.lua:1648-1664, :2431-2448) and the gang-member usage tables
(charactertweakdata.lua:9102-9676).
]]

local fixtures = dofile(ModPath .. 'tests/fixtures.lua')

-- Same rule as the other specs: do not re-install a tweak table an earlier spec
-- installed and mutates.
if rawget(_G, 'tweak_data') == nil then
	fixtures.install()
end

local henchmen = MoreWeaponStats.ui.henchmen
local context = MoreWeaponStats.core.context
local weapon = MoreWeaponStats.core.weapon

local BASE_ROW_NAMES = {
	'mws_spread',
	'mws_rof',
	'mws_autorounds',
	'mws_reload_full',
	'mws_aim_delay',
}

-- Unique FALLOFF distances of the gang-member usage tables.
local DISTANCES = {100, 300, 500, 700, 1000, 2000, 2500, 3000, 4000, 10000}

local CELL_NAMES = { 'a1', 'b1', 'a2', 'b2' }

local function new_cell()
	return {
		text = nil,
		set_text = function(self, value)
			self.text = value
		end,
	}
end

local function row_key(stat)
	return stat.text_name or stat.name
end

local function fake_gui()
	local gui = { mws_stats_texts = {} }

	gui.mws_stats_shown = henchmen.rows(gui)

	for _, stat in ipairs(gui.mws_stats_shown) do
		local cells = {}

		for _, cell_name in ipairs(CELL_NAMES) do
			cells[cell_name] = new_cell()
		end

		gui.mws_stats_texts[row_key(stat)] = cells
	end

	return gui
end

local function cell_text(gui, key, cell_name)
	return gui.mws_stats_texts[key][cell_name].text
end

local function assert_row(t, gui, key, a1, b1, a2, b2)
	t.assert_equal(cell_text(gui, key, 'a1'), a1, key .. ' a1 (equipped)')
	t.assert_equal(cell_text(gui, key, 'b1'), b1, key .. ' b1 (equipped)')
	t.assert_equal(cell_text(gui, key, 'a2'), a2, key .. ' a2 (selected)')
	t.assert_equal(cell_text(gui, key, 'b2'), b2, key .. ' b2 (selected)')
end

-- A data-only stand-in for a crew entry with an unknown usage, which the real
-- weapon model never produces but a modded weapon table could.
local function unknown_usage_model()
	return {
		_damage = 1,
		weapon_tweak_data = function()
			return {usage = 'is_underwater'}
		end,
		is_category = function()
			return false
		end,
	}
end

return function(t)
	t.test('henchmen.rows returns the base rows then one row per distance', function()
		local rows = henchmen.rows({})

		t.assert_equal(#rows, #BASE_ROW_NAMES + #DISTANCES, 'row count')

		for index, name in ipairs(BASE_ROW_NAMES) do
			t.assert_equal(rows[index].name, name, 'base row ' .. index)
			t.assert_type(rows[index].fct, 'function', name .. ' renderer')
		end

		for index, distance in ipairs(DISTANCES) do
			local row = rows[#BASE_ROW_NAMES + index]

			t.assert_equal(row.name, 'mws_damage_hitchance', 'damage row ' .. index .. ' name')
			t.assert_equal(row.text_name, 'mws_damage_hitchance_' .. distance, 'damage row ' .. index .. ' text_name')
			t.assert_type(row.fct, 'function', 'damage row ' .. index .. ' renderer')
			t.assert_equal(row.macros.DIS, distance / 100, 'damage row ' .. index .. ' DIS macro')
		end
	end)

	t.test('refresh fills spread, ROF, autofire, reload and aim delay', function()
		context.invalidate()

		local gui = fake_gui()
		local equipped = weapon.new_from_slot('new_m4', nil, { npc = true })
		local selected = weapon.new_from_slot('m95', nil, { npc = true })

		t.assert_equal(equipped._name_id, 'm4_crew', 'equipped model is the crew M4')
		t.assert_equal(selected._name_id, 'm95_crew', 'selected model is the crew M95')

		henchmen.refresh(gui, selected, equipped, {})

		-- m4_crew: is_rifle, automatic (auto.fire_rate 0.1, autofire 6/11).
		-- m95_crew: is_sniper, single-fire (cadence from FALLOFF at 1500 = 2/3).
		assert_row(t, gui, 'mws_spread', '25', '', '25', '')
		assert_row(t, gui, 'mws_rof', '600', '', '20', '')
		assert_row(t, gui, 'mws_autorounds', '6', ' | 11', '-', '')
		assert_row(t, gui, 'mws_reload_full', '1.00', '', '1.00', '')
		assert_row(t, gui, 'mws_aim_delay', '0.00s', ' | 0.50s', '0.25s', ' | 1.00s')
	end)

	t.test('damage and hit chance follow the falloff lookup', function()
		context.invalidate()

		local gui = fake_gui()
		local equipped = weapon.new_from_slot('new_m4', nil, { npc = true })
		local selected = weapon.new_from_slot('m95', nil, { npc = true })

		henchmen.refresh(gui, selected, equipped, {})

		-- is_rifle at 4000: second range (r 10000, dmg_mul 2.5), 2.5 * 1.5 * 10.
		-- is_sniper at 4000: fourth range (dmg_mul 5, acc 0.9/0.95), 5 * 22.5 * 10.
		assert_row(t, gui, 'mws_damage_hitchance_4000', '37.50', ' | 100%', '1125.00', ' | 95%')

		-- At 10000 the last range applies: is_sniper acc 0.85/0.9.
		assert_row(t, gui, 'mws_damage_hitchance_10000', '37.50', ' | 100%', '1125.00', ' | 90%')

		-- First is_rifle range (r 300) at 100cm: 5 * 1.5 * 10. The sniper's first
		-- range (r 500, dmg_mul 10) is 10 * 22.5 * 10.
		assert_row(t, gui, 'mws_damage_hitchance_100', '75.00', ' | 100%', '2250.00', ' | 100%')
	end)

	t.test('single-fire crew weapons use the CopActionShoot cadence', function()
		context.invalidate()

		local gui = fake_gui()
		local equipped = weapon.new_from_slot('glock_17', nil, { npc = true })
		local selected = weapon.new_from_slot('new_m4', nil, { npc = true })

		t.assert_equal(equipped._name_id, 'g17_crew', 'glock 17 maps to g17_crew')

		henchmen.refresh(gui, selected, equipped, {})

		-- is_pistol: no autofire rounds -> 60 / FALLOFF at 1500 (recoil[2] = 1).
		-- is_rifle: automatic -> 60 / 0.1.
		assert_row(t, gui, 'mws_rof', '60', '', '600', '')
		assert_row(t, gui, 'mws_autorounds', '-', '', '6', ' | 11')
		assert_row(t, gui, 'mws_reload_full', '1.50', '', '1.00', '')
	end)

	t.test('an unknown weapon usage shows the v76 question mark', function()
		local gui = fake_gui()
		local model = unknown_usage_model()

		henchmen.refresh(gui, nil, model, {})

		for _, name in ipairs(BASE_ROW_NAMES) do
			t.assert_equal(cell_text(gui, name, 'a1'), '?', name .. ' a1')
			t.assert_equal(cell_text(gui, name, 'b1'), '', name .. ' b1')
		end

		for _, distance in ipairs(DISTANCES) do
			local key = 'mws_damage_hitchance_' .. distance

			t.assert_equal(cell_text(gui, key, 'a1'), '?', key .. ' a1')
			t.assert_equal(cell_text(gui, key, 'b1'), '', key .. ' b1')
		end
	end)

	t.test('a nil model blanks every cell and never throws', function()
		local gui = fake_gui()

		for _, stat in ipairs(gui.mws_stats_shown) do
			local key = row_key(stat)

			for _, cell_name in ipairs(CELL_NAMES) do
				gui.mws_stats_texts[key][cell_name]:set_text('sentinel')
			end
		end

		henchmen.refresh(gui, nil, nil, {})

		for _, stat in ipairs(gui.mws_stats_shown) do
			local key = row_key(stat)

			for _, cell_name in ipairs(CELL_NAMES) do
				t.assert_equal(cell_text(gui, key, cell_name), '', key .. ' ' .. cell_name)
			end
		end

		henchmen.refresh(nil, nil, nil, nil)
		henchmen.refresh({}, nil, nil, nil)
		henchmen.refresh({ mws_stats_texts = {} }, nil, nil, nil)
	end)

	t.test('a second refresh clears the previous values', function()
		context.invalidate()

		local gui = fake_gui()
		local model = weapon.new_from_slot('new_m4', nil, { npc = true })

		henchmen.refresh(gui, model, model, {})
		t.assert_equal(cell_text(gui, 'mws_rof', 'a1'), '600', 'populated before the second refresh')

		gui.mws_stats_texts.mws_rof.a1:set_text('stale')
		gui.mws_stats_texts.mws_damage_hitchance_4000.a1:set_text('stale')

		henchmen.refresh(gui, nil, nil, {})

		for _, stat in ipairs(gui.mws_stats_shown) do
			local key = row_key(stat)

			for _, cell_name in ipairs(CELL_NAMES) do
				t.assert_equal(cell_text(gui, key, cell_name), '', 'stale ' .. key .. ' ' .. cell_name)
			end
		end
	end)

	t.test('a saw model keeps the spread row blank', function()
		context.invalidate()

		local gui = fake_gui()
		local model = weapon.new_from_slot('new_m4', nil, { npc = true })
		local saw = {
			_damage = 1,
			weapon_tweak_data = function()
				return {usage = 'is_rifle'}
			end,
			is_category = function(_, category)
				return category == 'saw'
			end,
		}

		henchmen.refresh(gui, model, saw, {})

		t.assert_equal(cell_text(gui, 'mws_spread', 'a1'), '', 'saw spread stays blank')
		t.assert_equal(cell_text(gui, 'mws_spread', 'a2'), '25', 'selected spread still shown')
	end)
end
