# More Weapon Stats — Menu Options Guide

**Where:** Mod Options (SuperBLT) → **More Weapon Stats**.

The mod extends the Black Market weapon panel with extra stat rows (reload,
equip/unequip delay, ammo pickup, recoil, spread, damage falloff), adds the
breakpoint table (hits-to-kill per enemy type), the bonus toggles above it and
the risk-icon difficulty picker, plus melee and henchman/NPC weapon stats.
Everything is calculated from tweak data; the mod does not spawn units, swap
weapon classes or touch the running game's difficulty.

Settings are stored in `mods\saves\more_weapon_stats.txt` (the game's save
folder, next to your profiles). The file is written whenever you leave the mod
options menu, and every key from the old v76 build is still understood, so an
existing file loads as-is: nothing is reset when you update.

## Menu options

### Show DLC information — default **on**

*"Display the DLC required to use a weapon."*

Shows the "requires DLC" line under the selected Black Market slot, next to the
weapon name, in the weapon, melee and buy-weapon pages. Turn it off if you own
everything and the extra line is just noise; the row is removed, not greyed out.

### Show all numbers of hits (breakpoints) — default **on**

*Saved key: `fill_breakpoints`.*

When on, every breakpoint row gets a hit count for every enemy type — a type
that gains nothing at that damage value repeats the count from the breakpoint
below it, so the whole table is filled. When off, those cells stay blank and you
only see the damage values where a given enemy actually crosses a threshold.
Off gives a cleaner table; on makes it obvious that, say, a Bulldozer still
needs two more bullets at this damage.

### Use preview key to switch breakpoints — default **on**

*Saved key: `use_preview_to_switch_breakpoints`.*

When on, the **preview** key (the same key/button that previews a weapon in the
Black Market) toggles between the stat rows and the breakpoint table, and it no
longer previews the weapon. When off, preview behaves normally and the separate
**Show breakpoints** / **Hide breakpoints** button drives the table.

### Enable trigger happy for 1st bullet — default **on**

*"If disabled, when calculating breakpoints with trigger happy, the first bullet
doesn't have the damage bonus and acts as a trigger for the skill."*

Only matters when the **Trigger Happy** bonus toggle is enabled and you are
looking at a pistol. On: the first shot already counts as buffed, so a fresh
magazine's breakpoints look best-case. Off: the first bullet is treated as the
trigger shot without the bonus, and the buff applies from the second bullet —
the realistic reading when you open fire from a cold start.

### Maximum clicks per second — default **5** (slider: 3 – 8, step 1)

*"Used in breakpoints calculations for time limited bonuses when weapon's fire
rate is physically impossible to reach."*

Semi-auto, burst and other non-full-auto weapons are limited by how fast a human
can pull the trigger. The breakpoint table uses this value as your assumed click
rate when the **Trigger Happy** bonus is enabled and the weapon's own fire rate
would be faster than a player can click, so it decides how many shots fit inside
the skill's stacking window. Higher values show slightly better breakpoints for
fast-firing pistols; akimbo weapons get double this rate, as in the base game's
own handling. Full-auto weapons always use their real fire rate and ignore this
setting.

## Display rows (settings file only)

These nine keys live under `"display"` in
`mods\saves\more_weapon_stats.txt`. They have no menu row: edit the file with the
game closed (leaving the mod options menu rewrites the file from memory, so an
edit made while the game is running is lost). The value must be a JSON boolean.

| Key | Row in the panel | Default | Shows |
| --- | --- | --- | --- |
| `ammo_pickup` | Ammo pickup | on | Rounds gained per pickup: the minimum and the maximum of the pickup range (maximum after ` \| `). |
| `equip_delay` | Equip delays | on | Time to equip and time to unequip (unequip after ` \| `). |
| `falloff` | Dmg. modifier | on | Damage multipliers near/far, or the optimal range in metres for shotguns. Blank on weapons whose tweak data has no falloff (`damage_falloff`/`damage_near`/`damage_far`) - in 248.2 that is every rifle, e.g. the Lion's Roar (`vhs`). The range chart follows the same data, so it is hidden for them too; v76 behaved identically. |
| `recoil_horiz` | Recoil L./R. | on | Horizontal recoil kick, left and right. |
| `recoil_vert` | Recoil U./D. | on | Vertical recoil kick, up and down. |
| `reload_full` | Reload | on | Full-magazine reload time. |
| `reload_partial` | Tact. reload | on | Tactical reload time; shell-by-shell weapons also show the per-shell time after ` \| `. |
| `spread` | Spread | on | Horizontal spread, standing and moving. |
| `spread_vert` | Spread vert. | **off** | Vertical spread, standing and moving. |

Notes:

- A key set to `false` hides that row; the panel closes the gap, so the rows
  below move up.
- A **missing** key counts as on — deleting `spread_vert` from the file turns the
  vertical spread row *on*. Keep the key with `false` to keep it hidden.
- Rows the mod cannot compute for a weapon (throwables, a locked slot, a saw
  with no spread) stay blank regardless of these switches.
- Melee rows (attack delay, cooldown, unequip delay, special type, special time)
  are outside `display` entirely — they always follow the weapon category.
- Henchman/NPC rows share the same filter: their **Spread** row is hidden by
  `display.spread` and their **Reload** row by `display.reload_full`. The other
  henchman rows (rate of fire, burst fire, aim delay, damage per hit chance) have
  no `display` key and are always shown.

Example:

```json
{
	"display": {
		"ammo_pickup": true,
		"equip_delay": true,
		"falloff": true,
		"recoil_horiz": true,
		"recoil_vert": true,
		"reload_full": true,
		"reload_partial": true,
		"spread": true,
		"spread_vert": false
	},
	"show_dlc_info": true,
	"last_used_difficulty": "overkill_290",
	"fill_breakpoints": true,
	"use_preview_to_switch_breakpoints": true,
	"clicks_per_second": 5,
	"enable_trigger_happy_for_first_bullet": true
}
```

## Breakpoint preview difficulty (`last_used_difficulty`)

*Internal, persisted; default `overkill_290` (Death Wish).*

Set by the risk-icon picker at the bottom of the breakpoint table and stored so
your last choice is restored next session. It selects **which difficulty the
breakpoint table is drawn for** — enemy health and headshot multipliers — and
nothing else. It no longer changes the difficulty the game is running, and
switching it does not alter your contract, your lobby or your next heist.

- Single-player: click the risk icons to preview any difficulty; clicking the
  icon that is already selected steps one rank down (kept from v76). The lowest
  icon has nothing below it, so that step stops at Normal — there is no way to
  preview a lower difficulty.
- Multiplayer / an active Crime Spree: the picker is read-only and follows the
  difficulty the game is actually running; the Crime Spree picker is hidden
  entirely, as in v76.

## Applying changes

Leaving the mod options menu saves the file. Changes to the menu rows take
effect the next time the Black Market weapon page is built (reopen the menu or
switch tabs); changes made by hand in `more_weapon_stats.txt` need a game
restart, because the file is read once when the mod loads.
