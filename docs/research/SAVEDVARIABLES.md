# SavedVariables, for the inspector

Checked against a real folder on this Mac (2026-10-29, 91 files, 74 MB). Stories S-035 to S-041.

## Format

The game writes each addon's variables (named by `## SavedVariables:`) to `SavedVariables/<addon name>.lua` when it quits or reloads the UI. A file holds one or more `Name = { ... }` assignments (AUI has 9). Inside:

- Keys are `["string"]` or `[number]`; values are strings, numbers, `true`, `false`, or tables. No functions, no long strings, no exponents in this folder, though the parser accepts them.
- Escapes seen: `\"`, `\\`, `\n`, `\r`, `\t`.
- Nesting goes 13 levels deep. Four spaces per level.

Addons that use ZO_SavedVars store under a fixed path, which the inspector labels:

```
Var
  ["NA Megaserver" | "EU Megaserver" | "Default"]   profile: often GetWorldName(); "Default" = no profile given
    ["@SOLAEGIS"]                                     account
      ["8796093036412335"]                            character ID (older files: "Name^Mx")
      ["$AccountWide"]                                shared by every character
        ["version"] = 1                               ZO_SavedVars version
        ["$LastCharacterName"] = "Masisi"
```

## IDs seen

| Kind | How it looks | Count | Name from |
|---|---|---|---|
| Character | 16-digit string key, `8796093036412335` | 33 characters | `ZO_Ingame.lua` and addon tables mapping ID to name |
| Account | `@SOLAEGIS`, `@vavasour` (yours); `@QueenMisi` (guild sales) | — | The key itself |
| Item | `\|H1:item:96175:4:22:0:…\|h\|h` | 123,621 links | LibSets (set items), UESP |
| Guild | `["guildId"] = 127263` | — | Guild tables in addons (LibGuildStore, MasterMerchant), UESP has none |
| Zone, map | `["zoneId"]`, `["mapId"]` | 431, 217 | LibZone `LibZone_Data.lua` |
| Achievement | `["achievementId"]` | 16 | UESP |
| Numeric keys | `[123456] = …` | 33,484 tables | Depends on the addon |

## Local name sources (installed addons, read as text)

- **LibSets** (2.6 MB, `Data/`): set IDs, names, and the item IDs in each set.
- **LibZone** (540 KB): zone IDs to names in every language.
- **LibQuestData** (4.2 MB): quest IDs to names and givers.
- **LibCharacterKnowledge** (260 KB): recipes, motifs, and furnishing plans.
- **TamrielTradeCentre** `ItemLookUpTable_EN.lua`: item names keyed by TTC's own IDs, not the game's, so it names items only by matching text.

## Online

UESP (`esoitem.uesp.net`, `en.uesp.net`) answers item, set, quest, and achievement IDs. Opt-in in Settings, cached on this Mac.
