--[[
tests/stats_spec.lua — timing, accuracy, falloff and ammo-pickup tests.

Every expected value is derived by hand from the real 248.2 tweak data copied
into tests/fixtures.lua, following the formulas documented in the modules:

	reload  = (timers.reload_empty|reload_not_empty or shell maths) / speed
	speed   = _convert_add_to_mul(sum of upgrade terms) * stats.reload[index]
	equip   = (timers.equip or 0.7) / swap speed multiplier
	spread  = stats.spread[index'] * tweak spread[stance] * steelsight * spread_multi
	recoil  = (stats.recoil[index] + addend) * multiplier * kick[stance]
	falloff = piecewise multiplier over optimal/near/far bands
	pickup  = AMMO_PICKUP * ammo_data muls * (1 + skill + crew)

The skill cases use the 248.2 upgrade values from
lib/tweak_data/upgradestweakdata.lua, never made-up numbers.
]]

local fixtures = dofile(ModPath .. 'tests/fixtures.lua')

fixtures.install()

local context = MoreWeaponStats.core.context
local weapon = MoreWeaponStats.core.weapon
local timers = MoreWeaponStats.core.timers
local accuracy = MoreWeaponStats.core.accuracy
local ballistics = MoreWeaponStats.core.ballistics
local ammo = MoreWeaponStats.core.ammo

local EPSILON = 1e-9

local function assert_near(t, actual, expected, message)
	t.assert_type(actual, 'number', message .. ' (type)')
	t.assert_true(math.abs(actual - expected) <= EPSILON, ('%s: expected %.9f, got %.9f'):format(message, expected, actual))
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

--[[
PlayerManager stand-in. `values` is category -> upgrade -> value; everything it
does not answer falls back to the caller's default, like PlayerManager does.
`crew` holds crew_ability_upgrade_value entries, `team` the team categories.
]]
local function managers_stub(values)
	values = values or {}

	return {
		player = {
			upgrade_value = function(_, category, upgrade, default)
				local category_values = values[category]

				if category_values and category_values[upgrade] ~= nil then
					return category_values[upgrade]
				end

				return default
			end,
			has_category_upgrade = function(_, category, upgrade)
				local category_values = values[category]

				return category_values ~= nil and category_values[upgrade] ~= nil
			end,
			has_activate_temporary_upgrade = function()
				return false
			end,
			temporary_upgrade_value = function(_, _, _, default)
				return default
			end,
			get_property = function(_, _, default)
				return default
			end,
			get_temporary_property = function(_, _, default)
				return default
			end,
			crew_ability_upgrade_value = function(_, upgrade, default)
				local crew = values.crew

				if crew and crew[upgrade] ~= nil then
					return crew[upgrade]
				end

				return default
			end,
			has_team_category_upgrade = function(_, category, upgrade)
				local team = values.team

				return team ~= nil and team[category] ~= nil and team[category][upgrade] ~= nil
			end,
			team_upgrade_value = function(_, category, upgrade, default)
				local team = values.team

				if team and team[category] and team[category][upgrade] ~= nil then
					return team[category][upgrade]
				end

				return default
			end,
		},
	}
end

return function(t)
	-- Context surface added for Task 3 ----------------------------------------

	t.test('context exposes the crew, team and temporary-property queries', function()
		local stub = managers_stub({
			crew = {crew_scavenge = 0.15},
			team = {weapon = {recoil_index_addend = 1}},
		})

		with_managers(stub, function()
			local ctx = fresh_context()

			assert_near(t, ctx:crew_ability_upgrade_value('crew_scavenge', 0), 0.15, 'crew scavenge')
			assert_near(t, ctx:crew_ability_upgrade_value('crew_health', 0), 0, 'missing crew upgrade default')
			t.assert_equal(ctx:has_team_category_upgrade('weapon', 'recoil_index_addend'), true, 'team upgrade present')
			t.assert_equal(ctx:has_team_category_upgrade('weapon', 'recoil_multiplier'), false, 'team upgrade absent')
			assert_near(t, ctx:team_upgrade_value('weapon', 'recoil_index_addend', 0), 1, 'team upgrade value')
			assert_near(t, ctx:get_temporary_property('bloodthirst_reload_speed', 1), 1, 'temporary property default')
			t.assert_equal(ctx.suppressed, false, 'no player unit means not suppressed')

			local overridden = context.get({suppressed = true})
			t.assert_equal(overridden.suppressed, true, 'suppressed override reaches the recoil branch')
		end)
	end)

	-- Reload speed -------------------------------------------------------------

	t.test('reload_speed_multiplier applies weapon upgrades over the reload stat', function()
		local ctx = fresh_context()
		local model = weapon.new('amcar', nil, ctx)

		-- stats.reload[11] = 1.0 (weapontweakdata.lua:6383-6389), no upgrades.
		assert_near(t, timers.reload_speed_multiplier(model, ctx), 1, 'baseline reload multiplier')

		-- upgradestweakdata.lua:414 assault_rifle.reload_speed_multiplier = 1.15
		with_managers(managers_stub({assault_rifle = {reload_speed_multiplier = 1.15}}), function()
			local skill_ctx = fresh_context()
			local skill_model = weapon.new('amcar', nil, skill_ctx)

			-- 1 + (1 - 1.15) = 0.85 -> convert_add_to_mul -> 1.15, * 1.0
			assert_near(t, timers.reload_speed_multiplier(skill_model, skill_ctx), 1.15, 'skill reload multiplier')
			assert_near(t, timers.reload_full(skill_model, 0, skill_ctx), 3 / 1.15, 'skill shortens the empty reload')
		end)

		local crew = weapon.new_from_slot('new_m4', nil, {npc = true})
		t.assert_nil(timers.reload_speed_multiplier(crew, ctx), 'crew weapon has no player reload stat')
	end)

	-- Full and partial reload ------------------------------------------------

	t.test('reload_full covers the empty and the tactical reload', function()
		local ctx = fresh_context()
		local model = weapon.new('amcar', nil, ctx)

		-- timers.reload_empty = 3, timers.reload_not_empty = 2.25 (:7230-7231)
		assert_near(t, timers.reload_full(model, 0, ctx), 3, 'empty reload')
		assert_near(t, timers.reload_full(model, 19, ctx), 2.25, 'tactical reload')
		assert_near(t, timers.reload_full(model, nil, ctx), 3, 'nil clip is an empty reload')
		t.assert_equal(model:clip_empty(0), true, 'clip_empty(0)')
		t.assert_equal(model:clip_not_empty(0), false, 'clip_not_empty(0)')
		t.assert_equal(model:clip_empty(19), false, 'clip_empty(19)')
		t.assert_nil(timers.clip_empty(model), 'unknown clip state stays nil')
	end)

	t.test('reload_partial returns the one-round-short reload and the shell time', function()
		local ctx = fresh_context()
		local model = weapon.new('amcar', nil, ctx)
		local partial, shell = timers.reload_partial(model, 1, ctx)

		assert_near(t, partial, 2.25, 'partial reload')
		assert_near(t, shell, 2.25, 'shell time equals the tactical reload without shell timers')

		-- Contender: CLIP_AMMO_MAX = 1 (weapontweakdata.lua:8122). The v76 row
		-- blanked both cells for single-shell weapons.
		local contender = weapon.new('contender', nil, ctx)
		local contender_partial, contender_shell = timers.reload_partial(contender, 1, ctx)

		t.assert_nil(contender_partial, 'single-shell partial is blank')
		t.assert_nil(contender_shell, 'single-shell shell time is blank')
		assert_near(t, timers.reload_full(contender, 0, ctx), 1.3, 'single-shell weapon still has a reload')
	end)

	t.test('shotgun shell reload adds enter, shells and exit timers', function()
		local ctx = fresh_context()
		local model = weapon.new('supernova', nil, ctx)

		t.assert_equal(timers.use_shotgun_reload(model), true, 'supernova reloads shell by shell')
		t.assert_equal(model:use_shotgun_reload(), true, 'model seam')
		t.assert_equal(timers.use_shotgun_reload(weapon.new('judge', nil, ctx)), false, 'judge uses a magazine')

		-- timers.shotgun_reload_* (:11540-11544)
		assert_near(t, model:reload_enter_expire_t(false), 0.8, 'reload enter')
		assert_near(t, model:reload_exit_expire_t(false), 0.9666666666666667, 'empty reload exit')
		assert_near(t, model:reload_exit_expire_t(true), 0.5666666666666667, 'tactical reload exit')
		assert_near(t, model:reload_shell_expire_t(false), 0.6, 'shell time')
		assert_near(t, model:_first_shell_reload_expire_t(false), 0.6, 'first shell offset is 0')

		-- 5 shells: ceil(5 / 1) * 0.6
		assert_near(t, model:reload_expire_t(0, false), 3, 'five shells')
		assert_near(t, model:reload_expire_t(4, true), 0.6, 'one shell')
		t.assert_equal(model:started_reload_empty(0), true, 'started empty from an empty clip')
		t.assert_equal(model:started_reload_empty(4), false, 'started not empty from a partial clip')

		assert_near(t, timers.reload_full(model, 0, ctx), 0.8 + 3 + 0.9666666666666667, 'full shell reload')
		assert_near(t, timers.reload_full(model, 4, ctx), 0.8 + 0.6 + 0.5666666666666667, 'tactical shell reload')

		local partial, shell = timers.reload_partial(model, 1, ctx)

		assert_near(t, partial, 0.8 + 0.6 + 0.5666666666666667, 'partial shell reload')
		assert_near(t, shell, 0.6, 'single shell time')

		local shotgun = weapon.new('m95', nil, ctx)
		t.assert_nil(timers.reload_expire_t(shotgun, 0, false), 'magazine weapon has no shell maths')
		t.assert_nil(shotgun:reload_enter_expire_t(false), 'magazine weapon has no reload enter timer')
		t.assert_nil(shotgun:reload_exit_expire_t(false), 'magazine weapon has no reload exit timer')
		t.assert_nil(shotgun:started_reload_empty(0), 'started_reload_empty is shotgun only')
	end)

	-- Equip and unequip ------------------------------------------------------

	t.test('equip_delay reads the weapon timers and the swap speed multiplier', function()
		local ctx = fresh_context()
		local model = weapon.new('amcar', nil, ctx)
		local equip, unequip = timers.equip_delay(model, ctx)

		-- timers.equip = 0.55, timers.unequip = 0.6 (:7232-7233)
		assert_near(t, equip, 0.55, 'amcar equip')
		assert_near(t, unequip, 0.6, 'amcar unequip')

		local judge_equip, judge_unequip = timers.equip_delay(weapon.new('judge', nil, ctx), ctx)
		assert_near(t, judge_equip, 0.45, 'judge equip')
		assert_near(t, judge_unequip, 0.5, 'judge unequip')

		-- upgradestweakdata.lua:6053 weapon.swap_speed_multiplier = 1.8
		with_managers(managers_stub({weapon = {swap_speed_multiplier = 1.8}}), function()
			local fast_ctx = fresh_context()
			local fast_model = weapon.new('amcar', nil, fast_ctx)
			local fast_equip, fast_unequip = timers.equip_delay(fast_model, fast_ctx)

			assert_near(t, timers.swap_speed_multiplier(fast_model, fast_ctx), 1.8, 'swap speed multiplier')
			assert_near(t, fast_equip, 0.55 / 1.8, 'faster equip')
			assert_near(t, fast_unequip, 0.6 / 1.8, 'faster unequip')
		end)

		assert_near(t, timers.swap_speed_multiplier(model, ctx), 1, 'baseline swap speed')

		-- No weapon tweak data means no equip timer to report.
		t.assert_nil(timers.equip_delay({_name_id = 'not_a_weapon'}, ctx), 'unknown weapon equip')
	end)

	-- Spread -----------------------------------------------------------------

	t.test('spread follows the stance, steelsight and deployed bipod', function()
		local ctx = fresh_context()
		local model = weapon.new('amcar', nil, ctx)

		-- stats.spread[10] = 1.28, tweak spread.standing = 3
		assert_near(t, accuracy.spread_horizontal(model, ctx), 3.84, 'standing horizontal spread')
		assert_near(t, accuracy.spread_vertical(model, ctx), 3.84, 'standing vertical spread')

		local crouched = fresh_context({ducking = true})
		assert_near(t, accuracy.spread_horizontal(model, crouched), 1.536, 'crouching spread')

		local deployed = fresh_context({deployed = true})
		assert_near(t, accuracy.spread_horizontal(model, deployed), 1.536, 'deployed bipod uses the crouching stance')

		local aiming = fresh_context({steelsight = true})
		local aiming_x, aiming_y = accuracy.spread_horizontal(model, aiming)
		assert_near(t, aiming_x, 3.84 * (1 + (1 - 3 * 0.4)), 'steelsight horizontal spread')
		assert_near(t, aiming_y, aiming_x, 'square stance keeps both axes equal')

		local spread_x, spread_y = model:_get_spread(ctx)
		assert_near(t, spread_x, 3.84, 'model _get_spread x')
		assert_near(t, spread_y, 3.84, 'model _get_spread y')
	end)

	t.test('spread index upgrades move the standing and moving values apart', function()
		-- upgradestweakdata.lua:1863 assault_rifle.move_spread_index_addend = 2
		with_managers(managers_stub({assault_rifle = {move_spread_index_addend = 2}}), function()
			local ctx = fresh_context()
			local model = weapon.new('amcar', nil, ctx)
			local standing, moving = accuracy.spread_horizontal(model, ctx)

			assert_near(t, standing, 3.84, 'standing spread unchanged')
			-- index = ceil((10 + 2 + 2) * 1) = 14 -> stats.spread[14] = 0.96
			assert_near(t, moving, 0.96 * 3, 'moving spread with the movement accuracy skill')
		end)

		-- upgradestweakdata.lua:144 player.not_moving_accuracy_increase = 4
		with_managers(managers_stub({player = {not_moving_accuracy_increase = 4}}), function()
			local ctx = fresh_context()
			local model = weapon.new('amcar', nil, ctx)
			local standing, moving = accuracy.spread_horizontal(model, ctx)

			assert_near(t, standing, 0.96 * 3, 'standing spread with the stationary accuracy skill')
			assert_near(t, moving, 3.84, 'moving spread unchanged')
		end)
	end)

	t.test('spread_multi scales the horizontal and vertical axes separately', function()
		local ctx = fresh_context()
		local model = weapon.new('judge', fixtures.blueprints.judge_duck, ctx)

		t.assert_type(model._spread_multiplier, 'table', 'duckbill spread_multi reaches the model')
		-- judge stats.spread[14] = 0.96, spread_multi = {2.25, 0.5}
		local horizontal = accuracy.spread_horizontal(model, ctx)
		local vertical = accuracy.spread_vertical(model, ctx)
		assert_near(t, horizontal, 0.96 * 3 * 2.25, 'horizontal spread with the duckbill')
		assert_near(t, vertical, 0.96 * 3 * 0.5, 'vertical spread with the duckbill')
	end)

	t.test('crew weapons have no player spread table and stay blank', function()
		local crew = weapon.new_from_slot('new_m4', nil, {npc = true})

		local x, y = accuracy.spread_horizontal(crew, fresh_context())
		t.assert_nil(x, 'crew weapon horizontal spread')
		t.assert_nil(y, 'crew weapon moving spread')
	end)

	-- Recoil -----------------------------------------------------------------

	t.test('recoil multiplies the kick table by the recoil stat', function()
		local ctx = fresh_context()
		local model = weapon.new('amcar', nil, ctx)

		-- stats.recoil[20] = 1.1, kick.standing = {0.6, 0.8, -1, 1}
		local left, right = accuracy.recoil_horizontal(model, ctx)
		local up, down = accuracy.recoil_vertical(model, ctx)

		assert_near(t, left, -1 * 1.1, 'recoil left')
		assert_near(t, right, 1 * 1.1, 'recoil right')
		assert_near(t, up, 0.6 * 1.1, 'recoil up')
		assert_near(t, down, 0.8 * 1.1, 'recoil down')

		local recoil = accuracy.recoil(model, ctx)
		assert_near(t, recoil.up, 0.66, 'model recoil table')

		-- Grimm kick.steelsight = {1.5, 1.7, -0.2, 0.2} (:7062-7067),
		-- stats.recoil[13] = 1.8
		local aiming = fresh_context({steelsight = true})
		local grimm_up, grimm_down = accuracy.recoil_vertical(weapon.new('basset', nil, ctx), aiming)
		assert_near(t, grimm_up, 1.5 * 1.8, 'steelsight recoil up')
		assert_near(t, grimm_down, 1.7 * 1.8, 'steelsight recoil down')
	end)

	t.test('recoil index and multiplier skills reduce the kick', function()
		-- upgradestweakdata.lua:710 assault_rifle.recoil_multiplier = 0.75,
		-- :1898 assault_rifle.recoil_index_addend = 2
		local stub = managers_stub({assault_rifle = {recoil_multiplier = 0.75, recoil_index_addend = 2}})

		with_managers(stub, function()
			local ctx = fresh_context()
			local model = weapon.new('amcar', nil, ctx)
			local up, down = accuracy.recoil_vertical(model, ctx)
			local left, right = accuracy.recoil_horizontal(model, ctx)

			-- index 20 + 2 = 22 -> stats.recoil[22] = 0.9, addend -0.2
			-- multiplier: 1 + (1 - 0.75) = 1.25 -> 1 / 1.25 = 0.8
			-- base: (1.1 - 0.2) * 0.8 = 0.72
			assert_near(t, up, 0.6 * 0.72, 'skilled recoil up')
			assert_near(t, down, 0.8 * 0.72, 'skilled recoil down')
			assert_near(t, left, -1 * 0.72, 'skilled recoil left')
			assert_near(t, right, 1 * 0.72, 'skilled recoil right')
		end)
	end)

	-- Damage falloff ---------------------------------------------------------

	t.test('get_damage_falloff follows the optimal, near and far bands', function()
		local ctx = fresh_context()
		local judge = weapon.new('judge', nil, ctx)

		-- SHOTGUN_FALL_SECONDARY_VERYHIGH: 800 / +600 / near 0 / far 400 / 0.7
		assert_near(t, ballistics.get_damage_falloff(judge, 0, ctx), 1, 'judge at 0 m')
		assert_near(t, ballistics.get_damage_falloff(judge, 800, ctx), 1, 'judge at the optimal start')
		assert_near(t, ballistics.get_damage_falloff(judge, 1400, ctx), 1, 'judge at the optimal end')
		assert_near(t, ballistics.get_damage_falloff(judge, 1600, ctx), 0.85, 'judge inside the far band')
		assert_near(t, ballistics.get_damage_falloff(judge, 1800, ctx), 0.7, 'judge at the far edge')
		assert_near(t, ballistics.get_damage_falloff(judge, 5000, ctx), 0.7, 'judge beyond the far edge')

		-- AKI_SMG_FALL_LOW: 700 / +700 / near 350 (1.05) / far 2100 (0.75)
		local mp5 = weapon.new('x_mp5', nil, ctx)
		assert_near(t, ballistics.get_damage_falloff(mp5, 0, ctx), 1.05, 'mp5 inside the near band')
		assert_near(t, ballistics.get_damage_falloff(mp5, 525, ctx), 1.025, 'mp5 mid near band')
		assert_near(t, ballistics.get_damage_falloff(mp5, 700, ctx), 1, 'mp5 optimal start')
		assert_near(t, ballistics.get_damage_falloff(mp5, 1750, ctx), 1 - (350 / 2100) * 0.25, 'mp5 inside the far band')
		assert_near(t, ballistics.get_damage_falloff(mp5, 3500, ctx), 0.75, 'mp5 at the far edge')
		assert_near(t, ballistics.get_damage_falloff(mp5, 4000, ctx), 0.75, 'mp5 beyond the far edge')

		-- No falloff data: the game returns the damage unchanged.
		assert_near(t, ballistics.get_damage_falloff(weapon.new('amcar', nil, ctx), 500, ctx), 1, 'no falloff data')
	end)

	t.test('steelsight_range_inc stretches the far end of the range', function()
		-- upgradestweakdata.lua:566 shotgun.steelsight_range_inc (real table at
		-- :566-568 holds 1.5 for the first level)
		with_managers(managers_stub({shotgun = {steelsight_range_inc = 1.5}}), function()
			local ctx = fresh_context({steelsight = true})
			local judge = weapon.new('judge', nil, ctx)

			-- optimal_end 1400 * 1.5 = 2100, so 1600 is inside the optimal band
			assert_near(t, ballistics.get_damage_falloff(judge, 1600, ctx), 1, 'steelsight keeps 1600 in range')
			-- far band now 2100 .. 2100 + 400 * 1.5
			assert_near(t, ballistics.get_damage_falloff(judge, 2400, ctx), 0.85, 'steelsight far band midpoint')
		end)
	end)

	t.test('part custom stats rescale the falloff table', function()
		local ctx = fresh_context()
		local plain = weapon.new('judge', nil, ctx)
		local explosive = weapon.new('judge', fixtures.blueprints.judge_explosive, ctx)

		assert_near(t, plain._far_falloff, 400, 'plain far falloff')
		-- damage_far_mul = 1.4 from the judge factory override (:17091-17099)
		assert_near(t, explosive._far_falloff, 400 * 1.4, 'explosive ammo stretches the far falloff distance')
		assert_near(t, explosive._optimal_range, 600, 'damage_near_mul = 1 leaves the optimal range')
		assert_near(t, ballistics.get_damage_falloff(explosive, 1600, ctx), 1 - (200 / 560) * 0.3, 'rescaled far band')
	end)

	t.test('is_weak_hit and the model damage helper use the same bands', function()
		local ctx = fresh_context()
		local mp5 = weapon.new('x_mp5', nil, ctx)

		assert_near(t, ballistics.is_weak_hit(mp5, 100, ctx), 1.2, 'weak hit inside the near band')
		assert_near(t, ballistics.is_weak_hit(mp5, 3000, ctx), 1, 'no weak hit inside the far distance')
		assert_near(t, ballistics.is_weak_hit(mp5, 4000, ctx), 0.5, 'weak hit beyond the far distance')

		local thanatos = weapon.new('m95', nil, ctx)
		assert_near(t, ballistics.is_weak_hit(thanatos, 4000, ctx), 1.2, 'sniper far multiplier above 1')
		assert_near(t, thanatos:is_weak_hit(), 1, 'no distance means no weak hit')

		local judge = weapon.new('judge', nil, ctx)
		assert_near(t, judge:get_damage_falloff(100, 1600, ctx), 85, 'model falloff returns damage')
		assert_near(t, judge:get_damage_falloff(nil, 1600, ctx), 15.5 * 0.85, 'model falloff uses the model damage')
	end)

	-- Ammo pickup ------------------------------------------------------------

	t.test('ammo_pickup returns the AMMO_PICKUP range', function()
		local ctx = fresh_context()
		local amcar_min, amcar_max = ammo.ammo_pickup(weapon.new('amcar', nil, ctx), ctx)

		assert_near(t, amcar_min, 6.6, 'amcar pickup min')
		assert_near(t, amcar_max, 9.9, 'amcar pickup max')

		local sniper_min, sniper_max = ammo.ammo_pickup(weapon.new('m95', nil, ctx), ctx)
		assert_near(t, sniper_min, 0.1, 'thanatos pickup min')
		assert_near(t, sniper_max, 0.65, 'thanatos pickup max')

		-- 1.8 / 4.95 for the ammo part's 0.4 / 0.6 multipliers
		local part_min, part_max = ammo.ammo_pickup(weapon.new('new_m4', {'wpn_fps_ammo_type'}, ctx), ctx)
		assert_near(t, part_min, 4.5 * 0.4, 'ammo part pickup min')
		assert_near(t, part_max, 8.25 * 0.6, 'ammo part pickup max')

		local crew_min, crew_max = ammo.ammo_pickup(weapon.new_from_slot('new_m4', nil, {npc = true}), ctx)
		t.assert_nil(crew_min, 'crew weapons have no pickup data')
		t.assert_nil(crew_max, 'crew weapons have no pickup max')
	end)

	t.test('ammo_pickup applies the pick-up skills and crew scavenge', function()
		-- upgradestweakdata.lua:523 pick_up_ammo_multiplier = {1.35, 1.75},
		-- :1452 pick_up_ammo_multiplier_2 = 1.3
		local stub = managers_stub({
			player = {pick_up_ammo_multiplier = 1.35, pick_up_ammo_multiplier_2 = 1.3},
			crew = {crew_scavenge = 0.15},
		})

		with_managers(stub, function()
			local ctx = fresh_context()
			local model = weapon.new('amcar', nil, ctx)
			local min_amount, max_amount = ammo.ammo_pickup(model, ctx)

			-- 1 + 0.35 + 0.3 + 0.15 = 1.8
			assert_near(t, min_amount, 6.6 * 1.8, 'pickup min with skills and scavenge')
			assert_near(t, max_amount, 9.9 * 1.8, 'pickup max with skills and scavenge')
		end)

		local ctx = fresh_context()
		local min_amount = ammo.ammo_pickup(weapon.new('amcar', nil, ctx), ctx)
		assert_near(t, min_amount, 6.6, 'no-skill baseline for the same weapon')
	end)

	-- Model wiring -----------------------------------------------------------

	t.test('the model delegates the remaining questions to the maths modules', function()
		local ctx = fresh_context()
		local supernova = weapon.new('supernova', nil, ctx)

		supernova:set_ammo_remaining_in_clip(0)
		t.assert_equal(supernova:get_ammo_remaining_in_clip(), 0, 'clip accessor')
		t.assert_equal(supernova:clip_empty(), true, 'model clip_empty')
		t.assert_equal(supernova:clip_not_empty(), false, 'model clip_not_empty')
		assert_near(t, supernova:reload_expire_t(0, false), 3, 'model reload_expire_t')
		assert_near(t, supernova:reload_speed_multiplier(), 1, 'model reload_speed_multiplier')

		local amcar = weapon.new('amcar', nil, ctx)
		assert_near(t, amcar:reload_speed_multiplier(), 1, 'model uses its own context')
		t.assert_nil(amcar:reload_expire_t(0, false), 'magazine weapon shell maths stays nil')

		local crew = weapon.new_from_slot('new_m4', nil, {npc = true})
		t.assert_nil(crew:reload_speed_multiplier(), 'crew model reload multiplier')
		t.assert_nil(crew:_get_spread(fresh_context()), 'crew model spread')
	end)
end
