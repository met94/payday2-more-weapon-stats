--[[
tests/weapon_spec.lua — context and WeaponModel tests for the clean rewrite.

The values are derived by hand from the real 248.2 tweak data copied into
tests/fixtures.lua, following the formulas documented in lua/core/weapon.lua:
	damage  = stats.damage[index] * stats_modifiers.damage
	clip    = CLIP_AMMO_MAX (+ upgrades)
	total   = round((AMMO_MAX + clip_amount_increase * clip) * ammo multiplier)
	rpm     = 60 / fire_mode_data.fire_rate
	conceal = stats.concealment + part stats (+ skin bonus)
	suspicion = concealment[clamp(#concealment - concealment - part concealment)]
]]

local fixtures = dofile(ModPath .. 'tests/fixtures.lua')

fixtures.install()

local context = MoreWeaponStats.core.context
local weapon = MoreWeaponStats.core.weapon

local EPSILON = 1e-9

local function assert_near(t, actual, expected, message)
	t.assert_type(actual, 'number', message .. ' (type)')
	t.assert_true(math.abs(actual - expected) <= EPSILON, ('%s: expected %.6f, got %.6f'):format(message, expected, actual))
end

local function contains_string(list, value)
	for _, entry in ipairs(list) do
		if entry == value then
			return true
		end
	end

	return false
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

-- One context per render: invalidate first so no case sees another case's cache.
local function fresh_context(overrides)
	context.invalidate()

	return context.get(overrides)
end

-- name, damage, damage index, categories, clip, total, fire interval, concealment, suspicion
local EXPECTED = {
	{
		id = 'amcar', name = 'AMCAR', categories = {'assault_rifle'},
		damage_index = 45, damage = 4.5, clip = 20, total = 220,
		fire_rate = 0.11, fire_mode_rate = 0.11, fire_mode = 'auto', toggle = true,
		concealment = 21, suspicion = 0.825,
	},
	{
		id = 'new_m4', name = 'CAR-4', categories = {'assault_rifle'},
		damage_index = 62, damage = 6.2, clip = 30, total = 150,
		fire_rate = 0.1, fire_mode_rate = 0.1, fire_mode = 'auto', toggle = true,
		concealment = 20, suspicion = 0.85,
	},
	{
		id = 'new_m14', name = 'M308', categories = {'assault_rifle'},
		damage_index = 160, damage = 16.0, clip = 10, total = 70,
		fire_rate = 0.085, fire_mode_rate = 0.085, fire_mode = 'single', toggle = true,
		concealment = 8, suspicion = 1.375,
	},
	{
		id = 'judge', name = 'Judge', categories = {'shotgun'},
		damage_index = 155, damage = 15.5, clip = 5, total = 35,
		-- judge declares no CAN_TOGGLE_FIREMODE in 248.2; only x_judge sets it
		fire_rate = 0.12, fire_mode_rate = 0.21, fire_mode = 'single', toggle = nil,
		concealment = 29, suspicion = 0.3,
	},
	{
		id = 'basset', name = 'Grimm', categories = {'shotgun'},
		damage_index = 18, damage = 1.8, clip = 8, total = 104,
		fire_rate = 0.2, fire_mode_rate = 0.2, fire_mode = 'auto', toggle = true,
		concealment = 21, suspicion = 0.825,
	},
	{
		id = 'm249', name = 'KSP', categories = {'lmg'},
		damage_index = 80, damage = 8.0, clip = 200, total = 400,
		fire_rate = 0.066, fire_mode_rate = 0.076, fire_mode = 'auto', toggle = false,
		concealment = 1, suspicion = 1.55,
	},
	{
		id = 'm95', name = 'Thanatos', categories = {'snp'},
		damage_index = 100, damage = 350, clip = 5, total = 15,
		fire_rate = 1.25, fire_mode_rate = 20, fire_mode = 'single', toggle = false,
		concealment = 1, suspicion = 1.55,
	},
	{
		id = 'x_mp5', name = 'Akimbo MP5', categories = {'akimbo', 'smg'},
		damage_index = 44, damage = 4.4, clip = 60, total = 300,
		fire_rate = 0.08, fire_mode_rate = 0.08, fire_mode = 'auto', toggle = true,
		concealment = 24, suspicion = 0.7,
	},
}

return function(t)
	t.test('entry bootstrap loads the core, ui and compat modules', function()
		local core = MoreWeaponStats.core
		local ui = MoreWeaponStats.ui

		for _, name in ipairs({'context', 'weapon', 'ballistics', 'timers', 'accuracy', 'ammo'}) do
			t.assert_type(core and core[name], 'table', 'MoreWeaponStats.core.' .. name)
		end

		for _, name in ipairs({'stats_panel', 'breakpoints_panel', 'melee', 'henchmen'}) do
			t.assert_type(ui and ui[name], 'table', 'ui.' .. name)
		end

		t.assert_type(MoreWeaponStats.compat, 'table', 'MoreWeaponStats.compat')
		t.assert_type(MoreWeaponStats.compat.init, 'function', 'MoreWeaponStats.compat.init')
	end)

	t.test('context.get() returns the documented defaults', function()
		context.invalidate()
		local ctx = fresh_context()

		t.assert_equal(ctx.difficulty, 'overkill_290', 'default difficulty')
		t.assert_equal(ctx.difficulty_rank, 7, 'default difficulty rank')
		t.assert_equal(ctx.moving, false, 'default moving')
		t.assert_equal(ctx.ducking, false, 'default ducking')
		t.assert_equal(ctx.steelsight, false, 'default steelsight')
		t.assert_equal(ctx.deployed, false, 'default deployed')
		t.assert_type(ctx.skills, 'table', 'default skills')
		t.assert_type(ctx.perks, 'table', 'default perks')
		t.assert_type(ctx.upgrades, 'table', 'default upgrades')
	end)

	t.test('context.get() applies overrides and isolates every returned table', function()
		context.invalidate()
		local first = context.get({ducking = true, steelsight = true})

		t.assert_equal(first.ducking, true, 'overridden ducking')
		t.assert_equal(first.steelsight, true, 'overridden steelsight')

		first.skills.shotgun_impact = 2
		first.perks.crew_chief = 3
		first.upgrades.player = {extra_ammo_multiplier = 9}

		local second = context.get()

		t.assert_nil(second.skills.shotgun_impact, 'skills must be deep-copied')
		t.assert_nil(second.perks.crew_chief, 'perks must be deep-copied')
		t.assert_nil(second.upgrades.player, 'upgrades must be deep-copied')
		t.assert_equal(second.ducking, false, 'fresh context ducking')
		t.assert_true(first ~= second, 'context.get() must return a new table')

		local rank = context.get({difficulty = 'sm_wish'}).difficulty_rank
		t.assert_equal(rank, 8, 'difficulty override recomputes the rank')
	end)

	t.test('context.capture() reads Global.game_settings.difficulty', function()
		local previous = rawget(_G, 'Global')
		_G.Global = {game_settings = {difficulty = 'overkill'}}
		context.invalidate()

		local ctx = fresh_context()

		t.assert_equal(ctx.difficulty, 'overkill', 'captured difficulty')
		t.assert_equal(ctx.difficulty_rank, 4, 'captured difficulty rank')

		_G.Global = previous
	end)

	t.test('context upgrade lookup delegates to managers.player and caches per render', function()
		local extra_calls = 0
		local stub = {
			player = {
				upgrade_value = function(_, category, upgrade, default)
					if category == 'player' and upgrade == 'extra_ammo_multiplier' then
						extra_calls = extra_calls + 1

						return 1.5
					end

					return default
				end,
				has_category_upgrade = function(_, category, upgrade)
					return category == 'player' and upgrade == 'add_armor_stat_skill_ammo_mul'
				end,
				body_armor_value = function()
					return 1.25
				end,
				get_property = function(_, name, default)
					return default
				end,
			},
		}

		with_managers(stub, function()
			context.invalidate()
			local ctx = fresh_context()

			t.assert_equal(ctx:upgrade_value('player', 'extra_ammo_multiplier', 1), 1.5, 'upgrade value')
			t.assert_equal(ctx:upgrade_value('player', 'extra_ammo_multiplier', 1), 1.5, 'cached upgrade value')
			t.assert_equal(ctx:upgrade_value('weapon', 'not_a_real_upgrade', 0.25), 0.25, 'upgrade default')
			t.assert_equal(extra_calls, 1, 'upgrade_value queried once per render')
			t.assert_equal(ctx:has_category_upgrade('player', 'add_armor_stat_skill_ammo_mul'), true, 'has_category_upgrade')
			t.assert_equal(ctx:body_armor_value('skill_ammo_mul', nil, 1), 1.25, 'body_armor_value')
		end)
	end)

	t.test('context upgrade cache keys include the requested default', function()
		local calls = 0
		local stub = {
			player = {
				-- PlayerManager:upgrade_value returns `default or 0`.
				upgrade_value = function(_, _, _, default)
					calls = calls + 1

					return default or 0
				end,
			},
		}

		with_managers(stub, function()
			local ctx = fresh_context()

			t.assert_equal(ctx:upgrade_value('weapon', 'clip_ammo_increase', 0), 0, 'default 0')
			t.assert_equal(ctx:upgrade_value('weapon', 'clip_ammo_increase', 5), 5, 'default 5 is not the cached 0')
			t.assert_equal(ctx:upgrade_value('weapon', 'clip_ammo_increase'), 0, 'nil default resolves to 0')
			t.assert_equal(calls, 3, 'each default is queried once')
		end)
	end)

	t.test('context capture reads skills, perks, detection risk and competitive', function()
		local lerp_seen
		local stub = {
			skilltree = {
				_global = {
					skills = {
						shotgun_impact = {unlocked = 2, total = 3},
						iron_man = {unlocked = 1, total = 1},
					},
					specializations = {
						current_specialization = 2,
						[1] = {points_spent = 5},
						[2] = {points_spent = 9},
						points = 14,
					},
				},
			},
			blackmarket = {
				get_suspicion_offset_of_local = function(_, lerp)
					lerp_seen = lerp

					return 0.42
				end,
			},
			job = {
				is_current_job_competitive = function()
					return true
				end,
			},
		}

		with_managers(stub, function()
			local ctx = fresh_context()

			t.assert_equal(ctx.skills.shotgun_impact, 2, 'skill unlocked level')
			t.assert_equal(ctx.skills.iron_man, 1, 'second skill level')
			t.assert_nil(ctx.skills.current_specialization, 'only real skills are captured')
			t.assert_equal(ctx.perks[1], 5, 'perk deck 1 points')
			t.assert_equal(ctx.perks[2], 9, 'perk deck 2 points')
			t.assert_nil(ctx.perks.points, 'scalar specialization fields are skipped')
			assert_near(t, lerp_seen, 0.75, 'suspicion lerp falls back to 0.75')
			t.assert_equal(ctx.detection_risk, 42, 'detection risk is the rounded suspicion offset * 100')
			t.assert_equal(ctx.competitive, true, 'competitive job flag')
		end)
	end)

	t.test('context leaves detection_risk nil without a loadout and competitive false', function()
		local ctx = fresh_context()

		t.assert_nil(ctx.detection_risk, 'no blackmarket manager means no detection risk')
		t.assert_equal(ctx.competitive, false, 'default not competitive')
	end)

	for _, expected in ipairs(EXPECTED) do
		t.test('WeaponModel core stats: ' .. expected.name, function()
			local ctx = fresh_context()
			local model = weapon.new(expected.id, nil, ctx)

			t.assert_type(model, 'table', expected.id .. ' model')
			t.assert_equal(model._name_id, expected.id, 'name id')
			t.assert_equal(model._npc, false, 'player model')
			t.assert_equal(model:categories()[1], expected.categories[1], 'primary category')
			t.assert_equal(#model:categories(), #expected.categories, 'category count')

			for _, category in ipairs(expected.categories) do
				t.assert_equal(model:is_category(category), true, 'is_category ' .. category)
			end

			t.assert_equal(model._current_stats_indices.damage, expected.damage_index, 'damage index')
			assert_near(t, model._current_stats.damage, expected.damage, 'resolved damage stat')
			assert_near(t, model._damage, expected.damage, 'weapon damage')

			t.assert_equal(model:get_ammo_max_per_clip(), expected.clip, 'magazine size')
			t.assert_equal(model:get_ammo_total(), expected.total, 'total ammo')
			t.assert_equal(model:get_ammo_max(), expected.total, 'ammo max')

			assert_near(t, model:weapon_fire_rate(), expected.fire_rate, 'fire interval')
			assert_near(t, model:mode_fire_rate(), expected.fire_mode_rate, 'mode fire interval')
			assert_near(t, model:fire_rate_rpm(), 60 / expected.fire_rate, 'fire rate rpm')
			assert_near(t, model._next_fire_allowed, expected.fire_rate, 'next fire interval')
			t.assert_equal(model:fire_rate_multiplier(), 1, 'fire rate multiplier')
			t.assert_equal(model._fire_mode_category, expected.fire_mode, 'fire mode category')
			t.assert_equal(model:can_toggle_firemode(), expected.toggle, 'can toggle firemode')

			t.assert_equal(model:concealment(), expected.concealment, 'concealment')
			assert_near(t, model:suspicion(), expected.suspicion, 'suspicion')

			t.assert_type(model.parts, 'table', 'parts table')
			t.assert_type(model.blueprint, 'table', 'blueprint')
			t.assert_type(model._factory_id, 'string', 'factory id')
		end)
	end

	t.test('default blueprints resolve adds, forbids and factory overrides', function()
		local ctx = fresh_context()

		local default = weapon.new('amcar', nil, ctx)
		local overridden = default.parts['wpn_fps_m4_uupg_b_medium_vanilla']
		t.assert_type(overridden, 'table', 'default barrel part')
		t.assert_equal(
			overridden.unit,
			'units/payday2/weapons/wpn_fps_ass_m4_pts/wpn_fps_para_b_medium',
			'factory override applied to the part data'
		)

		local scoped = weapon.new('amcar', fixtures.blueprints.amcar_scope, ctx)

		t.assert_type(scoped.blueprint[3], 'string', 'blueprint still carries the upper receiver')
		t.assert_equal(scoped.blueprint[3], 'wpn_fps_amcar_uupg_body_upperreciever', 'default upper receiver is in the blueprint')
		t.assert_nil(scoped.parts['wpn_fps_amcar_uupg_body_upperreciever'], 'scope forbids the default upper receiver')
		-- The factory adds three rail parts for the scope; the default (now
		-- forbidden) receiver forbids all three, so they stay in the assembled
		-- blueprint but not in the part table.
		local added = scoped._assembled_blueprint
		t.assert_true(contains_string(added, 'wpn_fps_m4_uupg_fg_rail_ext'), 'factory adds the rail extension')
		t.assert_true(contains_string(added, 'wpn_fps_m4_uupg_draghandle_vanilla'), 'factory adds the draghandle')
		t.assert_true(contains_string(added, 'wpn_fps_m4_upper_reciever_round_vanilla'), 'factory adds the round upper')
		t.assert_nil(scoped.parts['wpn_fps_m4_uupg_fg_rail_ext'], 'forbidden receiver forbids the rail extension')
		t.assert_nil(scoped.parts['wpn_fps_m4_uupg_draghandle_vanilla'], 'forbidden receiver forbids the draghandle')
		t.assert_nil(scoped.parts['wpn_fps_m4_upper_reciever_round_vanilla'], 'forbidden receiver forbids the round upper')
		t.assert_equal(scoped:concealment(), 18, 'scope part stats lower concealment')
		assert_near(t, scoped:suspicion(), 1.05, 'suspicion uses part concealment')
		assert_near(t, scoped._recoil, 1.0, 'recoil index +1 resolved')
		assert_near(t, scoped._zoom, 45, 'scope zoom index resolved')
		t.assert_equal(scoped:get_ammo_max_per_clip(), 20, 'magazine untouched')
	end)

	t.test('blueprint parts with adds_type pull the factory adapter', function()
		local ctx = fresh_context()
		local model = weapon.new('new_m4', fixtures.blueprints.car4_stock, ctx)

		t.assert_type(model.parts['wpn_fps_upg_m4_s_adapter'], 'table', 'stock adapter added via adds_type')
		t.assert_equal(model:concealment(), 19, 'stock concealment -1')
		assert_near(t, model:suspicion(), 1.0, 'suspicion from modified concealment')
		t.assert_equal(model:get_ammo_max_per_clip(), 30, 'magazine untouched by the stock')
		t.assert_equal(model:is_category('assault_rifle'), true, 'still an assault rifle')
	end)

	t.test('skin bonuses apply to stat indices and concealment', function()
		local ctx = fresh_context()
		local model = weapon.new('new_m4', nil, ctx, {id = 'new_m4_goldstripes', bonus = 'concealment_p1'})

		assert_near(t, model._current_stats.concealment, 1.35, 'concealment index +1')
		t.assert_equal(model:concealment(), 21, 'concealment value includes the skin bonus')
		assert_near(t, model:suspicion(), 0.85, 'suspicion ignores the skin bonus, like the game')
	end)

	t.test('total_ammo skin bonus scales the reserve pool', function()
		local ctx = fresh_context()
		local plain = weapon.new('m95', nil, ctx)
		local skinned = weapon.new('m95', nil, ctx, {bonus = 'total_ammo_p1'})

		assert_near(t, plain._total_ammo_mod, 0, 'default total ammo modifier')
		assert_near(t, skinned._total_ammo_mod, 0.05, 'skin total ammo modifier')
		t.assert_equal(plain:get_ammo_total(), 15, 'default reserve')
		t.assert_equal(skinned:get_ammo_total(), 16, 'reserve after +5% (15.75 rounded)')
	end)

	t.test('damage skin bonus moves the damage index', function()
		local ctx = fresh_context()
		local model = weapon.new('new_m4', nil, ctx, {bonus = 'damage_p2'})

		t.assert_equal(model._current_stats_indices.damage, 64, 'damage index +2')
		assert_near(t, model._damage, 6.4, 'damage after skin bonus')
	end)

	t.test('ammo parts feed _ammo_data and non-ammo custom stats fold into it', function()
		local ctx = fresh_context()
		local model = weapon.new('new_m4', {'wpn_fps_ammo_type'}, ctx)

		t.assert_type(model._ammo_data, 'table', 'ammo data table')
		assert_near(t, model._ammo_data.ammo_pickup_max_mul, 0.6, 'ammo pickup max multiplier')
		assert_near(t, model._ammo_data.ammo_pickup_min_mul, 0.4, 'ammo pickup min multiplier')

		-- newraycastweaponbase.lua:932-938 multiplies the pickup muls from
		-- non-ammo parts into the ammo part's custom_stats.
		local pickup = weapon.new('new_m4', fixtures.blueprints.car4_ammo_pickup, ctx)
		assert_near(t, pickup._ammo_data.ammo_pickup_min_mul, 0.4 * 1.2, 'folded pickup min multiplier')
		assert_near(t, pickup._ammo_data.ammo_pickup_max_mul, 0.6 * 1.2, 'folded pickup max multiplier')

		-- newraycastweaponbase.lua:944-946 stores (value - 1) for fire rate.
		local fast = weapon.new('new_m4', fixtures.blueprints.car4_fire_rate_part, ctx)
		assert_near(t, fast._ammo_data.fire_rate_multiplier, 0.3, 'folded fire rate delta')
		assert_near(t, fast:fire_rate_multiplier(), 1.3, 'fire rate multiplier applied')
		assert_near(t, fast._next_fire_allowed, 0.1 / 1.3, 'next fire interval uses the multiplier')
	end)

	t.test('new_from_slot forwards cosmetics to the player model', function()
		local skinned = weapon.new_from_slot('new_m4', nil, {npc = false, cosmetics = {bonus = 'damage_p2'}})

		t.assert_type(skinned, 'table', 'skinned slot model')
		t.assert_equal(skinned._current_stats_indices.damage, 64, 'cosmetics reached the stat indices')
		assert_near(t, skinned._damage, 6.4, 'damage skin bonus applied from the slot path')
	end)

	t.test('NPC models read damage, magazine, alert size and suppression from the crew entry', function()
		local crew = weapon.new_from_slot('new_m4', nil, {npc = true})

		t.assert_type(crew, 'table', 'crew model')
		t.assert_equal(crew._name_id, 'm4_crew', 'crew tweak id')
		t.assert_equal(crew._npc, true, 'npc flag')
		t.assert_equal(crew._factory_id, 'wpn_fps_ass_m4_npc', 'crew factory clone')
		t.assert_equal(crew:weapon_tweak_data().usage, 'is_rifle', 'crew usage data')
		t.assert_equal(crew:categories()[1], 'assault_rifle', 'categories come from the crew entry')
		assert_near(t, crew._damage, 1.5, 'crew DAMAGE, not player stat indices')
		t.assert_equal(crew:get_ammo_max_per_clip(), 30, 'crew CLIP_AMMO_MAX')
		t.assert_nil(crew:get_ammo_total(), 'crew entries define no AMMO_MAX in 248.2')
		assert_near(t, crew._alert_size, 5000, 'crew alert_size')
		assert_near(t, crew._suppression, 1, 'crew suppression')
		assert_near(t, crew:weapon_fire_rate(), 0.1, 'crew auto fire rate')
		t.assert_equal(crew:fire_rate_multiplier(), 1, 'npc skips player fire-rate upgrades')
		assert_near(t, crew._next_fire_allowed, 0.1, 'npc fire interval')
		t.assert_equal(crew:concealment(), 0, 'npc weapons have no concealment')
		t.assert_nil(crew:suspicion(), 'npc weapons have no suspicion')
		t.assert_nil(crew:can_toggle_firemode(), 'crew entry has no CAN_TOGGLE_FIREMODE')

		-- Task 6 formats these with %.2f; NPC models must expose numbers, never nil.
		for _, field in ipairs({'damage', 'spread', 'spread_moving', 'recoil', 'zoom', 'reload', 'alert_size', 'suppression'}) do
			t.assert_type(crew._current_stats[field], 'number', 'crew numeric stat ' .. field)
		end

		t.assert_type(crew._recoil, 'number', 'crew _recoil')
		t.assert_type(crew._spread, 'number', 'crew _spread')
		t.assert_type(crew._spread_moving, 'number', 'crew _spread_moving')
		t.assert_type(crew._zoom, 'number', 'crew _zoom')
		t.assert_type(crew._reload, 'number', 'crew _reload')
		t.assert_type(crew._alert_size, 'number', 'crew _alert_size')
		t.assert_type(crew._suppression, 'number', 'crew _suppression')

		local mapped = weapon.new_from_slot('glock_17', {}, {npc = true})
		t.assert_type(mapped, 'table', 'mapped crew model')
		t.assert_equal(mapped._name_id, 'g17_crew', 'glock_17 -> g17_crew mapping')
		assert_near(t, mapped._damage, 1, 'g17_crew DAMAGE')
		t.assert_equal(mapped:get_ammo_max_per_clip(), 17, 'g17_crew CLIP_AMMO_MAX')
		t.assert_nil(mapped:weapon_fire_rate(), 'single-fire crew weapon has no interval')
		t.assert_nil(mapped:fire_rate_rpm(), 'single-fire crew weapon must not invent an RPM')
		t.assert_nil(mapped._next_fire_allowed, 'no next-fire interval without an auto rate')
		t.assert_nil(mapped:mode_fire_rate(), 'g17_crew has no auto fire rate')
		assert_near(t, mapped._alert_size, 2500, 'g17_crew alert_size')
		t.assert_equal(mapped:is_category('pistol'), true, 'glock category')
		t.assert_equal(mapped._npc, true, 'glock npc flag')
		t.assert_type(mapped._recoil, 'number', 'g17 _recoil is a number')
		t.assert_type(mapped._spread_moving, 'number', 'g17 _spread_moving is a number')

		local player = weapon.new_from_slot('new_m4', nil, {npc = false})
		t.assert_equal(player._name_id, 'new_m4', 'player slot keeps the weapon id')
		t.assert_equal(player._npc, false, 'player slot is not npc')

		t.assert_nil(weapon.new_from_slot('not_a_weapon', nil, {npc = true}), 'unknown weapon returns nil')
	end)

	t.test('weapon.new() returns nil when tweak data cannot support a model', function()
		local ctx = fresh_context()

		t.assert_nil(weapon.new('not_a_weapon', nil, ctx), 'unknown id')
		t.assert_nil(weapon.new('m4_crew', nil, ctx), 'crew entry without a stat source')

		local stale = weapon.new('amcar', {'part_that_does_not_exist'}, ctx)
		t.assert_type(stale, 'table', 'stale parts still produce a base-stat model')
		t.assert_nil(stale.parts['part_that_does_not_exist'], 'unknown part is not recorded')
	end)

	t.test('context upgrades feed damage and ammo like the game managers', function()
		local stub = {
			player = {
				upgrade_value = function(_, category, upgrade, default)
					if category == 'player' and upgrade == 'damage_addend' then
						return 1
					elseif category == 'assault_rifle' and upgrade == 'damage_multiplier' then
						return 1.5
					elseif category == 'player' and upgrade == 'extra_ammo_multiplier' then
						return 1.5
					end

					return default
				end,
				has_category_upgrade = function(_, category, upgrade)
					return category == 'player' and upgrade == 'add_armor_stat_skill_ammo_mul'
				end,
				body_armor_value = function()
					return 1.25
				end,
				get_property = function(_, name, default)
					return default
				end,
			},
		}

		with_managers(stub, function()
			context.invalidate()
			local ctx = fresh_context()
			local model = weapon.new('new_m4', nil, ctx)

			-- (6.2 + 1) * 1.5 (category damage multiplier converts to 1.5)
			assert_near(t, model._damage, 10.8, 'damage with skill addend/multiplier')
			-- 150 * 1.5 (player extra ammo) * 1.25 (armor skill ammo) = 281.25 -> 281
			t.assert_equal(model:get_ammo_total(), 281, 'reserve with ammo upgrades')
			t.assert_equal(model:get_ammo_max_per_clip(), 30, 'clip unaffected by reserve upgrades')
		end)
	end)

	t.test('formula modules answer for a real weapon and stay nil without data', function()
		local ctx = fresh_context()
		local model = weapon.new('amcar', nil, ctx)

		t.assert_type(MoreWeaponStats.core.timers.reload_full(model, 0, ctx), 'number', 'timers.reload_full')
		t.assert_type(MoreWeaponStats.core.timers.reload_partial(model, 1, ctx), 'number', 'timers.reload_partial')
		t.assert_type(MoreWeaponStats.core.timers.equip_delay(model, ctx), 'number', 'timers.equip_delay')
		t.assert_type(MoreWeaponStats.core.accuracy.spread_horizontal(model, ctx), 'number', 'accuracy.spread_horizontal')
		t.assert_type(MoreWeaponStats.core.accuracy.recoil_vertical(model, ctx), 'number', 'accuracy.recoil_vertical')
		t.assert_type(MoreWeaponStats.core.ballistics.get_damage_falloff(model, 500, ctx), 'number', 'ballistics.get_damage_falloff')
		t.assert_type(MoreWeaponStats.core.ammo.ammo_pickup(model, ctx), 'number', 'ammo.ammo_pickup')
		t.assert_type(model:get_damage_falloff(100, 500, ctx), 'number', 'model falloff')
		t.assert_nil(weapon.new_from_slot('new_m4', nil, {npc = true}):reload_speed_multiplier(), 'crew model reload speed')

		-- A hand-built weapon without tweak data must not invent numbers.
		local unknown = {_name_id = 'not_a_weapon'}
		t.assert_nil(MoreWeaponStats.core.timers.reload_full(unknown, 0, ctx), 'unknown weapon reload')
		t.assert_nil(MoreWeaponStats.core.ammo.ammo_pickup(unknown, ctx), 'unknown weapon pickup')
		t.assert_nil(MoreWeaponStats.core.accuracy.spread_horizontal(unknown, ctx), 'unknown weapon spread')
	end)

	t.test('ui modules expose the stat/refresh seam', function()
		-- stats_panel has no per-page state and melee/henchmen build rows in
		-- `_setup`; only breakpoints_panel owns widget-tree state, so it is the
		-- only adapter with an init seam.
		local stats_panel = MoreWeaponStats.ui.stats_panel
		t.assert_type(stats_panel.rows, 'function', 'ui.stats_panel.rows')
		t.assert_type(stats_panel.refresh, 'function', 'ui.stats_panel.refresh')
		t.assert_type(stats_panel.visible, 'function', 'ui.stats_panel.visible')
		t.assert_nil(stats_panel.init, 'stats_panel has no dead init seam')

		for _, name in ipairs({'melee', 'henchmen'}) do
			local module = MoreWeaponStats.ui[name]
			t.assert_type(module.rows, 'function', 'ui.' .. name .. '.rows')
			t.assert_type(module.refresh, 'function', 'ui.' .. name .. '.refresh')
			t.assert_nil(module.init, 'ui.' .. name .. ' has no dead init seam')
		end

		t.assert_type(MoreWeaponStats.ui.breakpoints_panel.init, 'function', 'ui.breakpoints_panel.init')
		t.assert_type(MoreWeaponStats.ui.breakpoints_panel.refresh, 'function', 'ui.breakpoints_panel.refresh')
	end)
end
