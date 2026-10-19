# HealBot 3.3.5a – Remastered for Grimfall

HealBot 3.3.5.4 for the WoW 3.3.5a (WotLK) client, made compatible with the **Grimfall**
private server: the **Conquest of Azeroth (CoA)** realm with its custom classes and
backported races, and the **classless** realm.

Original addon by **StrifeCUK**.
Grimfall & Classless compatible by **Lidless**.

---

## Why this version?

The original HealBot only knows the 10 WotLK classes and races. On Grimfall it breaks:

- A new CoA character (e.g. a Goblin Cultist) gets a Lua error on login:
  `HealBot.lua:5868: bad argument #1 to 'pairs' (table expected, got nil)`.
- Custom classes have no HoT, dispel, buff or resurrection data, so HealBot can't use their spells.
- Reused class tokens (CoA *Hero* = `DRUID`, *Templar* = `MONK`) and similar names
  (*Witch Doctor* / *Witch Hunter*) would share or mix up settings.

## What's changed

**No more errors for unknown classes and races**
- Any class or race HealBot doesn't know gets safe defaults instead of a crash.
- Custom classes use the client's own class colors (`RAID_CLASS_COLORS`).
- Goblin and other backported races are handled.

**Separate settings per class and realm**
- The original 10 classes keep their old settings keys, so nothing changes for them.
- Every other class gets its own key: `TOKEN-ClassName@Realm`
  (e.g. `CULTIST-Cultist@Sargeras`, `DRUID-Hero@<realm>`).
  CoA and classless characters, and look-alike classes, never mix.
- Existing settings are carried over the first time (e.g. a Hero starts from your old Druid settings).

**Custom Spells – HealBot learns your spells**
- For custom classes HealBot reads your spellbook tooltips (English client) and detects
  HoTs/absorb shields, friendly dispels, long buffs and resurrection spells.
- Everything can be checked and changed in-game in the **Custom Spells** window – no file editing.

## Installation

1. Download this repository (**Code → Download ZIP**).
2. Copy the `HealBot` folder into
   `World of Warcraft\Interface\AddOns\` (replace the old HealBot folder).
3. **Restart the WoW client completely.** A `/reload` does not load new addon files.

Your existing HealBot settings are kept.

## Custom Spells window

Open it with the **Custom Spells** button next to the *Other* tab in HealBot Options,
or type `/hb cs` (this also prints the current result to chat).
Click **Help** in the window for the full guide.

For each spell in your spellbook choose **Use as** (left-click: next, right-click: previous):

| Setting | Meaning |
|---|---|
| Auto | Detected from the spell tooltip, e.g. `Auto: HoT`. `Auto: -` = not used. |
| HoT (mine) | Show an icon on the bars while **your** cast is active. |
| HoT (all) | Show an icon for anyone's cast of this spell. |
| Dispel | Removes debuffs from friends. Tick the types: **M**agic, **C**urse, **P**oison, **D**isease. |
| Buff | Long buff; listed in Options → Buffs so HealBot can warn when it's missing. |
| Resurrect | Used by Smart Cast on dead players. |
| Ignore | HealBot never uses this spell. |

After setting a spell:
- **Dispels:** pick the spell in Options → Cure.
- **Buffs:** pick the spell in Options → Buffs.
- **Healing on click:** type the spell name in Options → Spells (any spellbook spell or macro works).

Changes apply immediately. **Rescan** re-reads the spellbook after you learn new spells;
**Reset all to Auto** clears your settings for the current class.
The original 10 classes are not auto-detected, but manual settings work for them too.

The same guide is in `HealBot/Docs/CustomSpells.txt`.

## Slash commands

| Command | Action |
|---|---|
| `/hb` | Toggle the HealBot panel |
| `/hb o` | Options |
| `/hb cs` | Custom Spells window |
| `/hb h` | Help (all commands) |

## Feedback

Found a bug or a spell that's detected wrong? Please open an
[issue](../../issues) and include the spell's tooltip text and the output of `/hb cs`.

## Credits

- **StrifeCUK** – original HealBot author
- **Lidless** – Grimfall & Classless compatibility, Custom Spells
