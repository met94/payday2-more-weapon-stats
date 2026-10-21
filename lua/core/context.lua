--[[
core/context.lua — player state snapshot used by every stat calculation.

Responsibility:
	Describe the conditions a stat is computed under: difficulty, stance and the
	player's skills/perks/upgrades. Callers pass a context into core.weapon,
	core.timers, core.accuracy, core.ballistics and core.ammo instead of asking
	the engine themselves.

Public API:
	context.get(overrides) -> table
		Returns a new context table. Fields:
			difficulty      string  e.g. 'overkill_290'
			difficulty_rank number  1-based index into tweak_data.difficulties
			moving          boolean player is moving
			ducking         boolean player is crouched
			steelsight      boolean player is aiming down sights
			deployed        boolean bipod deployed
			skills          table   skill_name -> level
			perks           table   perk deck -> points/level
			upgrades        table   resolved upgrade values

	This task ships static defaults only. Task 2 replaces the body with a real
	snapshot taken from managers.player / managers.skilltree / managers.blackmarket,
	cached once per Black Market render. The field names above are the contract;
	overrides are copied over the defaults and the defaults table itself is never
	handed out.
]]

local context = {}

local DEFAULTS = {
	difficulty = 'overkill_290',
	difficulty_rank = 7,
	moving = false,
	ducking = false,
	steelsight = false,
	deployed = false,
	skills = {},
	perks = {},
	upgrades = {},
}

function context.get(overrides)
	local result = {}
	for key, value in pairs(DEFAULTS) do
		result[key] = value
	end
	if overrides then
		for key, value in pairs(overrides) do
			result[key] = value
		end
	end
	return result
end

return context
