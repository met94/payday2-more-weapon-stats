--[[
core/weapon.lua — pure data model for one weapon plus its blueprint.

Responsibility:
	Turn a weapon id and a factory blueprint into a table that answers the stat
	questions the Black Market UI asks, without spawning a unit or instantiating a
	game weapon class. All values come from tweak data, the crafted blueprint and
	the cosmetics passed in.

Public API (Task 2 fills these in):
	weapon.new(weapon_id, blueprint, context, cosmetics) -> WeaponModel|nil
	weapon.new_from_slot(weapon_id, blueprint, options) -> WeaponModel|nil
		options: { npc = boolean, category = string|nil, slot = number|nil }

	Both return nil until Task 2 lands the model. Callers must treat nil as
	"no model available" and skip anything that needs weapon data.

WeaponModel contract (subset of the old weapon-base API the UI relies on):
	weapon_tweak_data(), categories(), is_category(name)
	_name_id, _damage, _ammo_data, _fire_mode_category
	get_ammo_max_per_clip(), get_ammo_total()
	_get_spread(standing, moving, ducking, deployed, steelsight), recoil getters
	_optimal_distance, _optimal_range, _near_multiplier, _far_multiplier
	get_damage_falloff(damage, distance, context)
	reload_speed_multiplier(), reload_expire_t(), reload_enter_expire_t(),
	reload_exit_expire_t(), clip_empty(), clip_not_empty(), use_shotgun_reload()
	can_toggle_firemode(), get_add_head_shot_mul()
]]

local weapon = {}

function weapon.new(weapon_id, blueprint, context, cosmetics)
	-- Task 2: build the model from tweak_data.weapon, the blueprint parts and the
	-- crafted cosmetics. Returning nil keeps Task 1 honest: no fabricated stats.
	return nil
end

function weapon.new_from_slot(weapon_id, blueprint, options)
	-- Task 2: resolve what managers.blackmarket/managers.weapon_factory would give
	-- a real weapon base (category, slot, npc flag) and delegate to weapon.new.
	return nil
end

return weapon
