# ESO Addon Lua API Verification for a Passive SavedVariables/LAM Recorder (API 101050/101051, Oct 2026)

Most of what the companion addon needs exists and can be used as planned. ZO_SavedVars is a plain global table whose public methods your addon can wrap. LibAddonMenu-2.0 is a global library that publishes callbacks through CALLBACK_MANAGER. You can read SavedVariables tables with pairs/next/rawget. Two things do not exist: a guaranteed "about to write SavedVariables" hook, and `debug.getinfo` (the `debug` library only provides `traceback`).

## TL;DR
- **Wrapping ZO_SavedVars works if you get there first.** The four constructors (`New`, `NewCharacterIdSettings`, `NewCharacterNameSettings`, `NewAccountWide`) are methods on the global `ZO_SavedVars` table, so you can wrap them. They all call one file-local `GetNewSavedVars`, which you cannot reach. You only see calls made after your file has run. The layout is always `SV[profile][displayName][characterKey or "$AccountWide"][namespace]`, where profile defaults to `"Default"`. `NewAccountWideSettings` does not exist.
- **No hook fires right before the SavedVariables write.** The game writes SavedVariables to disk at /reloadui, logout, quit and loading screens, plus occasional small-file autosaves. A crash means no write. Keep your in-memory record complete at all times; don't plan to finalize it at logout.
- **Load order is only partly predictable, and API docs disagree.** Load order is guaranteed only along DependsOn/OptionalDependsOn chains, so you will miss SavedVariables created by addons that load before you, unless you scan `_G` for those tables later. The API version labels in the request are also off: 101050/101051 are Update 50/51 (12.0/12.1), not Update 47/48. Re-check the signatures marked "medium" against the live `ESOUIDocumentation.txt`.

## Version context
- **What the sources say about the current version:**
  - The ESOUI Wiki main page lists live as 101050 and PTS as 101051.\[1\]
  - The wiki's APIVersion page dates 101051 (ESO 12.1.0) as "1st hit on PTS" on August 3rd, 2026, with "live September 28th, 2026".\[2\]
  - The esoui/esoui GitHub mirror showed two different README states. One fetch said "Last update: 12.0.8 (API 101050) on 10 Aug 2026". The current README says "Last update: 12.1.6 (API 101051) on 19 Oct 2026". ESO Decoded separately says "the live game runs API 101051 (Update 51, live 2026-09-28)". So 101051 is live. Keep 101050 in your manifest as well (`## APIVersion: 101050 101051`).
- **Version-to-update mapping:** 101047 was Update 47 and 101048 was Update 48 (11.2, live October 27th, 2025).\[2\] These are older versions.
- **Signature sources:** ZO_SavedVars details below come from the UESP v101050 source mirror. Some AddOnManager and lookup-function signatures come from an API 101046 documentation mirror and were not re-checked against 101050/101051; they are marked medium confidence.

---

## 1. ZO_SavedVars

| Function / behavior | Verified signature / returns | Notes / restrictions | Confidence | Source |
|---|---|---|---|---|
| `ZO_SavedVars:New` | `(savedVariableTable, version, namespace, defaults, profile, displayName, characterName, characterId, characterKeyType)` → SV interface object (a proxy table with a metatable)\[3\] | Defaults: `displayName = GetDisplayName()`, `characterName = GetUnitName("player")`, `characterId = GetCurrentCharacterId()`, `characterKeyType = ZO_SAVED_VARS_CHARACTER_NAME_KEY`. Keyed by character name, so it is not rename-safe; the wiki calls it obsolete.\[3\]\[4\] | High | https://esodata.uesp.net/current/src/libraries/utility/zo_savedvars.lua.html |
| `:NewCharacterNameSettings` | `(savedVariableTable, version, namespace, defaults, profile)` | Passes `GetDisplayName(), GetUnitName("player"), GetCurrentCharacterId(), ZO_SAVED_VARS_CHARACTER_NAME_KEY`\[3\] | High | same |
| `:NewCharacterIdSettings` | `(savedVariableTable, version, namespace, defaults, profile)` | Same as above but with `ZO_SAVED_VARS_CHARACTER_ID_KEY`. Recommended for rename safety.\[3\]\[5\] | High | same |
| `:NewAccountWide` | `(savedVariableTable, version, namespace, defaults, profile, displayName)` | `displayName` defaults to `GetDisplayName()`. Passing a fixed string such as "AllAccountsTheSame" shares one table across accounts.\[6\] | High | same; https://www.esoui.com/forums/showthread.php?t=10469 |
| `:NewAccountWideSettings` | **Does not exist** | Not in the v101050 source. Only the four constructors above are defined. | High (absence) | same |
| `savedVariableTable` | String name of the global from `## SavedVariables:` (a table is also accepted) | If `_G[name] == nil`, it creates `_G[name] = {}`\[3\] | High | same |
| `version` | number | "If the saved data is a lower version it is destroyed and replaced with the defaults". A `version` key is written into each leaf table.\[3\] | High | same |
| `namespace` | optional string | If omitted and the 3rd argument is a table, the arguments shift: `profile = defaults; defaults = namespace; namespace = nil`.\[3\] With no namespace, data sits directly under the character/`$AccountWide` key. Some community posts say namespace defaults to "Default"; the source shows that default belongs to **profile**.\[7\] | High | same |
| `defaults` | table; supports wildcard key `'*'`\[3\] | Applied through metatables (`__index`). Default values are not stored as real keys until they are written. | High | same |
| `profile` | optional string, **default `"Default"`** | Confirmed: `profile = profile or "Default"`.\[3\] It is the **first** table level: `SV[profile][displayName][key][namespace]`. Many addons pass `GetWorldName()` here, so their first level is "NA Megaserver" and similar instead of "Default".\[8\]\[9\] | High | same; https://www.esoui.com/forums/showthread.php?p=53762 |
| `"$AccountWide"` | Literal key used when `characterName == nil` (the account-wide path)\[3\] | Sits at the third level, under displayName | High | same |
| `"$LastCharacterName"` | Written as `SV[profile][displayName][characterId]["$LastCharacterName"] = characterName`\[3\] | Written **only** when `characterKeyType == ZO_SAVED_VARS_CHARACTER_ID_KEY`. When a table already exists under the other key type (name vs ID), it is copied over. Old name-keyed tables are also migrated after a rename.\[3\] | High | same |
| Key-type constants | `ZO_SAVED_VARS_CHARACTER_NAME_KEY = 1`, `ZO_SAVED_VARS_CHARACTER_ID_KEY = 2` (globals)\[3\] | Present since at least API 100020\[10\] | High | https://esodata.uesp.net/current/src/libraries/utility/zo_savedvars.lua.html; https://esoapi.uesp.net/100020/src/libraries/utility/zo_savedvars.lua.html |
| Creation timing | "SavedVars must be created in the EVENT_ADD_ON_LOADED function event in order for the settings file to properly save."\[3\] | That is the window where calls happen, and your wrapper must already be installed by then | High | source comment, same URL |
| Is `ZO_SavedVars` wrappable? | `ZO_SavedVars = {}` is a plain global; the constructors are its methods. `GetNewSavedVars`, `CreateExposedInterface` and the helper functions are file-`local`.\[3\] | You can replace `ZO_SavedVars.NewAccountWide` and the other constructors with pass-through wrappers. You cannot intercept the internal helpers. A caller that cached the method in a local before your wrap, or that writes `_G[svName]` directly, bypasses you. | High (structure); Medium (practical coverage) | same |
| Is wrapping allowed/safe? | No ZOS rule against it. The constructors call no protected functions, so wrapping them causes no taint/"insecure" errors in practice. | Community guidance: "hook and overwrite responsibly, and always consider your addon is not the only one".\[11\] Wrapping/hooking has to keep the return values identical. | Medium | https://wiki.esoui.com/How_to_trigger_things_with_ESO's_default_code |

## 2. When SavedVariables are written to disk

| Behavior | Verified detail | Notes | Confidence | Source |
|---|---|---|---|---|
| Write triggers | "Writing to this file only happens as you logout/reload the UI/a loading screen appears (at zone change e.g.)." Quit and clean idle kicks also save.\[12\]\[13\] | A client crash loses any changes not yet written\[14\] | High | https://wiki.esoui.com/Storing_data_and_accessing_files; https://cdn.esoui.com/forums/showthread.php?t=4651 |
| Small-data autosave | ZOS_DanBatson on the ESOUI forum: "While not in a load screen, one addon's saved vars are saved every 3 minutes. Your addon can request to be bumped up the priority queue for the next save interval using RequestAddOnSavedVariablesPrioritySave(\"yourAddonName\") once every 15 minutes." A 2019 ESOUI thread adds that this happens only "as long as the resulting file is not bigger than 50kB and the write can be done within 4ms." | The manifest directive `## DisableSavedVariablesAutoSaving: 1` turns autosave off. The ESOUI Wiki quotes a ZOS hint that calling `RequestAddOnSavedVariablesPrioritySave` "will do one save even if it is disabled in the manifest". Autosaved files are written minified. | Medium | https://wiki.esoui.com/Storing_data_and_accessing_files; https://www.esoui.com/forums/showthread.php?p=40253; https://www.esoui.com/forums/showthread.php?t=8732 |
| Per-string limit | A single string value can be at most 1999 bytes (plus the terminating NUL). Longer strings are saved as `nil` with the comment `-- invalid string value (was your string larger than 2000 characters?)`\[12\] | Split long strings into chunks\[12\] | High | https://wiki.esoui.com/Storing_data_and_accessing_files |
| File-size problems | Big files slow down every login, /reloadui and loading screen. The wiki advises cleaning up files over 20 MB if you see very long loads or disconnects.\[12\] Older history: ZOS raised serialization capacity from 2^24 to 2^32 characters, and confirmed a Lua VM hard limit on string literals per file that can corrupt very large saves.\[15\] | A recorder that copies other addons' layouts must stay small. Store key paths and types, not values. | High (guidance); Medium (current limits) | same; https://www.esoui.com/forums/printthread.php?t=4933&page=2&pp=20 |

## 3. AddOnManager

| Function | Verified signature / returns | Notes | Confidence | Source |
|---|---|---|---|---|
| `GetAddOnManager()` | → AddOnManager object\[16\] | — | High | https://wiki.esoui.com/Controls |
| `:GetNumAddOns()` | → integer numAddOns\[17\] | — | High | same; https://wiki.esoui.com/IsAddonRunning |
| `:GetAddOnInfo(addOnIndex)` | → `name, title, author, description, enabled, state (AddOnLoadState), isOutOfDate, isLibrary`\[16\] | `name` is the folder/manifest name, which is the same string EVENT_ADD_ON_LOADED passes. Compare `state == ADDON_STATE_ENABLED` to check whether it loaded.\[18\] | High | https://wiki.esoui.com/Controls |
| `:GetAddOnVersion(addOnIndex)` | → integer version (from `## AddOnVersion:`)\[17\] | One 2021 report said it returns 0 for non-library addons; the thread was closed "[notabug]". Treat 0 as "unknown".\[19\] | Medium | https://www.esoui.com/forums/archive/index.php/t-9908.html |
| `:GetAddOnRootDirectoryPath(addOnIndex)` | → string directoryPath\[16\] | Exists. On console it looks like `user:/AddOnsManaged/<guid>/VotansMiniMap/`, which differs from the PC path.\[20\] On PC, one ESOUI forum user reported in 2020 getting "user:/Addons/xyz I get from GetAddOnRootDirectoryPath(index)". That is a single user report; ZOS has not documented the PC format. | High (exists); Medium (PC format, 2020 user report) | https://wiki.esoui.com/How_to_update_your_addon_for_console; https://www.esoui.com/forums/showthread.php?t=9218 |
| `:GetAddOnNumDependencies(i)` / `:GetAddOnDependencyInfo(i, depIndex)` | → integer; → `name, exists, active, minVersion, version, isLibrary` (from the API 101046 docs)\[17\] | Reportedly lists only `DependsOn` entries, **never** `OptionalDependsOn`. This comes from a third-party library wiki.\[21\]\[22\] | Medium | subagent check of the 101046 doc mirror (https://kawamonkey-eso.github.io/ESOUIDocumentation/); https://github.com/MPHONlC/LibAPH/wiki/DependencyManagement |
| `:GetLoadOutOfDateAddOns()` / `:SetLoadOutOfDateAddOns(bool)` | → bool | The setter is listed on the wiki; the getter's signature comes from the 101046 docs\[16\]\[17\] | Medium | https://wiki.esoui.com/Controls |
| Enabled state per character | Enabled state is stored per character, and the Add-Ons screen also offers an all-characters option (AddOnManager has `SetAddOnFilter`/`GetAddOnFilter`) | The UI behavior is well known, but I did not find a primary-source statement for it | Unconfirmed | — |
| Duplicate addon names | The game "always prefer[s] the one with the highest number" in `## AddOnVersion`. Without an AddOnVersion, "it will just pick the last file". When both `.addon` and `.txt` manifests exist on PC, "the one with the higher AddOnVersion will be used. If the AddOnVersion is the same for both… which one it uses is undefined."\[20\]\[23\]\[24\] | Manifests must have the same name as their folder. Subfolders are scanned, so libraries nested inside other addons count as duplicates.\[25\] | High | https://www.esoui.com/forums/showthread.php?t=7777; https://wiki.esoui.com/How_to_update_your_addon_for_console |
| Manifest metadata from Lua | You can't read arbitrary manifest tags (for example `## SavedVariables:`) from Lua\[26\] | Your addon cannot learn another addon's SavedVariables global name from the manifest. You have to observe the constructor calls or scan `_G`. | Medium (old thread, no newer API found) | https://www.esoui.com/forums/showthread.php?p=24366 |

## 4. Load order and timing

| Item | Verified behavior | Notes | Confidence | Source |
|---|---|---|---|---|
| EVENT_ADD_ON_LOADED order | ZOS code loads first. After that, order is guaranteed only for `DependsOn`/`OptionalDependsOn`: a dependency's files and its EVENT_ADD_ON_LOADED come before the addon that depends on it. Everything else is "undefined".\[27\]\[28\] | Two sources disagree on whether all files load before any event fires. The wiki's Addon Structure page says yes; an addon-author report says an addon misses events for addons that loaded before it.\[29\]\[30\] Assume the events interleave with file loading. | High (dependency rule); Medium (interleaving) | https://wiki.esoui.com/AddOn_Quick_Questions; https://wiki.esoui.com/Addon_Structure; https://www.esoui.com/downloads/info4926-2610.3.html |
| Observing other addons' loads | Register EVENT_ADD_ON_LOADED at file scope and **don't** unregister it. You receive the event for every addon processed after you.\[31\] | You can't force yourself to load early, short of other addons declaring an optional dependency on you.\[27\] Backfill the ones you missed by enumerating AddOnManager and scanning `_G` at EVENT_PLAYER_ACTIVATED. | High | https://wiki.esoui.com/EVENT_ADD_ON_LOADED |
| `RegisterForEvent(..., loadOnce)` | Optional 4th boolean `loadOnce`, "added with update47"\[32\] | Leave it off, because you need to see every load | Medium | https://wiki.esoui.com/Writing_your_first_addon |
| `GetGameTimeMilliseconds()` / `GetFrameTimeMilliseconds()` | Both exist and are widely used.\[33\] → integer milliseconds.\[33\] | Frame time is fixed for the whole frame, so use it for cheap timestamps within one frame. Neither is wall-clock time; use `GetTimeStamp()` for that. | High (exists); Medium (exact semantics) | https://esodecoded.com/dev/api |

## 5. Character identity

| Function | Verified signature / returns | Notes | Confidence | Source |
|---|---|---|---|---|
| `GetNumCharacters()` | → integer | An old (2016) report said it sometimes returned 1 after a /reloadui\[34\] | High | https://esoui.com/forums/showthread.php?p=45369 |
| `GetCharacterInfo(index)` | → `name, gender, level, classId, raceId, alliance, id (string), locationId`\[35\] | `championRank` was removed during the Update 2.5 cycle.\[34\] Works in-game but returns data stored at login ("the level and location will be of the character when you logged in").\[35\] Order is creation order, not the user-sorted order. One 2021 post showed 11 returns (`…, order, needsRename`), which is unexplained, so check the live doc.\[36\] | High (first 7); Medium (8th onward) | https://wiki.esoui.com/GetCharacterInfo; https://esoui.com/forums/showthread.php?p=28021; https://www.esoui.com/forums/showthread.php?t=9872 |
| `GetCurrentCharacterId()` | → string (a 64-bit ID as a decimal string)\[37\] | Same string ZO_SavedVars uses as the key. The wiki says character IDs are unique across servers.\[12\]\[37\] | High | https://esoui.com/forums/showthread.php?p=45369; https://wiki.esoui.com/Storing_data_and_accessing_files |
| `Id64ToString(id64)` | → string | Use it for other id64 values (e.g. item unique IDs). Character IDs already come back as strings. | Medium | subagent (wiki API index) |
| `GetUnitName("player")` / `GetRawUnitName` | → formatted name / raw name with gender control codes | ZO_SavedVars uses `GetUnitName("player")`\[3\] | High | zo_savedvars.lua (UESP) |
| `GetDisplayName()` | → "@AccountName" | Default `displayName` level in SavedVariables\[38\] | High | same |
| `GetWorldName()` | → `"NA Megaserver"`, `"EU Megaserver"`, `"PTS"` (PC)\[2\] | Console realms return different strings; see the wiki's "World names / Realms" page\[20\] | High | https://wiki.esoui.com/APIVersion |
| Rename event/function | No rename event found. Renames are handled after the fact through ZO_SavedVars' `$LastCharacterName` migration. | — | Unconfirmed (no event) | zo_savedvars.lua (UESP) |

## 6. Runtime introspection limits

| Item | Status | Notes | Confidence | Source |
|---|---|---|---|---|
| Lua flavor | Havok Script based on Lua 5.1, 64-bit since Update 18, with backports from 5.2/5.3\[39\]\[40\]\[41\] | io/file access removed\[12\] | High | https://wiki.esoui.com/Esolua |
| `debug.traceback` | **Available**; a custom `debug` table was added in Update 18 with `traceback()`\[40\] | — | High | same |
| `debug.getinfo` / `getlocal` / `getupvalue` | **Not available**: "the coroutine and debug module have also been removed"\[40\]\[42\] | You can't find out which addon a function or call came from by introspection. Use stack parsing on `debug.traceback()` instead (see pitfalls). | High | same; https://www.esoui.com/forums/showthread.php?t=2445 |
| `setmetatable`, `getmetatable`, `rawget`, `rawset`, `next`, `pairs`, `getfenv`/`setfenv`, `loadstring`, `pcall`/`xpcall` | **Available** in the core\[39\]\[41\] | `rawget` and `next` let you read SavedVariables without triggering ZO_SavedVars' default-filling `__index` | High | https://wiki.esoui.com/API |
| `collectgarbage("count")` | **Available**; ZOS's own `ZO_StartMemProfile` uses it\[43\] | — | High | https://esodata.uesp.net/current/src/libraries/globals/debugutils.lua.html |
| `HashString(text)` | **Exists** → number (undocumented, deterministic algorithm)\[39\]\[44\] | ZOS uses it for MOTD change checks and string caching\[44\]\[45\] | High | https://wiki.esoui.com/HashString; https://github.com/esoui/esoui/blob/master/esoui/libraries/globals/localization.lua |
| `zo_callLater(func, ms)` | Exists. UESP's v101046 function data lists `function zo_callLater(func, ms)` at `libraries/globals/globalapi.lua:274`. It registers a `"CallLaterFunction"..id` update through `EVENT_MANAGER:RegisterForUpdate` and returns the id. | The ESOUI Wiki says `zo_removeCallLater(id)` cancels it | High | UESP ESO Function Data v101046; ESOUI Wiki "Running LUA-Code asynchroneously" |
| Protected / private functions | Addon code is "insecure". Protected functions run only out of combat, via `CallSecureProtected("Name", ...)`. Private functions can't be called by addons at all.\[46\]\[47\] Use `IsProtectedFunction` / `IsPrivateFunction` to check.\[48\] | Hooking ZOS UI code can taint call chains that reach protected functions ("…from insecure code" errors).\[46\]\[47\] | High | https://www.esoui.com/forums/showthread.php?t=6806 |
| `ZO_PreHook(objTable, "fnName", hook)` / `ZO_PostHook` / `SecurePostHook` / `ZO_PreHookHandler` | All exist. Both forms work, with or without `objTable` (without it, `_G` is used). A PreHook that returns `true` suppresses the original function. `SecurePostHook` was added in Dragonhold (100029) to avoid taint.\[11\]\[49\]\[50\] | Mixing `ZO_PreHook` and `SecurePostHook` on the same inventory function caused insecure errors.\[49\] For non-UI library tables (ZO_SavedVars, LibAddonMenu2), a post-hook is the right tool. | High | https://wiki.esoui.com/How_to_run_your_code_before/after_functions_(PreHook/PostHook); https://www.esoui.com/forums/showpost.php?p=39445&postcount=6 |

## 7. LibAddonMenu-2.0

| Item | Verified detail | Notes | Confidence | Source |
|---|---|---|---|---|
| Access | Global `LibAddonMenu2` (since r28). Declare it with `## DependsOn: LibAddonMenu-2.0>=NN`.\[51\] | LibStub is no longer needed | High | https://www.esoui.com/downloads/fileinfo.php?s=a100f82fde8a2e8d72dffa315eea15e9&id=7 |
| `LAM:RegisterAddonPanel(panelName, panelData)` | → panel control; `panelData.type = "panel"`\[52\] | Use the returned panel to compare against in callbacks\[53\] | High | https://www.esoui.com/downloads/info7-LibAddonMenu.html |
| `LAM:RegisterOptionControls(panelName, optionsTable)` | Array of control tables | Controls are created lazily, when the panel is first shown\[52\] | High | same |
| Control fields | `type, name, tooltip, getFunc, setFunc, default, reference, warning, disabled, choices…`. `default` can be a function (since r20). Labels can be strings, string IDs or functions.\[54\] | Full per-type field list not re-checked; see the LAM GitHub docs | Medium | https://www.esoui.com/forums/showthread.php?t=6205 |
| Callbacks for third parties | `CALLBACK_MANAGER:RegisterCallback("LAM-PanelControlsCreated" / "LAM-PanelOpened" / "LAM-PanelClosed" / "LAM-RefreshPanel", fn(panel))`\[55\] | Any addon can listen. PanelControlsCreated "gets called right before a panel is shown for the first time" (r38).\[52\] There is **no** registration callback, so to see registrations you must wrap `RegisterAddonPanel` / `RegisterOptionControls` on the global table. | High | https://github.com/sirinsidiator/ESO-LibAddonMenu/blob/master/LibAddonMenu-2.0/development.lua; https://www.esoui.com/downloads/info7-LibAddonMenu.html |

## 8. Game constants and strings

| Item | Status | Notes | Confidence | Source |
|---|---|---|---|---|
| Enumerating `_G` | Works. Tools like GlobalDumper, Zgoo and merTorchbug dump every global.\[42\] | Constants such as `SI_*`, `SETTING_TYPE_*` and `CAMERA_SETTING_*` are plain global numbers, so a `pairs(_G)` loop with a prefix filter finds them. I did not check the individual names `SETTING_TYPE_*` / `CAMERA_SETTING_*` in this pass. | High (mechanism); Medium (specific names) | https://www.esoui.com/forums/showthread.php?t=2445 |
| `GetString(id)` / `GetString(prefix, enumValue)` | → localized string. `GetSetting`/`SetSetting` are heavily used.\[33\] | Enum strings use the second form, e.g. `GetString("SI_ITEMTYPE", itemType)`. Returns "" for unknown IDs. | Medium | https://esodecoded.com/dev/api |

## 9. Looking up entity names from IDs

| Function | Signature / returns | Notes | Confidence | Source |
|---|---|---|---|---|
| `GetItemLinkName(link)` | → string | Strip control codes with `zo_strformat("<<1>>", s)` | High | https://esodecoded.com/dev/api |
| `GetItemLinkQuality` | Replaced in the docs by `GetItemLinkFunctionalQuality(link)` → ItemQuality and `GetItemLinkDisplayQuality(link)` → ItemDisplayQuality\[17\] | It's unknown whether the old name still works as an alias. Use the new functions. | Medium | subagent check of the 101046 docs (kawamonkey mirror) |
| `GetItemLinkSetInfo(link, equipped)` | → `hasSet, setName, numBonuses, numNormalEquipped, maxEquipped, setId, numPerfectedEquipped`\[56\]\[57\] | `setId` is the 6th return and `numPerfectedEquipped` the 7th | Medium | LibSets page via subagent |
| `GetItemSetName(itemSetId)` | → string. Exists; there is also `GetItemSetInfo(setId)`.\[17\] | — | High | https://kawamonkey-eso.github.io/ESOUIDocumentation/ |
| `GetZoneNameById(zoneId)` | → string | — | High | same |
| `GetMapNameById(mapId)` | → string mapName\[17\] | — | Medium | subagent (101046 docs) |
| `GetCompletedQuestInfo(questId)` | → `name, questType` (**completed quests only**)\[17\] | Iterate with `GetNextCompletedQuestId(lastId)`\[58\] | High | same; https://www.esoui.com/forums/showthread.php?t=8000 |
| `GetQuestName(questId)` | → localized string for any quest ID (added in Update 30)\[59\] | Returns "" or internal dummy names (e.g. "TM01_OUTOFDATE") for unused IDs\[60\] | High | https://esoui.com/forums/showthread.php?p=34459; https://esoui.com/forums/showthread.php?p=52797 |
| `GetAchievementInfo(achievementId)` | → `name, description, points, icon, completed, date, time`\[17\]\[61\] | — | Medium | subagent (101046 docs) |
| `GetCollectibleName(collectibleId)` | → string | — | High | https://kawamonkey-eso.github.io/ESOUIDocumentation/ |
| `GetNumGuilds()` / `GetGuildId(index)` / `GetGuildName(guildId)` | → integer / guildId / string\[33\] | Guild names take a guild **ID**, not an index | Medium | https://esodecoded.com/dev/api |
| Rate limits | No documented rate limits on these client-side lookups | The cost is CPU time: large ID sweeps (e.g. 1..10000 quests) in one frame can cause hitches.\[60\] Spread them across frames. | Medium | — |

## 10. Session-boundary events

| Event | Parameters | Notes | Confidence | Source |
|---|---|---|---|---|
| `EVENT_PLAYER_ACTIVATED` | `(eventCode, initial)`\[62\] | Fires after login, /reloadui and every loading screen | High | https://wiki.esoui.com/Events |
| `EVENT_PLAYER_DEACTIVATED` | `(eventCode)`\[62\] | Fires "before a loading screen is incoming", including at logout. One report says the companion was already dismissed by then.\[62\]\[63\] | High | same; https://www.esoui.com/forums/showthread.php?t=10404 |
| `EVENT_LOGOUT_DEFERRED` | `(eventCode, deferMilliseconds, quitRequested)`\[62\] | Fires only when logout is delayed (not in a safe zone). There is also `EVENT_LOGOUT_DISALLOWED(eventCode, quitRequested)`.\[62\]\[64\] | High | https://wiki.esoui.com/Events |
| "About to save" hook | **None.** ZO_SavedVars has no callbacks. The workarounds are `EVENT_PLAYER_DEACTIVATED` plus pre-hooks on `Logout`, `Quit` and `ReloadUI`.\[13\] None of them catch crashes, disconnects or small-file autosaves. | Ayantir: "When player logout, reloadui, change cvar or get kicked for inactivity, saved variables are automatically saved. there's nothing to do."\[13\] Write data into your SavedVariables as soon as you have it. | High | https://www.esoui.com/forums/showthread.php?t=4965 |

---

## Pitfalls for a passive ZO_SavedVars + LAM layout recorder

1. **You miss calls that happen before your wrap.** ZOS code and any addon loaded before yours call the constructors before your wrapper exists. Install the wrapper at the top of your first Lua file, outside any event handler. At `EVENT_PLAYER_ACTIVATED`, backfill by scanning `_G` for tables shaped like SavedVariables: string keys at the first level, `@`-prefixed keys at the second, and `$AccountWide` or numeric-string character IDs at the third.
2. **Stay invisible.** Forward `self` and every argument unchanged, and return exactly what the original returned. Callers use `ZO_SavedVars:New...` method syntax, so keep the colon/self convention. Wrap the call in `pcall` so your bookkeeping can never break the caller, and record the call before invoking the original.
3. **Don't trigger defaults while reading.** Indexing the returned object or a raw table through `__index` copies defaults into the real SavedVariables table, which then get written to the other addon's file.\[3\] Walk the raw global with `next`/`rawget` only, and never touch `sv.someKey` on the proxy.
4. **The argument shift.** When `namespace` is a table, ZO_SavedVars treats it as `defaults`.\[3\] Normalize the arguments the same way in your logger, or you'll record the layout wrong.
5. **Profile ≠ namespace.** Profile is the first level (default "Default", often `GetWorldName()`). Namespace is the deepest level and has no default. Community posts mix these up; go by the source.
6. **Callers that bypass the wrapper.** These callers never go through your wrapper:
   - addons that cache `local NewAW = ZO_SavedVars.NewAccountWide` at file load before your wrap;
   - addons that use LibSavedVars or their own wrappers;
   - addons that write `_G[svName]` directly.\[12\]
   Treat the wrapper as a hint and the `_G` scan as the authoritative record.
7. **Working out which addon made a call.** There is no `debug.getinfo`. Parse `debug.traceback()` for `user:/AddOns/<Folder>/` paths to get the calling addon's folder. Fall back to the most recent `EVENT_ADD_ON_LOADED` name, which is unreliable because calls can also happen later.
8. **LAM data is lazy and full of functions.** `RegisterOptionControls` tables contain functions (`getFunc`, `setFunc`, `default`), so serialize only types, names and `reference` strings. Never call another addon's `getFunc` or `setFunc`. Controls exist only after "LAM-PanelControlsCreated". Wrap `LibAddonMenu2.RegisterAddonPanel` / `RegisterOptionControls` via `SecurePostHook` or a pass-through, because LAM offers no registration callback.
9. **Keep your own file small.** The 1999-byte string cap, multi-MB files slowing every loading screen, and the risk of corruption on very large files all apply.\[12\]\[15\] Store layouts as compact path signatures; `HashString` helps de-duplicate them. Don't store values.
10. **Don't count on a final save.** Keep your record current in memory at all times, since the next loading screen or reload will save it. Expect to lose any changes made since the last write if the client crashes.\[65\]
11. **Duplicates and version noise.** Embedded libraries can appear several times in `GetAddOnInfo`; only the highest `AddOnVersion` loads.\[66\] Use `state == ADDON_STATE_ENABLED` and the `name` field, not `title`. Expect `GetAddOnVersion` to return 0 sometimes.
12. **Multi-server and multi-account layouts.** The same SavedVariables file holds NA, EU and PTS data, possibly under several `@account` keys or shared keys like "AllAccountsTheSame".\[8\]\[9\] Key your records by `GetWorldName()` and don't assume the second level is the current `GetDisplayName()`.

## Caveats
- Signatures marked Medium come from an API 101046 documentation mirror or from third-party pages. Before shipping, diff them against the live `ESOUIDocumentation.txt` (101050/101051), especially the 8th-and-later `GetCharacterInfo` returns, `GetItemLinkQuality`, and `GetAddOnDependencyInfo`.
- Unconfirmed: whether addon enabled state is per character, any rename event, and the specific `SETTING_TYPE_*` / `CAMERA_SETTING_*` names. The PC format of `GetAddOnRootDirectoryPath` rests on a single 2020 user report.
- Some SavedVariables write rules (autosave thresholds, timing) come from 2019 forum observations and may have changed.

## Sources

1. [Main Page - ESOUI Wiki](https://wiki.esoui.com/Main_Page)
2. [APIVersion - ESOUI Wiki](https://wiki.esoui.com/APIVersion)
3. [UESP:ESO Lua File v101050 -- libraries/utility/zo\_savedvars.lua](https://esodata.uesp.net/current/src/libraries/utility/zo_savedvars.lua.html)
4. [Circonians Saved Variables Tutorial - ESOUI Wiki](https://wiki.esoui.com/Circonians_Saved_Variables_Tutorial)
5. [Reviving addons - What is to check/change - ESOUI](https://esoui.com/forums/showthread.php?p=44935)
6. [\[Video Tutorial\] LibAddonMenu and Saved Variables - ESOUI](https://www.esoui.com/forums/showthread.php?t=10469)
7. [esoui/esoui - Gitter](https://gitter.im/esoui/esoui?at=5d3c9db5a9200c24280af776)
8. [SavedVariables AllAccountsTheSame - ESOUI](https://www.esoui.com/forums/showthread.php?p=53762)
9. [Memory Garbage Collector : Utility Mods : Elder Scrolls Online AddOns](https://www.esoui.com/downloads/info4086-MemoryGarbageCollector.html)
10. [UESP:ESO Lua File v100020 -- libraries/utility/zo\_savedvars.lua](https://esoapi.uesp.net/100020/src/libraries/utility/zo_savedvars.lua.html)
11. [How to trigger things with ESO's default code - ESOUI Wiki](https://wiki.esoui.com/How_to_trigger_things_with_ESO's_default_code)
12. [Storing data and accessing files - ESOUI Wiki](https://wiki.esoui.com/Storing_data_and_accessing_files)
13. [Unload event - ESOUI](https://www.esoui.com/forums/showthread.php?t=4965)
14. [Logout-Events - ESOUI](https://cdn.esoui.com/forums/showthread.php?t=4651)
15. [ESOUI - \[fixed\] There's something terribly broken in saving and/or loading SavedVariables](https://www.esoui.com/forums/printthread.php?t=4933&page=2&pp=20)
16. [Controls - ESOUI Wiki](https://wiki.esoui.com/Controls)
17. [ESO UI Documentation for API Version 101046](https://kawamonkey-eso.github.io/ESOUIDocumentation/)
18. [IsAddonRunning - ESOUI Wiki](https://wiki.esoui.com/IsAddonRunning)
19. [\[notabug\] GetAddOnVersion only works with libraries \[Archive\] - ESOUI](https://www.esoui.com/forums/archive/index.php/t-9908.html)
20. [How to update your addon for console - ESOUI Wiki](https://wiki.esoui.com/How_to_update_your_addon_for_console)
21. [ACI-AddOn Conflict Inspector : ESO Tools & Utilities : Elder Scrolls Online AddOns](https://www.esoui.com/downloads/info4506-0.2.0.html)
22. [github.com](https://github.com/MPHONlC/LibAPH/wiki/DependencyManagement)
23. [DependsOn and Embedded versions of LibAddonMenu2 - ESOUI](https://esoui.com/forums/showthread.php?t=11537)
24. [\[outdated\] Are any of the strings from an addon's .txt file available within Lua? - ESOUI](https://www.esoui.com/forums/showthread.php?t=7777)
25. [AddOn Manifest File Changes - ESOUI](https://www.esoui.com/forums/showthread.php?p=32188)
26. [Manifest Version Number - ESOUI](https://www.esoui.com/forums/showthread.php?p=24366)
27. [AddOn Quick Questions - ESOUI Wiki](https://wiki.esoui.com/AddOn_Quick_Questions)
28. [optional dependencies - ESOUI](https://cdn.esoui.com/forums/showthread.php?p=45534)
29. [Addon Structure - ESOUI Wiki](https://wiki.esoui.com/Addon_Structure)
30. [Addon Initialisation Timer : ESO Tools & Utilities : Elder Scrolls Online AddOns](https://www.esoui.com/downloads/info4926-2610.3.html)
31. [EVENT ADD ON LOADED - ESOUI Wiki](https://wiki.esoui.com/EVENT_ADD_ON_LOADED)
32. [Writing your first addon - ESOUI Wiki](https://wiki.esoui.com/Writing_your_first_addon)
33. [ESO Lua API reference — the 400 most-used functions, with real usage · ESO Decoded](https://esodecoded.com/dev/api)
34. [Update 2.5 - Page 3 - ESOUI](https://esoui.com/forums/showthread.php?p=28021)
35. [GetCharacterInfo - ESOUI Wiki](https://wiki.esoui.com/GetCharacterInfo)
36. [\[open\] Return CURRENT order with GetCharacterInfo(i) - ESOUI](https://www.esoui.com/forums/showthread.php?t=9872)
37. [Any existing way to find out my character id? - ESOUI](https://esoui.com/forums/showthread.php?p=45369)
38. [General saved variable questions - ESOUI](https://www.esoui.com/forums/showthread.php?t=10609)
39. [API From ESOUI Wiki](https://solinur.de/Files/API.pdf)
40. [Esolua - ESOUI Wiki](https://wiki.esoui.com/Esolua)
41. [API - ESOUI Wiki](https://wiki.esoui.com/API)
42. [Variable Dump - ESOUI](https://www.esoui.com/forums/showthread.php?t=2445)
43. [UESP:ESO Lua File v101040 -- libraries/globals/debugutils.lua](https://esodata.uesp.net/current/src/libraries/globals/debugutils.lua.html)
44. [HashString - ESOUI Wiki](https://wiki.esoui.com/HashString)
45. [esoui/esoui/libraries/globals/localization.lua at master · esoui/esoui · GitHub](https://github.com/esoui/esoui/blob/master/esoui/libraries/globals/localization.lua)
46. [Secure Protected Function "UseItem" - ESOUI](https://esoui.com/forums/showthread.php?p=44968)
47. [\[SOLUTION\] Insecure Code Errors - ESOUI](https://www.esoui.com/forums/showthread.php?t=6806)
48. [API/ru - ESOUI Wiki](https://wiki.esoui.com/API/ru)
49. [ESOUI - View Single Post - Update 5.2](https://www.esoui.com/forums/showpost.php?p=39445&postcount=6)
50. [How to run your code before/after functions (PreHook/PostHook) - ESOUI Wiki](<https://wiki.esoui.com/How_to_run_your_code_before/after_functions_(PreHook/PostHook)>)
51. [LibAddonMenu : Libraries : Elder Scrolls Online AddOns](https://www.esoui.com/downloads/fileinfo.php?s=a100f82fde8a2e8d72dffa315eea15e9&id=7)
52. [LibAddonMenu-2.0 : Libraries : Elder Scrolls Online AddOns](https://www.esoui.com/downloads/info7-LibAddonMenu.html)
53. [LAM panel callback - ESOUI](https://www.esoui.com/forums/showthread.php?t=11774&goto=newpost)
54. [LibAddonMenu-2.0r20 released - ESOUI](https://www.esoui.com/forums/showthread.php?t=6205)
55. [ESO-LibAddonMenu/LibAddonMenu-2.0/development.lua at master · sirinsidiator/ESO-LibAddonMenu · GitHub](https://github.com/sirinsidiator/ESO-LibAddonMenu/blob/master/LibAddonMenu-2.0/development.lua)
56. [Grouping Pefected/Non-Perfected sets? - ESOUI](https://www.esoui.com/forums/showthread.php?p=49347)
57. [LibSets (All set items ingame & preview. lua API + excel sheet) : Libraries : Elder Scrolls Online AddOns](https://www.esoui.com/downloads/info2241-LibSets.html)
58. [Linking questId and questName please? - ESOUI](https://www.esoui.com/forums/showthread.php?t=8000)
59. [\[open\] More quest info for more quests - ESOUI](https://esoui.com/forums/showthread.php?p=34459)
60. [\[open\] More quest info for more quests - Page 2 - ESOUI](https://esoui.com/forums/showthread.php?p=52797)
61. [GetAchievementInfo - ESOUI Wiki](https://wiki.esoui.com/GetAchievementInfo)
62. [Events - ESOUI Wiki](https://wiki.esoui.com/Events)
63. [Saving Companiondata on user Logout - ESOUI](https://www.esoui.com/forums/showthread.php?t=10404)
64. [Am I in a City (Safe to Logout) - ESOUI](https://www.esoui.com/forums/showthread.php?t=2042&goto=newpost)
65. [\[PC\]HowTo: SavedVariables - Find the folder, backup, copy - ESOUI](https://www.esoui.com/forums/showthread.php?t=9235)
66. [Updating Independent Libs (Libraries) - ESOUI](https://www.esoui.com/forums/showthread.php?t=8435)
