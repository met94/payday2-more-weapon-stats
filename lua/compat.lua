--[[
compat.lua — integrations with other mods.

Responsibility:
	Keep every cross-mod accommodation in one place so the core modules stay
	independent of load order and of other mods' internals.

Planned integrations (Task 7 implements them):
	- Super Duper Skin Swapper, Optional Skin Attachments, Hide Duplicate Skins:
	  skin preview/apply data passed through as cosmetics.
	- VanillaHUD Plus and The Fixes: no shared panels or hooks expected; verify.
	- Anticrash and Mod Hider: verify the mod loads cleanly when they wrap menus.
	- Extra Heist Info: verify the Black Market panels coexist.

Public API:
	compat.init()
		Called once by the entry bootstrap after the core and ui modules load.
]]

local compat = {}

function compat.init()
end

return compat
