--[[
ui/henchmen.lua — henchman/NPC weapon stat rows.

Responsibility:
	Own the NPC rows (spread, rate of fire, autofire rounds, reload, aim delay
	and damage/hit chance per FALLOFF distance) that used to live in the Black
	Market adapter. Values come from the weapon usage entry
	(tweak_data.character.russian.weapon[weapon_tweak_data().usage]) and from
	the NPC model the adapter built (core/weapon.lua with `npc = true`); no NPC
	unit, weapon class or manager state is created here.

Public API:
	henchmen.rows(gui) -> table
		The v76 henchman row descriptors: mws_spread, mws_rof, mws_autorounds,
		mws_reload_full, mws_aim_delay, then one mws_damage_hitchance row per
		unique FALLOFF distance in tweak_data.character.russian.weapon. Each
		distance row keeps the v76 shape: name mws_damage_hitchance, text_name
		mws_damage_hitchance_<d>, macros { DIS = d / 100 } and a callback that
		carries its own distance.

	henchmen.refresh(gui, selected, equipped, context)
		Re-renders every henchman row that has a panel. `selected` fills the
		right column (cells a2/b2) and `equipped` the left column (a1/b1), the
		same argument order as ui/stats_panel and ui/melee. Cells are blanked
		first; a nil model or an unknown weapon usage shows the v76 '?' fallback
		instead of raising.

	The rows are data-only: `weapon_tweak_data()` must return the crew entry and
	`_damage` must hold the NPC damage, which is what the NPC model exposes.
]]

local henchmen = {}

-- v76 order, before the dynamic damage/hit-chance rows.
local ROW_NAMES = {
	'mws_spread',
	'mws_rof',
	'mws_autorounds',
	'mws_reload_full',
	'mws_aim_delay',
}

local COLUMN_CELLS = { 'a1', 'b1', 'a2', 'b2' }

local function raw_global(name)
	return rawget(_G, name)
end

local function tweak()
	return raw_global('tweak_data')
end

local function set_text(cell, value)
	if cell and type(cell.set_text) == 'function' then
		cell:set_text(value or '')
	end
end

local function blank(txts)
	for _, cell_name in ipairs(COLUMN_CELLS) do
		set_text(txts[cell_name], '')
	end
end

-- menu_seconds_suffix_short; the row still formats if localization is absent.
local function seconds_suffix()
	local managers = raw_global('managers')
	local localization = managers and managers.localization

	if localization and type(localization.text) == 'function' then
		local ok, text = pcall(localization.text, localization, 'menu_seconds_suffix_short')

		if ok and text then
			return text
		end
	end

	return 's'
end

-- The gang-member usage table: tweak_data.character.russian.weapon.
local function usage_tables()
	local data = tweak()
	local character = data and data.character
	local russian = character and character.russian
	local weapon = russian and russian.weapon

	return type(weapon) == 'table' and weapon or nil
end

--[[
v76 mws_get_weapon_usage_tweak: the weapon usage entry plus the crew weapon
tweak entry. Both are data; a fake model without weapon_tweak_data gets no
usage entry and the row keeps its '?' fallback.
]]
local function weapon_usage(model)
	if type(model) ~= 'table' or type(model.weapon_tweak_data) ~= 'function' then
		return nil, nil
	end

	local ok, weapon_tweak = pcall(model.weapon_tweak_data, model)

	if not ok or type(weapon_tweak) ~= 'table' then
		return nil, nil
	end

	local usage = weapon_tweak.usage
	local tables = usage_tables()
	local usage_tweak = usage and tables and tables[usage] or nil

	return type(usage_tweak) == 'table' and usage_tweak or nil, weapon_tweak
end

-- v76 BlackMarketGui.mws_CopActionShoot_get_shoot_falloff: the last range whose
-- start is further than the target, else the final one.
local function shoot_falloff(target_distance, falloff)
	if type(falloff) ~= 'table' or #falloff == 0 then
		return nil, nil
	end

	for index, range_data in ipairs(falloff) do
		if type(range_data) == 'table' and target_distance < range_data.r then
			return range_data, index
		end
	end

	return falloff[#falloff], #falloff
end

-- v76: automatic crew weapons fire with the auto interval, the others with the
-- CopActionShoot update cadence at 1500cm.
local function is_automatic(usage_tweak, weapon_tweak)
	return not not (weapon_tweak and weapon_tweak.auto and usage_tweak.autofire_rounds)
end

-- Renderers ------------------------------------------------------------------

local function render_spread(gui, model, index, txts)
	if not model then
		return
	end

	if type(model.is_category) == 'function' and model:is_category('saw') then
		return
	end

	local usage_tweak = weapon_usage(model)

	if not usage_tweak or type(usage_tweak.spread) ~= 'number' then
		set_text(txts['a' .. index], '?')
		return
	end

	set_text(txts['a' .. index], ('%.0f'):format(usage_tweak.spread))
end

local function render_rof(gui, model, index, txts)
	local usage_tweak, weapon_tweak = weapon_usage(model)

	if not usage_tweak then
		set_text(txts['a' .. index], '?')
		return
	end

	local rof

	if is_automatic(usage_tweak, weapon_tweak) then
		-- see NewNPCRaycastWeaponBase:trigger_held()
		local fire_rate = weapon_tweak.auto.fire_rate or 0.1
		rof = 60 / fire_rate
	else
		-- see end of CopActionShoot:update()
		local falloff = shoot_falloff(1500, usage_tweak.FALLOFF)
		local recoil = falloff and falloff.recoil
		local cadence = type(recoil) == 'table' and recoil[2] or nil

		if type(cadence) ~= 'number' or cadence == 0 then
			set_text(txts['a' .. index], '?')
			return
		end

		rof = 60 / cadence
	end

	set_text(txts['a' .. index], ('%.0f'):format(rof))
end

local function render_autorounds(gui, model, index, txts)
	local usage_tweak, weapon_tweak = weapon_usage(model)

	if not usage_tweak then
		set_text(txts['a' .. index], '?')
		return
	end

	local rounds = usage_tweak.autofire_rounds

	if is_automatic(usage_tweak, weapon_tweak)
		and type(rounds) == 'table'
		and type(rounds[1]) == 'number'
		and type(rounds[2]) == 'number'
	then
		set_text(txts['a' .. index], ('%i'):format(rounds[1]))
		set_text(txts['b' .. index], (' | %i'):format(rounds[2]))
	else
		set_text(txts['a' .. index], '-')
	end
end

local function render_reload(gui, model, index, txts)
	local usage_tweak = weapon_usage(model)

	if not usage_tweak or type(usage_tweak.RELOAD_SPEED) ~= 'number' then
		set_text(txts['a' .. index], '?')
		return
	end

	set_text(txts['a' .. index], ('%.2f'):format(usage_tweak.RELOAD_SPEED))
end

local function render_aim_delay(gui, model, index, txts)
	local usage_tweak = weapon_usage(model)
	local aim_delay = usage_tweak and usage_tweak.aim_delay

	if type(aim_delay) ~= 'table'
		or type(aim_delay[1]) ~= 'number'
		or type(aim_delay[2]) ~= 'number'
	then
		set_text(txts['a' .. index], '?')
		return
	end

	local suffix = seconds_suffix()

	set_text(txts['a' .. index], ('%.2f%s'):format(aim_delay[1], suffix))
	set_text(txts['b' .. index], (' | %.2f%s'):format(aim_delay[2], suffix))
end

local function render_damage_hitchance(gui, model, index, txts, distance)
	local usage_tweak = weapon_usage(model)

	if not usage_tweak then
		set_text(txts['a' .. index], '?')
		return
	end

	local falloff = shoot_falloff(distance - 0.01, usage_tweak.FALLOFF)
	local damage = type(model) == 'table' and model._damage or nil
	local accuracy = falloff and falloff.acc

	if not falloff
		or type(falloff.dmg_mul) ~= 'number'
		or type(accuracy) ~= 'table'
		or type(accuracy[2]) ~= 'number'
		or type(damage) ~= 'number'
	then
		set_text(txts['a' .. index], '?')
		return
	end

	set_text(txts['a' .. index], ('%.2f'):format(falloff.dmg_mul * damage * 10))
	set_text(txts['b' .. index], (' | %i%%'):format(100 * accuracy[2]))
end

--[[
The v76 dynamic row: the closure carries the distance and appends it to the
render call, so every row keeps its own distance without a shared table.
]]
local function damage_row(distance)
	return {
		name = 'mws_damage_hitchance',
		text_name = 'mws_damage_hitchance_' .. distance,
		fct = function(gui, model, index, txts, context)
			return render_damage_hitchance(gui, model, index, txts, distance)
		end,
		macros = { DIS = distance / 100 },
	}
end

local RENDERERS = {
	mws_spread = render_spread,
	mws_rof = render_rof,
	mws_autorounds = render_autorounds,
	mws_reload_full = render_reload,
	mws_aim_delay = render_aim_delay,
}

-- Unique FALLOFF distances of the gang-member usage tables, ascending (v76
-- collected table.map_values(dis) and sorted).
local function falloff_distances()
	local distances = {}
	local seen = {}
	local tables = usage_tables()

	for _, usage_tweak in pairs(tables or {}) do
		if type(usage_tweak) == 'table' and type(usage_tweak.FALLOFF) == 'table' then
			for _, range_data in ipairs(usage_tweak.FALLOFF) do
				local distance = type(range_data) == 'table' and range_data.r or nil

				if distance and not seen[distance] then
					seen[distance] = true
					distances[#distances + 1] = distance
				end
			end
		end
	end

	table.sort(distances)

	return distances
end

-- Public API ----------------------------------------------------------------

--[[
Kept for the module seam the entry bootstrap test checks: the GUI builds the
panels from rows(), so there is no per-page state to reconcile here.
]]
function henchmen.init(gui)
end

function henchmen.rows(gui)
	local rows = {}

	for index, name in ipairs(ROW_NAMES) do
		rows[index] = {
			name = name,
			fct = RENDERERS[name],
		}
	end

	for _, distance in ipairs(falloff_distances()) do
		rows[#rows + 1] = damage_row(distance)
	end

	return rows
end

function henchmen.refresh(gui, selected, equipped, context)
	if type(gui) ~= 'table' then
		return
	end

	local texts = gui.mws_stats_texts

	if type(texts) ~= 'table' then
		return
	end

	local rows = gui.mws_stats_shown or henchmen.rows(gui)

	for _, stat in ipairs(rows) do
		local text_name = stat.text_name or stat.name
		local txts = texts[text_name]

		if type(txts) == 'table' then
			blank(txts)

			if type(stat.fct) == 'function' then
				if equipped then
					stat.fct(gui, equipped, '1', txts, context)
				end

				if selected then
					stat.fct(gui, selected, '2', txts, context)
				end
			end
		end
	end
end

return henchmen
