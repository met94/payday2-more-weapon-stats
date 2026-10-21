local key = ModPath .. '	' .. RequiredScript
if _G[key] then return else _G[key] = true end

-- A failed bootstrap (or a namespace without the loader) must leave the Black
-- Market vanilla: install no MWS wrappers at all rather than a partial set.
if type(MoreWeaponStats) ~= 'table' or MoreWeaponStats.disabled then
	log('[More Weapon Stats] bootstrap unavailable, Black Market hooks skipped')

	return
end

if type(MoreWeaponStats.load_module) ~= 'function' then
	log('[More Weapon Stats] module loader unavailable, Black Market hooks skipped')

	return
end

-- The range chart is its own module: it is read through the loader so the
-- chunk's table comes back, and a missing chart leaves the menu vanilla.
local SimpleChart, chart_error = MoreWeaponStats:load_module(ModPath .. 'lua/_chart.lua')

if type(SimpleChart) ~= 'table' then
	log('[More Weapon Stats] failed to load lua/_chart.lua: ' .. tostring(chart_error))

	return
end

DB:create_entry(
	Idstring('texture'),
	Idstring('guis/textures/mws/stances_atlas'),
	ModPath .. 'assets/stances_atlas.texture'
)

local _dlc_info_patched = false
local _henchmen_weapon = false

local mws_original_blackmarketguislotitem_init = BlackMarketGuiSlotItem.init
function BlackMarketGuiSlotItem:init(main_panel, data, x, y, w, h)
	mws_original_blackmarketguislotitem_init(self, main_panel, data, x, y, w, h)

	if self._data.equipped then
		DelayedCalls:Add('DelayedModMWS_blackmarketguislotitem_init', 0, function()
			if alive(self.rect_bg) then
				self.rect_bg:set_color(Color.black)
				self.rect_bg:set_alpha(0.4)
				self.rect_bg:set_visible(true)
			end
		end)
	end
end

local mws_original_blackmarketgui_close = BlackMarketGui.close
function BlackMarketGui:close()
	if alive(self.mws_range_charts_floating_text) then
		self.mws_range_charts_floating_text:parent():remove(self.mws_range_charts_floating_text)
	end

	mws_original_blackmarketgui_close(self)
end

function BlackMarketGuiSlotItem:mws_change_text_visibility(state)
	if not MoreWeaponStats.settings.show_dlc_info then
		return
	end

	local equipped_text = self._panel:child('equipped_text')
	if alive(equipped_text) then
		equipped_text:set_visible(state)
	end

	local custom_name_text = self._panel:child('custom_name_text')
	if alive(custom_name_text) then
		custom_name_text:set_visible(state)
	end
end

local mws_original_blackmarketgui_select = BlackMarketGuiSlotItem.select
function BlackMarketGuiSlotItem:select(...)
	if _dlc_info_patched then
		self:mws_change_text_visibility(false)
	end
	return mws_original_blackmarketgui_select(self, ...)
end

local mws_original_blackmarketgui_deselect = BlackMarketGuiSlotItem.deselect
function BlackMarketGuiSlotItem:deselect(...)
	mws_original_blackmarketgui_deselect(self, ...)
	self:mws_change_text_visibility(true)
end

local mws_original_blackmarketgui_updateborders = BlackMarketGui._update_borders
function BlackMarketGui:_update_borders()
	mws_original_blackmarketgui_updateborders(self)

	if self._tabs[self._selected]._data.identifier == self.identifiers.weapon then
		self:mws_set_bonus_availability()

		local back_button = self._panel:child('back_button')
		back_button:set_right(self._box_panel:right())
		if self._detection_panel:visible() then
			self._detection_panel:set_right(back_button:left() - 8)
			self._detection_panel:set_center_y(back_button:center_y())
			self._detection_border:hide()
		end

		if self._btn_panel then
			self._btn_panel:set_bottom(self._panel:bottom())
		end

		local wh = self._weapon_info_panel:h()

		local weapon_info_height = self._panel:bottom() - (self._button_count > 0 and self._btn_panel:h() + 8 or 0) - self._weapon_info_panel:top()
		self._weapon_info_panel:set_h(weapon_info_height)
		self._stats_panel:set_h(weapon_info_height - self._stats_panel:top())
		self._rweapon_stats_panel:set_h(weapon_info_height)
		self._info_texts_panel:set_h(weapon_info_height - 20)

		if wh ~= self._weapon_info_panel:h() then
			self._weapon_info_border:create_sides(self._weapon_info_panel, { sides = { 1, 1, 1, 1 } })
		end
	end
end

local mws_original_blackmarketgui_setinfotext = BlackMarketGui.set_info_text
function BlackMarketGui:set_info_text(id, new_string, resource_color)
	if id == 2 then
		if self.mws_breakpoints and self.mws_bp_current_damage then
			self.mws_text2 = string.gsub(new_string, '##', '')
			new_string = ('%s %.2f'):format(utf8.to_upper(managers.localization:text('bm_menu_damage')), self.mws_bp_current_damage)
			self._info_texts[2]:set_h(20)
		end
	end

	mws_original_blackmarketgui_setinfotext(self, id, new_string, resource_color)

	if self._tabs[self._selected]._data.identifier == self.identifiers.weapon then
		if id == 3 or id == 5 then
			self._info_texts[id]:set_visible(false)
		end
	end
end

function BlackMarketGui:mws_is_buying()
	local identifier = self._tabs[self._selected]._data.identifier
	if identifier == self.identifiers.weapon then
		return not not self._data.buying_weapon
	elseif identifier == self.identifiers.masks then
		return self._data.topic_id == 'bm_menu_buy_mask_title'
	else
		return false
	end
end

function BlackMarketGui:mws_context()
	-- One context per render; the stance lives on the gui, everything else comes
	-- from core.context (a cached player snapshot).
	local core = MoreWeaponStats and MoreWeaponStats.core
	local context = core and core.context

	if not context or type(context.get) ~= 'function' then
		return {}
	end

	return context.get({
		moving = not not self.mws_moving,
		ducking = not not self.mws_ducking,
		steelsight = not not self.mws_in_steelsight,
		deployed = not not self.mws_deployed,
	})
end

function BlackMarketGui:mws_set_bonus_availability()
	local ui = MoreWeaponStats and MoreWeaponStats.ui
	local breakpoints_panel = ui and ui.breakpoints_panel

	if not breakpoints_panel then
		return
	end

	breakpoints_panel.sync_bonuses(self, self:mws_context())
end

function BlackMarketGui:mws_update_breakpoints()
	self:_mws_update_breakpoints()
end

function BlackMarketGui:_mws_update_breakpoints()
	local ui = MoreWeaponStats and MoreWeaponStats.ui
	local breakpoints_panel = ui and ui.breakpoints_panel

	if not breakpoints_panel then
		return
	end

	breakpoints_panel.refresh(self, self:mws_context())
end

local mws_original_blackmarketgui_updateinfotext = BlackMarketGui.update_info_text
function BlackMarketGui:update_info_text()
	mws_original_blackmarketgui_updateinfotext(self)

	if alive(self.mws_dlc_info_text) then
		local selected_slot_panel = self._selected_slot._panel
		self.mws_dlc_info_text:set_w(selected_slot_panel:w())
		self.mws_dlc_info_text:set_x(selected_slot_panel:world_left())
		self.mws_dlc_info_text:set_font_size(tweak_data.menu.pd2_tiny_font_size - 3)

		if self._selected_slot._data.empty_slot then
			self.mws_dlc_info_text:set_bottom(selected_slot_panel:world_bottom())
		else
			self.mws_dlc_info_text:set_top(selected_slot_panel:world_top() + 6)
		end

		if self._selected_slot then
			local scroll_bar = self._tabs[self._selected]._scroll_bar_panel:child("scroll_bar")
			self.mws_dlc_info_text:set_visible(selected_slot_panel:center_y() > scroll_bar:y() and MoreWeaponStats.settings.show_dlc_info)
		end

		self.mws_dlc_info_text_bg:set_shape(self.mws_dlc_info_text:shape())
	end
end

function BlackMarketGui:mws_realign_rcells(panel)
	for _, line in pairs(panel:children()) do
		if type(line.children) == 'function' then
			for _, cell in ipairs(line:children()) do
				if cell:width() == 45 then
					local left = cell:left()
					cell:set_left(left + 5 * (1 + (left - 100 - (left == 190 and 0 or 2)) / 45) + (left == 190 and 2 or 0))
				end
			end
		end
	end
end

function BlackMarketGui:mws_get_bottom(panel)
	local y = 0
	local lines_nr = 0

	for _, line in ipairs(panel:children()) do
		if type(line.bottom) == 'function' and line:alpha() > 0 then
			y = math.max(y, line:bottom())
			lines_nr = lines_nr + 1
		end
	end

	return y, lines_nr
end

local mws_original_blackmarketgui_setup = BlackMarketGui._setup
function BlackMarketGui:_setup(is_start_page, component_data)
	_dlc_info_patched = false
	_henchmen_weapon = false

	-- New render: drop the cached player snapshot so difficulty, skills and
	-- perks are re-read once for this page instead of once per stat row.
	-- Guarded: a partially loaded core must never break the vanilla menu.
	local core = MoreWeaponStats and MoreWeaponStats.core
	local context = core and core.context

	if context and type(context.invalidate) == 'function' then
		context.invalidate()
	end
	if component_data then
		if component_data.buying_weapon then
			_henchmen_weapon = not not (not component_data[1].on_create_func_name and component_data[1].on_create_func)
		elseif component_data.category == 'primaries' or component_data.category == 'secondaries' then
			_henchmen_weapon = not not component_data.custom_callback
		end
		if component_data.category == 'primaries'
		or component_data.category == 'secondaries'
		or component_data.topic_id == 'bm_menu_melee_weapons'
		or component_data.topic_id == 'bm_menu_buy_weapon_title'
		then
			_dlc_info_patched = true
		end
	end

	mws_original_blackmarketgui_setup(self, is_start_page, component_data)

	-- stats extension
	self.mws_stats_shown = nil
	local base_panel
	local text_columns = {}
	local identifier = self._tabs[self._selected]._data.identifier

	if self._mweapon_stats_panel and identifier == self.identifiers.melee_weapon then
		base_panel = self._mweapon_stats_panel

		self.mws_stats_shown = MoreWeaponStats.ui.melee.rows(self)

		text_columns = {
			{ size = 100, name = 'name' },
			{ size = 55, align = 'right', alpha = 0.75, blend = 'add', name = 'a1' },
			{ size = 88, align = 'right', alpha = 0.75, blend = 'add', name = 'a2' },
		}
	end

	-- move dlc info in slot item
	if _dlc_info_patched then
		local dlc_text = self._info_texts[4]
		if dlc_text then
			self.mws_dlc_info_text = self._panel:text({
				text = dlc_text:text(),
				wrap = dlc_text:wrap(),
				name = dlc_text:name(),
				word_wrap = dlc_text:word_wrap(),
				layer = 10,
				font_size = tweak_data.menu.pd2_tiny_font_size - 3,
				font = tweak_data.menu.pd2_small_font,
				color = dlc_text:color(),
				width = dlc_text:w(),
				align = 'center'
			})
			self._info_texts[4] = self.mws_dlc_info_text
			dlc_text:parent():remove(dlc_text)

			self.mws_dlc_info_text_bg = self._panel:rect({
				alpha = 0.2,
				visible = false,
				layer = 0,
				color = Color.black
			})
		end
	end

	if self._rweapon_stats_panel and identifier == self.identifiers.weapon then
		base_panel = self._rweapon_stats_panel
		for i, s in pairs(self._stats_shown) do
			local name = s.name
			if name == 'reload' or name == 'optimal_range' then
				self._rweapon_stats_panel:children()[i]:set_alpha(0)
			elseif _henchmen_weapon then
				if name == 'damage' or name == 'spread' or name == 'recoil' or name == 'concealment' or name == 'suppression' or name == 'totalammo' or name == 'fire_rate' then
					self._rweapon_stats_panel:children()[i]:set_alpha(0)
				end
			end
		end

		if _henchmen_weapon then
			self.mws_stats_shown = MoreWeaponStats.ui.henchmen.rows(self)
		else
			self.mws_stats_shown = MoreWeaponStats.ui.stats_panel.rows()
		end

		text_columns = {
			{ size = 100, name = 'name' },
			{ size = 50, align = 'right', alpha = 0.75, blend = 'add', name = 'a1' },
			{ size = 50, align = 'left', alpha = 0.75, blend = 'add', name = 'b1' },
			{ size = 50, align = 'right', alpha = 0.75, blend = 'add', name = 'a2' },
			{ size = 50, align = 'left', alpha = 0.75, blend = 'add', name = 'b2' },
		}
	end

	local y_stat_line
	if self.mws_stats_shown then
		local lines_nr
		y_stat_line, lines_nr = self:mws_get_bottom(base_panel)
		local oddeven = math.mod(lines_nr, 2)

		self.mws_stats_texts = {}
		
		for i, stat in ipairs(self.mws_stats_shown) do
			if MoreWeaponStats.ui.stats_panel.visible(stat) then
				local panel = base_panel:panel({
					layer = 1,
					x = 0,
					y = y_stat_line,
					w = base_panel:w(),
					h = 20
				})
				if math.mod(i, 2) == oddeven and not panel:child(tostring(i)) then
					panel:rect({
						color = Color.black:with_alpha(0.3)
					})
				end

				y_stat_line = y_stat_line + 20
				local x = 2
				local text_name = stat.text_name or stat.name
				self.mws_stats_texts[text_name] = {}
				for j, column in ipairs(text_columns) do
					local text_panel = panel:panel({
						layer = 0,
						x = x,
						w = column.size,
						h = panel:h()
					})
					self.mws_stats_texts[text_name][column.name] = text_panel:text({
						text = j == 1 and managers.localization:to_upper_text(stat.name, stat.macros) or nil,
						font_size = tweak_data.menu.pd2_small_font_size,
						font = tweak_data.menu.pd2_small_font,
						align = column.align,
						layer = 1,
						alpha = column.alpha,
						blend_mode = column.blend,
						color = column.color or tweak_data.screen_colors.text
					})
					x = x + column.size
				end
			end
		end
	end

	-- add components
	if self._rweapon_stats_panel and identifier == self.identifiers.weapon and not _henchmen_weapon then
		-- stances
		self.mws_in_steelsight = false
		self.mws_ducking = false

		self.mws_stances_panel = self._stats_panel:panel({
			visible = true,
			x = 0,
			layer = 1,
			w = self._stats_panel:w(),
			h = 64
		})
		self.mws_stances_panel:set_top(y_stat_line + 10)

		local stance_text = self.mws_stances_panel:text({
			name = 'mws_stance',
			align = 'center',
			vertical = 'center',
			text = utf8.to_upper(managers.localization:text('mws_stance')),
			font_size = 12,
			font = tweak_data.menu.pd2_small_font,
			color = MoreWeaponStats.stance_color,
			x = 2,
			y = 0,
			w = 200,
			h = self.mws_stances_panel:h()
		})
		local _, _, w, _ = stance_text:text_rect()
		stance_text:set_w(w)

		self.mws_stances_bitmaps = {}
		local top = -32
		local left = stance_text:right() + 10
		local visible = true
		for y = 0, 64, 64 do
			for x = 0, 64, 64 do
				table.insert(self.mws_stances_bitmaps, self.mws_stances_panel:bitmap({
					x = left,
					y = top,
					texture = 'guis/textures/mws/stances_atlas',
					color = MoreWeaponStats.stance_color,
					blend_mode = 'add',
					layer = 1,
					texture_rect = { x, y, 64, 64 },
					w = 64,
					h = 64,
					alpha = 1,
					visible = visible,
				}))
				visible = not visible
			end
			top = top + 64
		end

		-- damage range modifier. The two charts are a UI extra: if the chart
		-- widget cannot construct, the stat rows above still render without them.
		self.mws_range_charts = {}
		if type(SimpleChart.new) == 'function' then
			for _, chart_x in ipairs({ 105, 210 }) do
				local ok, chart = pcall(
					SimpleChart.new,
					SimpleChart,
					self.mws_stances_panel,
					chart_x,
					0,
					100,
					self.mws_stances_panel:h(),
					self.mws_stances_panel:h() / 2
				)

				if ok and chart then
					table.insert(self.mws_range_charts, chart)
				else
					log('[More Weapon Stats] range chart unavailable: ' .. tostring(chart))
				end
			end
		else
			log('[More Weapon Stats] range chart unavailable: no constructor')
		end
		self.mws_range_charts_floating_text = self.mws_range_charts_floating_text or self.mws_stances_panel:root():text({
			layer = 100000000000,
			visible = false,
			align = 'right',
			vertical = 'top',
			text = '',
			font_size = tweak_data.menu.pd2_small_font_size,
			font = tweak_data.menu.pd2_small_font,
			color = tweak_data.screen_colors.risk,
			blend_mode = 'normal',
			x = 0,
			y = 0,
			w = 200,
			h = 40
		})

		-- breakpoints key
		if MoreWeaponStats.settings.use_preview_to_switch_breakpoints then
			local preview_btn = self._btns.w_preview
			preview_btn._data.pc_btn = nil
			preview_btn._pc_btn = nil
		end

		-- breakpoint table, bonus toggles and difficulty picker
		MoreWeaponStats.ui.breakpoints_panel.init(self)
	end

	if self.mws_stats_shown then
		self:show_stats()
		self:update_info_text()
	end
end

local mws_original_blackmarketgui_showbtns = BlackMarketGui.show_btns
function BlackMarketGui:show_btns(...)
	mws_original_blackmarketgui_showbtns(self, ...)

	local btn -- no 1-liner!
	if self.mws_breakpoints then
		btn = self.mws_bp_hide_btn
	else
		btn = self.mws_bp_show_btn
	end
	if btn then
		btn:set_text_params()
		btn:show()
		if MoreWeaponStats.settings.use_preview_to_switch_breakpoints then
			self._controllers_pc_mapping[Idstring(btn._data.pc_btn):key()] = btn
		end
	end
end

function BlackMarketGui:mws_bp_show_callback(data)
	self.mws_breakpoints = true
	self._stats_panel:hide()
	self.mws_bp_panel:show()
	self._button_highlighted = nil
	self:show_btns(self._selected_slot)
	self:mws_update_breakpoints()

	self:set_info_text(2, self._info_texts[2]:text(), tweak_data.screen_colors.text:with_alpha(0.35))
end

function BlackMarketGui:mws_bp_hide_callback(data)
	self.mws_breakpoints = false
	self._stats_panel:show()
	self.mws_bp_panel:hide()
	self._button_highlighted = nil
	self:show_btns(self._selected_slot)

	if self.mws_text2 then
		self._info_texts[2]:set_text(self.mws_text2)
	end
end

-- Mouse interaction for the breakpoint panel: the difficulty picker and the
-- bonus toggles delegate to ui/breakpoints_panel. The stance and range-chart
-- branches are the v76 ones, unchanged.
local mws_original_blackmarketgui_mousepressed = BlackMarketGui.mouse_pressed
function BlackMarketGui:mouse_pressed(button, x, y)
	if self._enabled and not self._renaming_item and button == Idstring('0') then
		local ui = MoreWeaponStats and MoreWeaponStats.ui
		local breakpoints_panel = ui and ui.breakpoints_panel

		if self.mws_breakpoints then
			if breakpoints_panel and self.mws_bp_panel and self.mws_bp_panel:inside(x, y) then
				local difficulty_rank = breakpoints_panel.difficulty_at(self, x, y)

				if difficulty_rank then
					breakpoints_panel.set_difficulty(self, breakpoints_panel.difficulty_name(difficulty_rank), true)
					self:mws_update_breakpoints()
				end

				local bonus = breakpoints_panel.bonus_at(self, x, y)

				if bonus then
					breakpoints_panel.click_bonus(self, bonus)
					self:mws_update_breakpoints()
				end
			end

		elseif self.mws_stances_panel then
			if self.mws_stances_panel:inside(x, y) then
				if self.mws_stances_bitmaps[1]:inside(x, y) then
					self.mws_in_steelsight = not self.mws_in_steelsight
					self.mws_stances_bitmaps[1]:set_visible(not self.mws_in_steelsight)
					self.mws_stances_bitmaps[2]:set_visible(self.mws_in_steelsight)
					self:show_stats()
				elseif self.mws_stances_bitmaps[3]:inside(x, y) then
					self.mws_ducking = not self.mws_ducking
					self.mws_stances_bitmaps[3]:set_visible(not self.mws_ducking)
					self.mws_stances_bitmaps[4]:set_visible(self.mws_ducking)
					self:show_stats()
				end
			end
		end
	end

	return mws_original_blackmarketgui_mousepressed(self, button, x, y)
end

local mws_original_blackmarketgui_mousemoved = BlackMarketGui.mouse_moved
function BlackMarketGui:mouse_moved(o, x, y)
	if self._enabled and not self._renaming_item then
		local ui = MoreWeaponStats and MoreWeaponStats.ui
		local breakpoints_panel = ui and ui.breakpoints_panel

		if self.mws_breakpoints then
			if breakpoints_panel and self.mws_bp_panel and self.mws_bp_panel:inside(x, y) then
				if breakpoints_panel.difficulty_at(self, x, y) then
					return true, 'link'
				end

				if breakpoints_panel.bonus_at(self, x, y) then
					return true, 'link'
				end
			end

		elseif self.mws_stances_panel then
			if self.mws_range_charts then
				self.mws_range_charts_floating_text:hide()
				for _, chart in ipairs(self.mws_range_charts) do
					local txt = chart:visible() and chart:get_text_at(x, y)
					if txt then
						self.mws_range_charts_floating_text:show()
						self.mws_range_charts_floating_text:set_text(txt)
						self.mws_range_charts_floating_text:set_world_right(x)
						self.mws_range_charts_floating_text:set_world_top(y + 15)
						return true
					end
				end
			end

			if self.mws_stances_panel:inside(x, y) then
				if self.mws_stances_bitmaps[1]:inside(x, y) or self.mws_stances_bitmaps[3]:inside(x, y) then
					return true, 'link'
				end
			end
		end
	end

	return mws_original_blackmarketgui_mousemoved(self, o, x, y)
end

local function mws_pcall(what, fct)
	local ok, err = pcall(fct)
	if not ok then
		log(('[More Weapon Stats] %s: %s'):format(what, tostring(err)))
	end
end

local mws_original_blackmarketgui_showstats = BlackMarketGui.show_stats
function BlackMarketGui:show_stats()
	mws_pcall('show_stats pre-clear', function()
		if _henchmen_weapon and self:mws_is_buying() then
			self._slot_data.comparision_data = nil
		end
	end)

	mws_original_blackmarketgui_showstats(self)

	mws_pcall('show_stats', function()
		self:_show_stats()
	end)
end

function BlackMarketGui:_show_stats()
	local slot_data = self._slot_data

	-- One player snapshot per render: difficulty, skills and stances are read
	-- once and shared by the stat rows, the range chart and the comparison
	-- column instead of being re-read per row.
	local core = MoreWeaponStats and MoreWeaponStats.core
	local context_module = core and core.context

	if context_module and type(context_module.invalidate) == 'function' then
		context_module.invalidate()
	end

	local context = self:mws_context()

	-- breakpoints
	if self.mws_breakpoints then
		self._stats_panel:hide()

		local breakpoints_panel = MoreWeaponStats.ui.breakpoints_panel

		if breakpoints_panel then
			breakpoints_panel.refresh(self, context)
		end
	end

	-- melee
	if self._mweapon_stats_panel and self._mweapon_stats_panel:visible() and self.mws_stats_texts then
		local equipped_model = self:mws_get_wbase_from_slot(true)
		local selected_model = not slot_data.equipped and self:mws_get_wbase_from_slot(false)

		MoreWeaponStats.ui.melee.refresh(self, selected_model, equipped_model, context)
	end

	-- weapons
	if not _henchmen_weapon and self._rweapon_stats_panel and self._rweapon_stats_panel:visible() then
		self:mws_realign_rcells(self._rweapon_stats_panel)
		if self.mws_stats_texts then
			-- Left cells are the equipped weapon, right cells the selected slot,
			-- the same columns the vanilla table shows.
			local equipped_model = self:mws_get_wbase_from_slot(true)
			local selected_model = not slot_data.equipped and self:mws_get_wbase_from_slot(false)

			MoreWeaponStats.ui.stats_panel.refresh(self, selected_model, equipped_model, context)

			if self.mws_range_charts then
				local ballistics = core and core.ballistics

				local function update_bars(wbase, chart)
					if not chart then
						return
					end

					local weapon_tweak = wbase
						and type(wbase.weapon_tweak_data) == 'function'
						and wbase:weapon_tweak_data()

					if ballistics
						and wbase
						and type(wbase.is_weak_hit) == 'function'
						and weapon_tweak
						and weapon_tweak.damage_falloff
						and (wbase._optimal_distance or 0) + (wbase._optimal_range or 0) ~= 0
					then
						local col_ray = { distance = 0 }
						local function get_text_height_colour(i)
							col_ray.distance = (i - 1) * 50
							local value = ballistics.get_damage_falloff(wbase, col_ray.distance, context)
							if not value then
								return nil, 0
							end
							local dmg = value * wbase._damage * 10
							local txt = managers.localization:text('mws_range_chart_text', {
								DMG = ('%.1f'):format(dmg),
								DIS = ('%.1f'):format(col_ray.distance / 100)
							})
							if value == 1 then
								return txt, 1, Color(0.2, 1, 1, 1)
							else
								return txt, (value - 1) * -25, tweak_data.screen_colors[value < 1 and 'stats_negative' or 'stats_positive']
							end
						end
						chart:update(get_text_height_colour)
						chart:show()
					else
						chart:hide()
					end
				end
				update_bars(equipped_model, self.mws_range_charts[1])
				update_bars(selected_model, self.mws_range_charts[2])
			end
		end
	end

	-- henchmen
	if _henchmen_weapon and not slot_data.comparision_data and slot_data.unlocked and not slot_data.empty_slot then
		self:set_weapons_stats_columns()
		self._rweapon_stats_panel:show()
		self._stats_panel:show()
		self:hide_armor_stats()
		self:hide_melee_weapon_stats()

		local wbase_equipped, wbase_selected
		if self:mws_is_buying() then
			wbase_selected = self:mws_get_wbase_from_slot(false, nil, nil, nil, true)
		else
			wbase_equipped = self:mws_get_wbase_from_slot(false, nil, nil, self:mws_get_equipped_slot_npc(), true)
			wbase_selected = not slot_data.equipped and self:mws_get_wbase_from_slot(false, nil, nil, nil, true)
		end

		for _, title in pairs(self._stats_titles) do
			title:hide()
		end
		self:set_stats_titles({
			show = true,
			name = 'total'
		}, {
			name = 'equip',
			text_id = 'bm_menu_equipped',
			alpha = 0.75,
			x = 105,
			show = true
		})

		for _, stat in ipairs(self._stats_shown) do
			local value_equipped, value_selected = '', ''
			if stat.name == 'magazine' then
				if wbase_equipped then
					value_equipped = wbase_equipped:get_ammo_max_per_clip()
				end
				if wbase_selected then
					value_selected = wbase_selected:get_ammo_max_per_clip()
				end
			elseif stat.name == 'fire_rate' then
				if wbase_equipped then
					local td = wbase_equipped:weapon_tweak_data()
					local fire_rate = 60 / (td[td.FIRE_MODE] and td[td.FIRE_MODE].fire_rate or 1) -- see NPCRaycastWeaponBase:trigger_held()
					value_equipped = math.round(fire_rate / 10 * 10)
				end
				if wbase_selected then
					local td = wbase_selected:weapon_tweak_data()
					local fire_rate = 60 / (td.auto and td.auto.fire_rate or 1)
					value_selected = math.round(fire_rate / 10 * 10)
				end
			elseif stat.name == 'damage' then
				if wbase_equipped then
					value_equipped = wbase_equipped._damage * 10
				end
				if wbase_selected then
					value_selected = wbase_selected._damage * 10
				end
			end

			local stats_text = self._stats_texts[stat.name]
			stats_text.name:set_text(utf8.to_upper(managers.localization:text('bm_menu_' .. stat.name)))
			stats_text.equip:set_alpha(0.75)
			stats_text.equip:set_text(value_equipped)
			stats_text.equip:set_color(tweak_data.screen_colors.text)
			stats_text.total:set_text(value_selected)
			stats_text.total:set_color(tweak_data.screen_colors.text)
		end

		if self.mws_stats_texts then
			MoreWeaponStats.ui.henchmen.refresh(self, wbase_selected, wbase_equipped, context)
		end
	end
end

function BlackMarketGui:mws_get_equipped_slot_npc()
	for _, tabdata in ipairs(self._data) do
		for _, item in ipairs(tabdata) do
			if item.equipped then
				return item
			end
		end
	end
end

function BlackMarketGui:mws_get_wbase_from_slot(equipped, remove_mod, add_mod, slot_data, npc)
	slot_data = slot_data or self._slot_data
	if not slot_data or slot_data.name == 'sentry_gun' then
		return
	end

	local category = slot_data.category
	if tweak_data.weapon[slot_data.name] then
		local slot = equipped and managers.blackmarket:equipped_weapon_slot(category) or slot_data.slot

		-- One crafted-table read for the slot: it carries both the weapon id and
		-- the skin (`cosmetics`) the stat model needs.
		local crafted = equipped and managers.blackmarket:equipped_item(category) or managers.blackmarket:get_crafted_category_slot(category, slot)
		local weapon_id = crafted and crafted.weapon_id or slot_data.name
		local cosmetics = crafted and crafted.cosmetics or nil
		local factory_id = managers.weapon_factory:get_factory_id_by_weapon_id(weapon_id)

		local blueprint = managers.blackmarket:get_weapon_blueprint(category, slot)

		if not blueprint and factory_id then
			blueprint = managers.weapon_factory:get_default_blueprint_by_factory_id(factory_id)
		end

		blueprint = deep_clone(blueprint)
		if blueprint then
			if remove_mod then
				for i = 1, #blueprint do
					if blueprint[i] == remove_mod then
						table.remove(blueprint, i)
						break
					end
				end
			end
			if add_mod then
				table.insert(blueprint, add_mod)
			end
		end

		return MoreWeaponStats.core.weapon.new_from_slot(weapon_id, blueprint, {
			npc = npc,
			category = category,
			slot = slot,
			cosmetics = cosmetics,
		})

	elseif tweak_data.blackmarket.melee_weapons[slot_data.name] then
		local weapon_id = equipped and managers.blackmarket:equipped_item(category) or slot_data.name
		return {
			_name_id = weapon_id,
		}
	end
end
