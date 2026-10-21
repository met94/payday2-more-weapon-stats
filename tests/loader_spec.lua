--[[
tests/loader_spec.lua — MoreWeaponStats:load_module and the inert hook path.

Why these cases exist: the in-game crash in v78 was `lua/entry.lua:81`
("module must return a table: lua/ui/stats_panel.lua"). Headless LuaJIT's
`dofile` returns the chunk value, SuperBLT's does not, so the bootstrap only
failed in the game. The loader now reads the return value from the chunk call
itself; these cases pin the loader order and the failure policy:

	* blt.vm.loadfile is preferred when it exists (and gets the path);
	* plain loadfile is the fallback when blt is absent, and also when the blt
	  loader throws;
	* a missing path returns nil + an error naming the path, never throws;
	* a chunk that throws returns nil + the error, never throws;
	* a non-table chunk return is passed through for the caller's validation
	  (entry.lua's bootstrap is what rejects it);
	* the Black Market hook installs nothing while the namespace is disabled,
	  and nothing when the chart module is missing.

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
			blt = nil,
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
			blt = nil,
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

	t.test('the Black Market hook stays inert while the namespace is disabled', function()
		local setup = function() end
		local gui = {_setup = setup}
		local previous = MoreWeaponStats.disabled

		local ok, err = pcall(function()
			MoreWeaponStats.disabled = true

			with_globals({
				RequiredScript = 'mws_loader_spec_disabled',
				BlackMarketGui = gui,
				BlackMarketGuiSlotItem = {},
			}, function()
				-- dofile is the test runner's own loader; the mod never uses it.
				dofile(ModPath .. 'lua/blackmarketgui.lua')
			end)
		end)

		MoreWeaponStats.disabled = previous

		if not ok then
			error(err, 0)
		end

		t.assert_true(rawequal(gui._setup, setup), 'vanilla _setup untouched')
		t.assert_nil(gui.show_stats, 'no MWS method installed')
		t.assert_nil(gui.mws_context, 'no MWS helper installed')
	end)

	t.test('a missing chart module leaves the Black Market vanilla', function()
		local setup = function() end
		local gui = {_setup = setup}
		local original = MoreWeaponStats.load_module

		local ok, err = pcall(function()
			MoreWeaponStats.load_module = function()
				return nil, 'stub: chart unavailable'
			end

			with_globals({
				RequiredScript = 'mws_loader_spec_no_chart',
				BlackMarketGui = gui,
				BlackMarketGuiSlotItem = {},
			}, function()
				dofile(ModPath .. 'lua/blackmarketgui.lua')
			end)
		end)

		MoreWeaponStats.load_module = original

		if not ok then
			error(err, 0)
		end

		t.assert_true(rawequal(gui._setup, setup), 'vanilla _setup untouched')
		t.assert_nil(gui.show_stats, 'no MWS method installed')
		t.assert_true(rawequal(MoreWeaponStats.load_module, original), 'loader restored')
	end)
end
