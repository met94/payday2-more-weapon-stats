_G.MoreWeaponStats = _G.MoreWeaponStats or {}
MoreWeaponStats._path = ModPath
MoreWeaponStats._data_path = SavePath .. 'more_weapon_stats.txt'
MoreWeaponStats.stance_color = Color(0.114, 0.736, 0.517)
MoreWeaponStats.settings = {
	display = {
		ammo_pickup = true,
		equip_delay = true,
		falloff = true,
		recoil_horiz = true,
		recoil_vert = true,
		reload_full = true,
		reload_partial = true,
		spread = true,
		spread_vert = false,
	},
	show_dlc_info = true,
	last_used_difficulty = 'overkill_290',
	fill_breakpoints = true,
	use_preview_to_switch_breakpoints = true,
	clicks_per_second = 5,
	enable_trigger_happy_for_first_bullet = true
}

function MoreWeaponStats:load()
	local file = io.open(self._data_path, 'r')
	if file then
		for k, v in pairs(json.decode(file:read('*all')) or {}) do
			self.settings[k] = v
		end
		file:close()
	end
end

function MoreWeaponStats:save()
	local file = io.open(self._data_path, 'w+')
	if file then
		file:write(json.encode(self.settings))
		file:close()
	end
end

--[[
Module bootstrap.

Every file below is a plain Lua module: it owns one piece of the rewrite, has no
side effects at load time, and returns the table it exposes. Engine access only
happens inside the functions those tables export. The modules are loaded here
because entry.lua runs as a `lib/entry` pre-hook, before any menu or manager
code can ask for them.

Public namespaces after bootstrap:
	MoreWeaponStats.core.context | weapon | ballistics | timers | accuracy | ammo |
		breakpoints
	MoreWeaponStats.ui.stats_panel | breakpoints_panel | melee | henchmen
	MoreWeaponStats.compat
]]
MoreWeaponStats.core = MoreWeaponStats.core or {}
MoreWeaponStats.ui = MoreWeaponStats.ui or {}

local module_paths = {
	core = {
		'context',
		'weapon',
		'ballistics',
		'timers',
		'accuracy',
		'ammo',
		'breakpoints',
	},
	ui = {
		'stats_panel',
		'breakpoints_panel',
		'melee',
		'henchmen',
	},
}

local function load_module(relative_path)
	local module = dofile(MoreWeaponStats._path .. relative_path)
	assert(type(module) == 'table', 'More Weapon Stats: module must return a table: ' .. relative_path)
	return module
end

for namespace, names in pairs(module_paths) do
	for _, name in ipairs(names) do
		MoreWeaponStats[namespace][name] = load_module('lua/' .. namespace .. '/' .. name .. '.lua')
	end
end

MoreWeaponStats.compat = load_module('lua/compat.lua')
MoreWeaponStats.compat.init()
