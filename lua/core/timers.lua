--[[
core/timers.lua — reload, equip and unequip duration math.

Responsibility:
	Answer "how long does this take" questions from weapon data and the player
	context, instead of advancing a simulated player state machine.

Public API (Task 3 fills these in):
	timers.reload_full(weapon, ammo_remaining, context) -> seconds|nil
	timers.reload_partial(weapon, ammo_remaining, context) -> partial_seconds|nil, shell_seconds|nil
		`ammo_remaining` is the clip content before the reload starts; 0 means an
		empty-clip reload. reload_partial reports the reload from one round short
		and the single-shell time separately, because shotguns show both.
	timers.equip_delay(weapon, context) -> equip_seconds|nil, unequip_seconds|nil

	Every function returns nil until Task 3 lands the formulas, so the UI leaves
	the row blank rather than printing a made-up duration.
]]

local timers = {}

function timers.reload_full(weapon, ammo_remaining, context)
	return nil
end

function timers.reload_partial(weapon, ammo_remaining, context)
	return nil, nil
end

function timers.equip_delay(weapon, context)
	return nil, nil
end

return timers
