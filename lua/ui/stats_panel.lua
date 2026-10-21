--[[
ui/stats_panel.lua — extended stat rows in the Black Market weapon panel.

Responsibility:
	Own the extra stat rows (reload, equip delay, ammo pickup, spread, recoil,
	falloff) that Task 5 moved out of blackmarketgui.lua. It renders values but
	never computes them: values come from MoreWeaponStats.core and the row only
	formats them for the panels the GUI already built.

Public API:
	stats_panel.rows() -> table
		The normal weapon row descriptors in the v76 display order:
		reload partial/full, equip delay, ammo pickup, recoil horizontal/vertical,
		spread horizontal/vertical and damage falloff. Each descriptor keeps the
		{ name, fct } shape the Black Market `_setup` wrapper builds panels from;
		the GUI applies settings.display when it creates the rows.

	stats_panel.visible(stat) -> boolean
		The settings.display filter for one descriptor. A missing key means
		visible, exactly like the v76 `~= false` comparison.

	stats_panel.refresh(gui, selected, equipped, context)
		Re-renders every row that has a panel. `selected` is the slot being
		viewed (the right/total column, cells a2/b2); `equipped` is the currently
		equipped weapon (the left/equip column, cells a1/b1), matching how the
		v76 adapter filled those columns. All stale cells are blanked first, and
		a nil model leaves its column empty instead of raising. The
		menu_seconds_suffix_short localization is resolved once per refresh and
		shared by every timing cell.

The row functions receive (model, index, txts, context, suffix) and only touch
MoreWeaponStats.core, the gui's text cells and localization. They never create a
unit, a weapon class or a manager stub.
]]

local stats_panel = {}

local COLUMN_CELLS = { 'a1', 'b1', 'a2', 'b2' }

local function core()
	local mws = rawget(_G, 'MoreWeaponStats')
	return mws and mws.core or nil
end

-- menu_seconds_suffix_short; the row still formats if localization is absent.
local function seconds_suffix()
	local managers = rawget(_G, 'managers')
	local localization = managers and managers.localization

	if localization and type(localization.text) == 'function' then
		local ok, text = pcall(localization.text, localization, 'menu_seconds_suffix_short')

		if ok and text then
			return text
		end
	end

	return 's'
end

local function set_text(txts, cell_name, value)
	local cell = type(txts) == 'table' and txts[cell_name] or nil

	if cell and type(cell.set_text) == 'function' then
		cell:set_text(value or '')
	end
end

local function blank_column(txts, index)
	set_text(txts, 'a' .. index, '')
	set_text(txts, 'b' .. index, '')
end

local function blank_row(txts)
	for _, cell_name in ipairs(COLUMN_CELLS) do
		set_text(txts, cell_name, '')
	end
end

-- Row renderers --------------------------------------------------------------

local function render_reload_full(model, index, txts, context, suffix)
	local timers = core() and core().timers
	local seconds = model and timers and timers.reload_full(model, 0, context)

	if not seconds then
		blank_column(txts, index)
		return
	end

	set_text(txts, 'a' .. index, ('%.2f%s'):format(seconds, suffix or seconds_suffix()))
end

local function render_reload_partial(model, index, txts, context, suffix)
	local timers = core() and core().timers
	local partial, single_shell

	if model and timers then
		partial, single_shell = timers.reload_partial(model, 1, context)
	end

	if not partial then
		blank_column(txts, index)
		return
	end

	suffix = suffix or seconds_suffix()
	local shell = single_shell or partial

	set_text(txts, 'a' .. index, ('%.2f%s'):format(partial, suffix))
	set_text(txts, 'b' .. index, (partial == shell and '' or ' | %.2f%s'):format(shell, suffix))
end

local function render_equip_delay(model, index, txts, context, suffix)
	local timers = core() and core().timers
	local equip, unequip

	if model and timers then
		equip, unequip = timers.equip_delay(model, context)
	end

	if not equip then
		blank_column(txts, index)
		return
	end

	suffix = suffix or seconds_suffix()
	set_text(txts, 'a' .. index, ('%.2f%s'):format(equip, suffix))
	set_text(txts, 'b' .. index, (' | %.2f%s'):format(unequip or equip, suffix))
end

local function render_ammo_pickup(model, index, txts, context)
	local ammo = core() and core().ammo
	local near, far

	if model and ammo then
		near, far = ammo.ammo_pickup(model, context)
	end

	if not near then
		blank_column(txts, index)
		return
	end

	set_text(txts, 'a' .. index, ('%.2f'):format(near))
	set_text(txts, 'b' .. index, (' | %.2f'):format(far or near))
end

local function render_recoil_horiz(model, index, txts, context)
	local accuracy = core() and core().accuracy
	local left, right

	if model and accuracy then
		left, right = accuracy.recoil_horizontal(model, context)
	end

	if not left then
		blank_column(txts, index)
		return
	end

	set_text(txts, 'a' .. index, ("%.2f'"):format(left))
	set_text(txts, 'b' .. index, (" | %.2f'"):format(right or left))
end

local function render_recoil_vert(model, index, txts, context)
	local accuracy = core() and core().accuracy
	local up, down

	if model and accuracy then
		up, down = accuracy.recoil_vertical(model, context)
	end

	if not up then
		blank_column(txts, index)
		return
	end

	set_text(txts, 'a' .. index, ("%.2f'"):format(up))
	set_text(txts, 'b' .. index, (" | %.2f'"):format(down or up))
end

local function render_spread_horiz(model, index, txts, context)
	if not model then
		blank_column(txts, index)
		return
	end

	if type(model.is_category) == 'function' and model:is_category('saw') then
		blank_column(txts, index)
		return
	end

	local accuracy = core() and core().accuracy
	local standing, moving

	if accuracy then
		standing, moving = accuracy.spread_horizontal(model, context)
	end

	if not standing then
		blank_column(txts, index)
		return
	end

	set_text(txts, 'a' .. index, ("%.2f'"):format(standing))
	set_text(txts, 'b' .. index, moving and (" | %.2f'"):format(moving) or '')
end

local function render_spread_vert(model, index, txts, context)
	if not model then
		blank_column(txts, index)
		return
	end

	if type(model.is_category) == 'function' and model:is_category('saw') then
		blank_column(txts, index)
		return
	end

	local accuracy = core() and core().accuracy
	local standing, moving

	if accuracy then
		standing, moving = accuracy.spread_vertical(model, context)
	end

	if not standing then
		blank_column(txts, index)
		return
	end

	set_text(txts, 'a' .. index, ("%.2f'"):format(standing))
	set_text(txts, 'b' .. index, moving and (" | %.2f'"):format(moving) or '')
end

--[[
Damage falloff row, unchanged from v76 except for the steelsight range bonus:
the row asks the context instead of PlayerManager, so the value follows the same
snapshot as every other row and no manager is read here.
]]
local function render_falloff(model, index, txts, context)
	if not model then
		blank_column(txts, index)
		return
	end

	local weapon_tweak = type(model.weapon_tweak_data) == 'function' and model:weapon_tweak_data()
	local near_multiplier = model._near_multiplier
	local far_multiplier = model._far_multiplier
	local optimal_distance = model._optimal_distance or 0
	local optimal_range = model._optimal_range or 0

	if type(model.is_weak_hit) == 'function'
		and weapon_tweak
		and weapon_tweak.damage_falloff
		and optimal_distance + optimal_range ~= 0
	then
		set_text(txts, 'a' .. index, ('%.1f'):format(near_multiplier or 0))
		set_text(txts, 'b' .. index, (' | %.1f'):format(far_multiplier or 0))
		return
	end

	if model._damage_near then
		local inc_range_mul = 1

		if context and context.steelsight and type(context.upgrade_value) == 'function' then
			inc_range_mul = context:upgrade_value('shotgun', 'steelsight_range_inc', 1)
		end

		local near = inc_range_mul * model._damage_near / 100
		local far = inc_range_mul * model._damage_far / 100

		set_text(txts, 'a' .. index, ('%.1fm'):format(near))
		set_text(txts, 'b' .. index, (' | %.1fm'):format(near + far))
		return
	end

	blank_column(txts, index)
end

local ROW_DEFINITIONS = {
	{ name = 'mws_reload_partial', fct = render_reload_partial },
	{ name = 'mws_reload_full', fct = render_reload_full },
	{ name = 'mws_equip_delay', fct = render_equip_delay },
	{ name = 'mws_ammo_pickup', fct = render_ammo_pickup },
	{ name = 'mws_recoil_horiz', fct = render_recoil_horiz },
	{ name = 'mws_recoil_vert', fct = render_recoil_vert },
	{ name = 'mws_spread', fct = render_spread_horiz },
	{ name = 'mws_spread_vert', fct = render_spread_vert },
	{ name = 'mws_falloff', fct = render_falloff },
}

-- Public API ----------------------------------------------------------------

function stats_panel.rows()
	local rows = {}

	for index, definition in ipairs(ROW_DEFINITIONS) do
		rows[index] = {
			name = definition.name,
			fct = definition.fct,
		}
	end

	return rows
end

function stats_panel.visible(stat)
	if not stat or type(stat.name) ~= 'string' then
		return true
	end

	local mws = rawget(_G, 'MoreWeaponStats')
	local settings = mws and mws.settings
	local display = settings and settings.display

	if not display then
		return true
	end

	return display[stat.name:sub(5, -1)] ~= false
end

function stats_panel.refresh(gui, selected, equipped, context)
	if type(gui) ~= 'table' then
		return
	end

	local texts = gui.mws_stats_texts

	if type(texts) ~= 'table' then
		return
	end

	local rows = gui.mws_stats_shown or stats_panel.rows()
	-- One localization lookup per refresh, not one per timing cell.
	local suffix = seconds_suffix()

	for _, stat in ipairs(rows) do
		local text_name = stat.text_name or stat.name
		local txts = texts[text_name]

		if type(txts) == 'table' then
			blank_row(txts)

			if type(stat.fct) == 'function' and stats_panel.visible(stat) then
				if equipped then
					stat.fct(equipped, '1', txts, context, suffix)
				end

				if selected then
					stat.fct(selected, '2', txts, context, suffix)
				end
			end
		end
	end
end

return stats_panel
