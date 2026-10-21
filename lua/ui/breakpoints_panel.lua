--[[
ui/breakpoints_panel.lua — breakpoint table, chart and difficulty picker.

Responsibility:
	Own the breakpoint table, the bonus toggles, the fill-breakpoints setting and
	the difficulty picker that Task 6 moves out of _breakpoints.lua,
	_chart.lua and _difficulty_picker.lua. Values come from
	MoreWeaponStats.core.ballistics.

Public API (Task 6 fills these in):
	breakpoints_panel.init(gui)
		Called once per Black Market setup, after the breakpoint panels exist.
	breakpoints_panel.refresh(gui, context)
		Called when the selected weapon, difficulty or bonus toggles change.

	Both are no-ops until Task 6.
]]

local breakpoints_panel = {}

function breakpoints_panel.init(gui)
end

function breakpoints_panel.refresh(gui, context)
end

return breakpoints_panel
