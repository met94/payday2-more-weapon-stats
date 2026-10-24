--[[
tests/run_tests.lua — headless test runner for More Weapon Stats.

Usage, from the mod root:
	D:\Programowanie\payday\2\v2\tools\luajit\luajit.exe tests\run_tests.lua

The runner stubs the handful of globals the mod's Lua files need at load time
(ModPath, SavePath, json, Color, log), loads lua/entry.lua to run the module
bootstrap, then executes every case registered by the spec files. It never
touches the game executable, a manager or a unit.

Exit code: 0 when every case passes, 1 otherwise.
]]

-- Locate the mod root from this script's own path so the runner works no matter
-- which directory it is started from.
local script_path = (arg and arg[0]) or 'tests/run_tests.lua'
local script_dir = script_path:gsub('[/\\][^/\\]+$', '')
local root = script_dir:gsub('[/\\]?tests$', '')
if root == '' then
	root = '.'
end

ModPath = root .. '/'
SavePath = ModPath

json = {
	encode = function()
		return '{}'
	end,
	decode = function()
		return {}
	end,
}

function Color(r, g, b, a)
	local color = { r = r, g = g, b = b, a = a or 1 }

	function color:with_alpha(alpha)
		return Color(self.r, self.g, self.b, alpha)
	end

	return color
end

function log()
end

-- Minimal harness ------------------------------------------------------------

local harness = {}
local cases = {}

local function describe(value)
	if type(value) == 'string' then
		return ('%q'):format(value)
	end
	return tostring(value)
end

function harness.test(name, fn)
	cases[#cases + 1] = { name = name, fn = fn }
end

function harness.assert_true(value, message)
	if not value then
		error((message or 'expected a truthy value') .. ', got ' .. describe(value), 2)
	end
end

function harness.assert_equal(actual, expected, message)
	if actual ~= expected then
		error(('%s: expected %s, got %s'):format(message or 'assert_equal', describe(expected), describe(actual)), 2)
	end
end

function harness.assert_nil(value, message)
	if value ~= nil then
		error(('%s: expected nil, got %s'):format(message or 'assert_nil', describe(value)), 2)
	end
end

function harness.assert_type(value, expected_type, message)
	if type(value) ~= expected_type then
		error(('%s: expected a %s, got %s'):format(message or 'assert_type', expected_type, type(value)), 2)
	end
end

-- Load the mod through its normal bootstrap, then the spec files.

dofile(ModPath .. 'lua/entry.lua')

local specs = {
	'tests/weapon_spec.lua',
	'tests/stats_spec.lua',
	'tests/breakpoints_spec.lua',
	'tests/stats_panel_spec.lua',
	'tests/breakpoints_panel_spec.lua',
	'tests/melee_spec.lua',
	'tests/henchmen_spec.lua',
	'tests/compat_spec.lua',
	'tests/loader_spec.lua',
}

for _, spec_path in ipairs(specs) do
	local spec = dofile(ModPath .. spec_path)
	assert(type(spec) == 'function', spec_path .. ' must return a function that registers cases')
	spec(harness)
end

-- Run -----------------------------------------------------------------------

print('More Weapon Stats - headless tests')

local failed = 0
for _, case in ipairs(cases) do
	local ok, err = pcall(case.fn)
	if ok then
		print('  PASS  ' .. case.name)
	else
		failed = failed + 1
		print('  FAIL  ' .. case.name)
		print('        ' .. tostring(err))
	end
end

local total = #cases
print(('  %d passed, %d failed, %d total'):format(total - failed, failed, total))

if failed > 0 or total == 0 then
	os.exit(1)
end

os.exit(0)
