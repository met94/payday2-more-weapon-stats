--[[
tests/loader_spec.lua â€” MoreWeaponStats:load_module and the inert hook path.

Why these cases exist: the in-game crash in v78 was `lua/entry.lua:81`
("module must return a table: lua/ui/stats_panel.lua"). Headless LuaJIT's
`dofile` returns the chunk value, SuperBLT's does not, so the bootstrap only
failed in the game. The loader now reads the return value from the chunk call
itself; these cases pin the loader order and the failure policy:

	* blt.vm.loadfile is preferred when it exists (and gets the path);
	* plain loadfile is the fallback when blt is absent, and also when the blt
	  loader throws (SuperBLT aliases the global `loadfile` to its own loader, so
	  these are the same function in-game but different functions in the tests);
	* io.open + loadstring is the last resort, with `load` when loadstring is
	  absent;
	* a missing path returns nil + an error naming the path, never throws;
	* a chunk that throws returns nil + the error, never throws;
	* a non-table chunk return is passed through for the caller's validation
	  (entry.lua's bootstrap is what rejects it);
	* the Black Market hook installs nothing â€” not one method on either class â€”
	  while the namespace is disabled, and nothing when the chart module is
	  missing; SuperBLT's per-script load guard is cleared afterwards.

Every stubbed global is restored with pcall, same pattern as tests/compat_spec.lua.
]]

local load_module = MoreWeaponStats.load_module

-- Runs fn with temporary globals, restoring every previous value afterwards.
local function with_globals(stubs, fn)
	local previous = {}

	for name, value in pairs(stubs) do
		previous[name] = rawget(_G, name)
		_G[name] = value
	end

	local ok, err = pcall(fn)

	for name in pairs(stubs) do
		_G[name] = previous[name]
	end

	if not ok then
		error(err, 0)
	end
end

-- The full set of Black Market methods the hook file wraps or adds when it
-- loads successfully. The inert cases below must see every one untouched.
local GUI_METHODS = {
	'_setup',
	'close',
	'_update_borders',
	'set_info_text',
	'update_info_text',
	'show_btns',
	'show_stats',
	'mouse_pressed',
	'mouse_moved',
}

local SLOT_ITEM_METHODS = { 'init', 'select', 'deselect' }

-- Builds a stub class table whose methods are all distinguishable closures so
-- a replaced method is caught by identity.
local function stub_methods(names)
	local subject = {}
	local originals = {}

	for _, name in ipairs(names) do
		local fn = function() end

		subject[name] = fn
		originals[name] = fn
	end

	return subject, originals, #names
end

local function assert_untouched(t, label, subject, originals, expected_keys)
	for name, fn in pairs(originals) do
		t.assert_true(rawequal(subject[name], fn), label .. ' ' .. name .. ' untouched')
	end

	local count = 0

	for _ in pairs(subject) do
		count = count + 1
	end

	t.assert_equal(count, expected_keys, label .. ': no method added')
end

return function(t)
	t.test('load_module uses blt.vm.loadfile when present', function()
		local sentinel = {marker = 'blt module'}
		local loaded_paths = {}
		local loadfile_calls = 0

		with_globals({
			blt = {
				vm = {
					loadfile = function(path)
						loaded_paths[#loaded_paths + 1] = path

						return function()
							return sentinel
						end
					end,
				},
			},
			loadfile = function()
				loadfile_calls = loadfile_calls + 1

				return function()
					return {}
				end
			end,
		}, function()
			local module, err = load_module(MoreWeaponStats, 'mods/More Weapon Stats/lua/sentinel.lua')

			t.assert_nil(err, 'no error')
			t.assert_true(rawequal(module, sentinel), 'the blt chunk table is returned')
			t.assert_equal(#loaded_paths, 1, 'blt loader called once')
			t.assert_equal(loaded_paths[1], 'mods/More Weapon Stats/lua/sentinel.lua', 'path forwarded')
			t.assert_equal(loadfile_calls, 0, 'loadfile not used when blt works')
		end)
	end)

	t.test('load_module falls back to loadfile without blt', function()
		with_globals({
			blt = false,
		}, function()
			local module, err = load_module(MoreWeaponStats, ModPath .. 'lua/core/context.lua')

			t.assert_nil(err, 'no error')
			t.assert_type(module, 'table', 'context module returned')
			t.assert_type(module.get, 'function', 'context.get exported')
			t.assert_type(module.invalidate, 'function', 'context.invalidate exported')
		end)
	end)

	t.test('a throwing blt loader falls back to loadfile', function()
		with_globals({
			blt = {
				vm = {
					loadfile = function()
						error('blt loader exploded')
					end,
				},
			},
		}, function()
			local module, err = load_module(MoreWeaponStats, ModPath .. 'lua/core/context.lua')

			t.assert_nil(err, 'fallback succeeded')
			t.assert_type(module, 'table', 'context module returned')
		end)
	end)

	t.test('load_module returns nil and an error for a missing path', function()
		with_globals({
			blt = false,
		}, function()
			local module, err = load_module(MoreWeaponStats, ModPath .. 'lua/this_file_does_not_exist.lua')

			t.assert_nil(module, 'no module')
			t.assert_type(err, 'string', 'error message')
			t.assert_true(err:find('this_file_does_not_exist', 1, true) ~= nil, 'error names the path')
		end)
	end)

	t.test('a throwing chunk returns nil and the error message', function()
		with_globals({
			blt = {
				vm = {
					loadfile = function()
						return function()
							error('module body exploded')
						end
					end,
				},
			},
		}, function()
			local module, err = load_module(MoreWeaponStats, 'mods/More Weapon Stats/lua/throws.lua')

			t.assert_nil(module, 'no module')
			t.assert_type(err, 'string', 'error message')
			t.assert_true(err:find('module body exploded', 1, true) ~= nil, 'chunk error propagated')
		end)
	end)

	t.test('a non-table chunk return is passed through for caller validation', function()
		with_globals({
			blt = {
				vm = {
					loadfile = function()
						return function()
							return 42
						end
					end,
				},
			},
		}, function()
			local module, err = load_module(MoreWeaponStats, 'mods/More Weapon Stats/lua/not_a_table.lua')

			t.assert_nil(err, 'the loader itself does not reject non-tables')
			t.assert_equal(module, 42, 'value passed through')
			-- entry.lua's bootstrap is the validation point: it requires a table
			-- and disables the namespace otherwise.
			t.assert_true(type(module) ~= 'table', 'caller must reject this')
		end)
	end)

	t.test('load_module reaches the io.open + loadstring branch', function()
		local sentinel = {marker = 'loadstring module'}
		local opened = {}
		local source_seen
		local chunk_name

		with_globals({
			-- `false` rather than nil: nil values vanish from a table literal, so
			-- the key would not be stubbed at all.
			blt = false,
			loadfile = false,
			io = {
				open = function(path, mode)
					opened.path = path
					opened.mode = mode

					return {
						read = function(_, pattern)
							opened.pattern = pattern

							return 'return sentinel_source'
						end,
						close = function() end,
					}
				end,
			},
			loadstring = function(source, name)
				source_seen = source
				chunk_name = name

				return function()
					return sentinel
				end
			end,
		}, function()
			local module, err = load_module(MoreWeaponStats, 'mods/More Weapon Stats/lua/source_only.lua')

			t.assert_nil(err, 'no error')
			t.assert_true(rawequal(module, sentinel), 'the stubbed chunk table is returned')
			t.assert_equal(opened.path, 'mods/More Weapon Stats/lua/source_only.lua', 'path passed to io.open')
			t.assert_equal(opened.mode, 'rb', 'binary mode')
			t.assert_equal(opened.pattern, '*a', 'whole file read')
			t.assert_equal(source_seen, 'return sentinel_source', 'source forwarded to loadstring')
			t.assert_equal(chunk_name, '@mods/More Weapon Stats/lua/source_only.lua', 'chunk name')
		end)
	end)

	t.test('load_module uses load when loadstring is absent', function()
		local sentinel = {marker = 'load module'}
		local received_name

		with_globals({
			-- `false` rather than nil: nil values vanish from a table literal.
			blt = false,
			loadfile = false,
			loadstring = false,
			io = {
				open = function()
					return {
						read = function()
							return 'return sentinel'
						end,
						close = function() end,
					}
				end,
			},
			load = function(_, name)
				received_name = name

				return function()
					return sentinel
				end
			end,
		}, function()
			local module, err = load_module(MoreWeaponStats, 'mods/More Weapon Stats/lua/load_only.lua')

			t.assert_nil(err, 'no error')
			t.assert_true(rawequal(module, sentinel), 'the stubbed chunk table is returned')
			t.assert_equal(received_name, '@mods/More Weapon Stats/lua/load_only.lua', 'chunk name')
		end)
	end)

	t.test('the Black Market hook stays inert while the namespace is disabled', function()
		local gui, gui_originals, gui_keys = stub_methods(GUI_METHODS)
		local slot_item, slot_originals, slot_item_keys = stub_methods(SLOT_ITEM_METHODS)
		local previous = MoreWeaponStats.disabled
		local required_script = 'mws_loader_spec_disabled'
		local guard_key = ModPath .. '\t' .. required_script

		local ok, err = pcall(function()
			MoreWeaponStats.disabled = true

			with_globals({
				RequiredScript = required_script,
				BlackMarketGui = gui,
				BlackMarketGuiSlotItem = slot_item,
			}, function()
				-- dofile is the test runner's own loader; the mod never uses it.
				dofile(ModPath .. 'lua/blackmarketgui.lua')
			end)
		end)

		MoreWeaponStats.disabled = previous
		-- The hook writes SuperBLT's per-script guard before any early return.
		_G[guard_key] = nil

		if not ok then
			error(err, 0)
		end

		assert_untouched(t, 'BlackMarketGui', gui, gui_originals, gui_keys)
		assert_untouched(t, 'BlackMarketGuiSlotItem', slot_item, slot_originals, slot_item_keys)
		t.assert_nil(gui.mws_context, 'no MWS helper installed')
		t.assert_nil(rawget(_G, guard_key), 'no load guard left in _G')
	end)

	t.test('a missing chart module leaves the Black Market vanilla', function()
		local gui, gui_originals, gui_keys = stub_methods(GUI_METHODS)
		local slot_item, slot_originals, slot_item_keys = stub_methods(SLOT_ITEM_METHODS)
		local original = MoreWeaponStats.load_module
		local required_script = 'mws_loader_spec_no_chart'
		local guard_key = ModPath .. '\t' .. required_script

		local ok, err = pcall(function()
			MoreWeaponStats.load_module = function()
				return nil, 'stub: chart unavailable'
			end

			with_globals({
				RequiredScript = required_script,
				BlackMarketGui = gui,
				BlackMarketGuiSlotItem = slot_item,
			}, function()
				dofile(ModPath .. 'lua/blackmarketgui.lua')
			end)
		end)

		MoreWeaponStats.load_module = original
		_G[guard_key] = nil

		if not ok then
			error(err, 0)
		end

		assert_untouched(t, 'BlackMarketGui', gui, gui_originals, gui_keys)
		assert_untouched(t, 'BlackMarketGuiSlotItem', slot_item, slot_originals, slot_item_keys)
		t.assert_nil(gui.mws_context, 'no MWS helper installed')
		t.assert_nil(rawget(_G, guard_key), 'no load guard left in _G')
		t.assert_true(rawequal(MoreWeaponStats.load_module, original), 'loader restored')
	end)
end
