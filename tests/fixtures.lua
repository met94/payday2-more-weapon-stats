--[[
tests/fixtures.lua — real PAYDAY 2 248.2 tweak data for the headless tests.

Everything below is copied from the decompiled 248.2 source tree
(game-data/Payday-2-LuaJIT-Complete). Source lines are given per table; only the
fields the model consumes are copied, plus the factory parts needed by the
default blueprints and the blueprint-mutation cases. Do not add invented values
here: extend the copy from the game file instead.

Weapons: AMCAR, CAR-4 (new_m4), M308 (new_m14), Judge, Grimm (basset), KSP
(m249), Thanatos (m95), akimbo MP5 (x_mp5), Supernova (shell-by-shell reload),
Contender (single-round clip) and the NPC fixture glock_17.

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

fixtures.tweak_data = {
	-- lib/tweak_data/tweakdata.lua:373-382
	difficulties = {'easy', 'normal', 'hard', 'overkill', 'overkill_145', 'easy_wish', 'overkill_290', 'sm_wish'},

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
