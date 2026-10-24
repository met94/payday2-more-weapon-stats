--[[
tests/melee_spec.lua — the melee stat rows (Task 6b).

Covers the adapter seam that moved out of blackmarketgui.lua:
	* rows() returns the five v76 melee rows in display order;
	* refresh() fills the left column from the equipped melee weapon and the
	  right column from the selected slot, with the v76 formats;
	* a melee weapon without melee_damage_delay shows 0.00s (v76 fallback);
	* the tase branch fills both the special and the DoT length rows;
	* a nil model or an unknown melee id blanks the row instead of raising;
	* a second refresh clears the values the previous pair left behind;
	* the melee tweak entry is read through
	  BlackMarketManager:get_melee_weapon_data when the manager exists.

Expected strings are the v76 panel output, calculated from the real 248.2
melee tweak data copied into tests/fixtures.lua (kabar, fists, taser, the bare
melee weapon).
]]

local fixtures = dofile(ModPath .. 'tests/fixtures.lua')

-- Same rule as the other specs: do not re-install a tweak table an earlier spec
-- installed and mutates.
if rawget(_G, 'tweak_data') == nil then
	fixtures.install()
end

local melee = MoreWeaponStats.ui.melee

local ROW_NAMES = {
	'mws_attack_delay',
	'mws_cooldown',
	'mws_unequip_delay',
	'mws_special',
	'mws_dot_length',
}

local CELL_NAMES = { 'a1', 'a2' }

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

	gui.mws_stats_shown = melee.rows(gui)

	return gui
end

local function cell_text(gui, stat_name, cell_name)
	return gui.mws_stats_texts[stat_name][cell_name].text
end

local function assert_row(t, gui, stat_name, a1, a2)
	t.assert_equal(cell_text(gui, stat_name, 'a1'), a1, stat_name .. ' a1 (equipped)')
	t.assert_equal(cell_text(gui, stat_name, 'a2'), a2, stat_name .. ' a2 (selected)')
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

return function(t)
	t.test('melee.rows returns the five v76 rows in order', function()
		local rows = melee.rows({})

		t.assert_equal(#rows, #ROW_NAMES, 'row count')

		for index, name in ipairs(ROW_NAMES) do
			t.assert_equal(rows[index].name, name, 'row ' .. index)
		end
	end)

	t.test('refresh fills the equipped and selected melee values', function()
		local gui = fake_gui()

		-- kabar (:70-82) equipped, taser (:1387-1424) selected.
		melee.refresh(gui, { _name_id = 'taser' }, { _name_id = 'kabar' }, {})

		assert_row(t, gui, 'mws_attack_delay', '0.10s', '0.10s')
		assert_row(t, gui, 'mws_cooldown', '0.60s', '0.70s')
		assert_row(t, gui, 'mws_unequip_delay', '1.20s', '1.00s')
		assert_row(t, gui, 'mws_special', '', 'tase')
		assert_row(t, gui, 'mws_dot_length', '', 'light')
	end)

	t.test('a melee entry without melee_damage_delay shows the v76 0.00s', function()
		local gui = fake_gui()

		-- weapon (:18-19) and fists (:45-47).
		melee.refresh(gui, { _name_id = 'fists' }, { _name_id = 'weapon' }, {})

		assert_row(t, gui, 'mws_attack_delay', '0.00s', '0.20s')
		assert_row(t, gui, 'mws_cooldown', '0.60s', '0.55s')
		assert_row(t, gui, 'mws_unequip_delay', '0.60s', '1.00s')
		assert_row(t, gui, 'mws_special', '', '')
		assert_row(t, gui, 'mws_dot_length', '', '')
	end)

	t.test('a nil model or an unknown melee id blanks the row', function()
		local gui = fake_gui()

		melee.refresh(gui, { _name_id = 'taser' }, { _name_id = 'kabar' }, {})

		melee.refresh(gui, nil, { _name_id = 'not_a_melee_weapon' }, {})

		for _, name in ipairs(ROW_NAMES) do
			assert_row(t, gui, name, '', '')
		end

		melee.refresh(nil, nil, nil, nil)
		melee.refresh({}, nil, nil, nil)
		melee.refresh({ mws_stats_texts = {} }, nil, nil, nil)
	end)

	t.test('a second refresh clears the previous values', function()
		local gui = fake_gui()

		melee.refresh(gui, { _name_id = 'taser' }, { _name_id = 'kabar' }, {})
		t.assert_equal(cell_text(gui, 'mws_special', 'a2'), 'tase', 'populated before the second refresh')

		melee.refresh(gui, { _name_id = 'fists' }, nil, {})

		assert_row(t, gui, 'mws_attack_delay', '', '0.20s')
		assert_row(t, gui, 'mws_cooldown', '', '0.55s')
		assert_row(t, gui, 'mws_unequip_delay', '', '1.00s')
		assert_row(t, gui, 'mws_special', '', '')
		assert_row(t, gui, 'mws_dot_length', '', '')
	end)

	t.test('the melee tweak entry is read through the Black Market manager', function()
		local gui = fake_gui()
		local calls = {}

		with_globals({
			managers = {
				blackmarket = {
					get_melee_weapon_data = function(_, weapon_id)
						calls[#calls + 1] = weapon_id
						return {
							melee_damage_delay = 0.5,
							repeat_expire_t = 1.5,
							expire_t = 2.5,
							special_weapon = 'chainsaw',
						}
					end,
				},
			},
		}, function()
			melee.refresh(gui, { _name_id = 'taser' }, { _name_id = 'kabar' }, {})
		end)

		t.assert_equal(#calls, 2, 'one lookup per model')
		t.assert_equal(calls[1], 'taser', 'selected lookup')
		t.assert_equal(calls[2], 'kabar', 'equipped lookup')

		assert_row(t, gui, 'mws_attack_delay', '0.50s', '0.50s')
		assert_row(t, gui, 'mws_cooldown', '1.50s', '1.50s')
		assert_row(t, gui, 'mws_unequip_delay', '2.50s', '2.50s')
		assert_row(t, gui, 'mws_special', 'chainsaw', 'chainsaw')
	end)
end
