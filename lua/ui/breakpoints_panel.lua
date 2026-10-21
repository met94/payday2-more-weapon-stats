--[[
ui/breakpoints_panel.lua — the breakpoint table, its bonus toggles and the
difficulty picker.

Responsibility:
	Own the breakpoint side of the Black Market weapon page: the panel that
	replaces the stat rows when the player presses the preview key, the eight
	bonus toggles above the table, the six unit labels, the damage/hit cells and
	the risk-icon difficulty picker. The numbers come from
	MoreWeaponStats.core.breakpoints; this module only builds widgets, keeps the
	toggle state and draws what the maths returned.

	Nothing here writes Global.game_settings.difficulty, re-initialises
	tweak_data.character / tweak_data.player or patches a manager class: the
	difficulty picker selects the difficulty the *table* is drawn for, while the
	game keeps the difficulty it is actually running. In multiplayer the picker
	is read-only and follows the running difficulty, exactly like v76.

Public API:
	breakpoints_panel.init(gui)
		Builds the whole breakpoint UI that used to live in
		BlackMarketGui:_setup: the show/hide button panel, mws_bp_panel, the bonus
		bitmaps, the unit labels, the damage/bullet cells and the difficulty
		picker (gui.mws_difficulty_picker). Every widget name, size, position,
		rotation, alpha and colour is the v76 one.
	breakpoints_panel.refresh(gui, context)
		Re-draws the table for the selected slot: hides the panel for empty and
		locked slots, silently returns when the slot has no weapon model, and
		blanks every cell before filling so a shorter table cannot leave stale
		values behind. Sets gui.mws_bp_current_damage, gui.mws_bp_ref_damage and
		gui.mws_breakpoints.
	breakpoints_panel.clear(gui)
		Blanks every damage and hit cell (also clears the current/ref damage).
	breakpoints_panel.sync_bonuses(gui, context) -> table
		Recomputes bonus availability/checked state from the context and updates
		the bitmap alphas. The player's toggles survive a refresh and a Black
		Market rebuild (the module keeps the v76 class-level seed). Survives a
		page without bitmaps (returns the state).
	breakpoints_panel.set_bonus_state(gui, bitmap_or_name, state)
	breakpoints_panel.click_bonus(gui, bitmap)
	breakpoints_panel.bonus_at(gui, x, y) -> bitmap|nil
		The available bonus under the cursor, if any (mouse hit test).
	breakpoints_panel.difficulty_at(gui, x, y) -> rank|nil
		The difficulty rank a click at (x, y) selects (icon index + 1, v76).
	breakpoints_panel.difficulty_rank(difficulty) -> number
	breakpoints_panel.difficulty_name(rank) -> string|nil
	breakpoints_panel.get_difficulty(gui) -> difficulty, rank
		The difficulty the table is drawn for: the picker's selection in
		single-player, the running game difficulty in multiplayer.
	breakpoints_panel.set_difficulty(gui, difficulty, can_switch) -> difficulty, rank
		Selects a display difficulty. Persists MoreWeaponStats.settings
		.last_used_difficulty; never writes the game's difficulty.

Difficulty semantics:
	v76's picker wrote Global.game_settings.difficulty and then re-ran
	CharacterTweakData:_set_<difficulty> / PlayerTweakData:_set_<difficulty>, so
	previewing another difficulty changed the difficulty of the running game.
	The rewrite keeps the preview local: core.breakpoints.difficulty_snapshot
	holds the same multipliers, and this module only remembers which one is
	displayed. The one v76 quirk that is kept is the click-again socket: clicking
	the icon of the currently displayed difficulty steps one rank down (v76 did
	that by comparing the click against the difficulty it had just written).
]]

local breakpoints_panel = {}

-- v76 bonus alphas (the BlackMarketGui.mws_alpha_* constants).
breakpoints_panel.mws_alpha_unavailable = 0.1
breakpoints_panel.mws_alpha_disabled = 0.5
breakpoints_panel.mws_alpha_enabled = 1

local ALPHA_UNAVAILABLE = breakpoints_panel.mws_alpha_unavailable
local ALPHA_DISABLED = breakpoints_panel.mws_alpha_disabled
local ALPHA_ENABLED = breakpoints_panel.mws_alpha_enabled

-- The risk icons of the difficulty picker, in v76 order (the seven risk_* names).
breakpoints_panel.risks = {
	'risk_pd',
	'risk_swat',
	'risk_fbi',
	'risk_death_squad',
	'risk_easy_wish',
	'risk_murder_squad',
	'risk_sm_wish',
}

--[[
Horizontal offset of every bonus bitmap in units of the 32px icon (v76's
`bonus.x`): the eight icons sit on a 1.5-icon grid starting at 0.
]]
local BONUS_OFFSETS = {
	prison_wife = 0,
	hitman = 1.5,
	underdog = 2.5,
	overkill = 3.5,
	body_expertise = 4.5,
	backstab = 5.5,
	trigger_happy = 6.5,
	wolverine = 7.5,
}

-- tweak_data.difficulties (lib/tweak_data/tweakdata.lua:373-382), used when the
-- tweak table is not loaded (headless tests) or has no list of its own.
local DIFFICULTY_ORDER = {
	'easy',
	'normal',
	'hard',
	'overkill',
	'overkill_145',
	'easy_wish',
	'overkill_290',
	'sm_wish',
}

local DEFAULT_DIFFICULTY = 'overkill_290'

-- Context fields carried into the difficulty override so the table is drawn
-- under the same stances/skills as the stat rows of the same render.
local CONTEXT_FIELDS = {
	'moving',
	'ducking',
	'steelsight',
	'deployed',
	'skills',
	'perks',
	'upgrades',
	'detection_risk',
	'competitive',
	'suppressed',
}

local function raw_global(name)
	return rawget(_G, name)
end

local function mws()
	return raw_global('MoreWeaponStats')
end

local function core_breakpoints()
	local global = mws()
	local core = global and global.core
	return core and core.breakpoints or nil
end

local function core_context()
	local global = mws()
	local core = global and global.core
	return core and core.context or nil
end

local function settings()
	local global = mws()
	return global and global.settings or {}
end

local function managers()
	return raw_global('managers')
end

local function manager(name)
	local table_ = managers()
	return table_ and table_[name] or nil
end

local function tweak()
	return raw_global('tweak_data')
end

-- Localization/branding helpers; every one degrades to a plain string so a
-- partially loaded menu cannot throw inside a panel build.
local function localized(key)
	local localization = manager('localization')

	if localization and type(localization.text) == 'function' then
		local ok, value = pcall(localization.text, localization, key)

		if ok and value then
			return value
		end
	end

	return key
end

local function upper(text)
	local utf = raw_global('utf8')

	if utf and type(utf.to_upper) == 'function' then
		return utf.to_upper(text)
	end

	return string.upper(text or '')
end

local function menu_tweak()
	local data = tweak()
	return data and data.menu or {}
end

local function small_font()
	return menu_tweak().pd2_small_font
end

local function small_font_size()
	return menu_tweak().pd2_small_font_size
end

local function screen_color(name)
	local data = tweak()
	local colors = data and data.screen_colors
	return colors and colors[name] or nil
end

local function with_alpha(color, alpha)
	if color and type(color.with_alpha) == 'function' then
		return color:with_alpha(alpha)
	end

	return color
end

local function white(alpha)
	local color = raw_global('Color')
	local base = type(color) == 'table' and color.white or nil

	if base then
		return alpha and with_alpha(base, alpha) or base
	end

	if type(color) == 'function' then
		return color(1, 1, 1, alpha or 1)
	end

	return nil
end

local function yellow()
	local color = raw_global('Color')
	local base = type(color) == 'table' and color.yellow or nil

	if base then
		return base
	end

	if type(color) == 'function' then
		return color(1, 1, 0, 1)
	end

	return nil
end

local function black(alpha)
	local color = raw_global('Color')
	local base = type(color) == 'table' and color.black or nil

	if base then
		return alpha and with_alpha(base, alpha) or base
	end

	if type(color) == 'function' then
		return color(0, 0, 0, alpha or 1)
	end

	return nil
end

local function set_cell_text(cell, value)
	if cell and type(cell.set_text) == 'function' then
		cell:set_text(value)
	end
end

local function set_cell_color(cell, color)
	if cell and type(cell.set_color) == 'function' and color then
		cell:set_color(color)
	end
end

local function hud_icon(name)
	local data = tweak()
	local icons = data and data.hud_icons

	if icons and type(icons.get_icon_data) == 'function' then
		local ok, texture, rect = pcall(icons.get_icon_data, icons, name)

		if ok then
			return texture, rect
		end
	end

	return nil, nil
end

local function skill_icon_xy(name)
	local data = tweak()
	local skilltree = data and data.skilltree
	local skills = skilltree and skilltree.skills
	local entry = skills and skills[name]

	return entry and entry.icon_xy or nil
end

-- Single-player detection: v76 allowed switching only when no network session
-- existed (`not managers.network:session()`).
local function single_player()
	local network = manager('network')

	if not network or type(network.session) ~= 'function' then
		return true
	end

	local ok, session = pcall(network.session, network)

	return not (ok and session)
end

local function crime_spree_active()
	local crime_spree = manager('crime_spree')

	if crime_spree and type(crime_spree.is_active) == 'function' then
		local ok, active = pcall(crime_spree.is_active, crime_spree)
		return ok and not not active or false
	end

	return false
end

-- Difficulty names -----------------------------------------------------------

local function difficulty_names()
	local data = tweak()
	local difficulties = data and data.difficulties

	if type(difficulties) == 'table' and #difficulties > 0 then
		return difficulties
	end

	return DIFFICULTY_ORDER
end

--[[
TweakData:difficulty_to_index / TweakData:index_to_difficulty when the game is
running; the plain tweak_data.difficulties list otherwise (headless tests).
]]
function breakpoints_panel.difficulty_rank(difficulty)
	if type(difficulty) ~= 'string' then
		return 0
	end

	local data = tweak()

	if data and type(data.difficulty_to_index) == 'function' then
		local ok, rank = pcall(data.difficulty_to_index, data, difficulty)

		if ok and type(rank) == 'number' and rank > 0 then
			return rank
		end
	end

	for index, name in ipairs(difficulty_names()) do
		if name == difficulty then
			return index
		end
	end

	return 0
end

function breakpoints_panel.difficulty_name(rank)
	if type(rank) ~= 'number' or rank < 1 then
		return nil
	end

	local data = tweak()

	if data and type(data.index_to_difficulty) == 'function' then
		local ok, name = pcall(data.index_to_difficulty, data, rank)

		if ok and type(name) == 'string' then
			return name
		end
	end

	return difficulty_names()[rank]
end

-- 248.2 has no PlayerManager:get_difficulty; the difficulty the game is running
-- is Global.game_settings.difficulty (the value the game itself persists, the
-- same source core/context.lua reads). Read-only.
local function read_game_difficulty()
	local global = raw_global('Global')
	local game_settings = global and global.game_settings
	local difficulty = game_settings and game_settings.difficulty

	if type(difficulty) == 'string' then
		return difficulty
	end

	return settings().last_used_difficulty or DEFAULT_DIFFICULTY
end

local function update_difficulty_bitmaps(gui, rank)
	local picker = type(gui) == 'table' and gui.mws_difficulty_picker or nil

	if type(picker) ~= 'table' then
		return
	end

	local active_alpha = picker.can_set_difficulty and 1 or 0.5
	local active_color = screen_color('risk')

	for index, bitmap in pairs(picker.difficulty_bitmaps or {}) do
		local active = index < (rank or 0)

		if type(bitmap.set_alpha) == 'function' then
			bitmap:set_alpha(active and active_alpha or 0.25)
		end

		if type(bitmap.set_color) == 'function' then
			bitmap:set_color(active and active_color or white())
		end
	end
end

--[[
The difficulty the table is drawn for. In single-player the picker owns it
(stored on the picker, seeded from settings.last_used_difficulty); in
multiplayer it is the difficulty the game is actually running, read-only.
]]
function breakpoints_panel.get_difficulty(gui)
	local picker = type(gui) == 'table' and gui.mws_difficulty_picker or nil

	if type(picker) == 'table' and picker.can_set_difficulty then
		local difficulty = picker.difficulty

		if type(difficulty) ~= 'string' then
			difficulty = settings().last_used_difficulty or DEFAULT_DIFFICULTY
			picker.difficulty = difficulty
			picker.difficulty_rank = breakpoints_panel.difficulty_rank(difficulty)
		end

		return difficulty, picker.difficulty_rank or breakpoints_panel.difficulty_rank(difficulty)
	end

	local difficulty = read_game_difficulty()

	return difficulty, breakpoints_panel.difficulty_rank(difficulty)
end

--[[
Selects the display difficulty. `can_switch` keeps the v76 mouse-click quirk:
	clicking the icon of the difficulty that is already displayed steps one rank
	down (v76 compared the click against the Global it had just written).
The game's own difficulty is never written; only the mod's last-used setting is.
]]
function breakpoints_panel.set_difficulty(gui, difficulty, can_switch)
	local picker = type(gui) == 'table' and gui.mws_difficulty_picker or nil

	if type(picker) ~= 'table' then
		return breakpoints_panel.get_difficulty(gui)
	end

	if not picker.can_set_difficulty then
		local current = read_game_difficulty()
		local rank = breakpoints_panel.difficulty_rank(current)

		update_difficulty_bitmaps(gui, rank)

		return current, rank
	end

	local rank = breakpoints_panel.difficulty_rank(difficulty)

	if rank < 1 then
		difficulty = settings().last_used_difficulty or picker.difficulty or DEFAULT_DIFFICULTY
		rank = breakpoints_panel.difficulty_rank(difficulty)
	end

	if can_switch and rank > 1 and rank == picker.difficulty_rank then
		rank = rank - 1
		difficulty = breakpoints_panel.difficulty_name(rank)
	end

	picker.difficulty = difficulty
	picker.difficulty_rank = rank

	local storage = settings()

	if storage then
		storage.last_used_difficulty = difficulty
	end

	update_difficulty_bitmaps(gui, rank)

	return difficulty, rank
end

function breakpoints_panel.difficulty_at(gui, x, y)
	local picker = type(gui) == 'table' and gui.mws_difficulty_picker or nil

	if type(picker) ~= 'table' or not picker.can_set_difficulty then
		return nil
	end

	local panel = picker.panel

	if not panel or type(panel.inside) ~= 'function' or not panel:inside(x, y) then
		return nil
	end

	for index, bitmap in pairs(picker.difficulty_bitmaps or {}) do
		if type(bitmap.inside) == 'function' and bitmap:inside(x, y) then
			-- v76: icon index i selects difficulty rank i + 1.
			return index + 1
		end
	end

	return nil
end

-- Bonus toggles --------------------------------------------------------------

local function bonus_definitions()
	local breakpoints = core_breakpoints()
	local bonuses = breakpoints and breakpoints.bonuses or {}
	local definitions = {}

	for name, bonus in pairs(bonuses) do
		definitions[name] = {
			index = bonus.index,
			required_level = bonus.required_level,
			checked_by_default = bonus.checked_by_default,
			x = BONUS_OFFSETS[name] or ((bonus.index - 1) * 1.5),
		}
	end

	return definitions
end

--[[
v76 kept the toggle table on the BlackMarketGui class, so a toggle the player
set survived closing and reopening the menu. The gui itself is rebuilt on every
Black Market setup, so the same session-lived seed lives here: a new gui copies
the checked/available state the previous one left behind, then availability is
recomputed from the context as usual.
]]
local session_bonuses

local function default_bonus_state()
	local state = {}

	for name, definition in pairs(bonus_definitions()) do
		local previous = type(session_bonuses) == 'table' and session_bonuses[name] or nil
		local checked = definition.checked_by_default

		if previous and previous.checked ~= nil then
			checked = previous.checked and true or false
		end

		state[name] = {
			index = definition.index,
			required_level = definition.required_level,
			checked_by_default = definition.checked_by_default,
			x = definition.x,
			level = previous and previous.level or 0,
			available = previous and previous.available or false,
			checked = checked,
		}
	end

	return state
end

local function sorted_bonus_names(state)
	local names = {}

	for name in pairs(state) do
		names[#names + 1] = name
	end

	table.sort(names, function(a, b)
		return (state[a].index or 0) < (state[b].index or 0)
	end)

	return names
end

local function bonus_bitmap_name(bitmap)
	if type(bitmap) == 'table' and type(bitmap.name) == 'function' then
		return bitmap:name()
	end

	return nil
end

local function find_bonus_bitmap(gui, name)
	local bitmaps = gui.mws_bp_skill_bitmaps

	if type(bitmaps) ~= 'table' then
		return nil
	end

	for _, bitmap in pairs(bitmaps) do
		if bonus_bitmap_name(bitmap) == name then
			return bitmap
		end
	end

	return nil
end

local function update_bonus_bitmaps(gui)
	local bitmaps = gui.mws_bp_skill_bitmaps
	local state = gui.mws_bonuses

	if type(bitmaps) ~= 'table' or type(state) ~= 'table' then
		return
	end

	for _, bitmap in pairs(bitmaps) do
		local name = bonus_bitmap_name(bitmap)
		local bonus = name and state[name]

		if bonus and type(bitmap.set_alpha) == 'function' then
			bitmap:set_alpha(
				not bonus.available and ALPHA_UNAVAILABLE
				or bonus.checked and ALPHA_ENABLED
				or ALPHA_DISABLED
			)
		end
	end
end

--[[
Bonus availability from the context. The player's own toggle state survives a
refresh (the core keeps it through `previous`) and a rebuild (the session seed
above); a bonus whose skill is not owned is forced off and dimmed, exactly like
v76's mws_set_bonus_availability.
]]
function breakpoints_panel.sync_bonuses(gui, context)
	if type(gui) ~= 'table' then
		return nil
	end

	local breakpoints = core_breakpoints()

	if not breakpoints then
		return gui.mws_bonuses
	end

	local previous = type(gui.mws_bonuses) == 'table' and gui.mws_bonuses or session_bonuses
	local state = breakpoints.bonus_availability(context, previous)
	local definitions = bonus_definitions()

	for name, entry in pairs(state) do
		local definition = definitions[name]

		if definition then
			entry.x = definition.x
		end
	end

	gui.mws_bonuses = state
	session_bonuses = state

	update_bonus_bitmaps(gui)

	return state
end

function breakpoints_panel.set_bonus_state(gui, bitmap, state)
	if type(gui) ~= 'table' then
		return
	end

	if type(bitmap) == 'string' then
		bitmap = find_bonus_bitmap(gui, bitmap)
	end

	if not bitmap then
		return
	end

	if type(bitmap.set_alpha) == 'function' then
		bitmap:set_alpha(state and ALPHA_ENABLED or ALPHA_DISABLED)
	end

	local name = bonus_bitmap_name(bitmap)
	local bonuses = gui.mws_bonuses
	local bonus = name and type(bonuses) == 'table' and bonuses[name] or nil

	if bonus then
		local checked = state and true or false

		bonus.checked = checked

		-- A toggle clicked before the first availability sync must still reach
		-- the session seed the next gui rebuild reads.
		local seeded = name and type(session_bonuses) == 'table' and session_bonuses[name] or nil

		if seeded and seeded ~= bonus then
			seeded.checked = checked
		end
	end
end

function breakpoints_panel.click_bonus(gui, bitmap)
	if not bitmap or type(bitmap.alpha) ~= 'function' then
		return
	end

	breakpoints_panel.set_bonus_state(gui, bitmap, bitmap:alpha() ~= ALPHA_ENABLED)
end

function breakpoints_panel.bonus_at(gui, x, y)
	if type(gui) ~= 'table' then
		return nil
	end

	local bitmaps = gui.mws_bp_skill_bitmaps
	local bonuses = gui.mws_bonuses

	if type(bitmaps) ~= 'table' or type(bonuses) ~= 'table' then
		return nil
	end

	for _, bitmap in pairs(bitmaps) do
		local name = bonus_bitmap_name(bitmap)
		local bonus = name and bonuses[name]

		if bonus and bonus.available and type(bitmap.inside) == 'function' and bitmap:inside(x, y) then
			return bitmap
		end
	end

	return nil
end

-- Table rendering ------------------------------------------------------------

--[[
Explosion damage disabled by a mutator: v76 asked
	managers.modifiers:modify_value('CopDamage:DamageExplosion', 123, unit_type) == 0
inside the per-unit loop, after priming an active crime spree with
`managers.crime_spree:_setup_modifiers()`.

The rewrite does not call that setup method (it writes manager state), and the
pure maths takes one flag for the whole table. The conservative reading is used
instead: an active crime spree counts as blocked (v76 only showed explosion rows
there when the primed modifiers said so), and a query that cannot run (no
modifiers manager or a throwing modify_value) counts as blocked too. In a normal
game the query answers, and the table is blocked only when every unit type
reports 0, which is the global mutator case.
]]
local function explosion_damage_blocked()
	if crime_spree_active() then
		return true
	end

	local modifiers = manager('modifiers')

	if not modifiers or type(modifiers.modify_value) ~= 'function' then
		return true
	end

	local breakpoints = core_breakpoints()
	local unit_types = breakpoints and breakpoints.unit_types or {}

	if #unit_types == 0 then
		return true
	end

	for _, unit_type in ipairs(unit_types) do
		local ok, value = pcall(modifiers.modify_value, modifiers, 'CopDamage:DamageExplosion', 123, unit_type)

		if not ok then
			return true
		end

		if value ~= 0 then
			return false
		end
	end

	return true
end

local function is_explosive(model)
	local ammo_data = type(model) == 'table' and model._ammo_data

	return type(ammo_data) == 'table' and ammo_data.bullet_class == 'InstantExplosiveBulletBase'
end

--[[
Rebuilds the context with the picker's difficulty. core.context.get() re-reads
the cached player snapshot, so the skills/perks decide bonus availability under
the displayed difficulty the same way they do for the stat rows.
]]
local function context_with_difficulty(context, difficulty, rank)
	if not difficulty then
		return context
	end

	if type(context) == 'table' and context.difficulty == difficulty then
		return context
	end

	local overrides = {
		difficulty = difficulty,
		difficulty_rank = rank,
	}

	if type(context) == 'table' then
		for _, key in ipairs(CONTEXT_FIELDS) do
			if context[key] ~= nil then
				overrides[key] = context[key]
			end
		end
	end

	local context_module = core_context()

	if context_module and type(context_module.get) == 'function' then
		return context_module.get(overrides)
	end

	local copy = {}

	for key, value in pairs(context or {}) do
		copy[key] = value
	end

	for key, value in pairs(overrides) do
		copy[key] = value
	end

	return copy
end

function breakpoints_panel.clear(gui)
	if type(gui) ~= 'table' then
		return
	end

	local half = white(0.5)

	for _, cell in pairs(gui.mws_bp_bullet or {}) do
		set_cell_text(cell, '-')
		set_cell_color(cell, half)
	end

	for _, cell in pairs(gui.mws_bp_damage or {}) do
		set_cell_text(cell, '-')
		set_cell_color(cell, half)
	end

	gui.mws_bp_current_damage = nil
	gui.mws_bp_ref_damage = nil
	gui.mws_breakpoints = {}
end

local function fill_cells(gui, list, ref_damage)
	local breakpoints = core_breakpoints()
	local unit_types = breakpoints and breakpoints.unit_types or {}
	local panel = gui.mws_bp_panel
	local yellow_damage = yellow()
	local half = white(0.5)
	local full = white()

	for index, damage_cell in pairs(gui.mws_bp_damage or {}) do
		local breakpoint = list[index]

		if breakpoint then
			local is_ref = breakpoint.value == ref_damage
			local color = is_ref and yellow_damage or half

			set_cell_text(damage_cell, ('%0.2f'):format(breakpoint.value))
			set_cell_color(damage_cell, color)

			for _, unit_type in ipairs(unit_types) do
				local hit_cell = panel and type(panel.child) == 'function'
					and panel:child('mws_bp_bullet_' .. index .. '_' .. unit_type)
					or nil
				local hit_nr = breakpoint.hits_nr[unit_type]
				local cell_color = is_ref and yellow_damage or full

				if not hit_nr then
					cell_color = with_alpha(cell_color, 0.5)
					hit_nr = breakpoint.herited_hits_nr[unit_type] or '-'
				end

				set_cell_color(hit_cell, cell_color)
				set_cell_text(hit_cell, hit_nr)
			end
		else
			set_cell_text(damage_cell, '-')
			set_cell_color(damage_cell, half)
		end
	end
end

--[[
v76 wrapped the breakpoint update in a pcall and logged the error. refresh is
reachable from mouse_pressed, so one throwing engine callback must not escape
the menu; on failure the panel is left blank rather than half-filled.
]]
local function log_failure(where, err)
	local log_fn = raw_global('log')

	if type(log_fn) == 'function' then
		pcall(log_fn, ('[More Weapon Stats] breakpoints_panel %s: %s'):format(where, tostring(err)))
	end
end

function breakpoints_panel.refresh(gui, context)
	if type(gui) ~= 'table' then
		return
	end

	local panel = gui.mws_bp_panel
	local slot_data = gui._slot_data

	if not panel or not slot_data then
		return
	end

	if slot_data.empty_slot or not slot_data.unlocked then
		panel:hide()
		return
	end

	panel:show()

	local ok, err = pcall(function()
		local breakpoints = core_breakpoints()
		local difficulty, rank = breakpoints_panel.get_difficulty(gui)
		local effective_context = context_with_difficulty(context, difficulty, rank)

		breakpoints_panel.sync_bonuses(gui, effective_context)

		local model = type(gui.mws_get_wbase_from_slot) == 'function' and gui:mws_get_wbase_from_slot(false) or nil

		if not model or not breakpoints then
			breakpoints_panel.clear(gui)
			return
		end

		local blocked = is_explosive(model) and explosion_damage_blocked() or false
		local params = breakpoints.prepare_params(model, effective_context, gui.mws_bonuses, {
			explosion_blocked = blocked,
		})

		if not params then
			breakpoints_panel.clear(gui)
			return
		end

		local data = breakpoints.get_all(params, difficulty)
		local damage = breakpoints.current_damage(model)
		local ref_damage, list = breakpoints.consolidate(
			data,
			damage,
			#(gui.mws_bp_damage or {}),
			settings().fill_breakpoints
		)

		-- Blank first: a table that got shorter (or a unit that is no longer in
		-- it) must not keep the previous render's numbers.
		breakpoints_panel.clear(gui)

		gui.mws_bp_current_damage = damage
		gui.mws_bp_ref_damage = ref_damage
		gui.mws_breakpoints = list

		fill_cells(gui, list, ref_damage)
	end)

	if not ok then
		log_failure('refresh', err)
		breakpoints_panel.clear(gui)
	end
end

-- Widget construction --------------------------------------------------------

local function make_callback(gui, name)
	local callback_factory = raw_global('callback')

	if type(callback_factory) == 'function' then
		return callback_factory(gui, gui, name)
	end

	return function() end
end

local function new_button(gui, panel, data)
	local button_class = raw_global('BlackMarketGuiButtonItem')

	if not button_class or type(button_class.new) ~= 'function' then
		return nil
	end

	return button_class:new(panel, data, 10)
end

-- v76: show/hide breakpoints button pair on its own panel above the weapon info.
local function build_switch_buttons(gui)
	local parent = gui._panel
	local buttons = gui._buttons
	local weapon_info = gui._weapon_info_panel

	if type(parent) ~= 'table' or type(buttons) ~= 'table' or type(weapon_info) ~= 'table' then
		return
	end

	gui.mws_bp_switch_panel = parent:panel({
		w = buttons:w(),
		h = 30,
	})
	gui.mws_bp_switch_panel:set_bottom(weapon_info:y() + 2)
	gui.mws_bp_switch_panel:set_right(parent:w())

	local prio = gui.si_extra_button_added and 2 or 1

	gui.mws_bp_show_btn = new_button(gui, gui.mws_bp_switch_panel, {
		prio = prio,
		name = 'mws_bp_show',
		pc_btn = 'menu_preview_item',
		callback = make_callback(gui, 'mws_bp_show_callback'),
	})

	if gui.mws_bp_show_btn then
		gui.mws_bp_show_btn._data.prio = 5 -- ugly trick for double-click
		gui._btns['mws_bp_show'] = gui.mws_bp_show_btn
	end

	gui.mws_bp_hide_btn = new_button(gui, gui.mws_bp_switch_panel, {
		prio = prio,
		name = 'mws_bp_hide',
		pc_btn = 'menu_preview_item',
		callback = make_callback(gui, 'mws_bp_hide_callback'),
	})

	if gui.mws_bp_hide_btn then
		gui.mws_bp_hide_btn._data.prio = 5
		gui._btns['mws_bp_hide'] = gui.mws_bp_hide_btn
	end

	if type(gui.show_btns) == 'function' then
		gui:show_btns(gui._selected_slot)
	end
end

-- v76: the eight checkable bonus icons above the table.
local function build_bonus_panel(gui)
	local parent = gui.mws_bp_panel

	gui.mws_bp_bonus_panel = parent:panel({
		y = 0,
		x = 0,
		layer = 1,
		w = 200,
		h = 40,
	})

	if type(gui.mws_bonuses) ~= 'table' then
		gui.mws_bonuses = default_bonus_state()
	end

	local max_x = 0
	local bonus_dim = 32
	gui.mws_bp_skill_bitmaps = {}

	for _, name in ipairs(sorted_bonus_names(gui.mws_bonuses)) do
		local bonus = gui.mws_bonuses[name]
		local icon_xy = skill_icon_xy(name)

		if icon_xy then
			max_x = math.max(max_x, bonus.x * bonus_dim)
			gui.mws_bp_skill_bitmaps[bonus.index] = gui.mws_bp_bonus_panel:bitmap({
				x = bonus.x * bonus_dim,
				y = 0,
				texture = 'guis/textures/pd2/skilltree_2/icons_atlas_2',
				name = name,
				blend_mode = 'add',
				layer = 1,
				texture_rect = {
					icon_xy[1] * 80,
					icon_xy[2] * 80,
					80,
					80,
				},
				w = bonus_dim,
				h = bonus_dim,
				alpha = not bonus.available and ALPHA_UNAVAILABLE
					or bonus.checked and ALPHA_ENABLED
					or ALPHA_DISABLED,
			})
		end
	end

	gui.mws_bp_bonus_panel:set_w(max_x + bonus_dim)
	gui.mws_bp_bonus_panel:set_center_x(parent:w() / 2)
end

-- v76: the six rotated unit labels under the table.
local function build_unit_texts(gui)
	local parent = gui.mws_bp_panel
	local unit_types = gui.mws_unit_types or {}

	local col_width = 38
	local height = parent:h() - 10

	gui.mws_bp_unit_texts = {}

	for index, unit_name in ipairs(unit_types) do
		local text = parent:text({
			vertical = 'center',
			align = 'right',
			text = localized('mws_bp_option_' .. unit_name),
			font_size = small_font_size(),
			font = small_font(),
			color = with_alpha(screen_color('text'), 0.3 + index * 0.06),
			x = index * col_width - 32,
			y = height - 60,
			w = 100,
			h = 30,
		})

		text:rotate(-45)

		gui.mws_bp_unit_texts[index] = text
	end
end

-- v76: one damage cell and six hit-count cells per row, striped background.
local function build_cells(gui)
	local parent = gui.mws_bp_panel
	local unit_types = gui.mws_unit_types or {}

	gui.mws_bp_damage = {}
	gui.mws_bp_bullet = {}

	if not gui.mws_bp_unit_texts or not gui.mws_bp_unit_texts[1] then
		return
	end

	local col_width = 38
	local row_max = math.floor(gui.mws_bp_unit_texts[1]:top() / 20) - 2
	local nr = 0

	for i = 2, row_max do
		local y = i * 20
		local row = parent:panel({
			layer = 1,
			x = 0,
			y = y,
			w = parent:w(),
			h = 20,
		})

		if i % 2 == 0 then
			row:rect({
				color = black(0.3),
			})
		end

		gui.mws_bp_damage[i - 1] = parent:text({
			name = 'mws_bp_damage_' .. tostring(i - 1),
			layer = 2,
			align = 'right',
			vertical = 'center',
			font_size = small_font_size(),
			font = small_font(),
			text = '?',
			x = 0,
			y = y,
			w = 60,
			h = 20,
			color = white(),
		})

		for j = 1, 6 do
			nr = nr + 1
			gui.mws_bp_bullet[nr] = parent:text({
				name = 'mws_bp_bullet_' .. tostring(i - 1) .. '_' .. (unit_types[j] or j),
				layer = 2,
				align = 'center',
				vertical = 'center',
				font_size = small_font_size(),
				font = small_font(),
				text = '-',
				x = 80 + (j - 1) * col_width,
				y = y,
				w = 25,
				h = 20,
				color = white(),
				alpha = 1,
			})
		end
	end
end

-- v76 difficulty picker:init, folded in. No class, no global.
local function build_difficulty_picker(gui)
	local parent = gui.mws_bp_panel

	local picker = {
		can_set_difficulty = single_player(),
		difficulty_bitmaps = {},
	}

	picker.panel = parent:panel({
		y = parent:h() - 30,
		x = 0,
		layer = 1,
		w = 200,
		h = 30,
		visible = not crime_spree_active(),
	})

	local risk_text = picker.panel:text({
		name = 'mws_bp_risk',
		align = 'center',
		vertical = 'center',
		text = upper(localized('menu_risk')),
		font_size = small_font_size(),
		font = small_font(),
		color = with_alpha(screen_color('risk'), picker.can_set_difficulty and 1 or 0.5),
		x = 0,
		y = 0,
		w = 100,
		h = 30,
	})

	local _, _, width, _ = risk_text:text_rect()
	risk_text:set_w(width)

	for i = 2, 7 do
		local name = breakpoints_panel.risks[i]
		local texture, rect = hud_icon(name)

		picker.difficulty_bitmaps[i] = picker.panel:bitmap({
			blend_mode = 'add',
			y = 0,
			x = risk_text:right() + (i - 2) * 35,
			name = name,
			texture = texture,
			texture_rect = rect,
			alpha = 0.25,
			color = white(),
		})
	end

	if picker.difficulty_bitmaps[7] then
		picker.panel:set_w(picker.difficulty_bitmaps[7]:right())
	end

	picker.panel:set_center_x(parent:w() / 2)

	gui.mws_difficulty_picker = picker

	breakpoints_panel.set_difficulty(gui, nil)
end

function breakpoints_panel.init(gui)
	if type(gui) ~= 'table' then
		return
	end

	local breakpoints = core_breakpoints()
	local weapon_info = gui._weapon_info_panel

	if not breakpoints or type(weapon_info) ~= 'table' then
		return
	end

	-- Kept for compatibility with code that reads the gui fields (v76 held both
	-- on the class); the module owns the values.
	gui.mws_unit_types = breakpoints.unit_types

	if type(gui.mws_bonuses) ~= 'table' then
		-- Seeded from the session (see default_bonus_state): v76 kept this table
		-- on the class, so a toggle the player set survived a Black Market
		-- rebuild instead of snapping back to checked_by_default.
		gui.mws_bonuses = default_bonus_state()
	end

	build_switch_buttons(gui)

	gui.mws_bp_panel = weapon_info:panel({
		visible = false,
		y = 58,
		x = 10,
		layer = 1,
		w = weapon_info:w() - 20,
		h = weapon_info:h() - 84,
	})

	build_bonus_panel(gui)
	build_unit_texts(gui)
	build_cells(gui)
	build_difficulty_picker(gui)

	-- v76 refreshed the toggles from _update_borders; do it here too so the
	-- icons do not start fully dim until the first render.
	local context_module = core_context()
	local context

	if context_module and type(context_module.get) == 'function' then
		context = context_module.get()
	end

	breakpoints_panel.sync_bonuses(gui, context)

	if gui.mws_breakpoints and type(gui.mws_update_breakpoints) == 'function' then
		gui:mws_update_breakpoints()
	end
end

return breakpoints_panel
