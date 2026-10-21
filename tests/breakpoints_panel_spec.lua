--[[
tests/breakpoints_panel_spec.lua — the breakpoint table adapter (Task 6a).

Covers the UI seam that moved out of the v76 breakpoint and difficulty-picker
adapter code:
	* refresh() fills the damage/hit cells from a real fixture model and the
	  per-difficulty multipliers, with fill_breakpoints on and off;
	* a bonus toggle changes the table, and a bonus whose skill is not owned
	  stays off and cannot be clicked;
	* selecting another display difficulty changes the table while
	  Global.game_settings.difficulty and tweak_data.character health stay
	  untouched;
	* an empty or locked slot hides the panel, a nil model leaves '-' cells;
	* a second refresh blanks every cell before filling (no stale values);
	* multiplayer keeps the picker read-only and follows the game difficulty;
	* a toggled bonus survives a Black Market rebuild (the v76 class-level seed);
	* explosion breakpoints follow the conservative blocked path (no modifier
	  answer, a throwing modify_value, an active crime spree);
	* a throwing render is logged and leaves a blank panel instead of escaping;
	* a cell that throws during the fill and again during the recovery clear
	  cannot escape `refresh` either.

Expected numbers are the breakpoint values the v76 panel produced, recalculated
from the real 248.2 tweak data in tests/fixtures.lua (CAR-4, no upgrade values,
crit chance 0 and full health so the berserker term is 1):
	normal:      54.69 / 58.60 / 59.77 / 62.50 / 65.63   (swat 2/2/2/2/2)
	overkill:    58.60 / 59.77 / 60.94 / 62.50 / 63.75   (swat 3 hits)
	overkill_290:59.07 / 59.54 / 59.77 / 63.29 / 63.75   (swat 8 hits)
	headshot:    49.22 / 49.81 / 57.04 / 66.41 / 74.71   (swat 1 hit)
]]

local fixtures = dofile(ModPath .. 'tests/fixtures.lua')

-- Same rule as stats_panel_spec: do not re-install an earlier spec's tweak
-- table, so character-table mutations in breakpoints_spec keep working.
if rawget(_G, 'tweak_data') == nil then
	fixtures.install()
end

local breakpoints_panel = MoreWeaponStats.ui.breakpoints_panel
local breakpoints = MoreWeaponStats.core.breakpoints
local context = MoreWeaponStats.core.context
local weapon = MoreWeaponStats.core.weapon
local settings = MoreWeaponStats.settings

local UNIT_TYPES = breakpoints.unit_types
local ROWS = 5

-- Declared before the fakes so fake_gui can seed a default toggle state; the
-- definition sits with the other fixtures below.
local bonus_state

-- The runner defines Color(r, g, b, a) as a function; ui/breakpoints_panel falls
-- back to that constructor when the menu's named colours are absent, so the
-- specs do not need Color.white/yellow/black.

-- Fakes ----------------------------------------------------------------------

local function new_text(name)
	local text = {
		_name = name,
		_text = '?',
		_alpha = 1,
		_inside = false,
	}

	function text:set_text(value)
		self._text = value
	end

	function text:set_color(color)
		self._color = color
	end

	function text:set_alpha(alpha)
		self._alpha = alpha
	end

	function text:alpha()
		return self._alpha
	end

	function text:name()
		return self._name
	end

	function text:inside()
		return self._inside
	end

	return text
end

local function new_panel()
	local panel = {
		_children = {},
		_visible = true,
	}

	function panel:child(name)
		return self._children[name]
	end

	function panel:show()
		self._visible = true
	end

	function panel:hide()
		self._visible = false
	end

	function panel:visible()
		return self._visible
	end

	function panel:inside()
		return true
	end

	return panel
end

local function new_picker(difficulty, can_set)
	local picker = {
		can_set_difficulty = can_set ~= false,
		difficulty = difficulty or 'normal',
		panel = new_panel(),
		difficulty_bitmaps = {},
	}

	picker.difficulty_rank = breakpoints_panel.difficulty_rank(picker.difficulty)

	for index = 2, 7 do
		picker.difficulty_bitmaps[index] = new_text(breakpoints_panel.risks[index])
	end

	return picker
end

local function fake_gui(options)
	options = options or {}

	local gui = {
		_slot_data = options.slot_data or {
			name = 'new_m4',
			category = 'primaries',
			slot = 1,
			unlocked = true,
		},
		mws_bp_panel = new_panel(),
		mws_bp_damage = {},
		mws_bp_bullet = {},
		mws_bp_skill_bitmaps = options.bitmaps or {},
		mws_difficulty_picker = options.picker or new_picker(),
		mws_bonuses = options.bonuses or bonus_state(),
	}

	-- A rebuilt gui has no bonus table of its own (init seeds it); the refresh
	-- path must fall back to the module's session seed.
	if options.rebuilt then
		gui.mws_bonuses = nil
	end

	local rows = options.rows or ROWS

	for index = 1, rows do
		local damage = new_text('mws_bp_damage_' .. index)
		gui.mws_bp_damage[index] = damage
		gui.mws_bp_panel._children[damage._name] = damage

		for _, unit_type in ipairs(UNIT_TYPES) do
			local name = 'mws_bp_bullet_' .. index .. '_' .. unit_type
			local hit = new_text(name)
			gui.mws_bp_bullet[#gui.mws_bp_bullet + 1] = hit
			gui.mws_bp_panel._children[name] = hit
		end
	end

	if options.model ~= false then
		gui._model = options.model
	end

	function gui:mws_get_wbase_from_slot()
		return self._model
	end

	return gui
end

local function cell_text(gui, index, unit_type)
	local cell = gui.mws_bp_panel:child('mws_bp_bullet_' .. index .. '_' .. unit_type)
	return tostring(cell._text)
end

local function damage_text(gui, index)
	return tostring(gui.mws_bp_damage[index]._text)
end

--[[
Bonus state with every toggle available and unchecked (the tests switch the
ones they exercise); mirrors what a previous refresh would have left on the gui.
]]
function bonus_state(overrides)
	local state = {}

	for name, bonus in pairs(breakpoints.bonuses) do
		state[name] = {
			index = bonus.index,
			required_level = bonus.required_level,
			checked_by_default = bonus.checked_by_default,
			level = fixtures.skills[name] or 0,
			available = true,
			checked = false,
		}
	end

	for name, value in pairs(overrides or {}) do
		state[name].checked = value
	end

	return state
end

local function skills_with(skill_id, level)
	local skills = {}

	for id, value in pairs(fixtures.skills) do
		skills[id] = value
	end

	skills[skill_id] = level

	return skills
end

-- PlayerManager + SkillTreeManager stand-in: the skills decide bonus
-- availability, every upgrade falls back to its default (no aced bonuses).
local function managers_stub(options)
	options = options or {}

	local skills = options.skills or fixtures.skills
	local skill_entries = {}

	for skill_id, level in pairs(skills) do
		skill_entries[skill_id] = { unlocked = level, total = 5 }
	end

	return {
		player = {
			upgrade_value = function(_, category, upgrade, default)
				return default
			end,
			critical_hit_chance = function()
				return 0
			end,
			get_damage_health_ratio = function()
				return 0
			end,
		},
		skilltree = {
			_global = { skills = skill_entries },
		},
		modifiers = options.modifiers,
		crime_spree = options.crime_spree,
	}
end

-- Runs fn with a stubbed managers table, restoring the global and dropping the
-- context snapshot even when the case fails.
local function with_managers(options, fn)
	local previous = rawget(_G, 'managers')
	_G.managers = managers_stub(options)

	local ok, err = pcall(fn)

	_G.managers = previous
	context.invalidate()

	if not ok then
		error(err, 0)
	end
end

local function with_global(name, value, fn)
	local previous = rawget(_G, name)
	_G[name] = value

	local ok, err = pcall(fn)

	_G[name] = previous

	if not ok then
		error(err, 0)
	end
end

-- Settings field with restore-on-error.
local function with_setting(key, value, fn)
	local previous = settings[key]
	settings[key] = value

	local ok, err = pcall(fn)

	settings[key] = previous

	if not ok then
		error(err, 0)
	end
end

-- Renders one weapon through the panel: fresh context, fresh fake gui.
local function render(options)
	options = options or {}

	context.invalidate()

	local ctx = context.get({ skills = options.skills or fixtures.skills })
	local gui = fake_gui(options)

	if options.model == nil then
		gui._model = weapon.new('new_m4', nil, ctx)
	end

	return gui, ctx
end

return function(t)
	t.test('refresh fills damage and hit cells from the fixture model', function()
		with_managers({}, function()
			local gui, ctx = render()

			breakpoints_panel.refresh(gui, ctx)

			t.assert_equal(damage_text(gui, 1), '54.69', 'row 1 damage')
			t.assert_equal(damage_text(gui, 2), '58.60', 'row 2 damage')
			t.assert_equal(damage_text(gui, 3), '59.77', 'row 3 damage')
			t.assert_equal(damage_text(gui, 4), '62.50', 'row 4 damage')
			t.assert_equal(damage_text(gui, 5), '65.63', 'row 5 damage')

			t.assert_equal(cell_text(gui, 1, 'swat'), '2', 'row 1 swat')
			t.assert_equal(cell_text(gui, 1, 'heavy_swat'), '3', 'row 1 heavy swat')
			t.assert_equal(cell_text(gui, 1, 'sniper'), '1', 'row 1 sniper')
			t.assert_equal(cell_text(gui, 1, 'taser'), '6', 'row 1 taser')
			t.assert_equal(cell_text(gui, 1, 'spooc'), '11', 'row 1 cloaker')
			t.assert_equal(cell_text(gui, 1, 'tank'), '35', 'row 1 bulldozer')
			t.assert_equal(cell_text(gui, 3, 'taser'), '5', 'row 3 taser')
			-- fill_breakpoints carries the previous hit count into the cells a
			-- unit does not reach at this damage value.
			t.assert_equal(cell_text(gui, 3, 'tank'), '32', 'row 3 bulldozer inherited')

			t.assert_equal(#gui.mws_breakpoints, 5, 'consolidated rows')
			t.assert_equal(gui.mws_bp_panel:visible(), true, 'panel shown for a real slot')
			t.assert_true(math.abs(gui.mws_bp_current_damage - 62) < 1e-9, 'CAR-4 damage in table units')
			t.assert_true(math.abs(gui.mws_bp_ref_damage - 59.77) < 1e-9, 'reached breakpoint')
		end)
	end)

	t.test('a bonus toggle changes the table and survives a refresh', function()
		with_managers({}, function()
			local bitmap = new_text('prison_wife')
			bitmap._inside = true

			local gui, ctx = render({ bitmaps = { [1] = bitmap } })

			breakpoints_panel.refresh(gui, ctx)
			t.assert_equal(damage_text(gui, 1), '54.69', 'headshot off')
			t.assert_equal(gui.mws_bonuses.prison_wife.checked, false, 'toggle starts unchecked')

			t.assert_true(breakpoints_panel.bonus_at(gui, 10, 10) == bitmap, 'toggle under the cursor')
			breakpoints_panel.click_bonus(gui, bitmap)
			t.assert_equal(bitmap:alpha(), breakpoints_panel.mws_alpha_enabled, 'toggle drawn as checked')

			breakpoints_panel.refresh(gui, ctx)
			t.assert_equal(gui.mws_bonuses.prison_wife.checked, true, 'checked state survives the refresh')
			t.assert_equal(damage_text(gui, 1), '49.22', 'headshot table')

			breakpoints_panel.click_bonus(gui, bitmap)
			breakpoints_panel.refresh(gui, ctx)
			t.assert_equal(damage_text(gui, 1), '54.69', 'headshot off again')
		end)
	end)

	t.test('a bonus whose skill is not owned stays off', function()
		local skills = skills_with('backstab', 0)

		with_managers({ skills = skills }, function()
			local bitmap = new_text('backstab')
			bitmap._inside = true

			local gui, ctx = render({
				skills = skills,
				bonuses = bonus_state({ backstab = true }),
				bitmaps = { [6] = bitmap },
			})

			breakpoints_panel.refresh(gui, ctx)

			t.assert_equal(gui.mws_bonuses.backstab.available, false, 'skill locked')
			t.assert_equal(gui.mws_bonuses.backstab.checked, false, 'toggle forced off')
			t.assert_equal(bitmap:alpha(), breakpoints_panel.mws_alpha_unavailable, 'toggle dimmed')
			t.assert_nil(breakpoints_panel.bonus_at(gui, 10, 10), 'locked toggle is not clickable')
		end)
	end)

	t.test('fill_breakpoints on and off changes the inherited cells', function()
		with_managers({}, function()
			with_setting('fill_breakpoints', true, function()
				local gui, ctx = render()
				breakpoints_panel.refresh(gui, ctx)
				t.assert_equal(cell_text(gui, 1, 'swat'), '2', 'inherited hit count')
			end)

			with_setting('fill_breakpoints', false, function()
				local gui, ctx = render()
				breakpoints_panel.refresh(gui, ctx)
				t.assert_equal(cell_text(gui, 1, 'swat'), '-', 'no inherited hit count')
				t.assert_equal(cell_text(gui, 1, 'tank'), '35', 'bulldozer still draws')
			end)
		end)
	end)

	t.test('the difficulty picker previews without touching the game difficulty', function()
		with_global('Global', { game_settings = { difficulty = 'hard' } }, function()
			with_managers({}, function()
				with_setting('last_used_difficulty', 'normal', function()
					local swat_health = fixtures.tweak_data.character.swat.HEALTH_INIT
					local revive_steps = fixtures.tweak_data.player.damage.REVIVE_HEALTH_STEPS
					local gui, ctx = render({ picker = new_picker('normal') })

					breakpoints_panel.refresh(gui, ctx)
					t.assert_equal(damage_text(gui, 1), '54.69', 'normal table')
					t.assert_equal(cell_text(gui, 1, 'swat'), '2', 'normal swat hits')

					breakpoints_panel.set_difficulty(gui, 'overkill')
					breakpoints_panel.refresh(gui, ctx)
					t.assert_equal(damage_text(gui, 1), '58.60', 'overkill table')
					t.assert_equal(cell_text(gui, 1, 'swat'), '3', 'overkill swat hits')

					breakpoints_panel.set_difficulty(gui, 'overkill_290')
					breakpoints_panel.refresh(gui, ctx)
					t.assert_equal(damage_text(gui, 1), '59.07', 'death sentence table')
					t.assert_equal(cell_text(gui, 1, 'swat'), '8', 'death sentence swat hits')

					local difficulty, rank = breakpoints_panel.get_difficulty(gui)
					t.assert_equal(difficulty, 'overkill_290', 'displayed difficulty')
					t.assert_equal(rank, 7, 'displayed difficulty rank')
					t.assert_equal(settings.last_used_difficulty, 'overkill_290', 'last used persisted')

					local global = rawget(_G, 'Global')
					t.assert_equal(global.game_settings.difficulty, 'hard', 'game difficulty untouched')
					t.assert_equal(fixtures.tweak_data.character.swat.HEALTH_INIT, swat_health, 'enemy health untouched')
					t.assert_equal(fixtures.tweak_data.player.damage.REVIVE_HEALTH_STEPS, revive_steps, 'player tweak data untouched')

					-- Risk icons follow the selection: rank 7 lights icons 2..6.
					local picker = gui.mws_difficulty_picker
					t.assert_equal(picker.difficulty_bitmaps[2]:alpha(), 1, 'first risk icon active')
					t.assert_equal(picker.difficulty_bitmaps[7]:alpha(), 0.25, 'last risk icon inactive')
				end)
			end)
		end)
	end)

	t.test('clicking the displayed difficulty icon steps one rank down (v76 quirk)', function()
		with_managers({}, function()
			with_setting('last_used_difficulty', 'overkill', function()
				local gui = fake_gui({ picker = new_picker('overkill') })

				gui.mws_difficulty_picker.difficulty_bitmaps[3]._inside = true
				t.assert_equal(breakpoints_panel.difficulty_at(gui, 10, 10), 4, 'icon 3 selects rank 4')

				local difficulty, rank = breakpoints_panel.set_difficulty(gui, 'overkill', true)
				t.assert_equal(rank, 3, 'same icon steps down')
				t.assert_equal(difficulty, 'hard', 'one rank lower')
				t.assert_equal(settings.last_used_difficulty, 'hard', 'persisted')
			end)
		end)
	end)

	t.test('multiplayer keeps the picker read-only and follows the game', function()
		with_global('Global', { game_settings = { difficulty = 'overkill' } }, function()
			with_managers({}, function()
				with_setting('last_used_difficulty', 'normal', function()
					local gui, ctx = render({ picker = new_picker('normal', false) })

					local difficulty, rank = breakpoints_panel.get_difficulty(gui)
					t.assert_equal(difficulty, 'overkill', 'game difficulty')
					t.assert_equal(rank, 4, 'game difficulty rank')

					breakpoints_panel.refresh(gui, ctx)
					t.assert_equal(damage_text(gui, 1), '58.60', 'overkill table in multiplayer')

					local selected, selected_rank = breakpoints_panel.set_difficulty(gui, 'sm_wish')
					t.assert_equal(selected, 'overkill', 'selection ignored')
					t.assert_equal(selected_rank, 4, 'rank unchanged')
					t.assert_equal(settings.last_used_difficulty, 'normal', 'setting untouched')
					t.assert_nil(breakpoints_panel.difficulty_at(gui, 10, 10), 'no clickable icons')
				end)
			end)
		end)
	end)

	t.test('empty and locked slots hide the panel, a nil model draws nothing', function()
		with_managers({}, function()
			context.invalidate()
			local ctx = context.get({ skills = fixtures.skills })

			local empty = fake_gui({ slot_data = { empty_slot = true, unlocked = true } })
			breakpoints_panel.refresh(empty, ctx)
			t.assert_equal(empty.mws_bp_panel:visible(), false, 'empty slot hides the panel')

			local locked = fake_gui({ slot_data = { unlocked = false } })
			breakpoints_panel.refresh(locked, ctx)
			t.assert_equal(locked.mws_bp_panel:visible(), false, 'locked slot hides the panel')

			local no_model = fake_gui({ model = false })
			breakpoints_panel.refresh(no_model, ctx)
			t.assert_equal(no_model.mws_bp_panel:visible(), true, 'panel stays for a weapon slot')
			t.assert_equal(damage_text(no_model, 1), '-', 'no damage without a model')
			t.assert_equal(cell_text(no_model, 1, 'swat'), '-', 'no hit count without a model')
			t.assert_nil(no_model.mws_bp_current_damage, 'no current damage')

			-- No slot data at all: v76 returned without touching the panel.
			local no_slot = fake_gui()
			no_slot._slot_data = nil
			breakpoints_panel.refresh(no_slot, ctx)
			t.assert_equal(damage_text(no_slot, 1), '?', 'panel untouched without slot data')

			breakpoints_panel.refresh(nil, nil)
			breakpoints_panel.clear(nil)
			breakpoints_panel.clear({})
		end)
	end)

	t.test('a second refresh clears the cells a longer table left behind', function()
		with_managers({}, function()
			local gui, ctx = render()
			breakpoints_panel.refresh(gui, ctx)
			t.assert_equal(damage_text(gui, 5), '65.63', 'populated before the second refresh')

			for _, cell in pairs(gui.mws_bp_damage) do
				cell:set_text('stale')
			end

			for _, cell in pairs(gui.mws_bp_bullet) do
				cell:set_text('stale')
			end

			with_setting('fill_breakpoints', false, function()
				breakpoints_panel.refresh(gui, ctx)
				t.assert_equal(cell_text(gui, 1, 'swat'), '-', 'stale hit cell cleared')
				t.assert_equal(cell_text(gui, 1, 'tank'), '35', 'reachable cell refilled')
				t.assert_equal(damage_text(gui, 1), '54.69', 'damage cell refilled')
			end)
		end)
	end)

	t.test('a toggled bonus survives a Black Market rebuild', function()
		with_managers({}, function()
			-- underdog defaults to off and changes every unit's breakpoints.
			local bitmap = new_text('underdog')
			bitmap._inside = true

			local first, first_ctx = render({ bitmaps = { [3] = bitmap } })
			breakpoints_panel.refresh(first, first_ctx)

			local default_text = damage_text(first, 1)
			t.assert_equal(default_text, '54.69', 'table before the toggle')

			breakpoints_panel.click_bonus(first, bitmap)
			breakpoints_panel.refresh(first, first_ctx)

			local toggled_text = damage_text(first, 1)

			t.assert_equal(first.mws_bonuses.underdog.checked, true, 'toggle on in the first gui')
			t.assert_true(toggled_text ~= default_text, 'toggle changes the table')

			-- Reopening the Black Market builds a new gui without a bonus table of
			-- its own; v76 kept the table on the class, so the choice came back.
			local rebuilt_bitmap = new_text('underdog')
			rebuilt_bitmap._inside = true

			local rebuilt, rebuilt_ctx = render({ rebuilt = true, bitmaps = { [3] = rebuilt_bitmap } })
			t.assert_nil(rebuilt.mws_bonuses, 'rebuilt gui starts without a bonus table')

			breakpoints_panel.refresh(rebuilt, rebuilt_ctx)

			t.assert_equal(rebuilt.mws_bonuses.underdog.checked, true, 'checked state seeded from the session')
			t.assert_equal(damage_text(rebuilt, 1), toggled_text, 'same table after the rebuild')

			-- A toggle set on the rebuilt gui is the new session state.
			breakpoints_panel.set_bonus_state(rebuilt, 'underdog', false)

			local third, third_ctx = render({ rebuilt = true })
			breakpoints_panel.refresh(third, third_ctx)
			t.assert_equal(third.mws_bonuses.underdog.checked, false, 'cleared state survives the next rebuild')
			t.assert_equal(damage_text(third, 1), default_text, 'default table after the rebuild')
		end)
	end)

	t.test('explosion breakpoints use the conservative blocked path', function()
		context.invalidate()

		local function explosive_gui(options)
			local gui, ctx = render(options)
			gui._model = weapon.new('judge', fixtures.blueprints.judge_explosive, ctx)

			return gui, ctx
		end

		-- No modifiers manager at all: v76's query cannot answer, so explosion
		-- rows are hidden instead of promising damage a mutator can zero.
		with_managers({}, function()
			local gui, ctx = explosive_gui()
			breakpoints_panel.refresh(gui, ctx)
			t.assert_equal(damage_text(gui, 1), '-', 'hidden without a modifier answer')
			t.assert_equal(gui.mws_bp_ref_damage, -1, 'no breakpoint reached')
		end)

		-- A throwing modify_value is the same "cannot answer" case.
		with_managers({
			modifiers = {
				modify_value = function()
					error('modifier exploded')
				end,
			},
		}, function()
			local gui, ctx = explosive_gui()
			breakpoints_panel.refresh(gui, ctx)
			t.assert_equal(damage_text(gui, 1), '-', 'hidden when the query throws')
		end)

		-- A real answer that keeps explosion damage draws the table.
		with_managers({
			modifiers = {
				modify_value = function(_, name, value)
					return value
				end,
			},
		}, function()
			local gui, ctx = explosive_gui()
			breakpoints_panel.refresh(gui, ctx)
			t.assert_true(damage_text(gui, 1) ~= '-', 'drawn when modifiers keep explosion damage')
			t.assert_true(gui.mws_bp_ref_damage > 0, 'breakpoint reached')
		end)

		-- An active crime spree is conservative-blocked even when the modifiers
		-- table answers (v76 primed managers.crime_spree:_setup_modifiers first).
		with_managers({
			crime_spree = {
				is_active = function()
					return true
				end,
			},
			modifiers = {
				modify_value = function(_, name, value)
					return value
				end,
			},
		}, function()
			local gui, ctx = explosive_gui()
			breakpoints_panel.refresh(gui, ctx)
			t.assert_equal(damage_text(gui, 1), '-', 'hidden during an active crime spree')
		end)
	end)

	t.test('a throwing render leaves a blank panel instead of escaping the menu', function()
		with_managers({}, function()
			context.invalidate()

			local ctx = context.get({ skills = fixtures.skills })
			local gui = fake_gui()

			gui.mws_get_wbase_from_slot = function()
				error('engine callback exploded')
			end

			local logged = {}

			with_global('log', function(message)
				logged[#logged + 1] = message
			end, function()
				breakpoints_panel.refresh(gui, ctx)
			end)

			t.assert_equal(damage_text(gui, 1), '-', 'panel blanked after the failure')
			t.assert_nil(gui.mws_bp_current_damage, 'no damage value after the failure')
			t.assert_true(#logged >= 1, 'failure logged')
			t.assert_true(tostring(logged[1]):find('breakpoints_panel refresh', 1, true) ~= nil, 'log names the panel refresh')
		end)
	end)

	t.test('a throwing cell cannot escape refresh through the recovery clear', function()
		with_managers({}, function()
			local gui, ctx = render()
			local cell = gui.mws_bp_panel:child('mws_bp_bullet_1_swat')
			local calls = 0

			-- First call (the pre-fill clear) works, the fill throws, and the
			-- recovery clear hits the same cell again.
			cell.set_text = function(self, value)
				calls = calls + 1

				if calls >= 2 then
					error('cell set_text exploded')
				end

				self._text = value
			end

			local logged = {}
			local ok, err = pcall(function()
				with_global('log', function(message)
					logged[#logged + 1] = message
				end, function()
					breakpoints_panel.refresh(gui, ctx)
				end)
			end)

			t.assert_true(ok, 'refresh returned without throwing: ' .. tostring(err))
			t.assert_true(calls >= 3, 'cell threw during the fill and again during the recovery clear')

			local refresh_logged, clear_logged = false, false

			for _, message in ipairs(logged) do
				if tostring(message):find('breakpoints_panel refresh', 1, true) then
					refresh_logged = true
				end

				if tostring(message):find('breakpoints_panel clear', 1, true) then
					clear_logged = true
				end
			end

			t.assert_true(refresh_logged, 'render failure logged')
			t.assert_true(clear_logged, 'recovery clear failure logged')
		end)
	end)
end
