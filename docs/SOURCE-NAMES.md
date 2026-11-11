# Names for SavedVariables keys from addon source

The Inspector shows paths like
`AccountSettings_SV › Default › @SOLAEGIS › $AccountWide › allSettings › #10`. The question is
whether MacMinion can say what `allSettings[10]` is by reading the addon's Lua in AddOns. It
reads the source once with the SavedVariables (`SVSourceNames`, in MacMinionKit) and never runs it.

## What the source can tell us, and how reliably

Survey of the 90 installed addons on 2026-10-30 (`SOURCE_NAMES_ADDONS=<AddOns> swift test --filter surveyInstalledAddons`):
50 addons have LibAddonMenu panels, with 2,677 `getFunc`s. 2,041 of them (76%) are one-line returns
of a saved field. There are 9,267 `ZO_CreateStringId` calls. Reading every addon that saves took
about 2.7 s in all, off the main thread; files over 1.5 MB (data, not code) are skipped.

| Source | Example | Accuracy | Shown as |
|---|---|---|---|
| Settings panel (LibAddonMenu) | `name = GetString(SI_X)`, `getFunc = function() return sv.showMap end` | High. The control reads exactly this key, and `name` is the label the player sees. `SI_*` strings resolve through the addon's own `ZO_CreateStringId` calls. | The name, with the tooltip under it. |
| Same, matched by key name alone | `return sv.log` with no parent in the chain | Good for distinctive keys. A short key (under 4 letters) may belong to another table. | A guess: `Log?` and "guess". |
| Comment beside a default | `autoLoot = false, -- Loot everything when you open a body` | Medium. Comments are matched by key name anywhere in the source, and many describe locals, not saved keys. We keep only prose of 3+ words with no code characters. | A guess, as a description only. |
| Addon constants as keys | `MODE_SLOW = 2` … `sv.counts[MODE_SLOW]` | Medium. The number is right, but the table is matched by its field name. | A guess: `MODE_SLOW?`. |
| Game constants as keys | `for _,x in pairs(AllSettingSystemType) do Default.allSettings[x] = {} end` | We know which family the keys come from, but not the numbers. | A note on the table: "Keyed by SETTING_TYPE_* values …". |

## What static analysis can't do

- **Game constants.** `SETTING_TYPE_CAMERA`, `CAMERA_SETTING_DISTANCE`, `CHAT_CATEGORY_*` and the rest are numbers
  the game's C++ client sets when it runs. They aren't in any Lua file on disk: grep finds no
  `SETTING_TYPE_X = n` among the installed addons. That's why `allSettings[10]` can be called "a
  SETTING_TYPE value" but not "Camera". The game's own `SI_*` strings (`SI_INTERFACE_OPTIONS_…`) are also
  compiled into the client, so only strings an addon defines itself can be resolved.
- **Computed keys.** `sv[GetUnitName("player")]`, `sv.list[#sv.list + 1]`, and getters with logic in them
  (`getFunc = function() return sv.x and 1 or 0 end`) aren't followed.
- **Positions in lists.** `{ x, y, "name" }` saved by position has no names in the source unless a
  comment says so.
- **Which table a bare key belongs to.** A chain like `Addon.sv.window.x` is matched to the saved key
  `x` under a table `window`. The root (`Addon.sv`) can't be tied to a ZO_SavedVars level, and the
  same key name in two tables can't be told apart. These are marked as guesses.

## AI for the rest

Keys the rules can't name (getters with logic, keys only a `setFunc` or the addon's code uses) can be
named by the AI set in Settings: **Inspector › Name Keys with AI** (Option-Command-N), or the sparkles
button beside Settings/Tree. It works one table at a time, on demand (`SVAINaming`).

- **What's sent:** the addon's name, the table's path, the key names, and up to 6 lines of the addon's Lua
  that use each key. Saved values are never sent, so no account, character, or guild names leave the Mac.
  Keys the source never mentions aren't sent, because a model could only guess from the name.
- **How it's shown:** always as a guess: "Name?" with "AI guess" under it. A name from the source
  always wins over one from AI.
- **Kept:** in `ai-key-names.json` in the app's store, per addon folder and version. A new version
  of the addon asks again.
- **Not asked:** game constants. A model's memory of `SETTING_TYPE_*` numbers isn't reliable.

## How this could be finished

The ESO Mac Minion addon (`~/git/solaegis/eso-mac-minion`) runs in the game, so it can
read the constants. A later version could save `SETTING_TYPE_*`, the per-system setting IDs, and the
English text of the `SI_*` strings an addon references, for example in a `constants` table. MacMinion
would then name `allSettings[10]` exactly. This doesn't depend on the companion today: the names
above work without it.

## In the app

- Settings view: the key's name from the panel replaces the made-up label, with the key and the tooltip
  in small text under it. Guesses end in "?" and say "guess"; hover says where the name came from.
- Tree: the name appears beside the key, in secondary text.
- Path bar: `byType (Show material cost)`-style titles when the source names a key.
- A table keyed by game constants shows a note at the top saying so.
