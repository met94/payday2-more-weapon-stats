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
Module loader.

SuperBLT's file-include helper compiles and runs a file but does not hand the
chunk's return value back to the caller. Loading a module that returns its table
would therefore yield nothing and the bootstrap would fail on the first module.
Modules are loaded as chunks instead, and the return value is read from the
call:

	1. blt.vm.loadfile(path)      SuperBLT's loader, pcall'd
	2. loadfile(path)             plain LuaJIT loader, pcall'd; SuperBLT aliases
	                              the global `loadfile` to blt.vm.loadfile, so
	                              this branch only differs when `blt` is absent
	                              (or its loader throws first)
	3. io.open(path, 'rb') + loadstring(src, '@'..path)  last resort

The chunk itself also runs under pcall, so a missing file, a syntax error or a
throwing module body returns nil + a message instead of killing the game.

Returns the chunk's return value and nil on success, nil + an error string on
any load or execution failure.
]]
function MoreWeaponStats:load_module(path)
	path = tostring(path)

	local chunk
	local errors = {}

	local function remember(loader, ok, result, err)
		if ok and type(result) == 'function' then
			chunk = result
			return
		end

		if ok then
			errors[#errors + 1] = ('%s returned %s'):format(loader, type(result))
		else
			errors[#errors + 1] = ('%s: %s'):format(loader, tostring(err or result))
		end
	end

	if type(blt) == 'table' and type(blt.vm) == 'table' and type(blt.vm.loadfile) == 'function' then
		local ok, result, err = pcall(blt.vm.loadfile, path)
		remember('blt.vm.loadfile', ok, result, err)
	end

	if not chunk and type(loadfile) == 'function' then
		local ok, result, err = pcall(loadfile, path)
		remember('loadfile', ok, result, err)
	end

	if not chunk then
		local source
		local ok, data, err = pcall(function()
			local file = io.open(path, 'rb')

			if not file then
				return nil, 'cannot open ' .. path
			end

			local contents = file:read('*a')
			file:close()

			return contents
		end)

		if ok and data then
			source = data
		else
			errors[#errors + 1] = 'io.open: ' .. tostring(ok and err or data)
		end

		if source then
			local loader = type(loadstring) == 'function' and loadstring
				or (type(load) == 'function' and load or nil)

			if loader then
				local loaded, result, serr = pcall(loader, source, '@' .. path)
				remember('loadstring', loaded, result, serr)
			else
				errors[#errors + 1] = 'loadstring: unavailable'
			end
		end
	end

	if type(chunk) ~= 'function' then
		return nil, ('could not load %s (%s)'):format(
			path,
			#errors > 0 and table.concat(errors, '; ') or 'no loader available'
		)
	end

	local ok, module = pcall(chunk)

	if not ok then
		return nil, ('%s: %s'):format(path, tostring(module))
	end

	return module, nil
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

-- A module has to return a table; anything else (nil, a number, an error from
-- the loader) is reported as a load failure.
local function load_table_module(relative_path)
	local module, err = MoreWeaponStats:load_module(MoreWeaponStats._path .. relative_path)

	if type(module) ~= 'table' then
		return nil, ('module must return a table: %s (%s)'):format(relative_path, tostring(err))
	end

	return module, nil
end

-- Failure policy: log once, mark the namespace disabled and leave the rest to
-- the hook files. Nothing here asserts: a broken module must cost the mod, not
-- the game. The Black Market hook returns early while `disabled` is set, so a
-- partial bootstrap never wraps vanilla menu methods.
local function disable(relative_path, err)
	MoreWeaponStats.disabled = true
	MoreWeaponStats.load_error = err

	log('[More Weapon Stats] failed to load ' .. relative_path .. ': ' .. tostring(err))
end

local function bootstrap()
	MoreWeaponStats.disabled = false
	MoreWeaponStats.load_error = nil

	for namespace, names in pairs(module_paths) do
		for _, name in ipairs(names) do
			local relative_path = 'lua/' .. namespace .. '/' .. name .. '.lua'
			local module, err = load_table_module(relative_path)

			if not module then
				disable(relative_path, err)
				return
			end

			MoreWeaponStats[namespace][name] = module
		end
	end

	local compat, err = load_table_module('lua/compat.lua')

	if not compat then
		disable('lua/compat.lua', err)
		return
	end

	MoreWeaponStats.compat = compat

	-- Only reached when every module above loaded. compat.init() hooks game
	-- managers, so a throw there is as fatal as a bad module: pcall it and turn
	-- the namespace off rather than let the error escape the lib/entry pre-hook.
	local ok, init_err = pcall(MoreWeaponStats.compat.init)

	if not ok then
		disable('lua/compat.lua', 'compat.init failed: ' .. tostring(init_err))
	end
end

bootstrap()
