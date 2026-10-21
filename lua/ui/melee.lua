--[[
ui/melee.lua — melee weapon stat rows.

Responsibility:
	Own the melee stats (attack delay, cooldown, unequip delay, special, DoT
	length) that used to live in the Black Market adapter. Values come from the
	melee weapon tweak entry (BlackMarketManager:get_melee_weapon_data,
	lib/managers/blackmarketmanager.lua:5488), compared between the selected and
	the equipped melee weapon. No unit, class or manager state is created here.

Public API:
	melee.rows(gui) -> table
		The five v76 melee row descriptors in display order:
		mws_attack_delay, mws_cooldown, mws_unequip_delay, mws_special,
		mws_dot_length. The GUI builds the panels and the 100/55/88 text columns.

	melee.refresh(gui, selected, equipped, context)
		Re-renders every melee row that has a panel. `equipped` is the equipped
		melee weapon (the left column, cell a1) and `selected` the slot being
		viewed (the right column, cell a2), matching how the v76 adapter filled
		those columns. Cells are blanked first, and a nil model or unknown melee
		id leaves the row empty instead of raising.

	The models are the pseudo-models `mws_get_wbase_from_slot` returns for melee
	slots (`{ _name_id = <melee tweak id> }`): only the id is read and the tweak
	entry supplies every value. `context` is accepted for the adapter's call
	shape; melee stats do not depend on the player snapshot.
]]

local melee = {}

-- v76 display order (blackmarketgui.lua at the v76 baseline).
local ROW_NAMES = {
	'mws_attack_delay',
	'mws_cooldown',
	'mws_unequip_delay',
	'mws_special',
	'mws_dot_length',
}

local COLUMN_CELLS = { 'a1', 'a2' }

local function raw_global(name)
	return rawget(_G, name)
end

local function tweak()
	return raw_global('tweak_data')
end

local function manager(name)
	local managers = raw_global('managers')
	return managers and managers[name] or nil
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

--[[
The melee tweak entry for one pseudo-model. The Black Market manager owns the
lookup (BlackMarketManager:get_melee_weapon_data, blackmarketmanager.lua:5488,
which is a plain tweak_data.blackmarket.melee_weapons read); the direct tweak
read is the fallback for a menu that runs before the manager exists (and for
the headless tests).
]]
local function data_for(model)
	if type(model) ~= 'table' then
		return nil
	end

	local name_id = model._name_id

	if type(name_id) ~= 'string' then
		return nil
	end

	local blackmarket = manager('blackmarket')
	local getter = blackmarket and blackmarket.get_melee_weapon_data

	if type(getter) == 'function' then
		local ok, data = pcall(getter, blackmarket, name_id)

		if ok then
			return data
		end
	end

	local data = tweak()
	local blackmarket_tweak = data and data.blackmarket
	local melee_weapons = blackmarket_tweak and blackmarket_tweak.melee_weapons

	return melee_weapons and melee_weapons[name_id] or nil
end

-- v76 formats every timing as seconds with two decimals; a missing value stays
-- blank instead of raising inside a menu render.
local function format_seconds(value)
	if type(value) ~= 'number' then
		return nil
	end

	return ('%.2fs'):format(value)
end

-- v76 mws_special descriptor: the explicit special weapon, else the tase/fire
-- payload, else the generic dot type.
local function special_description(data)
	if type(data) ~= 'table' then
		return nil
	end

	if data.special_weapon then
		return data.special_weapon
	elseif data.tase_data then
		return 'tase'
	elseif data.fire_dot_data then
		return 'fire'
	elseif data.dot_data then
		return data.dot_data.type or 'dot'
	end

	return nil
end

-- v76 mws_dot_length descriptor order: dot custom length, tase strength, fire
-- dot length.
local function dot_length(data)
	if type(data) ~= 'table' then
		return nil
	end

	local dot = data.dot_data

	if dot and dot.custom_data then
		return format_seconds(dot.custom_data.dot_length or 0)
	end

	if data.tase_data and data.tase_data.tase_strength then
		return data.tase_data.tase_strength
	end

	if data.fire_dot_data then
		return format_seconds(data.fire_dot_data.dot_length or 0)
	end

	return nil
end

local RENDERERS = {
	mws_attack_delay = function(data)
		-- v76: a melee entry without melee_damage_delay shows 0.00s.
		return format_seconds(data.melee_damage_delay or 0)
	end,
	mws_cooldown = function(data)
		return format_seconds(data.repeat_expire_t)
	end,
	mws_unequip_delay = function(data)
		return format_seconds(data.expire_t)
	end,
	mws_special = special_description,
	mws_dot_length = dot_length,
}

local function value_for(stat_name, data)
	local renderer = RENDERERS[stat_name]

	if not renderer or type(data) ~= 'table' then
		return nil
	end

	local ok, value = pcall(renderer, data)

	return ok and value or nil
end

-- Public API ----------------------------------------------------------------

--[[
Kept for the module seam the entry bootstrap test checks: the GUI builds the
panels from rows(), so there is no per-page state to reconcile here.
]]
function melee.init(gui)
end

function melee.rows(gui)
	local rows = {}

	for index, name in ipairs(ROW_NAMES) do
		rows[index] = { name = name }
	end

	return rows
end

function melee.refresh(gui, selected, equipped, context)
	if type(gui) ~= 'table' then
		return
	end

	local texts = gui.mws_stats_texts

	if type(texts) ~= 'table' then
		return
	end

	local rows = gui.mws_stats_shown or melee.rows(gui)
	local selected_data = data_for(selected)
	local equipped_data = data_for(equipped)

	for _, stat in ipairs(rows) do
		local txts = texts[stat.name]

		if type(txts) == 'table' then
			blank(txts)

			set_text(txts.a1, value_for(stat.name, equipped_data))
			set_text(txts.a2, value_for(stat.name, selected_data))
		end
	end
end

return melee
