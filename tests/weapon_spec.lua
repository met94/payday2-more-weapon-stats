--[[
tests/weapon_spec.lua — scaffold smoke tests for the clean rewrite (Task 1).

These tests pin the seams the rest of the rewrite depends on:
  * entry.lua's bootstrap loads every core/ui/compat module,
  * core.context.get() returns the documented default fields,
  * core.weapon and the formula modules return nil instead of invented values.

They are deliberately not formula tests; Tasks 2-4 add those.
]]

local fixtures = dofile(ModPath .. 'tests/fixtures.lua')

return function(t)
	t.test('entry bootstrap loads the core, ui and compat modules', function()
		local core = MoreWeaponStats.core
		local ui = MoreWeaponStats.ui

		for _, name in ipairs({ 'context', 'weapon', 'ballistics', 'timers', 'accuracy', 'ammo' }) do
			t.assert_type(core and core[name], 'table', 'MoreWeaponStats.core.' .. name)
		end

		for _, name in ipairs({ 'stats_panel', 'breakpoints_panel', 'melee', 'henchmen' }) do
			t.assert_type(ui and ui[name], 'table', 'MoreWeaponStats.ui.' .. name)
		end

		t.assert_type(MoreWeaponStats.compat, 'table', 'MoreWeaponStats.compat')
		t.assert_type(MoreWeaponStats.compat.init, 'function', 'MoreWeaponStats.compat.init')
	end)

	t.test('context.get() returns the documented defaults', function()
		local context = MoreWeaponStats.core.context.get()

		t.assert_equal(context.difficulty, 'overkill_290', 'default difficulty')
		t.assert_equal(context.difficulty_rank, 7, 'default difficulty rank')
		t.assert_equal(context.moving, false, 'default moving')
		t.assert_equal(context.ducking, false, 'default ducking')
		t.assert_equal(context.steelsight, false, 'default steelsight')
		t.assert_equal(context.deployed, false, 'default deployed')
		t.assert_type(context.skills, 'table', 'default skills')
		t.assert_type(context.perks, 'table', 'default perks')
		t.assert_type(context.upgrades, 'table', 'default upgrades')
	end)

	t.test('context.get() applies overrides without leaking into later contexts', function()
		local first = MoreWeaponStats.core.context.get({ ducking = true, steelsight = true })
		t.assert_equal(first.ducking, true, 'overridden ducking')
		t.assert_equal(first.steelsight, true, 'overridden steelsight')

		local second = MoreWeaponStats.core.context.get()
		t.assert_equal(second.ducking, false, 'fresh context ducking')
		t.assert_true(first ~= second, 'context.get() must return a new table')
	end)

	t.test('weapon.new() returns nil by design until Task 2', function()
		local weapon = fixtures.weapons[1]
		local model = MoreWeaponStats.core.weapon.new(weapon.id, fixtures.blueprints[weapon.id], fixtures.context)
		t.assert_nil(model, 'core.weapon.new(' .. weapon.id .. ')')
	end)

	t.test('weapon.new_from_slot() returns nil by design until Task 2', function()
		local weapon = fixtures.weapons[1]
		local model = MoreWeaponStats.core.weapon.new_from_slot(weapon.id, fixtures.blueprints[weapon.id], { npc = false })
		t.assert_nil(model, 'core.weapon.new_from_slot(' .. weapon.id .. ')')
	end)

	t.test('formula stubs return nil instead of invented numbers', function()
		local weapon = fixtures.weapons[1].id
		local context = MoreWeaponStats.core.context.get()

		t.assert_nil(MoreWeaponStats.core.timers.reload_full(weapon, 0, context), 'timers.reload_full')
		t.assert_nil(MoreWeaponStats.core.timers.reload_partial(weapon, 1, context), 'timers.reload_partial')
		t.assert_nil(MoreWeaponStats.core.timers.equip_delay(weapon, context), 'timers.equip_delay')
		t.assert_nil(MoreWeaponStats.core.accuracy.spread_horizontal(weapon, context), 'accuracy.spread_horizontal')
		t.assert_nil(MoreWeaponStats.core.accuracy.recoil_vertical(weapon, context), 'accuracy.recoil_vertical')
		t.assert_nil(MoreWeaponStats.core.ballistics.get_damage_falloff(weapon, 500, context), 'ballistics.get_damage_falloff')
		t.assert_nil(MoreWeaponStats.core.ammo.ammo_pickup(weapon, context), 'ammo.ammo_pickup')
	end)

	t.test('ui modules expose the init/refresh seam', function()
		for _, name in ipairs({ 'stats_panel', 'breakpoints_panel', 'melee', 'henchmen' }) do
			local module = MoreWeaponStats.ui[name]
			t.assert_type(module.init, 'function', 'ui.' .. name .. '.init')
			t.assert_type(module.refresh, 'function', 'ui.' .. name .. '.refresh')
		end
	end)
end
