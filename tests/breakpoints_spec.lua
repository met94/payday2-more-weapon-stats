--[[
tests/breakpoints_spec.lua — breakpoint table tests for the clean rewrite.

Every expected value is derived by hand from the real 248.2 data copied into
tests/fixtures.lua, following the formulas documented in
lua/core/breakpoints.lua:

	health        = HEALTH_INIT * difficulty health multiplier * 10
	health_step   = health / 512                       (CopDamage granularity)
	headshot      = passive_headshot_damage_multiplier * headshot_dmg_mul
	body expert.  = 1 + automatic_head_shot_add * (headshot_dmg_mul - 1)
	crit          = ceil(i * crit_chance) extra hits at (crit_mul - 1)
	trigger happy = boosted shots at (damage_bonus - 1), max_time / shoot_interval
	bonus_mul     = headshot * hitman * underdog * overkill * berserker
	bp(i)         = ceil(health / i / step) * step [- step when no bonus] / bonus_mul

The enemy health multipliers come from CharacterTweakData:_multiply_all_hp
(charactertweakdata.lua:11014, :11033, :11959, :12207, :12456, :12649, :12815,
:13273) and the sm_wish tank override (:13291).
]]

local fixtures = dofile(ModPath .. 'tests/fixtures.lua')

fixtures.install()

local context = MoreWeaponStats.core.context
local weapon = MoreWeaponStats.core.weapon
local breakpoints = MoreWeaponStats.core.breakpoints

local EPSILON = 1e-9

local function assert_near(t, actual, expected, message)
	t.assert_type(actual, 'number', message .. ' (type)')
	t.assert_true(math.abs(actual - expected) <= EPSILON, ('%s: expected %.6f, got %.6f'):format(message, expected, actual))
end

-- Runs fn with a stubbed managers table, restoring the previous global even on
-- failure, so a broken case cannot poison the rest of the suite.
local function with_managers(stub, fn)
	local previous = rawget(_G, 'managers')
	_G.managers = stub
	local ok, err = pcall(fn)
	_G.managers = previous
	context.invalidate()

	if not ok then
		error(err, 0)
	end
end

local function fresh_context(overrides)
	context.invalidate()

	return context.get(overrides)
end

-- Runs fn with a global replaced, restoring the previous value even on failure,
-- so a failed assertion cannot leak a stub into the rest of the suite.
local function with_global(name, value, fn)
	local previous = rawget(_G, name)
	_G[name] = value
	local ok, err = pcall(fn)
	_G[name] = previous

	if not ok then
		error(err, 0)
	end
end

-- Same idea for one field of a tweak_data.character unit: save, set, restore.
local function with_character_field(unit_type, field, value, fn)
	local character = fixtures.tweak_data.character[unit_type]
	local previous = character[field]
	local had_field = character[field] ~= nil

	character[field] = value

	local ok, err = pcall(fn)

	if had_field then
		character[field] = previous
	else
		character[field] = nil
	end

	if not ok then
		error(err, 0)
	end
end

-- Same idea for a whole tweak_data.character entry (nil removes the unit).
local function with_character_unit(unit_type, value, fn)
	local character = fixtures.tweak_data.character
	local previous = character[unit_type]

	character[unit_type] = value

	local ok, err = pcall(fn)

	character[unit_type] = previous

	if not ok then
		error(err, 0)
	end
end

--[[
PlayerManager stand-in. `values` is category -> upgrade -> value; everything it
does not answer falls back to the caller's default, like PlayerManager does.
`critical_hit_chance` and `get_damage_health_ratio` mirror the manager methods
the breakpoint maths asks the context for (playermanager.lua:2742, :5409).
]]
local function managers_stub(options)
	options = options or {}

	local values = options.values or {}
	local skills = options.skills or fixtures.skills
	local threshold = fixtures.tweak_data.upgrades.player_damage_health_ratio_threshold

	local skill_entries = {}

	for skill_id, level in pairs(skills) do
		skill_entries[skill_id] = {unlocked = level, total = 5}
	end

	return {
		player = {
			upgrade_value = function(_, category, upgrade, default)
				local category_values = values[category]

				if category_values and category_values[upgrade] ~= nil then
					return category_values[upgrade]
				end

				return default
			end,
			critical_hit_chance = function()
				return options.critical_hit_chance or 0
			end,
			get_damage_health_ratio = function(_, health_ratio, category)
				if options.damage_health_ratio ~= nil then
					return options.damage_health_ratio
				end

				local category_threshold = threshold

				if category then
					local player_values = values.player
					local multiplier = player_values and player_values[category .. '_damage_health_ratio_threshold_multiplier'] or 1

					category_threshold = category_threshold * multiplier
				end

				return math.max(1 - health_ratio / math.max(0.01, category_threshold), 0)
			end,
		},
		skilltree = {
			_global = {skills = skill_entries},
		},
	}
end

-- A full bonus state with every toggle available and off; overrides enable the
-- ones a case exercises. `level` follows the skill level the game would report.
local function bonus_state(overrides)
	local state = {}

	for name, bonus in pairs(breakpoints.bonuses) do
		state[name] = {
			index = bonus.index,
			required_level = bonus.required_level,
			checked_by_default = bonus.checked_by_default,
			level = 1,
			available = true,
			checked = false,
		}
	end

	for name, value in pairs(overrides or {}) do
		if type(value) == 'table' then
			state[name] = value
		else
			state[name].checked = value
		end
	end

	return state
end

--[[
Builds a model and its breakpoint params in one call. `opts.weapon_overrides` is
the blueprint, `opts.values` the upgrade values the manager stub answers,
`opts.bonuses` the toggle state, `opts.options` the settings overrides.
]]
local function build(weapon_id, opts)
	opts = opts or {}

	local ctx = opts.context or fresh_context()
	local model = weapon.new(weapon_id, opts.blueprint, ctx)

	return model, breakpoints.prepare_params(model, ctx, opts.bonuses or bonus_state(), opts.options)
end

-- Sorted list of the hit counts a breakpoint table holds.
local function hit_counts(table_)
	local counts = {}

	for hit_nr in pairs(table_) do
		counts[#counts + 1] = hit_nr
	end

	table.sort(counts)

	return counts
end

return function(t)
	t.test('unit types and bonus toggles match v76', function()
		t.assert_equal(#breakpoints.unit_types, 6, 'six unit types')
		t.assert_equal(breakpoints.unit_types[1], 'swat', 'first unit type')
		t.assert_equal(breakpoints.unit_types[6], 'tank', 'last unit type')

		local expected = {
			prison_wife = {1, 0, true},
			hitman = {2, 1, false},
			underdog = {3, 1, false},
			overkill = {4, 1, false},
			body_expertise = {5, 1, true},
			backstab = {6, 1, true},
			trigger_happy = {7, 1, true},
			wolverine = {8, 1, true},
		}

		for name, fields in pairs(expected) do
			local bonus = breakpoints.bonuses[name]

			t.assert_type(bonus, 'table', 'bonus ' .. name)
			t.assert_equal(bonus.index, fields[1], name .. ' index')
			t.assert_equal(bonus.required_level, fields[2], name .. ' required_level')
			t.assert_equal(bonus.checked_by_default, fields[3], name .. ' checked_by_default')
		end
	end)

	t.test('bonus_availability reads skill levels and keeps the player choice', function()
		local skills = {}
		local previous = {}

		for skill_id, level in pairs(fixtures.skills) do
			skills[skill_id] = level
			previous[skill_id] = {checked = level > 0}
		end

		-- hitman at 0: the toggle is unavailable whatever the player picked.
		skills.hitman = 0

		with_managers(managers_stub({skills = skills}), function()
			local ctx = fresh_context()
			local availability = breakpoints.bonus_availability(ctx)

			t.assert_equal(availability.hitman.level, 0, 'hitman level')
			t.assert_equal(availability.hitman.available, false, 'hitman unavailable without the skill')
			t.assert_equal(availability.hitman.checked, false, 'unavailable toggle is forced off')
			t.assert_equal(availability.overkill.level, 2, 'overkill level from the skill snapshot')
			t.assert_equal(availability.overkill.available, true, 'overkill available')
			t.assert_equal(availability.overkill.checked, breakpoints.bonuses.overkill.checked_by_default, 'default check state')

			local explicit = breakpoints.bonus_availability(ctx, {
				overkill = {checked = true},
				hitman = {checked = true},
			})

			t.assert_equal(explicit.overkill.checked, true, 'player choice survives a refresh')
			t.assert_equal(explicit.hitman.checked, false, 'an unavailable toggle ignores the old choice')
		end)

		-- The manager read is a read: the skill table is untouched.
		t.assert_equal(skills.hitman, 0, 'skill levels are not written back')
	end)

	t.test('base breakpoints for four enemy types (normal, no bonuses)', function()
		local _, params = build('amcar')
		local data = breakpoints.get_all(params, 'normal')

		for _, unit_type in ipairs(breakpoints.unit_types) do
			t.assert_type(data[unit_type], 'table', unit_type .. ' table')
		end

		-- swat: 8 * 10 = 80 health, step 80 / 512
		assert_near(t, data.swat[1], 79.85, 'swat one hit')
		assert_near(t, data.swat[2], 39.85, 'swat two hits')
		assert_near(t, data.swat[3], 26.57, 'swat three hits')

		-- heavy_swat: 16 * 10 = 160
		assert_near(t, data.heavy_swat[1], 159.69, 'heavy_swat one hit')

		-- sniper: 4 * 10 = 40
		assert_near(t, data.sniper[1], 39.93, 'sniper one hit')
		assert_near(t, data.sniper[2], 19.93, 'sniper two hits')

		-- tank: 200 * 10 = 2000
		assert_near(t, data.tank[1], 1996.1, 'tank one hit')

		-- The table stops once a hit needs less than a tenth of a damage unit;
		-- swat needs 8 hits, so hits 1..7 are listed.
		t.assert_equal(#hit_counts(data.swat), 7, 'swat hit count')
		t.assert_nil(data.swat[8], 'swat has no eighth breakpoint')
	end)

	t.test('difficulty scales swat, heavy_swat and tank health (no global writes)', function()
		local _, params = build('amcar')

		local easy = breakpoints.get_all(params, 'easy')
		local normal = breakpoints.get_all(params, 'normal')
		local hard = breakpoints.get_all(params, 'hard')
		local overkill = breakpoints.get_all(params, 'overkill')
		local overkill_145 = breakpoints.get_all(params, 'overkill_145')
		local easy_wish = breakpoints.get_all(params, 'easy_wish')
		local death_sentence = breakpoints.get_all(params, 'overkill_290')
		local sm_wish = breakpoints.get_all(params, 'sm_wish')

		-- _multiply_all_hp(1, 1) on easy (:11014), normal (:11033) and hard
		-- (:11959): the police units have the same health on all three.
		assert_near(t, easy.swat[1], 79.85, 'swat easy')
		assert_near(t, normal.swat[1], 79.85, 'swat normal')
		assert_near(t, hard.swat[1], 79.85, 'swat hard')
		-- (2, 2) on overkill (:12207), (3, 3) on overkill_145 (:12456)
		assert_near(t, overkill.swat[1], 159.69, 'swat overkill')
		assert_near(t, overkill_145.swat[1], 239.54, 'swat mayhem')
		-- (6, 2) on easy_wish (:12649), (6, 1.5) on death sentence (:12815)
		assert_near(t, easy_wish.swat[1], 479.07, 'swat death wish')
		assert_near(t, death_sentence.swat[1], 479.07, 'swat death sentence')

		assert_near(t, normal.heavy_swat[1], 159.69, 'heavy_swat normal')
		assert_near(t, overkill_145.heavy_swat[1], 479.07, 'heavy_swat mayhem')
		assert_near(t, death_sentence.heavy_swat[1], 958.13, 'heavy_swat death sentence')

		assert_near(t, normal.tank[1], 1996.1, 'tank normal')
		assert_near(t, overkill_145.tank[1], 5988.29, 'tank mayhem')
		assert_near(t, death_sentence.tank[1], 11976.57, 'tank death sentence')
		-- sm_wish overrides tank with 2400 health after the multiply (:13291)
		assert_near(t, sm_wish.tank[1], 23953.13, 'tank sm_wish override')

		-- death wish doubles the headshot multiplier (hs 2) where death sentence
		-- keeps 1.5, so the same headshot toggle lands on a different number.
		local _, headshot = build('amcar', {bonuses = bonus_state({prison_wife = true})})

		-- swat on easy_wish: 480 health, headshot 2 * 2 = 4 -> 479.0625 / 4
		assert_near(t, breakpoints.get_for_unit('swat', headshot, 'easy_wish')[1], 119.77, 'swat easy_wish headshot')
		-- swat on death sentence: headshot 2 * 1.5 = 3 -> 479.0625 / 3
		assert_near(t, breakpoints.get_for_unit('swat', headshot, 'overkill_290')[1], 159.69, 'swat death sentence headshot')

		-- A breakpoint table shrinks and grows with the health, never stays put.
		t.assert_true(death_sentence.swat[1] > overkill_145.swat[1], 'death sentence swat above mayhem')
		t.assert_true(overkill.swat[1] > normal.swat[1], 'overkill swat above normal')
		assert_near(t, hard.swat[1], easy.swat[1], 'easy and hard share the swat health')
	end)

	t.test('a nil difficulty falls back to the context difficulty', function()
		local _, params = build('amcar', {context = fresh_context({difficulty = 'overkill_290'})})

		assert_near(t, breakpoints.get_for_unit('swat', params)[1], 479.07, 'params context difficulty used')
		assert_near(t, breakpoints.get_all(params).swat[1], 479.07, 'get_all forwards the same default')
		assert_near(t, breakpoints.get_for_unit('swat', params, 'normal')[1], 79.85, 'an explicit difficulty wins')

		-- The headshot multiplier follows the fallback too: easy_wish doubles it.
		local _, headshot = build('amcar', {
			context = fresh_context({difficulty = 'easy_wish'}),
			bonuses = bonus_state({prison_wife = true}),
		})

		assert_near(t, breakpoints.get_for_unit('swat', headshot)[1], 119.77, 'headshot follows the context difficulty')
	end)

	t.test('weapon damage drives the reached breakpoint, not the table shape', function()
		local _, rifle_params = build('amcar')
		local _, judge_params = build('judge')
		local _, sniper_params = build('m95')
		local rifle = weapon.new('amcar', nil, fresh_context())
		local judge = weapon.new('judge', nil, fresh_context())
		local sniper = weapon.new('m95', nil, fresh_context())

		assert_near(t, breakpoints.current_damage(rifle), 45, 'AMCAR damage')
		assert_near(t, breakpoints.current_damage(judge), 155, 'Judge damage')
		assert_near(t, breakpoints.current_damage(sniper), 3500, 'Thanatos damage')

		local rifle_data = breakpoints.get_all(rifle_params, 'normal')
		local judge_data = breakpoints.get_all(judge_params, 'normal')

		-- Without a pistol/shotgun bonus the rifle and shotgun params produce the
		-- same table: the maths only depends on the enemy and the bonuses.
		for _, unit_type in ipairs(breakpoints.unit_types) do
			t.assert_equal(#hit_counts(rifle_data[unit_type]), #hit_counts(judge_data[unit_type]), unit_type .. ' shared shape')
		end

		-- The Thanatos one-shots every unit, so the highest one-hit breakpoint
		-- (the bulldozer's) is the one the weapon reaches.
		local sniper_ref, sniper_reached = breakpoints.consolidate(breakpoints.get_all(sniper_params, 'normal'), 3500, 10, true)

		assert_near(t, sniper_ref, 1996.1, 'Thanatos reached breakpoint')

		local found = false

		for _, entry in ipairs(sniper_reached or {}) do
			found = found or entry.value == sniper_ref
		end

		t.assert_true(found, 'the reached breakpoint is inside the trimmed window')
	end)

	t.test('tank keeps its init-time crit multiplier across difficulties', function()
		with_managers(managers_stub({critical_hit_chance = 0.2}), function()
			local _, params = build('amcar', {
				bonuses = bonus_state({backstab = true}),
			})

			-- critical_hits.damage_mul is a snapshot of the *base* headshot
			-- multiplier (:2762-2764), so it stays 5 while headshot_dmg_mul scales.
			local normal = breakpoints.get_for_unit('tank', params, 'normal')
			local death_sentence = breakpoints.get_for_unit('tank', params, 'overkill_290')

			-- 2000 health, one crit hit counts as 5 hits at 400 damage:
			-- 400 / 3.90625 = 102.4 -> 103 steps
			assert_near(t, normal[1], 402.35, 'tank normal crit breakpoint')
			-- 12000 health: 12000 / 5 = 2400, / 23.4375 = 102.4 -> 103 steps
			assert_near(t, death_sentence[1], 2414.07, 'tank death sentence crit breakpoint')
		end)
	end)

	t.test('headshot toggle uses the passive headshot multiplier', function()
		local _, plain = build('amcar')
		local _, headshot = build('amcar', {bonuses = bonus_state({prison_wife = true})})

		assert_near(t, breakpoints.get_for_unit('swat', plain, 'normal')[1], 79.85, 'without headshot')
		assert_near(t, breakpoints.get_for_unit('swat', headshot, 'normal')[1], 39.93, 'with headshot (x2)')

		-- weapon.passive_headshot_damage_multiplier = 1.25 (:791-793): x2.5.
		-- PlayerManager resolves the value list to the picked level's number, so
		-- the stub answers [1] rather than the raw table.
		local passive_headshot = fixtures.tweak_data.upgrades.values.weapon.passive_headshot_damage_multiplier

		with_managers(managers_stub({values = {weapon = {passive_headshot_damage_multiplier = passive_headshot[1]}}}), function()
			local _, skill = build('amcar', {bonuses = bonus_state({prison_wife = true})})

			assert_near(t, breakpoints.get_for_unit('swat', skill, 'normal')[1], 31.94, 'headshot with the skill multiplier')
		end)
	end)

	t.test('crit toggle scales by the player crit chance', function()
		with_managers(managers_stub({critical_hit_chance = 0.2}), function()
			local _, params = build('amcar', {bonuses = bonus_state({backstab = true})})
			local data = breakpoints.get_for_unit('swat', params, 'normal')

			-- i = 1: ceil(0.2) = 1 extra hit at (2 - 1) -> 80 / 2 = 40
			assert_near(t, data[1], 40, 'swat crit one hit')
			assert_near(t, data[2], 26.72, 'swat crit two hits')
			-- i = 6: two crits -> 80 / 8 = 10
			assert_near(t, data[6], 10, 'swat crit six hits')
		end)

		-- No crit chance from the tree: the toggle changes nothing.
		with_managers(managers_stub({}), function()
			local _, params = build('amcar', {bonuses = bonus_state({backstab = true})})

			assert_near(t, breakpoints.get_for_unit('swat', params, 'normal')[1], 79.85, 'crit toggle without crit chance')
		end)
	end)

	t.test('berserker uses the difficulty revive health step', function()
		local damage_ratio_mul = fixtures.tweak_data.upgrades.values.player.damage_health_ratio_multiplier[1]
		local revived_health_regain = fixtures.tweak_data.upgrades.values.player.revived_health_regain[1]
		local melee_ratio_mul = fixtures.tweak_data.upgrades.values.player.melee_damage_health_ratio_multiplier[1]

		with_managers(managers_stub({values = {player = {damage_health_ratio_multiplier = damage_ratio_mul}}}), function()
			local _, params = build('amcar', {bonuses = bonus_state({wolverine = true})})

			t.assert_equal(params.berserker, 'damage_health_ratio_multiplier', 'automatic weapon uses the damage ratio')

			-- normal: 80 health, revive step 0.4 (:128-130), threshold 0.5 (:601)
			--   1 - 0.4 / 0.5 = 0.2  -> 1 + 1 * 0.2 = 1.2
			assert_near(t, breakpoints.get_for_unit('swat', params, 'normal')[1], 66.54, 'normal berserker')

			-- death sentence: 480 health and revive step 0.1 (:50-52)
			--   1 - 0.1 / 0.5 = 0.8  -> 1.8; 479.0625 / 1.8 = 266.1458 -> 266.15
			assert_near(t, breakpoints.get_for_unit('swat', params, 'overkill_290')[1], 266.15, 'death sentence berserker')
		end)

		-- player.revived_health_regain = 1.4 (:1061-1063) pushes the revive step
		-- to 0.56, above the 0.5 threshold: no damage bonus at all.
		with_managers(managers_stub({values = {player = {
			damage_health_ratio_multiplier = damage_ratio_mul,
			revived_health_regain = revived_health_regain,
		}}}), function()
			local _, params = build('amcar', {bonuses = bonus_state({wolverine = true})})

			assert_near(t, breakpoints.get_for_unit('swat', params, 'normal')[1], 79.85, 'revive above the threshold gives nothing')
		end)

		-- A saw uses the melee variant: player.melee_damage_health_ratio_multiplier
		-- = 2.5 (:595-597) -> 1 + 2.5 * 0.2 = 1.5 on normal.
		with_managers(managers_stub({values = {player = {melee_damage_health_ratio_multiplier = melee_ratio_mul}}}), function()
			local saw = {_categories = {'saw'}, _fire_mode_category = 'auto', can_toggle_firemode = function() return false end}
			local params = breakpoints.prepare_params(saw, fresh_context(), bonus_state({wolverine = true}), {})

			t.assert_equal(params.berserker, 'melee_damage_health_ratio_multiplier', 'saw uses the melee ratio')
			assert_near(t, breakpoints.get_for_unit('swat', params, 'normal')[1], 53.23, 'melee berserker')
		end)
	end)

	t.test('overkill only applies to shotguns unless the skill is aced', function()
		local _, rifle = build('amcar', {bonuses = bonus_state({overkill = true})})
		local _, shotgun = build('judge', {bonuses = bonus_state({overkill = true})})
		local _, shotgun_aced = build('judge', {
			bonuses = bonus_state({overkill = {checked = true, level = 2, available = true}}),
		})

		t.assert_equal(rifle.overkill, false, 'rifle is not a shotgun')
		t.assert_equal(shotgun.overkill, true, 'shotgun gets the overkill bonus')
		-- temporary.overkill_damage_multiplier = 1.75 (:609-614)
		assert_near(t, breakpoints.get_for_unit('swat', shotgun, 'normal')[1], 45.63, 'shotgun overkill breakpoint')
		assert_near(t, breakpoints.get_for_unit('swat', shotgun_aced, 'normal')[1], 45.63, 'aced overkill same on a shotgun')
		assert_near(t, breakpoints.get_for_unit('swat', rifle, 'normal')[1], 79.85, 'rifle breakpoint unchanged')
	end)

	t.test('body expertise uses automatic_head_shot_add and skips the tank', function()
		-- Aced level of weapon.automatic_head_shot_add (:646-649) = 0.9, resolved
		-- by PlayerManager to a number rather than the raw value list.
		local automatic_head_shot_add = fixtures.tweak_data.upgrades.values.weapon.automatic_head_shot_add[2]

		with_managers(managers_stub({values = {weapon = {automatic_head_shot_add = automatic_head_shot_add}}}), function()
			local _, params = build('amcar', {bonuses = bonus_state({body_expertise = true})})

			t.assert_equal(params.body_expertise, true, 'body expertise active for the rifle')
			-- 1 + 0.9 * (2 - 1) = 1.9
			assert_near(t, breakpoints.get_for_unit('swat', params, 'normal')[1], 42.03, 'swat body expertise')
			-- the bulldozer helmet ignores it (:2762 tags contains "tank")
			assert_near(t, breakpoints.get_for_unit('tank', params, 'normal')[1], 1996.1, 'tank ignores body expertise')
		end)

		-- A pistol is not automatic, so the toggle cannot be prepared.
		with_managers(managers_stub({values = {weapon = {automatic_head_shot_add = automatic_head_shot_add}}}), function()
			local _, params = build('glock_17', {bonuses = bonus_state({body_expertise = true})})

			t.assert_equal(params.body_expertise, false, 'pistol has no automatic headshot bonus')
		end)
	end)

	t.test('trigger happy only applies to pistols and honours the first-bullet setting', function()
		local _, pistol = build('glock_17', {bonuses = bonus_state({trigger_happy = true})})
		local _, rifle = build('amcar', {bonuses = bonus_state({trigger_happy = true})})

		t.assert_equal(pistol.trigger_happy, 1, 'pistol carries the trigger happy level')
		t.assert_equal(rifle.trigger_happy, nil, 'rifle has no trigger happy')
		-- single-fire pistol: shoot interval is the click rate, 1 / 5 s
		assert_near(t, pistol.shoot_interval, 0.2, 'manual click interval')

		-- max_time 2 s (level 1) / 0.2 s = 10 boosted-shot gaps.
		-- first-bullet on: floor(1 / 11) = 0 initiators -> 1 + 1.2 * 1 = 2.2
		assert_near(t, breakpoints.get_for_unit('swat', pistol, 'normal')[1], 36.41, 'first bullet boosted')

		local _, pistol_plain = build('glock_17', {
			bonuses = bonus_state({trigger_happy = true}),
			options = {enable_trigger_happy_for_first_bullet = false},
		})

		assert_near(t, breakpoints.get_for_unit('swat', pistol_plain, 'normal')[1], 79.85, 'first bullet unboosted')

		-- clicks_per_second moves the manual interval: 0.11 s fire rate wins at 10 cps
		local _, fast = build('glock_17', {
			bonuses = bonus_state({trigger_happy = true}),
			options = {clicks_per_second = 10},
		})

		assert_near(t, fast.shoot_interval, 0.11, 'fire rate wins over a fast click rate')
	end)

	t.test('underdog and hitman multiply the expected enemy types', function()
		local _, underdog = build('amcar', {bonuses = bonus_state({underdog = true})})
		local _, hitman_1 = build('amcar', {
			bonuses = bonus_state({hitman = {checked = true, level = 1, available = true}}),
		})
		local _, hitman_2 = build('amcar', {
			bonuses = bonus_state({hitman = {checked = true, level = 2, available = true}}),
		})

		-- temporary.dmg_multiplier_outnumbered = 1.15 (:508-513)
		assert_near(t, breakpoints.get_for_unit('swat', underdog, 'normal')[1], 69.43, 'underdog swat')

		-- player.marked_enemy_damage_mul = 1.15 (:229) hits the "special" tag only
		assert_near(t, breakpoints.get_for_unit('swat', hitman_1, 'normal')[1], 79.85, 'hitman ignores the swat')
		assert_near(t, breakpoints.get_for_unit('sniper', hitman_1, 'normal')[1], 34.72, 'hitman level 1 sniper')
		-- marked_inc_dmg_distance[1][2] = 1.5 (:1702-1707) as well
		assert_near(t, breakpoints.get_for_unit('sniper', hitman_2, 'normal')[1], 23.15, 'hitman level 2 sniper')

		-- Explosive ammo caps hitman at level 1 and drops the headshot toggle.
		local explosive_model, explosive = build('judge', {
			blueprint = fixtures.blueprints.judge_explosive,
			bonuses = bonus_state({
				hitman = {checked = true, level = 2, available = true},
				prison_wife = true,
			}),
		})

		t.assert_equal(explosive.explosion, true, 'explosive ammo detected')
		t.assert_equal(explosive.headshot, false, 'explosive ammo cannot headshot')
		t.assert_equal(explosive.hitman, 1, 'explosive ammo caps hitman at level 1')
		t.assert_equal(explosive_model._ammo_data.bullet_class, 'InstantExplosiveBulletBase', 'bullet class from the ammo part')
	end)

	t.test('crit-capable vs crit-disabled weapon and ammo', function()
		local model = weapon.new('amcar', nil, fresh_context())

		t.assert_equal(breakpoints.can_be_critical(nil, 'bullet'), true, 'no weapon means no restriction')
		t.assert_equal(breakpoints.can_be_critical(model, 'bullet'), true, 'rifle bullets can crit')
		t.assert_equal(breakpoints.can_be_critical(model, 'explosion'), true, 'a category without an entry can crit')

		-- The real 248.2 disable table keys (tweakdata.lua:2324-2414): a frag
		-- projectile cannot crit any damage type, an electric grenade neither.
		local frag = {weapon_tweak_data = function()
			return {categories = {'frag'}}
		end}

		t.assert_equal(breakpoints.can_be_critical(frag, 'bullet'), false, 'frag bullets cannot crit')
		t.assert_equal(breakpoints.can_be_critical(frag, 'explosion'), false, 'frag explosions cannot crit')
		-- wpn_gre_electric is the third entry copied from tweakdata.lua:2358-2361
		local electric = {weapon_tweak_data = function()
			return {categories = {'wpn_gre_electric'}}
		end}

		t.assert_equal(breakpoints.can_be_critical(electric, 'explosion'), false, 'electric grenades cannot crit')
		t.assert_equal(breakpoints.can_be_critical(electric, 'tase'), false, 'electric grenades cannot taser-crit')

		-- weapon_tweak_data().ignore_crit_damage (weapontweakdata.lua:21610) is the
		-- other 248.2 switch the game checks before the category lookup.
		local underbarrel = {weapon_tweak_data = function()
			return {categories = {'flamethrower'}, ignore_crit_damage = true}
		end}

		t.assert_equal(breakpoints.can_be_critical(underbarrel, 'bullet'), false, 'ignore_crit_damage disables crits')

		-- A flamethrower category without the flag answers true and makes
		-- prepare_params flag the fire damage type.
		local flamethrower = {_categories = {'flamethrower'}}
		local params = breakpoints.prepare_params(flamethrower, fresh_context(), bonus_state(), {})

		t.assert_equal(params.fire, true, 'flamethrower category detected')
		t.assert_equal(params.headshot, false, 'fire cannot headshot')
		t.assert_equal(params.hitman, 0, 'fire ignores the mark bonus')
	end)

	t.test('a missing enemy table answers an empty table instead of throwing', function()
		with_character_unit('sniper', nil, function()
			local _, params = build('amcar')
			local ok, data = pcall(breakpoints.get_for_unit, 'sniper', params, 'normal')
			local ok_all, all = pcall(breakpoints.get_all, params, 'normal')

			t.assert_true(ok, 'get_for_unit does not throw')
			t.assert_equal(#hit_counts(data), 0, 'missing enemy has no breakpoints')
			t.assert_true(ok_all, 'get_all does not throw')
			t.assert_equal(#hit_counts(all.sniper), 0, 'missing enemy stays empty in get_all')
		end)
	end)

	t.test('damage clamps truncate the table', function()
		local _, params = build('amcar')

		--[[
		248.2 has no DAMAGE_CLAMP_BULLET / DAMAGE_CLAMP_EXPLOSION on the six table
		units; the helmeted bulldozer is the real carrier of the bullet clamp
		(tank_hw, charactertweakdata.lua:2790). Borrow its 235 so the truncation
		branch is exercised on a table unit.
		]]
		with_character_field('swat', 'DAMAGE_CLAMP_BULLET', 235, function()
			-- normal swat: the one-hit breakpoint (79.85) sits under the clamp
			assert_near(t, breakpoints.get_for_unit('swat', params, 'normal')[1], 79.85, 'clamp above the table changes nothing')
			-- death sentence swat: 479.07 > 235, so the row stops at the clamp
			t.assert_equal(#hit_counts(breakpoints.get_for_unit('swat', params, 'overkill_290')), 0, 'clamp below the one-hit breakpoint truncates')
		end)

		local _, explosive = build('judge', {
			blueprint = fixtures.blueprints.judge_explosive,
			bonuses = bonus_state(),
		})

		t.assert_equal(explosive.explosion, true, 'explosive params for the clamp case')

		with_character_field('tank', 'DAMAGE_CLAMP_EXPLOSION', 235, function()
			-- tank explosion_damage_mul = 2 -> one hit needs 1000 damage > 235
			t.assert_equal(#hit_counts(breakpoints.get_for_unit('tank', explosive, 'normal')), 0, 'explosion clamp truncates')
			-- swat explosion_damage_mul = 1 -> 79.85 < 235, table kept
			t.assert_true(#hit_counts(breakpoints.get_for_unit('swat', explosive, 'normal')) > 0, 'a unit under its clamp keeps the table')
		end)

		-- clamp removed again: the same explosive table comes back
		t.assert_true(#hit_counts(breakpoints.get_for_unit('tank', explosive, 'normal')) > 0, 'no clamp, no truncation')
	end)

	t.test('an explosion-blocked mutator empties the explosion table', function()
		local _, plain = build('judge', {
			blueprint = fixtures.blueprints.judge_explosive,
			bonuses = bonus_state(),
		})
		local _, blocked = build('judge', {
			blueprint = fixtures.blueprints.judge_explosive,
			bonuses = bonus_state(),
			options = {explosion_blocked = true},
		})

		t.assert_equal(plain.explosion, true, 'explosive ammo')
		t.assert_equal(plain.explosion_blocked, false, 'not blocked by default')
		t.assert_equal(blocked.explosion_blocked, true, 'the flag is carried through the params')
		t.assert_true(#hit_counts(breakpoints.get_for_unit('swat', plain, 'normal')) > 0, 'unblocked explosion has breakpoints')
		t.assert_equal(#hit_counts(breakpoints.get_for_unit('swat', blocked, 'normal')), 0, 'blocked explosion has none')

		-- Bullet damage ignores the flag.
		local _, bullet_blocked = build('amcar', {options = {explosion_blocked = true}})

		t.assert_true(#hit_counts(breakpoints.get_for_unit('swat', bullet_blocked, 'normal')) > 0, 'bullets ignore the flag')
	end)

	t.test('consolidate sorts, inherits with fill, and trims to amount_wanted', function()
		local data = {
			swat = {[1] = 300, [2] = 150, [3] = 100},
			tank = {[1] = 600, [2] = 300},
		}

		local ref_filled, filled = breakpoints.consolidate(data, 250, 10, true)
		local _, plain = breakpoints.consolidate(data, 250, 10, false)

		assert_near(t, ref_filled, 150, 'reached breakpoint for 250 damage')
		t.assert_equal(#filled, 4, 'one entry per distinct value')

		local values = {100, 150, 300, 600}

		for index, value in ipairs(values) do
			assert_near(t, filled[index].value, value, 'sorted value ' .. index)
		end

		t.assert_equal(filled[3].hits_nr.swat, 1, 'swat hits at 300')
		t.assert_equal(filled[3].hits_nr.tank, 2, 'tank hits at 300')
		t.assert_nil(filled[1].hits_nr.tank, 'no tank hit at 100')
		t.assert_nil(filled[2].herited_hits_nr.tank, 'nothing to inherit at 150')
		-- at 600 the swat keeps its last hit count, the tank reaches hit 1
		t.assert_equal(filled[4].hits_nr.tank, 1, 'tank hits at 600')
		t.assert_nil(filled[4].hits_nr.swat, 'swat has no 600 breakpoint')
		t.assert_equal(filled[4].herited_hits_nr.swat, 1, 'swat inherits its last hit count')

		-- With fill off no inheritance is recorded.
		t.assert_nil(plain[4].herited_hits_nr.swat, 'fill off records no inheritance')

		local ref_trimmed, trimmed = breakpoints.consolidate(data, 250, 2, true)

		assert_near(t, ref_trimmed, 150, 'trimmed reached breakpoint')
		t.assert_equal(#trimmed, 2, 'amount_wanted respected')
		assert_near(t, trimmed[1].value, 150, 'window starts at the reached breakpoint')
		assert_near(t, trimmed[2].value, 300, 'window continues upwards')

		local _, empty = breakpoints.consolidate({}, 100, 5, true)

		t.assert_equal(#empty, 0, 'empty input answers an empty list')
	end)

	t.test('breakpoints never write the game difficulty or the tweak data', function()
		with_global('Global', {game_settings = {difficulty = 'overkill_290'}}, function()
			local swat_health = fixtures.tweak_data.character.swat.HEALTH_INIT
			local revive_step = fixtures.tweak_data.player.damage.REVIVE_HEALTH_STEPS

			local _, params = build('amcar', {
				context = fresh_context({difficulty = 'normal'}),
				bonuses = bonus_state({prison_wife = true, underdog = true, wolverine = true}),
			})

			for _, difficulty in ipairs(fixtures.tweak_data.difficulties) do
				breakpoints.get_all(params, difficulty)
				breakpoints.character_data('tank', difficulty)
				breakpoints.difficulty_snapshot(difficulty)
			end

			t.assert_equal(_G.Global.game_settings.difficulty, 'overkill_290', 'game difficulty untouched')
			t.assert_equal(fixtures.tweak_data.character.swat.HEALTH_INIT, swat_health, 'enemy health untouched')
			t.assert_equal(fixtures.tweak_data.player.damage.REVIVE_HEALTH_STEPS, revive_step, 'player tweak data untouched')

			-- The live HEALTH_INIT is not the source of the maths: changing it does
			-- not move a breakpoint.
			local before = breakpoints.get_for_unit('swat', params, 'normal')

			with_character_field('swat', 'HEALTH_INIT', 999, function()
				local after = breakpoints.get_for_unit('swat', params, 'normal')

				assert_near(t, after[2], before[2], 'live HEALTH_INIT is ignored')
			end)

			t.assert_equal(fixtures.tweak_data.character.swat.HEALTH_INIT, swat_health, 'health restored')
		end)

		context.invalidate()
	end)
end
