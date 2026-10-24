--[[
tests/fixtures.lua — real PAYDAY 2 248.2 tweak data for the headless tests.

Everything below is copied from the decompiled 248.2 source tree
(game-data/Payday-2-LuaJIT-Complete). Source lines are given per table; only the
fields the model consumes are copied, plus the factory parts needed by the
default blueprints and the blueprint-mutation cases. Do not add invented values
here: extend the copy from the game file instead.

Weapons: AMCAR, CAR-4 (new_m4), M308 (new_m14), Judge, Grimm (basset), KSP
(m249), Thanatos (m95), akimbo MP5 (x_mp5), Supernova (shell-by-shell reload),
Contender (single-round clip) and the NPC fixture glock_17. Glock 17 doubles as
the pistol of the breakpoint cases.

Enemy tables for the breakpoint maths: tweak_data.character entries for the six
table units, tweak_data.weapon_disable_crit_for_damage, and the
tweak_data.upgrades.values entries the bonus toggles read.

Falloff templates, AMMO_PICKUP tables, reload/equip timers, spread and kick
tables are the real 248.2 values; the distance maths itself lives in
lua/core/ballistics.lua.
]]

local fixtures = {}

-- tweak_data.weapon.stats (lib/tweak_data/weapontweakdata.lua:5957-6390) -----

-- lib/tweak_data/weapontweakdata.lua:5958-5979
local alert_size = {
	30000, 20000, 15000, 10000, 7500, 6000, 4500, 4000, 3500, 1800,
	1500, 1200, 1000, 850, 700, 500, 350, 200, 100, 0,
}

-- lib/tweak_data/weapontweakdata.lua:5980-6001
local suppression = {
	4.5, 3.9, 3.6, 3.3, 3, 2.8, 2.6, 2.4, 2.2, 1.6,
	1.5, 1.4, 1.3, 1.2, 1.1, 1, 0.8, 0.6, 0.4, 0.2,
}

-- lib/tweak_data/weapontweakdata.lua:6002-6213 (0.1 .. 21 step 0.1)
local damage = {}
for index = 1, 210 do
	damage[index] = index / 10
end

-- lib/tweak_data/weapontweakdata.lua:6229-6240
local zoom = {63, 60, 55, 50, 45, 40, 35, 30, 25, 20}

-- lib/tweak_data/weapontweakdata.lua:6243-6270
local spread = {
	2, 1.92, 1.84, 1.76, 1.68, 1.6, 1.52, 1.44, 1.36, 1.28, 1.2, 1.12, 1.04,
	0.96, 0.88, 0.8, 0.72, 0.64, 0.56, 0.48, 0.4, 0.32, 0.24, 0.16, 0.08, 0,
}

-- lib/tweak_data/weapontweakdata.lua:6271-6298
local spread_moving = {
	2.5, 2.42, 2.34, 2.26, 2.18, 2.1, 2.02, 1.94, 1.86, 1.78, 1.7, 1.62, 1.54,
	1.46, 1.38, 1.3, 1.22, 1.14, 1.06, 0.98, 0.9, 0.82, 0.74, 0.66, 0.58, 0.5,
}

-- lib/tweak_data/weapontweakdata.lua:6299-6326
local recoil = {
	3, 2.9, 2.8, 2.7, 2.6, 2.5, 2.4, 2.3, 2.2, 2.1, 2, 1.9, 1.8, 1.7, 1.6, 1.5,
	1.4, 1.3, 1.2, 1.1, 1, 0.9, 0.8, 0.7, 0.6, 0.5,
}

-- lib/tweak_data/weapontweakdata.lua:6327-6338
local value = {1, 2, 3, 4, 5, 6, 7, 8, 9, 10}

-- lib/tweak_data/weapontweakdata.lua:6339-6369
local concealment = {
	0.3, 0.4, 0.5, 0.6, 0.65, 0.7, 0.75, 0.8, 0.825, 0.85, 1, 1.05, 1.1, 1.15,
	1.2, 1.225, 1.25, 1.275, 1.3, 1.325, 1.35, 1.375, 1.4, 1.425, 1.45, 1.475,
	1.5, 1.525, 1.55, 1.6,
}

-- lib/tweak_data/weapontweakdata.lua:6371-6375
local extra_ammo = {}
for value_at_index = -100, 100, 2 do
	extra_ammo[#extra_ammo + 1] = value_at_index
end

-- lib/tweak_data/weapontweakdata.lua:6377-6381
local total_ammo_mod = {}
for value_at_index = -100, 100, 5 do
	total_ammo_mod[#total_ammo_mod + 1] = value_at_index / 100
end

-- lib/tweak_data/weapontweakdata.lua:6383-6389
local reload = {}
for value_at_index = 5, 20, 0.5 do
	if value_at_index <= 10 or value_at_index == math.floor(value_at_index) then
		reload[#reload + 1] = value_at_index / 10
	end
end

-- Shared weapon tables ------------------------------------------------------

-- lib/tweak_data/weapontweakdata.lua:6759-6774 (CAR-4; AMCAR, M308, Judge,
-- Grimm, KSP, Thanatos, akimbo MP5 and Glock 17 copy it verbatim).
local m4_spread = {
	standing = 3,
	crouching = 3 * 0.4,
	steelsight = 3 * 0.4,
	moving_standing = 3,
	moving_crouching = 3,
	moving_steelsight = 3 * 0.4,
}

-- lib/tweak_data/weapontweakdata.lua:6766-6774
local m4_kick_standing = {0.6, 0.8, -1, 1}

--[[
lib/tweak_data/WeaponFalloffTweakData.lua:3-231 (falloff templates). Copied per
template, with the source line of each block.
]]
local falloff = {
	-- :209-216
	SHOTGUN_FALL_SECONDARY_VERYHIGH = {
		optimal_distance = 800, optimal_range = 600,
		near_falloff = 0, near_multiplier = 1,
		far_falloff = 400, far_multiplier = 0.7,
	},
	-- :185-192
	SHOTGUN_FALL_SECONDARY_LOW = {
		optimal_distance = 600, optimal_range = 500,
		near_falloff = 0, near_multiplier = 1,
		far_falloff = 300, far_multiplier = 0.6,
	},
	-- :14-21
	SHOTGUN_FALL_PRIMARY_MEDIUM = {
		optimal_distance = 700, optimal_range = 700,
		near_falloff = 350, near_multiplier = 1,
		far_falloff = 2100, far_multiplier = 0.5,
	},
	-- :54-61
	SNIPER_FALL_VERYHIGH = {
		optimal_distance = 0, optimal_range = 2500,
		near_falloff = 0, near_multiplier = 1,
		far_falloff = 500, far_multiplier = 1.2,
	},
	-- :46-53
	SNIPER_FALL_HIGH = {
		optimal_distance = 0, optimal_range = 2500,
		near_falloff = 0, near_multiplier = 1,
		far_falloff = 1000, far_multiplier = 1.2,
	},
	-- :118-125
	AKI_SMG_FALL_LOW = {
		optimal_distance = 700, optimal_range = 700,
		near_falloff = 350, near_multiplier = 1.05,
		far_falloff = 2100, far_multiplier = 0.75,
	},
	-- :62-69
	LMG_FALL_MEDIUM = {
		optimal_distance = 0, optimal_range = 1700,
		near_falloff = 0, near_multiplier = 1,
		far_falloff = 1700, far_multiplier = 0.7,
	},
	-- :150-157
	PISTOL_FALL_LOW = {
		optimal_distance = 600, optimal_range = 600,
		near_falloff = 300, near_multiplier = 1.1,
		far_falloff = 1800, far_multiplier = 0.75,
	},
}

--[[
lib/tweak_data/weapontweakdata.lua:6392-6490 _pickup_chance: AMMO_PICKUP is
{ AMMO_MAX * low, AMMO_MAX * high } for the PICKUP class the weapon passes.
Kept explicit per weapon below; the class constants are noted next to each.
]]

--[[
tweak_data.character.russian.weapon = clone(presets.weapon.gang_member)
(lib/tweak_data/charactertweakdata.lua:3946-3953; `weapons_of_choice` is added
at :3950-3952). The aliases at :9669-9676 share or clone the same tables, so
the unique FALLOFF distances the henchman rows show are 100, 300, 500, 700,
1000, 2000, 2500, 3000, 4000 and 10000. Only the fields the henchman rows read
are copied per usage (aim_delay, spread, RELOAD_SPEED, autofire_rounds and the
FALLOFF entry fields dmg_mul/r/acc/recoil).
]]
local gang_member_weapon = {
	-- :9103-9151
	is_pistol = {
		aim_delay = {0, 0.5},
		spread = 25,
		RELOAD_SPEED = 1.5,
		FALLOFF = {
			{dmg_mul = 5, r = 700, acc = {1, 1}, recoil = {0.25, 0.45}},
			{dmg_mul = 2.5, r = 10000, acc = {1, 1}, recoil = {0.7, 1}},
		},
	},
	-- :9163-9214
	is_rifle = {
		aim_delay = {0, 0.5},
		spread = 25,
		RELOAD_SPEED = 1,
		-- :4601-4604 (presets.weapon.normal.is_rifle.autofire_rounds)
		autofire_rounds = {6, 11},
		FALLOFF = {
			{dmg_mul = 5, r = 300, acc = {1, 1}, recoil = {0.25, 0.45}},
			{dmg_mul = 2.5, r = 10000, acc = {1, 1}, recoil = {1, 1.5}},
		},
	},
	-- :9251-9360
	is_sniper = {
		aim_delay = {0.25, 1},
		spread = 25,
		RELOAD_SPEED = 1,
		FALLOFF = {
			{dmg_mul = 10, r = 500, acc = {1, 1}, recoil = {1, 1}},
			{dmg_mul = 10, r = 1000, acc = {1, 1}, recoil = {2, 3}},
			{dmg_mul = 10, r = 2500, acc = {0.95, 1}, recoil = {2, 3}},
			{dmg_mul = 5, r = 4000, acc = {0.9, 0.95}, recoil = {3, 4}},
			{dmg_mul = 5, r = 10000, acc = {0.85, 0.9}, recoil = {4, 5}},
		},
	},
	-- :9361-9489
	is_lmg = {
		aim_delay = {0, 0.5},
		spread = 30,
		RELOAD_SPEED = 0.7,
		-- :5180-5183 (presets.weapon.normal.is_lmg.autofire_rounds)
		autofire_rounds = {20, 40},
		FALLOFF = {
			{dmg_mul = 4, r = 100, acc = {1, 1}, recoil = {0.25, 0.45}},
			{dmg_mul = 3, r = 1000, acc = {0.85, 0.9}, recoil = {0.4, 0.65}},
			{dmg_mul = 2, r = 2000, acc = {0.6, 0.8}, recoil = {0.8, 1.25}},
			{dmg_mul = 1, r = 3000, acc = {0.5, 0.7}, recoil = {0.8, 1.25}},
			{dmg_mul = 0.4, r = 4000, acc = {0.02, 0.25}, recoil = {1, 2}},
			{dmg_mul = 0.25, r = 10000, acc = {0.01, 0.1}, recoil = {2, 3}},
		},
	},
	-- :9490-9541
	is_shotgun_pump = {
		aim_delay = {0, 0.25},
		spread = 15,
		RELOAD_SPEED = 2,
		FALLOFF = {
			{dmg_mul = 5, r = 300, acc = {1, 1}, recoil = {0.5, 0.9}},
			{dmg_mul = 2.5, r = 10000, acc = {1, 1}, recoil = {1.5, 2}},
		},
	},
	-- :9542-9668
	is_shotgun_mag = {
		aim_delay = {0, 0.25},
		spread = 18,
		RELOAD_SPEED = 1.6,
		autofire_rounds = {4, 8},
		FALLOFF = {
			{dmg_mul = 5, r = 100, acc = {1, 1}, recoil = {0.1, 0.1}},
			{dmg_mul = 5, r = 500, acc = {1, 1}, recoil = {0.1, 0.1}},
			{dmg_mul = 4, r = 1000, acc = {0.85, 0.95}, recoil = {0.1, 0.15}},
			{dmg_mul = 1.5, r = 2000, acc = {0.75, 0.9}, recoil = {0.25, 0.45}},
			{dmg_mul = 0.5, r = 3000, acc = {0.4, 0.7}, recoil = {0.4, 0.5}},
			{dmg_mul = 0.1, r = 10000, acc = {0.05, 0.2}, recoil = {0.5, 1}},
		},
	},
	-- :5276-5370 (presets.weapon.normal.is_flamethrower, shared at :9677)
	is_flamethrower = {
		aim_delay = {0.5, 0.5},
		spread = 0,
		RELOAD_SPEED = 0.6,
		autofire_rounds = {20, 40},
		FALLOFF = {
			{dmg_mul = 6, r = 100, acc = {1, 1}, recoil = {0.15, 0.25}},
			{dmg_mul = 5, r = 500, acc = {1, 1}, recoil = {0.45, 0.65}},
			{dmg_mul = 4, r = 1000, acc = {1, 1}, recoil = {0.75, 1}},
			{dmg_mul = 2, r = 2000, acc = {1, 1}, recoil = {0.75, 1}},
			{dmg_mul = 1, r = 3000, acc = {1, 1}, recoil = {0.75, 1}},
		},
	},
}

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

-- :9670-9676: the aliases collapse onto the tables above; `rifle` is a deep
-- clone of is_rifle with autofire_rounds removed (:9674-9675), not the same
-- table, so it is modelled separately.
gang_member_weapon.is_revolver = gang_member_weapon.is_pistol
gang_member_weapon.is_smg = gang_member_weapon.is_rifle
gang_member_weapon.is_bullpup = gang_member_weapon.is_rifle
gang_member_weapon.mac11 = gang_member_weapon.is_rifle
gang_member_weapon.akimbo_pistol = gang_member_weapon.is_pistol

gang_member_weapon.rifle = deep_copy(gang_member_weapon.is_rifle)
gang_member_weapon.rifle.autofire_rounds = nil

-- :3950-3952: the crew weapon the gang-member preset spawns.
gang_member_weapon.weapons_of_choice = {
	primary = 'wpn_fps_ass_m4_npc',
}

fixtures.tweak_data = {
	-- lib/tweak_data/tweakdata.lua:373-382
	difficulties = {'easy', 'normal', 'hard', 'overkill', 'overkill_145', 'easy_wish', 'overkill_290', 'sm_wish'},

	--[[
	The six enemy types the breakpoint table shows. Base (un-scaled) values as
	CharacterTweakData builds them in `_init_*`; the game multiplies these in
	place per difficulty, so tweak_data.character at runtime holds different
	numbers. lua/core/breakpoints.lua therefore scales the base constants it
	documents and only reads the non-scaled fields (tags, critical_hits,
	ignore_headshot, damage.explosion_damage_mul, damage clamps) from here.
	]]
	character = {
		-- lib/tweak_data/charactertweakdata.lua:425-462 (_init_swat)
		swat = {
			HEALTH_INIT = 8,          -- :433
			headshot_dmg_mul = 2,     -- :434
			tags = {'law'},           -- :427-429
			damage = {explosion_damage_mul = 1}, -- presets.base :4302-4305
		},
		-- :464-506 (_init_heavy_swat)
		heavy_swat = {
			HEALTH_INIT = 16,         -- :472
			headshot_dmg_mul = 2,     -- :473
			tags = {'law'},           -- :466-468
			damage = {explosion_damage_mul = 1}, -- :474
		},
		-- :617-655 (_init_sniper)
		sniper = {
			HEALTH_INIT = 4,          -- :627
			headshot_dmg_mul = 2,     -- :628
			tags = {'law', 'sniper', 'special'}, -- :619-623
			damage = {explosion_damage_mul = 1}, -- presets.base :4305
		},
		-- :3388-3560 (_init_taser; tags :3388-3392)
		taser = {
			HEALTH_INIT = 30,         -- :3517
			headshot_dmg_mul = 2,     -- :3518
			tags = {'law', 'taser', 'special'},
			damage = {explosion_damage_mul = 1}, -- presets.base :4305
		},
		-- :2945-3020 (_init_spooc)
		spooc = {
			HEALTH_INIT = 60,         -- :2955
			headshot_dmg_mul = 6,     -- :2956
			tags = {'law', 'spooc', 'special'}, -- :2947-2951
			damage = {explosion_damage_mul = 1}, -- presets.base :4305
		},
		-- :2476-2942 (_init_tank)
		tank = {
			HEALTH_INIT = 200,        -- :2731
			headshot_dmg_mul = 5,     -- :2732
			tags = {'law', 'tank', 'special'}, -- :2478-2482
			damage = {explosion_damage_mul = 2}, -- :2733
			-- :2762-2764: snapshot of the base headshot multiplier, so it does NOT
			-- follow the difficulty (see breakpoints.get_for_unit).
			critical_hits = {damage_mul = 5},
		},
		-- :3946-3953 (_init_team_ai): the crew weapon usage tables the henchman
		-- rows read (see gang_member_weapon above).
		russian = {
			weapon = gang_member_weapon,
		},
	},

	-- lib/tweak_data/tweakdata.lua:2324-2414 (entries the crit check consults;
	-- keys are the first weapon category / projectile id the game looks up).
	weapon_disable_crit_for_damage = {
		-- :2325-2328
		frag = {explosion = false, fire = false},
		-- :2337-2340
		launcher_frag = {explosion = false, fire = false},
		-- :2358-2361
		wpn_gre_electric = {explosion = false, tase = false},
	},

	weapon = {
		stats = {
			alert_size = alert_size,
			suppression = suppression,
			damage = damage,
			zoom = zoom,
			spread = spread,
			spread_moving = spread_moving,
			recoil = recoil,
			value = value,
			concealment = concealment,
			extra_ammo = extra_ammo,
			total_ammo_mod = total_ammo_mod,
			reload = reload,
		},

		-- lib/tweak_data/weapontweakdata.lua:6721-6815 (CAR-4)
		new_m4 = {
			categories = {'assault_rifle'},
			DAMAGE = 1,
			CLIP_AMMO_MAX = 30,
			NR_CLIPS_MAX = 5,
			AMMO_MAX = 30 * 5,
			-- :6752 AMMO_MAX * PICKUP.AR_MED_CAPACITY (0.03, 0.055)
			AMMO_PICKUP = {4.5, 8.25},
			-- :6737-6740
			timers = {reload_not_empty = 2.665, reload_empty = 3.43, unequip = 0.6, equip = 0.6},
			FIRE_MODE = 'auto',
			fire_mode_data = {fire_rate = 0.1},
			auto = {fire_rate = 0.1},
			CAN_TOGGLE_FIREMODE = true,
			-- :6759-6765 / :6766-6774
			spread = m4_spread,
			kick = {
				standing = m4_kick_standing,
				crouching = m4_kick_standing,
				steelsight = m4_kick_standing,
			},
			stats = {
				alert_size = 7, concealment = 20, damage = 62, extra_ammo = 51,
				recoil = 16, reload = 11, spread = 12, spread_moving = 10,
				suppression = 10, total_ammo_mod = 21, value = 1, zoom = 1,
			},
		},

		-- lib/tweak_data/weapontweakdata.lua:7214-7303 (AMCAR)
		amcar = {
			categories = {'assault_rifle'},
			DAMAGE = 1,
			CLIP_AMMO_MAX = 20,
			NR_CLIPS_MAX = 11,
			AMMO_MAX = 20 * 11,
			-- :7245 AMMO_MAX * PICKUP.AR_HIGH_CAPACITY (0.03, 0.055, :6439-6441)
			AMMO_PICKUP = {6.6, 12.1},
			-- :7230-7233
			timers = {reload_not_empty = 2.25, reload_empty = 3, unequip = 0.6, equip = 0.55},
			FIRE_MODE = 'auto',
			fire_mode_data = {fire_rate = 0.11},
			auto = {fire_rate = 0.11},
			CAN_TOGGLE_FIREMODE = true,
			-- :7253-7258 / :7259-7262
			spread = m4_spread,
			kick = {
				standing = m4_kick_standing,
				crouching = m4_kick_standing,
				steelsight = m4_kick_standing,
			},
			stats = {
				alert_size = 7, concealment = 21, damage = 45, extra_ammo = 51,
				recoil = 20, reload = 11, spread = 10, spread_moving = 8,
				suppression = 10, total_ammo_mod = 21, value = 1, zoom = 1,
			},
		},

		-- lib/tweak_data/weapontweakdata.lua:8864-8948 (M308)
		new_m14 = {
			categories = {'assault_rifle'},
			DAMAGE = 2,
			CLIP_AMMO_MAX = 10,
			NR_CLIPS_MAX = 7,
			AMMO_MAX = 10 * 7,
			-- :8894 AMMO_MAX * PICKUP.AR_DMR_CAPACITY (0.018, 0.04)
			AMMO_PICKUP = {1.26, 2.8},
			-- :8879-8882
			timers = {reload_not_empty = 2.65, reload_empty = 3.15, unequip = 0.6, equip = 0.55},
			FIRE_MODE = 'single',
			fire_mode_data = {fire_rate = 0.085},
			single = {fire_rate = 0.085},
			CAN_TOGGLE_FIREMODE = true,
			-- :8902-8911
			spread = m4_spread,
			kick = {
				standing = m4_kick_standing,
				crouching = m4_kick_standing,
				steelsight = m4_kick_standing,
			},
			stats = {
				alert_size = 7, concealment = 8, damage = 160, extra_ammo = 51,
				recoil = 10, reload = 11, spread = 22, spread_moving = 20,
				suppression = 4, total_ammo_mod = 21, value = 1, zoom = 1,
			},
		},

		-- lib/tweak_data/weapontweakdata.lua:10206-10305 (Judge). 248.2 sets no
		-- CAN_TOGGLE_FIREMODE on judge (only x_judge sets it, to false).
		judge = {
			categories = {'shotgun'},
			upgrade_blocks = {weapon = {'clip_ammo_increase'}},
			DAMAGE = 6,
			damage_near = 2000,
			damage_far = 3000,
			-- :10246
			damage_falloff = falloff.SHOTGUN_FALL_SECONDARY_VERYHIGH,
			CLIP_AMMO_MAX = 5,
			NR_CLIPS_MAX = 7,
			AMMO_MAX = 5 * 7,
			-- :10250 AMMO_MAX * PICKUP.SNIPER_HIGH_DAMAGE (0.005, 0.015)
			AMMO_PICKUP = {0.175, 0.525},
			-- :10223-10226
			timers = {reload_not_empty = 2.25, reload_empty = 2.25, unequip = 0.5, equip = 0.45},
			FIRE_MODE = 'single',
			fire_mode_data = {fire_rate = 0.12},
			single = {fire_rate = 0.21},
			-- :10251-10266
			spread = m4_spread,
			kick = {
				standing = {2.9, 3, -0.5, 0.5},
				crouching = {2.9, 3, -0.5, 0.5},
				steelsight = {2.9, 3, -0.5, 0.5},
			},
			stats = {
				alert_size = 7, concealment = 29, damage = 155, extra_ammo = 51,
				recoil = 8, reload = 11, spread = 14, spread_moving = 14,
				suppression = 5, total_ammo_mod = 21, value = 1, zoom = 1,
			},
		},

		-- lib/tweak_data/weapontweakdata.lua:23209-23284 (Grimm)
		basset = {
			categories = {'shotgun'},
			has_magazine = true,
			DAMAGE = 6,
			damage_near = 2000,
			damage_far = 3000,
			-- :23237
			damage_falloff = falloff.SHOTGUN_FALL_SECONDARY_LOW,
			CLIP_AMMO_MAX = 8,
			NR_CLIPS_MAX = 13,
			AMMO_MAX = 8 * 13,
			-- :23244 AMMO_MAX * PICKUP.SHOTGUN_HIGH_CAPACITY (0.05, 0.075)
			AMMO_PICKUP = {5.2, 7.8},
			-- :23223-23226
			timers = {reload_not_empty = 2.16, reload_empty = 2.9, unequip = 0.55, equip = 0.55},
			FIRE_MODE = 'auto',
			fire_mode_data = {fire_rate = 0.2},
			auto = {fire_rate = 0.2},
			CAN_TOGGLE_FIREMODE = true,
			-- :23251-23261 (steelsight kick differs from standing, :7062-7067)
			spread = m4_spread,
			kick = {
				standing = {1.9, 2, -0.2, 0.2},
				crouching = {1.9, 2, -0.2, 0.2},
				steelsight = {1.5, 1.7, -0.2, 0.2},
			},
			stats = {
				alert_size = 7, concealment = 21, damage = 18, extra_ammo = 51,
				recoil = 13, reload = 11, spread = 4, spread_moving = 8,
				suppression = 5, total_ammo_mod = 21, value = 1, zoom = 1,
			},
		},

		-- lib/tweak_data/weapontweakdata.lua:11081-11172 (KSP)
		m249 = {
			categories = {'lmg'},
			DAMAGE = 1,
			CLIP_AMMO_MAX = 200,
			NR_CLIPS_MAX = 2,
			AMMO_MAX = 200 * 2,
			-- :11115
			damage_falloff = falloff.LMG_FALL_MEDIUM,
			-- :11119 AMMO_MAX * PICKUP.LMG_CAPACITY (0.025, 0.03)
			AMMO_PICKUP = {10, 12},
			-- :11096-11099
			timers = {reload_not_empty = 5.62, reload_empty = 5.62, unequip = 0.9, equip = 0.9},
			FIRE_MODE = 'auto',
			fire_mode_data = {fire_rate = 0.066},
			auto = {fire_rate = 0.076},
			CAN_TOGGLE_FIREMODE = false,
			-- :11127-11142
			spread = m4_spread,
			kick = {
				standing = {-0.2, 0.8, -1, 1.4},
				crouching = {-0.2, 0.8, -1, 1.4},
				steelsight = {-0.2, 0.8, -1, 1.4},
			},
			stats = {
				alert_size = 8, concealment = 1, damage = 80, extra_ammo = 51,
				recoil = 8, reload = 11, spread = 13, spread_moving = 8,
				suppression = 4, total_ammo_mod = 21, value = 9, zoom = 1,
			},
		},

		-- lib/tweak_data/weapontweakdata.lua:11299-11396 (Thanatos)
		m95 = {
			categories = {'snp'},
			upgrade_blocks = {weapon = {'clip_ammo_increase'}},
			DAMAGE = 1,
			CLIP_AMMO_MAX = 5,
			NR_CLIPS_MAX = 3,
			AMMO_MAX = 5 * 3,
			-- :11331
			damage_falloff = falloff.SNIPER_FALL_VERYHIGH,
			-- :11335-11338 (literal table, not _pickup_chance)
			AMMO_PICKUP = {0.1, 0.65},
			-- :11317-11320
			timers = {reload_not_empty = 3.8, reload_empty = 5.1, unequip = 0.6, equip = 0.6},
			FIRE_MODE = 'single',
			fire_mode_data = {fire_rate = 1.25},
			single = {fire_rate = 20},
			CAN_TOGGLE_FIREMODE = false,
			armor_piercing_chance = 1,
			stats_modifiers = {damage = 35},
			-- :11346-11360
			spread = m4_spread,
			kick = {
				standing = {3, 3.8, -0.5, 0.5},
				crouching = {3, 3.8, -0.5, 0.5},
				steelsight = {3, 3.8, -0.5, 0.5},
			},
			stats = {
				alert_size = 9, concealment = 1, damage = 100, extra_ammo = 51,
				recoil = 2, reload = 11, spread = 24, spread_moving = 24,
				suppression = 2, total_ammo_mod = 21, value = 9, zoom = 1,
			},
		},

		-- lib/tweak_data/weapontweakdata.lua:19276-19377 (akimbo MP5)
		x_mp5 = {
			categories = {'akimbo', 'smg'},
			DAMAGE = 1,
			CLIP_AMMO_MAX = 60,
			NR_CLIPS_MAX = 5,
			AMMO_MAX = 60 * 5,
			-- :19307
			damage_falloff = falloff.AKI_SMG_FALL_LOW,
			-- :19311 AMMO_MAX * PICKUP.OTHER (0.01, 0.035)
			AMMO_PICKUP = {3, 10.5},
			-- :19293-19296
			timers = {reload_not_empty = 2.5, reload_empty = 3, unequip = 0.5, equip = 0.5},
			FIRE_MODE = 'auto',
			fire_mode_data = {fire_rate = 0.08},
			single = {fire_rate = 0.08},
			CAN_TOGGLE_FIREMODE = true,
			-- :19319-19333
			spread = m4_spread,
			kick = {
				standing = {1.4, 1.2, -0.5, 0.5},
				crouching = {1.4, 1.2, -0.5, 0.5},
				steelsight = {1.4, 1.2, -0.5, 0.5},
			},
			stats = {
				alert_size = 7, concealment = 24, damage = 44, extra_ammo = 51,
				recoil = 21, reload = 11, spread = 12, spread_moving = 8,
				suppression = 17, total_ammo_mod = 21, value = 1, zoom = 3,
			},
		},

		-- lib/tweak_data/weapontweakdata.lua:6820-6907 (Glock 17, NPC fixture;
		-- also the player pistol used for the near-falloff case)
		glock_17 = {
			categories = {'pistol'},
			DAMAGE = 1,
			CLIP_AMMO_MAX = 17,
			NR_CLIPS_MAX = 9,
			AMMO_MAX = 17 * 9,
			-- :6851
			damage_falloff = falloff.PISTOL_FALL_LOW,
			-- :6855 AMMO_MAX * PICKUP.PISTOL_HIGH_CAPACITY (0.025, 0.035)
			AMMO_PICKUP = {3.825, 5.355},
			-- :6838-6841
			timers = {reload_not_empty = 1.47, reload_empty = 2.12, unequip = 0.5, equip = 0.35},
			FIRE_MODE = 'single',
			fire_mode_data = {fire_rate = 0.11},
			single = {fire_rate = 0.11},
			CAN_TOGGLE_FIREMODE = false,
			-- :6857-6871
			spread = m4_spread,
			kick = {
				standing = {1.2, 1.8, -0.5, 0.5},
				crouching = {1.2, 1.8, -0.5, 0.5},
				steelsight = {1.2, 1.8, -0.5, 0.5},
			},
			stats = {
				alert_size = 7, concealment = 30, damage = 53, extra_ammo = 51,
				recoil = 16, reload = 11, spread = 14, spread_moving = 14,
				suppression = 16, total_ammo_mod = 21, value = 1, zoom = 1,
			},
		},

		-- lib/tweak_data/weapontweakdata.lua:11520-11641 (Supernova): the real
		-- shell-by-shell shotgun (use_shotgun_reload = true, no
		-- timers.reload_empty; every shell timer lives in timers.shotgun_reload_*).
		supernova = {
			categories = {'shotgun'},
			use_shotgun_reload = true,
			upgrade_blocks = {weapon = {'clip_ammo_increase'}},
			DAMAGE = 6,
			damage_near = 2000,
			damage_far = 3000,
			-- :11558
			damage_falloff = falloff.SHOTGUN_FALL_PRIMARY_MEDIUM,
			CLIP_AMMO_MAX = 5,
			NR_CLIPS_MAX = 5,
			AMMO_MAX = 5 * 5,
			-- :11565 AMMO_MAX * PICKUP.SHOTGUN_HIGH_CAPACITY (0.05, 0.075)
			AMMO_PICKUP = {1.25, 1.875},
			-- :11540-11546
			timers = {
				shotgun_reload_enter = 0.8,
				shotgun_reload_exit_empty = 0.9666666666666667,
				shotgun_reload_exit_not_empty = 0.5666666666666667,
				shotgun_reload_shell = 0.6,
				shotgun_reload_first_shell_offset = 0,
				unequip = 0.85,
				equip = 0.85,
			},
			FIRE_MODE = 'single',
			fire_mode_data = {fire_rate = 0.6},
			single = {fire_rate = 0.6},
			-- :11582-11602
			spread = m4_spread,
			kick = {
				standing = {2.1, 2.2, -0.1, 0.1},
				crouching = {2.1, 2.2, -0.1, 0.1},
				steelsight = {1.5, 1.7, -0.2, 0.2},
			},
			stats = {
				alert_size = 7, concealment = 13, damage = 134, extra_ammo = 51,
				recoil = 9, reload = 11, spread = 11, spread_moving = 10,
				suppression = 5, total_ammo_mod = 21, value = 1, zoom = 1,
			},
		},

		-- lib/tweak_data/weapontweakdata.lua:8080-8196 (Contender): single-round
		-- clip (CLIP_AMMO_MAX = 1), the case the reload-partial row blanks.
		contender = {
			categories = {'snp'},
			upgrade_blocks = {weapon = {'clip_ammo_increase'}},
			DAMAGE = 6,
			damage_near = 2000,
			damage_far = 3000,
			-- :8121
			damage_falloff = falloff.SNIPER_FALL_HIGH,
			CLIP_AMMO_MAX = 1,
			NR_CLIPS_MAX = 10,
			AMMO_MAX = 10,
			-- :8125-8128 (literal table)
			AMMO_PICKUP = {0.55, 0.65},
			-- :8100-8105
			timers = {reload_not_empty = 1.3, reload_empty = 1.3, unequip = 0.6, equip = 0.6},
			FIRE_MODE = 'single',
			fire_mode_data = {fire_rate = 1.7},
			single = {fire_rate = 1.7},
			-- :8135-8149
			spread = m4_spread,
			kick = {
				standing = {2.9, 3, -0.5, 0.5},
				crouching = {2.9, 3, -0.5, 0.5},
				steelsight = {2.9, 3, -0.5, 0.5},
			},
			armor_piercing_chance = 1,
			stats_modifiers = {damage = 4},
			stats = {
				alert_size = 7, concealment = 20, damage = 120, extra_ammo = 51,
				recoil = 2, reload = 11, spread = 17, spread_moving = 16,
				suppression = 14, total_ammo_mod = 21, value = 1, zoom = 1,
			},
		},

		-- NPC crew entries: skeleton at lib/tweak_data/weapontweakdata.lua:29905-29962,
		-- values filled in by _init_data_m4_crew (:1648-1664) and
		-- _init_data_g17_crew (:1829-1844).
		m4_crew = {
			categories = {'assault_rifle'},
			usage = 'is_rifle',
			sounds = {},
			use_data = {},
			DAMAGE = 1.5,
			CLIP_AMMO_MAX = 30,
			NR_CLIPS_MAX = 5,
			auto = {fire_rate = 0.1},
			alert_size = 5000,
			suppression = 1,
			FIRE_MODE = 'auto',
		},
		g17_crew = {
			categories = {'pistol'},
			usage = 'is_pistol',
			sounds = {},
			use_data = {},
			DAMAGE = 1,
			CLIP_AMMO_MAX = 17,
			NR_CLIPS_MAX = 5,
			alert_size = 2500,
			suppression = 1,
			FIRE_MODE = 'single',
		},
		-- Skeleton at lib/tweak_data/weapontweakdata.lua:30175-30181 (incl.
		-- anim_usage = "is_bullpup", which only drives the cop animation),
		-- values filled in by _init_data_m95_crew (:2431-2448).
		m95_crew = {
			categories = {'snp'},
			anim_usage = 'is_bullpup',
			usage = 'is_sniper',
			sounds = {},
			use_data = {},
			DAMAGE = 22.5,
			CLIP_AMMO_MAX = 5,
			NR_CLIPS_MAX = 5,
			auto = {fire_rate = 1.5},
			alert_size = 5000,
			suppression = 1,
			FIRE_MODE = 'single',
		},

		factory = {
			parts = {
				-- lib/tweak_data/weaponfactorytweakdata.lua:5317
				wpn_fps_m4_lower_reciever = {
					type = 'lower_reciever', stats = {value = 1},
				},

				-- lib/tweak_data/weaponfactorytweakdata.lua:5349
				wpn_fps_m4_upper_reciever_round = {
					type = 'upper_reciever', stats = {value = 1},
					override = {
						wpn_fps_amcar_bolt_standard = {
							unit = 'units/payday2/weapons/wpn_fps_ass_m4_pts/wpn_fps_m4_bolt_round',
						},
					},
				},

				-- lib/tweak_data/weaponfactorytweakdata.lua:6366 (forbids list is
				-- a subset of the source list, kept to the ids this suite uses)
				wpn_fps_amcar_uupg_body_upperreciever = {
					type = 'sight',
					adds = {'wpn_fps_ass_m16_os_frontsight'},
					forbids = {
						'wpn_fps_m4_upper_reciever_round_vanilla',
						'wpn_fps_m4_uupg_draghandle_vanilla',
						'wpn_fps_m4_uupg_fg_rail_ext',
					},
				},

				-- lib/tweak_data/weaponfactorytweakdata.lua:6390
				wpn_fps_amcar_uupg_fg_amcar = {type = 'foregrip'},

				-- lib/tweak_data/weaponfactorytweakdata.lua:6395
				wpn_fps_amcar_bolt_standard = {type = 'bolt'},

				-- lib/tweak_data/weaponfactorytweakdata.lua:5698
				wpn_fps_m4_uupg_fg_rail = {
					type = 'foregrip', stats = {value = 1},
					adds = {'wpn_fps_m4_uupg_fg_rail_ext'},
					forbids = {'wpn_fps_addon_ris'},
				},

				-- lib/tweak_data/weaponfactorytweakdata.lua:5780
				wpn_fps_m4_uupg_fg_rail_ext = {type = 'foregrip_ext', stats = {value = 1}},

				-- lib/tweak_data/weaponfactorytweakdata.lua:5771
				wpn_fps_m4_uupg_draghandle = {type = 'drag_handle', stats = {value = 1}},

				-- lib/tweak_data/weaponfactorytweakdata.lua:5755
				wpn_fps_m4_uupg_o_flipup = {
					type = 'sight', stats = {value = 1},
					forbids = {'wpn_fps_upg_o_xpsg33_magnifier'},
				},

				-- Vanilla part clones: lib/tweak_data/weaponfactorytweakdata.lua:5976-5993.
				-- The game deep-clones the modded part and sets stats = nil.
				wpn_fps_m4_uupg_draghandle_vanilla = {type = 'drag_handle'},
				wpn_fps_m4_upper_reciever_round_vanilla = {type = 'upper_reciever'},
				wpn_fps_m4_uupg_m_std_vanilla = {type = 'magazine'},
				wpn_fps_upg_m4_m_straight_vanilla = {type = 'magazine'},
				wpn_fps_upg_m4_s_standard_vanilla = {type = 'stock'},
				wpn_fps_upg_m4_g_standard_vanilla = {type = 'grip'},
				wpn_fps_m4_uupg_b_medium_vanilla = {type = 'barrel'},
				wpn_fps_upg_o_shortdot_vanilla = {type = 'sight'},

				-- lib/tweak_data/weaponfactorytweakdata.lua:5889
				wpn_fps_upg_m4_s_standard = {
					type = 'stock',
					stats = {concealment = -1, recoil = 1, spread_moving = -1, value = 1},
					adds_type = {'stock_adapter'},
					forbids = {'wpn_fps_shot_r870_ris_special'},
				},

				-- lib/tweak_data/weaponfactorytweakdata.lua:5867
				wpn_fps_upg_m4_m_straight = {
					type = 'magazine',
					stats = {concealment = 1, extra_ammo = -4, spread_moving = 2, value = 2},
				},

				-- lib/tweak_data/weaponfactorytweakdata.lua:5400
				wpn_fps_m4_uupg_b_medium = {
					type = 'barrel',
					stats = {concealment = -1, spread = 1, value = 1},
				},

				-- lib/tweak_data/weaponfactorytweakdata.lua:5939
				wpn_fps_upg_m4_s_adapter = {type = 'stock_adapter', stats = {value = 1}},

				-- lib/tweak_data/weaponfactorytweakdata.lua:50723 (forbids list is
				-- a subset of the source list)
				wpn_fps_upg_o_spot = {
					type = 'sight',
					stats = {concealment = -3, recoil = 1, spread_moving = -3, value = 8, zoom = 4},
					perks = {'scope'},
					forbids = {
						'wpn_fps_amcar_uupg_body_upperreciever',
						'wpn_fps_upg_o_xpsg33_magnifier',
					},
				},

				-- lib/tweak_data/weaponfactorytweakdata.lua (generic ammo part)
				wpn_fps_ammo_type = {
					type = 'ammo',
					stats = {value = 1},
					custom_stats = {ammo_pickup_max_mul = 0.6, ammo_pickup_min_mul = 0.4},
				},

				-- lib/tweak_data/weaponfactorytweakdata.lua:12965 (non-ammo part
				-- with ammo pickup custom stats; used only to exercise the
				-- custom_stats fold that newraycastweaponbase.lua:932-947 does)
				wpn_fps_pis_deagle_ck = {
					type = 'exclusive_set',
					stats = {concealment = -1, damage = 1, recoil = 2, spread = 2, value = 1},
					custom_stats = {ammo_pickup_max_mul = 1.2, ammo_pickup_min_mul = 1.2},
				},

				-- lib/tweak_data/weaponfactorytweakdata.lua:20879 (non-ammo part
				-- with a fire-rate custom stat)
				wpn_fps_snp_awp_dh_speed = {
					type = 'bolt',
					stats = {concealment = -1, fire_rate = 2, value = 1},
					custom_stats = {fire_rate_multiplier = 1.3},
				},

				-- lib/tweak_data/weaponfactorytweakdata.lua:12322-12418 (M308)
				wpn_fps_ass_m14_b_standard = {type = 'barrel', stats = {value = 1}},
				wpn_fps_ass_m14_body_lower = {type = 'lower_body', stats = {value = 1}},
				wpn_fps_ass_m14_body_upper = {type = 'upper_body', stats = {value = 1}},
				wpn_fps_ass_m14_body_dmr = {type = 'stock', stats = {value = 1}},
				wpn_fps_ass_m14_m_standard = {type = 'magazine', stats = {value = 1}},

				-- lib/tweak_data/weaponfactorytweakdata.lua:51102-51122 (Duckbill
				-- barrel extension): the only 248.2 part carrying spread_multi,
				-- which NewRaycastWeaponBase:_get_spread applies per axis.
				wpn_fps_upg_ns_duck = {
					type = 'barrel_ext',
					parent = 'barrel',
					stats = {
						concealment = -2,
						damage = 2,
						recoil = 2,
						value = 1,
						spread_multi = {2.25, 0.5},
					},
				},

				-- lib/tweak_data/weaponfactorytweakdata.lua:29156-29179 (explosive
				-- ammo part). The Judge factory overrides custom_stats below, so
				-- the judge sees the override values, not falloff_mul.
				wpn_fps_upg_a_explosive = {
					type = 'ammo',
					sub_type = 'ammo_explosive',
					stats = {damage = 25, spread = 2, total_ammo_mod = -2, value = 5},
					custom_stats = {
						bullet_class = 'InstantExplosiveBulletBase',
						falloff_mul = 1.5,
						ignore_statistic = true,
						rays = 1,
					},
				},

				-- lib/tweak_data/weaponfactorytweakdata.lua:17013-17058 (Judge)
				wpn_fps_pis_judge_body_standard = {
					type = 'lower_reciever', stats = {value = 1},
					forbids = {'wpn_fps_addon_ris'},
				},
				wpn_fps_pis_judge_b_standard = {type = 'slide', stats = {value = 1}},
				wpn_fps_pis_judge_g_standard = {type = 'grip', stats = {value = 1}},

				-- lib/tweak_data/weaponfactorytweakdata.lua:57595-57699 (Grimm)
				wpn_fps_sho_basset_b_standard = {type = 'barrel', stats = {value = 1}},
				wpn_fps_sho_basset_body_standard = {
					type = 'lower_receiver', stats = {value = 1},
					forbids = {'wpn_fps_addon_ris'},
				},
				wpn_fps_sho_basset_bolt = {type = 'drag_handle', stats = {value = 1}},
				wpn_fps_sho_basset_fg_standard = {type = 'foregrip', stats = {value = 1}},
				wpn_fps_sho_basset_g_standard = {type = 'grip', stats = {value = 1}},
				wpn_fps_sho_basset_o_standard = {
					type = 'sight', stats = {value = 1},
					forbids = {'wpn_fps_upg_o_xpsg33_magnifier'},
				},

				-- lib/tweak_data/weaponfactorytweakdata.lua:10138
				wpn_fps_shot_saiga_m_5rnd = {type = 'magazine', stats = {value = 1}},

				-- lib/tweak_data/weaponfactorytweakdata.lua:19928-20046 (KSP)
				wpn_fps_lmg_m249_b_short = {type = 'barrel', stats = {value = 1}},
				wpn_fps_lmg_m249_body_standard = {type = 'lower_reciever', stats = {value = 1}},
				wpn_fps_lmg_m249_fg_standard = {type = 'foregrip', stats = {value = 1}},
				wpn_fps_lmg_m249_m_standard = {type = 'magazine', stats = {value = 1}},
				wpn_fps_lmg_m249_s_para = {type = 'stock', stats = {value = 1}},
				wpn_fps_lmg_m249_upper_reciever = {type = 'upper_reciever', stats = {value = 1}},

				-- lib/tweak_data/weaponfactorytweakdata.lua:20316-20419 (Thanatos)
				wpn_fps_snp_m95_barrel_standard = {type = 'barrel', stats = {value = 1}},
				wpn_fps_snp_m95_bipod = {type = 'extra', stats = {value = 1}},
				wpn_fps_snp_m95_lower_reciever = {type = 'lower_body', stats = {value = 1}},
				wpn_fps_snp_m95_upper_reciever = {type = 'upper_body', stats = {value = 1}},
				wpn_fps_snp_m95_magazine = {type = 'magazine', stats = {value = 1}},

				-- lib/tweak_data/weaponfactorytweakdata.lua:13334-13512 (MP5)
				wpn_fps_smg_mp5_b_mp5a5 = {type = 'barrel', stats = {value = 1}},
				wpn_fps_smg_mp5_body_mp5 = {type = 'lower_reciever', stats = {value = 1}},
				wpn_fps_smg_mp5_fg_mp5a4 = {
					type = 'foregrip', stats = {value = 1},
					adds = {'wpn_fps_smg_mp5_b_mp5a5'},
				},
				wpn_fps_smg_mp5_m_std = {type = 'magazine', stats = {value = 1}},
				wpn_fps_smg_mp5_s_ring_vanilla = {type = 'stock'},
			},

			-- lib/tweak_data/weaponfactorytweakdata.lua:5997-6028
			wpn_fps_ass_m4 = {
				stock_adapter = 'wpn_fps_upg_m4_s_adapter',
				default_blueprint = {
					'wpn_fps_upg_m4_g_standard_vanilla',
					'wpn_fps_m4_lower_reciever',
					'wpn_fps_m4_upper_reciever_round',
					'wpn_fps_m4_uupg_b_medium_vanilla',
					'wpn_fps_m4_uupg_fg_rail',
					'wpn_fps_m4_uupg_m_std_vanilla',
					'wpn_fps_upg_m4_s_standard_vanilla',
					'wpn_fps_m4_uupg_draghandle',
					'wpn_fps_m4_uupg_o_flipup',
					'wpn_fps_amcar_bolt_standard',
				},
			},

			-- lib/tweak_data/weaponfactorytweakdata.lua:6403-6544 (adds kept to
			-- the one entry this suite exercises)
			wpn_fps_ass_amcar = {
				stock_adapter = 'wpn_fps_upg_m4_s_adapter',
				override = {
					wpn_fps_m4_uupg_b_medium_vanilla = {
						unit = 'units/payday2/weapons/wpn_fps_ass_m4_pts/wpn_fps_para_b_medium',
					},
				},
				adds = {
					wpn_fps_upg_o_spot = {
						'wpn_fps_m4_upper_reciever_round_vanilla',
						'wpn_fps_m4_uupg_draghandle_vanilla',
						'wpn_fps_m4_uupg_fg_rail_ext',
					},
				},
				default_blueprint = {
					'wpn_fps_m4_uupg_b_medium_vanilla',
					'wpn_fps_m4_lower_reciever',
					'wpn_fps_amcar_uupg_body_upperreciever',
					'wpn_fps_amcar_uupg_fg_amcar',
					'wpn_fps_upg_m4_m_straight_vanilla',
					'wpn_fps_upg_m4_s_standard_vanilla',
					'wpn_fps_upg_m4_g_standard_vanilla',
					'wpn_fps_amcar_bolt_standard',
				},
			},

			-- lib/tweak_data/weaponfactorytweakdata.lua:6148
			-- (deep clone of wpn_fps_ass_m4; only the default blueprint matters here)
			wpn_fps_ass_m4_npc = {
				default_blueprint = {
					'wpn_fps_upg_m4_g_standard_vanilla',
					'wpn_fps_m4_lower_reciever',
					'wpn_fps_m4_upper_reciever_round',
					'wpn_fps_m4_uupg_b_medium_vanilla',
					'wpn_fps_m4_uupg_fg_rail',
					'wpn_fps_m4_uupg_m_std_vanilla',
					'wpn_fps_upg_m4_s_standard_vanilla',
					'wpn_fps_m4_uupg_draghandle',
					'wpn_fps_m4_uupg_o_flipup',
					'wpn_fps_amcar_bolt_standard',
				},
			},

			-- lib/tweak_data/weaponfactorytweakdata.lua:12438-12444
			wpn_fps_ass_m14 = {
				default_blueprint = {
					'wpn_fps_ass_m14_b_standard',
					'wpn_fps_ass_m14_body_lower',
					'wpn_fps_ass_m14_body_upper',
					'wpn_fps_ass_m14_body_dmr',
					'wpn_fps_ass_m14_m_standard',
				},
			},

			-- lib/tweak_data/weaponfactorytweakdata.lua:17190-17194
			wpn_fps_pis_judge = {
				-- :17068-17100 (the Judge factory override for the two parts this
				-- suite exercises; the rest is unchanged source data)
				override = {
					wpn_fps_upg_ns_duck = {parent = 'slide'},
					wpn_fps_upg_a_explosive = {
						custom_stats = {
							bullet_class = 'InstantExplosiveBulletBase',
							damage_far_mul = 1.4,
							damage_near_mul = 1,
							ignore_statistic = true,
							rays = 1,
						},
					},
				},
				default_blueprint = {
					'wpn_fps_pis_judge_body_standard',
					'wpn_fps_pis_judge_b_standard',
					'wpn_fps_pis_judge_g_standard',
				},
			},

			-- lib/tweak_data/weaponfactorytweakdata.lua:57737-57745
			wpn_fps_sho_basset = {
				default_blueprint = {
					'wpn_fps_sho_basset_b_standard',
					'wpn_fps_sho_basset_body_standard',
					'wpn_fps_sho_basset_bolt',
					'wpn_fps_sho_basset_fg_standard',
					'wpn_fps_sho_basset_g_standard',
					'wpn_fps_shot_saiga_m_5rnd',
					'wpn_fps_sho_basset_o_standard',
				},
			},

			-- lib/tweak_data/weaponfactorytweakdata.lua:20062-20076
			wpn_fps_lmg_m249 = {
				stock_adapter = 'wpn_fps_lmg_m249_s_modern',
				default_blueprint = {
					'wpn_fps_lmg_m249_b_short',
					'wpn_fps_lmg_m249_body_standard',
					'wpn_fps_lmg_m249_fg_standard',
					'wpn_fps_lmg_m249_m_standard',
					'wpn_fps_lmg_m249_s_para',
					'wpn_fps_lmg_m249_upper_reciever',
				},
			},

			-- lib/tweak_data/weaponfactorytweakdata.lua:20446-20454
			wpn_fps_snp_m95 = {
				default_blueprint = {
					'wpn_fps_snp_m95_barrel_standard',
					'wpn_fps_snp_m95_bipod',
					'wpn_fps_snp_m95_lower_reciever',
					'wpn_fps_snp_m95_upper_reciever',
					'wpn_fps_snp_m95_magazine',
					'wpn_fps_upg_o_shortdot_vanilla',
					'wpn_fps_upg_m4_g_standard_vanilla',
				},
			},

			-- lib/tweak_data/weaponfactorytweakdata.lua:48354-48359
			wpn_fps_smg_x_mp5 = {
				default_blueprint = {
					'wpn_fps_smg_mp5_body_mp5',
					'wpn_fps_smg_mp5_fg_mp5a4',
					'wpn_fps_smg_mp5_m_std',
					'wpn_fps_smg_mp5_s_ring_vanilla',
				},
			},
		},
	},

	-- lib/tweak_data/playertweakdata.lua:77-140 (fields a difficulty would rewrite
	-- in place; the breakpoint maths reads the documented multipliers instead)
	player = {
		damage = {
			-- :128-130 (easy_wish/overkill_290/sm_wish set it to 0.1: :36-38, :50-52, :64-66)
			REVIVE_HEALTH_STEPS = {0.4},
		},
	},

	-- lib/tweak_data/upgradestweakdata.lua:11209-11412 (weapon -> factory)
	upgrades = {
		-- :713-717 (the single/auto spread index branch)
		sharpshooter_categories = {'assault_rifle', 'smg', 'snp'},
		definitions = {
			amcar = {category = 'weapon', factory_id = 'wpn_fps_ass_amcar', weapon_id = 'amcar'},
			new_m4 = {category = 'weapon', factory_id = 'wpn_fps_ass_m4', weapon_id = 'new_m4'},
			new_m14 = {category = 'weapon', factory_id = 'wpn_fps_ass_m14', weapon_id = 'new_m14'},
			judge = {category = 'weapon', factory_id = 'wpn_fps_pis_judge', weapon_id = 'judge'},
			basset = {category = 'weapon', factory_id = 'wpn_fps_sho_basset', weapon_id = 'basset'},
			m249 = {category = 'weapon', factory_id = 'wpn_fps_lmg_m249', weapon_id = 'm249'},
			m95 = {category = 'weapon', factory_id = 'wpn_fps_snp_m95', weapon_id = 'm95'},
			x_mp5 = {category = 'weapon', factory_id = 'wpn_fps_smg_x_mp5', weapon_id = 'x_mp5'},
			glock_17 = {category = 'weapon', factory_id = 'wpn_fps_pis_g17', weapon_id = 'glock_17'},
			supernova = {category = 'weapon', factory_id = 'wpn_fps_sho_supernova', weapon_id = 'supernova'},
			contender = {category = 'weapon', factory_id = 'wpn_fps_pis_contender', weapon_id = 'contender'},
		},

		--[[
		Upgrade values the breakpoint bonuses read. Each block cites the
		upgradestweakdata.lua line it is copied from; the bonus toggles only ever
		read these entries, never the definitions above.
		]]
		values = {
			player = {
				-- :229
				marked_enemy_damage_mul = 1.15,
				-- :1702-1707
				marked_inc_dmg_distance = {{1000, 1.5}},
				-- :595-597
				melee_damage_health_ratio_multiplier = {2.5},
				-- :598-600
				damage_health_ratio_multiplier = {1},
				-- :1061-1063
				revived_health_regain = {1.4},
			},
			-- :508-513
			temporary = {
				dmg_multiplier_outnumbered = {{1.15, 7}},
				-- :609-614
				overkill_damage_multiplier = {{1.75, 20}},
			},
			-- :402-413
			pistol = {
				stacking_hit_damage_multiplier = {
					{damage_bonus = 2.2, max_stacks = 1, max_time = 2},
					{damage_bonus = 2.2, max_stacks = 1, max_time = 4},
				},
			},
			-- :646-649
			weapon = {
				automatic_head_shot_add = {0.3, 0.9},
				-- :791-793
				passive_headshot_damage_multiplier = {1.25},
			},
		},
		-- :601 (PlayerManager:get_damage_health_ratio threshold)
		player_damage_health_ratio_threshold = 0.5,
	},

	-- lib/tweak_data/economytweakdata.lua:1722-1777
	economy = {
		bonuses = {
			concealment_p1 = {stats = {concealment = 1}},
			recoil_p1 = {stats = {recoil = 1}},
			damage_p1 = {stats = {damage = 1}},
			damage_p2 = {stats = {damage = 2}},
			total_ammo_p1 = {stats = {total_ammo_mod = 1}},
		},
	},

	-- lib/tweak_data/blackmarket/weaponskinstweakdata.lua (bonus ids only)
	blackmarket = {
		-- lib/tweak_data/blackmarket/meleeweaponstweakdata.lua. The fields the
		-- melee rows read, with the source line of each weapon block.
		melee_weapons = {
			-- :15-20 (bare melee weapon; no melee_damage_delay)
			weapon = {
				expire_t = 0.6,
				repeat_expire_t = 0.6,
			},
			-- :21-47
			fists = {
				expire_t = 1,
				repeat_expire_t = 0.55,
				melee_damage_delay = 0.2,
			},
			-- :70-82
			kabar = {
				repeat_expire_t = 0.6,
				expire_t = 1.2,
				melee_damage_delay = 0.1,
			},
			-- :1387-1424
			taser = {
				tase_data = {tase_strength = 'light'},
				expire_t = 1,
				repeat_expire_t = 0.7,
				melee_damage_delay = 0.1,
			},
		},
		weapon_skins = {
			new_m4_goldstripes = {weapon_id = 'new_m4', bonus = 'concealment_p1'},
			new_m4_cs3 = {weapon_id = 'new_m4', bonus = 'recoil_p1'},
			m95_luxury = {weapon_id = 'm95', bonus = 'total_ammo_p1'},
		},
	},
}

fixtures.weapons = {
	{id = 'amcar', name = 'AMCAR', category = 'primaries'},
	{id = 'new_m4', name = 'CAR-4', category = 'primaries'},
	{id = 'new_m14', name = 'M308', category = 'primaries'},
	{id = 'judge', name = 'Judge', category = 'secondaries'},
	{id = 'basset', name = 'Grimm', category = 'primaries'},
	{id = 'm249', name = 'KSP', category = 'primaries'},
	{id = 'm95', name = 'Thanatos', category = 'primaries'},
	{id = 'x_mp5', name = 'Akimbo MP5', category = 'secondaries'},
	{id = 'supernova', name = 'Supernova', category = 'primaries'},
	{id = 'contender', name = 'Contender', category = 'secondaries'},
}

fixtures.context = {
	difficulty = 'overkill_290',
	difficulty_rank = 7,
	ducking = false,
	steelsight = false,
}

--[[
Player skill state for the bonus toggles: SkillTreeManager._global.skills as the
context snapshot flattens it (lib/managers/skilltreemanager.lua:64; each entry is
{ unlocked = level, total = max_level }). The skill ids are the real 248.2 ones
that carry the toggles (lib/tweak_data/skilltreetweakdata.lua:645, :809, :1758,
:1820, :1925, :1965, :2331); the levels stand for a player who owns all of them.
A case that needs an unowned skill copies the table and sets that id to 0.
]]
fixtures.skills = {
	prison_wife = 1,
	hitman = 2,
	underdog = 1,
	overkill = 2,
	body_expertise = 1,
	backstab = 1,
	trigger_happy = 2,
	wolverine = 1,
}

-- Blueprints used by the mutation tests, on top of each weapon default:
--   * AMCAR + scope: the default blueprint plus the spot scope. The factory adds
--     three rail parts, the scope forbids the default upper receiver, and that
--     (now forbidden) receiver still forbids the rail extension.
--   * CAR-4 + stock: replaces the stat-less vanilla stock with the real one
--     (concealment -1, recoil +1) and pulls in the stock adapter via adds_type.
fixtures.blueprints = {
	amcar_scope = {
		'wpn_fps_m4_uupg_b_medium_vanilla',
		'wpn_fps_m4_lower_reciever',
		'wpn_fps_amcar_uupg_body_upperreciever',
		'wpn_fps_amcar_uupg_fg_amcar',
		'wpn_fps_upg_m4_m_straight_vanilla',
		'wpn_fps_upg_m4_s_standard_vanilla',
		'wpn_fps_upg_m4_g_standard_vanilla',
		'wpn_fps_amcar_bolt_standard',
		'wpn_fps_upg_o_spot',
	},
	car4_stock = {
		'wpn_fps_upg_m4_g_standard_vanilla',
		'wpn_fps_m4_lower_reciever',
		'wpn_fps_m4_upper_reciever_round',
		'wpn_fps_m4_uupg_b_medium_vanilla',
		'wpn_fps_m4_uupg_fg_rail',
		'wpn_fps_m4_uupg_m_std_vanilla',
		'wpn_fps_upg_m4_s_standard',
		'wpn_fps_m4_uupg_draghandle',
		'wpn_fps_m4_uupg_o_flipup',
		'wpn_fps_amcar_bolt_standard',
	},
	-- Custom-stats folding cases: a real ammo part plus real non-ammo parts.
	car4_ammo_pickup = {
		'wpn_fps_ammo_type',
		'wpn_fps_pis_deagle_ck',
	},
	car4_fire_rate_part = {
		'wpn_fps_snp_awp_dh_speed',
	},
	-- Judge + the Duckbill barrel extension: spread_multi = {2.25, 0.5}.
	judge_duck = {
		'wpn_fps_pis_judge_body_standard',
		'wpn_fps_pis_judge_b_standard',
		'wpn_fps_pis_judge_g_standard',
		'wpn_fps_upg_ns_duck',
	},
	-- Judge + explosive ammo: the factory override replaces the part's
	-- custom_stats, so modify_damage_falloff sees damage_near_mul = 1 and
	-- damage_far_mul = 1.4 (blackmarketmanager.lua:3209-3266).
	judge_explosive = {
		'wpn_fps_pis_judge_body_standard',
		'wpn_fps_pis_judge_b_standard',
		'wpn_fps_pis_judge_g_standard',
		'wpn_fps_upg_a_explosive',
	},
}

function fixtures.install()
	_G.tweak_data = fixtures.tweak_data
	return fixtures.tweak_data
end

return fixtures
