--[[
tests/fixtures.lua — placeholder fixtures for the More Weapon Stats test suite.

Task 1 only needs stable, real identifiers to prove that the scaffold loads.
Task 2 replaces the empty blueprint tables with real factory part lists and adds
the expected values (damage, magazine, concealment, ...) taken from tweak data.
Nothing in this file is a computed expectation yet.

Weapon ids are real PAYDAY 2 tweak ids (tweak_data.weapon): AMCAR, CAR-4, M308,
Judge, Compact-5, KSP, R93, akimbo Goliath and the OVE9000 saw.
]]

local fixtures = {}

fixtures.weapons = {
	{ id = 'amcar', name = 'AMCAR', category = 'primaries' },
	{ id = 'new_m4', name = 'CAR-4', category = 'primaries' },
	{ id = 'new_m14', name = 'M308', category = 'primaries' },
	{ id = 'judge', name = 'Judge', category = 'secondaries' },
	{ id = 'new_mp5', name = 'Compact-5', category = 'secondaries' },
	{ id = 'm249', name = 'KSP', category = 'primaries' },
	{ id = 'r93', name = 'R93', category = 'primaries' },
	{ id = 'x_sko12', name = 'Akimbo Goliath', category = 'secondaries' },
	{ id = 'saw', name = 'OVE9000 Saw', category = 'primaries' },
}

fixtures.blueprints = {
	-- Task 2: factory part ids per weapon, for example { 'wpn_fps_upg_o_spot' }.
	-- An empty list means "default blueprint".
	amcar = {},
	new_m4 = {},
	new_m14 = {},
	judge = {},
	new_mp5 = {},
	m249 = {},
	r93 = {},
	x_sko12 = {},
	saw = {},
}

fixtures.context = {
	difficulty = 'overkill_290',
	difficulty_rank = 7,
	ducking = false,
	steelsight = false,
}

fixtures.skills = {
	-- Task 2 / Task 4: skill_name -> level, for example prison_wife = 1.
}

return fixtures
