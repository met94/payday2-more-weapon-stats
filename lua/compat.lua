--[[
compat.lua — integrations with other mods.

Responsibility:
	Keep every cross-mod guarantee in one place so the core modules stay
	independent of load order and of other mods' internals. Nothing here hooks,
	creates globals or writes a manager: with the rewrite there is no shim left
	to install, and this file documents why.

Verified against the live mods in
`C:\Program Files (x86)\Steam\steamapps\common\PAYDAY 2\mods` (2026-10-21):

	Super Duper Skin Swapper 3.2.2 (priority 0, hooks blackmarketgui and
	blackmarketmanager)
		Wraps BlackMarketGui:mouse_pressed (calls the captured original),
		pre/post-hooks update_info_text and hides `_stats_panel` on the
		weapon_cosmetic tab. It never wraps _setup/show_stats and never defines
		a global MWS uses. MWS captures mouse_pressed the same way, so the
		chain stays intact in either load order.

	Optional Skin Attachments 5.0.2 (priority 0, hooks blackmarketgui and
	blackmarketmanager)
		Replaces _weapon_cosmetics_callback, wraps
		preview_cosmetic_on_weapon_callback and post-hooks populate_mods. Its
		blackmarketmanager reads `equipped_primary/secondary`; the rewrite no
		longer swaps those fields, so those reads see the real equipped item
		again. No shared names.

	Hide Duplicate Skins 2.1.1 (priority 0, hooks blackmarketgui)
		Wraps equip_weapon_cosmetics_callback and pre-hooks
		BlackMarketGuiTabItem:init. It reads `crafted.cosmetics` and uses its
		own ncUtils menu; it never touches `_setup`, `show_stats`, the MWS
		names or the stats panels.

	VanillaHUD Plus 3.4.18 (priority 1, hooks blackmarketgui)
		Wraps BlackMarketGui:_setup and BlackMarketGuiSlotItem:init, calling
		the captured original each time. MWS captures the current methods at
		load (priority 20 runs after it), so both wrappers run; the live log
		shows the resulting `_setup` chain.

	The Fixes 32.7 (supermod, priority -10, post-hooks only)
		Wraps BlackMarketManager:_get_weapon_stats (strips `cosmetics.bonus`
		for color skins) and reads Global.game_settings.difficulty. MWS reads
		the crafted table and the difficulty but never writes either, so the
		Fixes' reads stay authoritative. MWS does not call that wrapper; its
		own model treats `cosmetics.bonus` as a lookup key, so a colour skin's
		table-valued bonus resolves to no bonus instead of reaching the
		arithmetic crash the Fixes wrapper guards against.

	Anticrash v23 (priority 500, hooks weaponfactorymanager and menumanager)
		Sanitizes blueprints in WeaponFactoryManager:unpack_blueprint_from_string
		(the network path). MWS never unpacks a blueprint itself: it takes the
		crafted blueprint from managers.blackmarket, else the factory default
		from managers.weapon_factory, so a sanitized blueprint is what it
		consumes.

	Mod Hider 1.0 (replaces MenuCallbackHandler.build_mods_list and the
		is_modded_client predicates)
		No Black Market, MWS or stats-panel surface.

	Extra Heist Info r446 (supermod, priority -100, post-hooks blackmarketgui)
		Captures _setup at load and wraps it (calls the original), then mutates
		`_throwable_stats_shown`; also wraps _get_grenade_stats and
		populate_deployables/populate_grenades. MWS captures _setup at load
		too, so the two wrappers nest. EHI writes
		LocalizationManager._custom_localizations; MWS only calls
		LocalizationManager:text.

Cosmetics contract (SDSS/OSA/HDS):
	The rewrite reads the chosen skin from the crafted table
	(`get_crafted_category_slot` / `equipped_item(...).cosmetics`) and passes it
	to `core.weapon.new_from_slot(weapon_id, blueprint, { cosmetics = ... })`.
	It does not touch the skin callbacks those mods own, and it does not write
	BlackMarketManager.equipped_primary/secondary or
	Global.game_settings.difficulty anywhere.

Shared panel:
	`BlackMarketGui._stats_panel` is vanilla state. MWS only shows/hides it on
	the same paths the game does (vanilla show_stats restores it, the breakpoint
	panel hides it while open). SDSS hides it while a skin preview is open and
	the next weapon page re-shows it through vanilla show_stats, so MWS adds no
	visibility state a skin preview can strand.

Public API:
	compat.init()
		Called once by the entry bootstrap after the core and ui modules load.
		It is intentionally a no-op: every guarantee above is a property of the
		existing wrapper/read patterns, so there is nothing to install. Kept as
		the seam for a future integration that genuinely needs one.
]]

local compat = {}

function compat.init()
end

return compat
