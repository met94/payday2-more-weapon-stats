# More Weapon Stats

Extended weapon statistics for the PAYDAY 2 Black Market, rebuilt as a pure-Lua
mod for **PAYDAY 2 248.2** (64-bit, SuperBLT).

The mod keeps the original name, options, localization and player-facing layout.
It adds the numbers the vanilla Black Market does not show, without spawning or
faking any engine weapon unit.

## What it shows

- Extended weapon rows: tactical/full reload, equip/unequip delay, ammo pickup,
  horizontal and vertical recoil, horizontal and vertical spread, damage falloff.
- Breakpoint table: damage needed to kill each enemy type in a chosen number of
  hits, with headshot/crit/Berserker/Overkill/Trigger Happy/Underdog/HVT/body
  expertise toggles.
- Difficulty preview for the breakpoint table, without changing the difficulty
  the game is actually running.
- Melee stats: attack delay, cooldown, unequip delay, special effect and DoT
  length.
- Henchman/NPC weapon stats: damage and hit chance by range, rate of fire,
  reload, aim delay and falloff.
- Damage-range charts and stance preview (hip fire, ADS, standing, crouched).
- DLC information, existing localization files and the original settings menu.

## 248.2 rewrite and crash fix

The original implementation built fake weapon units and swapped gameplay weapon
classes into menu code. On 248.2 that could crash natively in
`_set_material_textures` while a real menu weapon was assembled, especially when
entering the Black Market or previewing/applying a skin.

This rewrite removes that engine entirely:

- no `Faker`, `Overrider`, fake units, fake `PlayerInventory` or `SoundDevice`;
- no `NewRaycastWeaponBase` / `ShotgunBase` / other weapon-class hooks;
- no fake `PlayerInventory` registration, manager stubs or class snapshots;
- no `xpcall` assumptions (PAYDAY 2 Lua has no `xpcall`);
- no auto-update metadata, so the old v76 build cannot overwrite this one.

Stats are computed by a pure-Lua `WeaponModel` from:

- `tweak_data.weapon` and `tweak_data.weapon.stats`;
- the crafted blueprint and `tweak_data.weapon.factory.parts`
  (`adds`, `forbids`, `override`, part stats and custom stats);
- the player skill/perk/difficulty context;
- crafted cosmetics, including skin bonus stats.

The Black Market UI reads that model instead of a fake weapon base.

Additional fixes since the rewrite:

- **v79** — module loading uses an explicit chunk loader
  (`blt.vm.loadfile` → `loadfile` → `io.open`/`loadstring`). SuperBLT's
  `dofile` does not return a chunk's value; the old bootstrap treated that as a
  fatal module error.
- **v80** — the breakpoint table/bonus icons/difficulty picker build correctly
  on engine userdata panels, and the open/closed flag is kept separate from the
  breakpoint row list.

## Requirements

- PAYDAY 2 248.2, 64-bit.
- [SuperBLT](https://superblt.znix.xyz/) installed and working.

## Installation

1. Close PAYDAY 2.
2. Remove or rename any older More Weapon Stats folders in
   `...\PAYDAY 2\mods\`:
   - `More Weapon Stats`
   - `More Weapon Stats-fix-crash`
   - `More Weapon Stats-mws-rewrite`
3. Extract the release/download so the result is exactly:
   `...\PAYDAY 2\mods\More Weapon Stats\mod.txt`
4. Launch the game and open the Black Market.

If you download the GitHub source ZIP, rename the extracted
`payday2-more-weapon-stats-main` folder to `More Weapon Stats`.

Settings are stored in `...\PAYDAY 2\mods\saves\more_weapon_stats.txt`.
Old v76 setting keys are preserved.

Logs are in `...\PAYDAY 2\mods\logs\`. The expected line is
`Setting up mod 'More Weapon Stats'`; there should be no
`[More Weapon Stats] failed to load` or `FATAL ERROR` line.

> Do not install two folders with the same `mod.txt` name. SuperBLT treats the
> name as the dependency key and one copy will win unpredictably.

## Compatibility

Verified against the current load order with:

- Super Duper Skin Swapper
- Optional Skin Attachments
- Hide Duplicate Skins
- VanillaHUD Plus
- The Fixes
- Anticrash
- Mod Hider
- Extra Heist Info

The rewrite installs no weapon-class hooks and writes no globals outside its own
`MoreWeaponStats` table. Skin data is read from the crafted weapon and passed to
the model; the mod does not replace the skin-preview callbacks.

## A note on rifle falloff

In 248.2 many rifles (for example Lion's Roar/`vhs`, CAR-4/`new_m4`, AMCAR)
carry no `damage_falloff` or `damage_near`/`damage_far` data. For those weapons
the `Dmg. modifier` row and the range chart are blank by design. Shotguns,
pistols, SMGs, LMGs and snipers do have that data and display it.

## Development

Repository layout:

```text
lua/
  entry.lua              settings, loader, module bootstrap
  blackmarketgui.lua     Black Market hooks and adapters
  core/                  context, weapon model, ballistics, timers, accuracy,
                         ammo, breakpoints
  ui/                    stats, breakpoint, melee and henchman panels
  compat.lua             compatibility notes/contracts
  menumanager.lua        localization and settings menu
menu/options.txt         settings menu definition
loc/                     translations
tests/                   headless LuaJIT specs (not shipped in the mod zip)
MENU_OPTIONS.md          player-facing option guide
changelog.txt            release notes / player notes
```

Run the headless suite from the repository root with LuaJIT:

```powershell
luajit tests\run_tests.lua
```

Optional syntax gate:

```powershell
luajit -bl lua\entry.lua
```

The current release is **v80**. Keep `mod.txt` and `changelog.txt` in sync when
shipping changes.

## Credits

Original More Weapon Stats by TdlQ, with code from Better Weapon Stats GUI by
KarateF22, code maintenance by Nexqua, and translations by Arknights (Chinese),
NewPJzuza (Thai), andole and x(GOREMAGEDDON)x (Russian), Kilowide (Spanish).

This repository is the 248.2 clean-Lua rewrite.
