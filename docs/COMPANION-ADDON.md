# ESO Mac Minion: an in-game addon for what files can't tell

MacMinion reads the game folder from outside. Some answers exist only inside the running game: which characters still exist, which addons actually loaded, which ones throw errors, how the game performs, and what an item or quest ID is called. **ESO Mac Minion** (`EsoMacMinion`, repo `solaegis/eso-mac-minion`) is a small ESO addon that writes those answers to its own SavedVariables file, which MacMinion already parses (S-035), so the Inspector, Problems, and Space can use them. Stories: S-042 to S-047.

## Constraints that shape everything

- **ESO's sandbox has no files, no network, and no `os`.** The only way out is SavedVariables, which the game writes when you log out, quit, or `/reloadui`. So everything here is a snapshot as of the last save, and MacMinion shows its age ("as of logout, 2 hours ago").
- **The game rewrites the file when it saves.** MacMinion writes to it only while ESO is closed (it already checks), and only to the `requests` part (see Name lookups).
- **Load and save cost is paid by the player.** The companion has a size budget (under 300 KB in normal use), caps every list, does its work on events rather than polling, and does nothing in combat.
- **Nothing about other players beyond what the game shows you,** no chat, and nothing leaves the Mac.
- **No overlap with addons that already do the job well:** builds and skills (CharacterMarkdown, ESO-Database Export, SuperStar), prices (TTC, MasterMerchant), and collections (CharacterKnowledge). The companion records facts about the game and its addons, not gameplay data.

## Shape

One addon, `EsoMacMinion`, at `~/git/solaegis/eso-mac-minion`. Optional: LibAddonMenu-2.0 (settings) and LibDebugLogger. Built from `eso-addon-template` with its Taskfile, luacheck, and StyLua.

```
## Title: ESO Mac Minion
## APIVersion: 101051 101050
## SavedVariables: EsoMacMinion_Data
## OptionalDependsOn: LibAddonMenu-2.0 LibDebugLogger
```

The file uses `ZO_SavedVars:NewAccountWide("EsoMacMinion_Data", 1, nil, defaults, GetWorldName())`, so it lands under the server and account levels MacMinion already labels. `GetWorldName()` is the **profile** (first table level), not the namespace. The game writes that table to `SavedVariables/EsoMacMinion.lua` (the addon folder name).

```lua
EsoMacMinion_Data =
{
    ["NA Megaserver"] = { ["@SOLAEGIS"] = { ["$AccountWide"] =
    {
        ["version"] = 1,
        ["schema"] = 1,                -- bumped when a section changes shape
        ["written"] = 1793288692,      -- GetTimeStamp() at the last save
        ["env"]        = { ... },      -- 1. the game and client
        ["characters"] = { ... },      -- 2. the roster
        ["addons"]     = { ... },      -- 3. what loaded, and how
        ["errors"]     = { ... },      -- 4. Lua errors, by addon
        ["perf"]       = { ... },      -- 5. frame rate, latency, memory, load times
        ["guilds"]     = { ... },      -- 6. guild IDs and names
        ["lookups"]    = { ["requests"] = { ... }, ["answers"] = { ... } },  -- 7. names for IDs
        ["account"]    = { ... },      -- 8. optional: currencies and space
        ["layouts"]    = { ["sv"] = { ... }, ["lam"] = { ... } },  -- 9. SV + LAM layouts
    } } },
}
```

## What it records

Each section lists the ESO API calls it relies on. **Verify each in the client before relying on it:** names and return orders change between game updates, and the mock harness stubs them loosely.

### 1. Environment (`env`), refreshed at every login

| Field | From | MacMinion uses it for |
|---|---|---|
| `apiVersion` | `GetAPIVersion()` | Flag addons whose `## APIVersion` is behind, the way the game does |
| `gameVersion` | `GetESOVersionString()` | Match ESOUI's "compatible with" field exactly |
| `server`, `language` | `GetWorldName()`, `GetCVar("language.2")` | Show which server the snapshot is from |
| `companionVersion` | the manifest | Offer an update when MacMinion ships a newer one |

### 2. Characters (`characters`), refreshed at every login

The definitive roster for this account and server, keyed by character ID (as a string, like the game's own files):

```lua
["8796093036412335"] = { name = "Masisi", class = 3, race = 9, alliance = 1, level = 50,
                         champion = 2410, zoneId = 3, lastPlayed = 1793288692 },
```

From `GetNumCharacters()` and `GetCharacterInfo(i)`; `lastPlayed` and champion points only for the character logged in (`GetCurrentCharacterId()`, `GetPlayerChampionPointsEarned()`), kept from earlier sessions for the rest.

Each row also keeps `names = { ["Masisi"] = <first seen>, … }`: every name the ID has had, so a rename shows as two keys (`CompanionCharacter.previousNames`).

**Unlocks:** "Unknown character" becomes certain. A character ID in other files that isn't on the roster for its server is a **deleted character**, so Space can say "Data for 3 deleted characters: 1.2 MB" and, when trimming arrives, remove it safely. Character rows get class, level, and last played.

### 3. Addons (`addons`), at every login

What the game actually did with each addon, which MacMinion can't see from files:

```lua
["pChat"] = { title = "pChat", version = "10.0.5", enabled = true, state = "loaded",
              outOfDate = false, isLibrary = false, missing = { },        -- unmet dependencies
              loadOrder = 41, loadMs = 18 },
```

From `GetAddOnManager()`: `GetNumAddOns()`, `GetAddOnInfo(i)` (name, title, author, enabled, state, out of date, library), `GetAddOnVersion(i)`, and `GetAddOnDependencyInfo(i, j)` for missing dependencies. `loadOrder` and `loadMs` come from timing `EVENT_ADD_ON_LOADED`: the companion registers as early as it can and records `GetGameTimeMilliseconds()` at each event, so `loadMs` is the time since the previous addon finished. That's an estimate (the first addons before the companion are lumped together), and MacMinion says so.

Rows keep only what the running game knows, and leave out defaults. Title, versions, and the library flag are in the manifest, which MacMinion reads itself. An absent `enabled` means on, an absent `state` means loaded, and `rootPath` (`GetAddOnRootDirectoryPath`) is kept only when it isn't the usual `user:/AddOns/<name>/`: that's how a duplicate name shows which copy loaded (the game lists only that one). The table is rebuilt every login and kept only in the block written last.

`enabledBy[characterId] = { at, disabled = { … }, notLoaded = { … } }` records, per character, the addons that character turned off and the enabled ones that didn't load. `GetAddOnInfo`'s enabled flag is the current character's choice, so each login fills only that character's row. This is the Character↔Addon edge for the graph (docs/research/sv-graph-model-findings.md), without reading `AddOnSettings.txt`.

**Unlocks:** Problems gains "Didn't load: missing LibX", "Out of date for this game version", and "Slow to load: 1.4 s". Installed shows which addons are on for the character you last played. Overview gets "Login cost: 6.2 s across 94 addons".

### 4. Lua errors (`errors`), as they happen

```lua
[1] = { addon = "WizardsWardrobe", at = 1793288692, count = 12, character = "8796093036412335",
        message = "user:/AddOns/WizardsWardrobe/ui.lua:212: attempt to index a nil value" },
```

From `EVENT_LUA_ERROR`. The addon is taken from the `user:/AddOns/<name>/` path in the message. Repeats of the same message add to `count` instead of a new row. At most 50 rows, newest kept; messages cut at 500 characters.

**Unlocks:** Problems gains "WizardsWardrobe threw 12 errors last session", with the message and a link to the addon's ESOUI comments, and the error count shows on its Installed row. This is the most useful thing a player can't easily see today.

### 5. Performance (`perf`), sampled every 60 seconds out of combat

```lua
["samples"] = { [1] = { at = 1793288692, fps = 92, ms = 61, luaKB = 412000, zoneId = 3, inCombat = false } },
["loads"]   = { [1] = { at = 1793288692, seconds = 14.2, zoneId = 3 } },
```

`GetFramerate()`, `GetLatency()`, `collectgarbage("count")`, and load-screen time from `EVENT_PLAYER_DEACTIVATED` to `EVENT_PLAYER_ACTIVATED`. Ring buffers: the last 240 samples (4 hours of play) and the last 50 loads.

**Unlocks:** the graphics suggestions in S-032 can check themselves ("since the background frame limit went on, idle frame rate is 30 and memory is steady"), and Overview can chart frame rate, memory, and load times across sessions. Lua memory over time also shows which addons' data keeps growing.

### 6. Guilds (`guilds`), at every login

```lua
[127263] = { name = "Bandits Clan", members = 487, rank = "Officer", server = "NA Megaserver" },
```

From `GetNumGuilds()`, `GetGuildId(i)`, `GetGuildName(id)`, `GetNumGuildMembers(id)`. **Unlocks:** every guild ID in every file gets a name, not only the ones LibGuildStore happened to see.

### 7. Name lookups (`lookups`): MacMinion asks, the game answers

This replaces the UESP lookups that UESP's bot check blocks. While ESO is closed, MacMinion adds the IDs it can't name to `requests`:

```lua
["requests"] = { ["item"] = { 96175, 119682 }, ["quest"] = { 5531 }, ["achievement"] = { 1000 },
                 ["collectible"] = { 5034 }, ["zone"] = { 1318 }, ["set"] = { 576 } },
```

At login the companion answers them, a few hundred per frame so login doesn't stall, and moves them to `answers`:

```lua
["answers"] = { ["item:96175"] = { name = "Ring of the Wild Hunt", quality = 5, set = 576, icon = "/esoui/art/icons/..." },
                ["quest:5531"] = { name = "The Harborage" } },
```

From `GetItemLinkName()`, `GetItemLinkQuality()`, `GetItemLinkSetInfo()` (built from a minimal link for the item ID), `GetCompletedQuestInfo()`, `GetAchievementInfo()`, `GetCollectibleName()`, `GetZoneNameById()`, and `GetItemSetName()` where available. Names are in the client's language. At most 2,000 answers are kept; MacMinion stores its own cache too, so answers survive the companion trimming them.

**Unlocks:** item names, quality colors, and icons everywhere in the Inspector, with no network at all.

### 8. Account snapshot (`account`), optional, off by default

Gold, Alliance Points, Tel Var, and Writ Vouchers per character, and bank and bag space used. `GetCurrentMoney()`, `GetCurrencyAmount()`, `GetNumBagUsedSlots()`, `GetBagUseableSize()`. For an Overview card; it's a setting because some players don't want it recorded.

### 9. Layouts (`layouts`), the globals MacMinion asks for, plus constructor calls when captured

What files cannot tell: which addon called which `ZO_SavedVars` constructor, and which LibAddonMenu controls exist (types, names, `reference` only).

```lua
["sv"] = { ["pChat_Settings"] = { addon = "pChat", ctor = "NewAccountWide", source = "wrap+scan",
                                  profile = "NA Megaserver", keyType = "account",
                                  keys = { "NA Megaserver" }, pathCount = 42, sig = 123456 } },
["lam"] = { ["pChatPanel"] = { addon = "pChat", name = "pChat",
                               controls = { { type = "checkbox", name = "Enable", reference = "pChatEnable" } } } },
```

**Requests.** While ESO is closed, MacMinion writes `lookups.requests.svGlobals` into every `$AccountWide` table of the companion's file: every global the installed manifests declare (`CompanionRequests`, on each Game Folder read). Only that entry is rewritten; other request keys are kept. After the next login the addon looks up each name with `rawget(_G, name)`, 10 per frame and out of combat, and keeps only `layouts.scanned = { at, requested, found, missing }`: proof the request reached the game. The tables' keys aren't copied; MacMinion reads them from the files. `_G` itself is never walked: that aborted the CrossOver client during load.

**Constructor calls.** The `ZO_SavedVars` wrap installs after the first `EVENT_PLAYER_ACTIVATED`, which is after every addon has created its SavedVariables, so by default it sees only late calls. `/emm early on` (experimental, off by default) wraps in the addon's own `EVENT_ADD_ON_LOADED` and queues calls in memory, flushed after activation, and starts the load observer so `loadOrder` / `loadMs` fill. It's the test of whether load-time wrapping is safe on CrossOver; if the client stops while loading, set `experimental.earlyCapture = false` in the file while ESO is closed. It never indexes the returned proxy. LAM is wrapped on `RegisterAddonPanel` / `RegisterOptionControls`; `getFunc` / `setFunc` are never called.

**Unlocks:** Settings Matrix and the Inspector can label keys from live LAM names and tell a profile (`Default` vs `NA Megaserver`) from a namespace.

## Settings (LibAddonMenu if present, slash command always)

`/emm` shows what was recorded and when. Toggles: layouts, errors, performance samples, account snapshot. A "Clear recorded data" button. Nothing is sent anywhere, and the settings panel says so.

## How MacMinion ships and reads it

- **Bundled with MacMinion.** Settings > General > "Install ESO Mac Minion" copies `EsoMacMinion` into AddOns. Recommended for You lists it when the folder is missing. It can also go on ESOUI later. Until then, install from the app or from `~/git/solaegis/eso-mac-minion` with `task install:live`.
- **File names.** The game writes `SavedVariables/EsoMacMinion.lua`. MacMinion also reads `EsoMacMinion_Data.lua`. The variable inside is always `EsoMacMinion_Data`.
- **A new name source:** answers and the roster rank above LibSets, LibZone, and LibQuestData; UESP becomes a fallback link only.
- **Freshness everywhere:** every value that comes from the companion says when it was recorded. If the snapshot is older than the newest file in SavedVariables, MacMinion says "log in once to refresh".
- **Schema check:** an unknown `schema` makes MacMinion skip the sections it can't read and say which.

## Test plan

- Lua: unit tests for each collector against the template's mock harness (roster, addon states, error attribution and de-duplication, ring buffers, lookup batching and caps).
- Swift: fixtures of `EsoMacMinion_Data` at schema 1, and one from the future, read by the Kit; self-test with a seeded companion file.
- In game: a checklist per section (`/emm` shows each one populated), plus `/reloadui` and logout timings with and without the companion, to hold the size and time budget.
