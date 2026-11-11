# Stories

All decided by the agent from the brief. Snapshot pages: `installed`, `updates`, `find-more`, `details`, `settings`, `menubar`.

## M1 Core loop

### S-001 Load the catalog
As the user, I open the app and the ESOUI catalog and categories load (from cache first, then refreshed).
Screens: find-more
Acceptance:
- [unit] `filelist.json` decodes into Addon values (UID, name, author, version, date, dirs, category, counts, thumbs).
- [unit] The cache is written to Application Support and read back on the next launch with no network.
- [self] A failed refresh keeps the cached catalog and shows "Couldn't refresh the catalog" in the toolbar status.
UX: the status sits in the toolbar subtitle ("Catalog: 3,330 addons · updated 2 min ago").
Status: done

### S-002 See installed addons
As the user, I open Installed and see every addon in my AddOns folder, matched to ESOUI.
Screens: installed
Depends: S-001
Acceptance:
- [unit] Folders are matched by UIDir; an addon counts as installed when all its UIDir folders exist; nested `Libs` are ignored.
- [unit] Install records are seeded once from `~/.minion/minion.xml` (uid, ui-version, md5, dirs, ignored).
- [snap] The table shows Name, Author, Installed, Latest, Status; unmatched folders show a manifest title and "Not on ESOUI".
UX: Status badge words are "Up to date", "Update available", "Ignored", "Not on ESOUI".
Status: done

### S-003 Update one addon
As the user, I click Update on a row and the addon is replaced with the latest version.
Screens: installed, updates
Depends: S-002
Acceptance:
- [unit] The zip is downloaded from UIDownload, its MD5 checked against UIMD5, unzipped to a temp folder, and each top-level folder replaces the matching folder in AddOns.
- [unit] A failed MD5 check or unzip leaves the existing folders untouched.
- [self] A progress indicator shows on the row; on success the row reads "Up to date".
Status: done

### S-004 Update all
As the user, I press Update All (⌘U) and every addon with an update (that isn't ignored) is updated, two at a time.
Screens: updates
Depends: S-003
Acceptance:
- [unit] Update All runs at most 2 concurrent downloads.
- [self] The toolbar shows "Updating 3 of 12…"; errors are listed per addon and don't stop the rest.
Status: done

### S-005 Search and install
As the user, I search Find More, select an addon and press Install.
Screens: find-more, details
Depends: S-001, S-003
Acceptance:
- [unit] Search matches name and author, case- and diacritic-insensitive.
- [self] Find More leaves out installed addons; when everything matching is installed it says so and points to Installed.
- [snap] The details pane shows thumbnail, author, version, date, downloads, favorites, compatibility, description (BBCode to plain text) and changelog.
- [self] Install writes the folders and the addon then appears in Installed.
UX: The primary button reads "Install", "Update" or "Reinstall" depending on state; "Open on ESOUI" is secondary.
Status: done

### S-006 Remove an addon
As the user, I choose Remove… from a row's context menu and confirm, and its folders are moved to the Trash.
Screens: installed
Depends: S-002
Acceptance:
- [unit] Folders are moved to the Trash (recoverable), never hard-deleted; SavedVariables are left alone.
- [self] A confirmation alert names the folders: "Move “HarvestMap” to the Trash?".
Status: done

### S-007 Ignore updates for an addon
As the user, I toggle "Ignore Updates" on a row, so Update All skips it.
Screens: installed
Depends: S-002
Acceptance:
- [unit] Ignored state persists and is excluded from the update count.
Status: done

## M2 Organize

### S-008 Browse by category
As the user, I pick a category from Find More's Filter menu and see only those addons, sorted by downloads, favorites, newest or name.
Screens: find-more
Acceptance:
- [unit] Category filter includes child categories (UICATParentIDs).
- [snap] Sort picker in the toolbar.
Status: done

### S-009 Choose the AddOns folder
As the user, I choose live or PTS (or any folder) in Settings.
Screens: settings
Acceptance:
- [unit] Changing the folder rescans Installed.
- [self] The default is the live folder when it exists.
Status: done

## M5 System

### S-010 Menu bar update count
As the user, I see the number of available updates in the menu bar and can run Update All from there.
Screens: menubar
Depends: S-004
Acceptance:
- [self] The MenuBarExtra shows a count badge, "Update All", "Open MacMinion", and "Check for Updates".
- [unit] Auto-check runs on a timer (default every 60 min).
Status: done

### S-012 See an overview on the home page
As the user, I open MacMinion to an Overview page: how my addons stand today and how they have been kept current.
Screens: overview
Depends: S-002, S-003
Acceptance:
- [snap] A hero card says "Everything's up to date" or "N updates ready" with Update All.
- [snap] Tiles: From ESOUI, Updates Ready, Libraries, Not on ESOUI, Ignored, On Disk; each opens its page.
- [snap] Cards: Updates Installed (weekly chart, 26 weeks), By Category, Recent Activity, Updated Most Often, Popular This Month (with Install).
- [unit] Minion's auto-update log is imported once as history; MacMinion logs every install, update, and removal.
UX: The page is called "Overview" in the sidebar; history rows read "Updated 1.2 → 1.3 · by Minion".
Status: done

### S-013 Summarize what an update changes
As the user, I press Summarize Changes on an addon (or Summarize Updates on the Updates page) and the assistant explains the changelog since my version.
Screens: updates, settings-ai
Depends: S-005
Acceptance:
- [unit] Ollama requests go to `<server>/api/chat`; Claude requests go to the Messages API with the key from the Keychain, Opus 5.5 by default, server-side fallbacks on Opus and Sonnet.
- [unit] A refusal or HTTP error shows its reason; an unconfigured provider says what to set instead of sending anything.
- [snap] The "What's New" card sits under the facts and names the model that wrote it.
- [manual] A live Ollama summary of a real ESOUI changelog reads correctly.
UX: Provider choices read "Off", "Ollama (on this Mac)", "Claude", "OpenAI". AI is off until chosen.
Status: done

### S-014 Settings for updates, the app, and AI
As the user, I set how often MacMinion checks, whether it installs updates itself, how many download at once, notifications, the menu bar item, open at login, the AI provider, appearance, and the UI language.
Screens: settings-general, settings-updates, settings-ai, settings-appearance
Acceptance:
- [snap] Tabs: General, Updates, Layout, Backups, AI, Appearance.
- [snap] Settings → Appearance: accent, light/dark/system, and Language (Match System, English, Deutsch, Français, Español, Русский).
- [self] A language override writes AppleLanguages; Match System clears the app override; relaunch applies it.
- [unit] Test and snapshot runs keep settings in memory and never touch the Keychain.
Status: done

### S-015 Browse Installed and Find More as a bento grid
As the user, I see Installed and Find More as a grid of cards: updates as wide cards first, libraries in their own section, the top four Find More results as wide cards above a grid of equal cards. Selecting a card opens its details in an inspector.
Screens: installed, findMore, settings-layout
Acceptance:
- [unit] Cards pack densely: small cards fill the gaps beside wide and large ones; wide cards shrink on one column.
- [snap] A toolbar switch (and Option-Command-1/2) changes grid and list per page.
- [snap] Settings > Layout: Installed and Find More layout, card size, preview images, updates first, group libraries, feature popular.
Status: done

### S-016 One color scheme, matching the icon
As the user, I see one blue across the icon, the banner, charts, buttons, and selection; green means up to date and red means a problem.
Acceptance:
- [unit] The default accent is Minion Blue (#007AFF), the icon's fill.
- [manual] No raw colors, radii, or durations outside the token files (design/DESIGN-SYSTEM.md).
Status: done

### S-017 Drive MacMinion from the command line
As an agent (Claude Code, a script), I run `macminion <noun> <verb> --json` and the running app does it, like a button press.
Acceptance:
- [self] `check-agent-cli.sh macminion` prints PASS agent CLI (help, JSON errors, every read command, MCP tool list).
- [unit] `addons remove` only reports the folders it would trash until `--yes`.
- [manual] A fresh Claude Code session lists updates and summarizes one with the skill in `.claude/skills/macminion`.
Status: done

### S-018 Recommend an Ollama model
As the user, I see which installed Ollama model suits changelog summaries on this Mac and can switch to it in one click.
Acceptance:
- [unit] Coding and embedding models are never recommended; models must fit in 60% of memory; near 12B and newer families rank first.
- [unit] The host counts: a model larger than the memory free now drops, a loaded model rises, and a benchmarked model slower than 15 tokens/s drops.
- [manual] Benchmark Top Models measures real tokens per second (M2 Ultra: gemma4 115, phi4 52, llama3.3 70B 13).
- [snap] Settings > AI shows "Recommended: <model>" with a reason and a Use button.
Status: done

### S-019 Recommended for You
As the user, I see on the Overview a few uninstalled addons the AI thinks would add something to the ones I have, each with a reason and Install.
Screens: overview
Acceptance:
- [unit] Candidates are popular, uninstalled, non-library addons, weighted to my most-used categories; answers that name anything else are dropped.
- [unit] The model sees every installed addon and candidate with its category and a one-line description (the manifest's own, else ESOUI's, noise lines skipped), so it can skip candidates that duplicate an installed addon's job; forks that install into a folder on disk are never candidates.
- [unit] A folder that can't be read never prunes install records; agent commands and suggestions wait for the first scan.
- [self] Suggestions are saved, hide once installed, and refresh on their own after a week (never in test runs).
- [manual] Live gemma4 suggestions from 86 installed addons read sensibly.
Status: done

### S-020 Thumbs up and down
As the user, I give any addon a thumbs up or down from its card, row menu, detail pane, or an AI pick.
Acceptance:
- [self] Thumbs down hides a suggestion and keeps the addon out of AI candidates; both ratings are saved and go into AI prompts.

### S-021 Install a specific version
As the user, I pick any release ESOUI still has from the Version menu in an addon's details.
Acceptance:
- [unit] Archived releases are read from the addon's ESOUI page, newest first.
- [self] An older release installs and is pinned (Update All skips it); installing the latest unpins it.

### S-022 Search the catalog in my own words
As the user, I describe what I want in the search bar under Recommended for You and the AI finds catalog addons that fit, with a reason each.
Acceptance:
- [unit] The AI's keywords and categories filter the catalog; descriptions count; thumbs-down addons never appear.
- [snap] Results show under the bar with Install and thumbs.
Status: done

### S-023 Install the libraries my addons can use
As the user, I see on the Overview, right under the banner, a "Libraries for Installed Addons" card listing the libraries my addons ask for that I don't have ("Missing: 1 required, 3 optional"): required ones flagged first, then optional ones, each with the addons that want it, Install, and Install All.
Acceptance:
- [unit] Read from every manifest's DependsOn and OptionalDependsOn; optional ones must be ESOUI libraries; LibStub and names not on ESOUI are left out.
- [unit] A library bundled inside another addon (up to three folders down, with its own manifest) counts as installed, as the game loads it.
- [self] Each row has thumbs; an optional library with a thumbs down is hidden for good, a required one always shows.
- [self] Install All installs them and the card disappears.
Status: done

### S-024 Filter Installed and Find More
As the user, I narrow Installed and Find More from a Filter menu: category on both; status and a sort order on Installed (with a search box); update age on Find More; rating, current game version, and hide libraries on both. Active filters show as chips I can turn off one at a time.
Acceptance:
- [self] Each filter narrows the list; Clear Filters (Option-Command-0) turns them all off.
- [snap] Chips above the results; an empty filtered page offers Clear Filters.
Status: done

### S-025 Arrange the Overview
As the user, I choose which Overview sections show and in what order: from Customize in the toolbar or Settings > Layout (check to show, drag to reorder), or by right-clicking a section (Move Up, Move Down, Hide).
Acceptance:
- [self] Moving, hiding, and Reset to Default work; order and hidden sections are saved.
- [unit] Sections added in a later version join the saved order at their default place.
- [snap] The Customize sheet lists every section with a checkbox and a drag handle.
Status: done

### S-026 Back up and restore, compatible with Minion
As the user, I back up SavedVariables, AddOnSettings.txt, UserSettings.txt, and my addon list (Backups page, Command-B, or weekly on its own), and restore any backup, including Minion's and Minion's first full AddOns backup.
Acceptance:
- [unit] Writes Minion's layout: <backup-dir>/minion-backups/<game id>/<yyyy-MM-dd>.zip with absolute entry paths, and <date>-addons.txt ("7,57,"); reads Minion's initial-backup/<game id>.zip.
- [manual] Every real Minion backup unpacks and maps into the game folder (224 and 1,582 files); Minion's own Java reads a MacMinion zip.
- [self] Restore brings back files, installs missing addons, optionally trashes others, saves the current state first; old backups beyond Keep go to the Trash.
Status: done

## M6 Polish

### S-027 Use OpenAI, with keys kept per provider
As the user, I pick OpenAI (or Claude) in Settings > AI, save my own API key to the Keychain, choose or type a model, and test the connection; Ollama keeps working as before.
Screens: settings-ai, settings-ai-openai
Depends: S-013
Acceptance:
- [unit] Each adapter encodes its own request (Ollama NDJSON chat, Anthropic Messages with a top-level system and no temperature, OpenAI Chat Completions with max_completion_tokens) and parses a recorded stream into text, usage, and a stop reason.
- [unit] 401/403 read "Check your API key", 429 "rate limiting", 5xx "having problems"; provider messages never show a key; model lists retry with backoff, streams never retry; cancelling stops the request.
- [self] OpenAI without a key asks for one; a saved key belongs to one provider and stays out of UserDefaults; Remove Key forgets it.
- [snap] Settings > AI with OpenAI shows Status, API Key, Remove Key, Save to Keychain, Model with a list, and Test Connection.
- [manual] With real keys: tokens stream into What's New, a wrong key shows Invalid key, and Ollama still summarizes offline.
UX: Status reads "No key configured", "Not tested", "Connected", "Invalid key", or "Rate limited".
Status: done

### S-011 App icon and empty states
Acceptance:
- [snap] The Dock icon is a one-eyed red creature with a fanged grin, after Minion's icon, as two glass layers (eye, grin).
- [snap] Empty Installed shows "No addons found in <folder>" plus a "Choose Folder…" button.
- [manual] The icon matches the native style.
Status: todo

## M7 Game folder

The rest of the `live` folder: see `docs/research/LIVE-FOLDER.md`. Nothing changes while ESO runs; removed files go to the Trash, after a backup when they hold settings.

### S-028 See what's in the game folder
As the user, I open Game Folder in the sidebar and see each item beside AddOns (SavedVariables, the two settings files, graphics caches, GuildHistory, Logs, Errors, Screenshots) with its size, last change, and what it is for, and loose copies like `*.bak*` grouped as "Your own copies".
Screens: gameFolder
Acceptance:
- [unit] A scan of a /tmp game folder lists every known item with byte size and date, and puts `*.bak*` files and unknown folders under "Your own copies".
- [self] The scan of the seed folder finds every seeded item.
- [snap] The page shows a row per item, a Reveal in Finder button, and a banner while ESO runs: "Quit Elder Scrolls Online to make changes."
Status: removed in S-064 (the Folder view; the scan stays, for Problems' copies and strays)

### S-029 Tidy SavedVariables
As the user, I see each SavedVariables file with the addon it belongs to and its size, find files no installed addon uses, and move those and my loose `.bak` copies to the Trash after a backup.
Screens: gameFolder-savedvariables
Depends: S-026, S-028
Acceptance:
- [unit] A file belongs to an addon when it is named after an installed manifest (`<Folder>/<Folder>.txt` or `.addon`, up to three folders deep) with a `## SavedVariables:` line; `ZO_*` files are the game's and never flagged.
- [unit] Nested addons, laid out as on a real folder (GS16Data in LibGuildStore, HarvestMapAD in HarvestMap/Modules), are not flagged; one four folders down is.
- [self] Clean Up backs up first, moves the chosen files to the Trash, and refuses while ESO runs.
- [snap] Files sort by size; flagged ones read "No installed addon".
Status: done; the SavedVariables list was removed in S-064: the Inspector lists the files, and Clean Up opens Problems

### S-030 Clean up and copy addon choices
As the user, I see AddOnSettings.txt as a grid of characters and addons, remove entries for addons I no longer have and characters I choose, and copy one character's addon choices to others.
Screens: game-folder-addonsettings
Depends: S-028
Acceptance:
- [unit] Parses and writes `#Version`, `#AcknowledgedOutOfDateAddonsVersion`, `#AddOnsEnabled`, `#Default`, and `#<server>-<character>` blocks back byte for byte when nothing changed.
- [unit] Entries naming no installed addon are flagged; character blocks are never flagged on their own (files can't tell a deleted character).
- [self] Copy to Characters and Remove back up the file first and refuse while ESO runs.
- [snap] Characters are grouped by server; flagged entries read "Not installed".
Status: todo

### S-031 Clear the graphics caches
As the user, I clear ShaderCache.cooked and PipelineCache.esopc when the game stutters or looks wrong after a patch; MacMinion suggests it once when the game version in AddOnSettings.txt changes.
Depends: S-028
Acceptance:
- [unit] A change of `#Version` since the last scan raises the suggestion once.
- [self] Clear moves both files to the Trash and refuses while ESO runs.
- [snap] The row says "Rebuilt on next login; it takes a few minutes."
Status: todo

### S-032 Graphics suggestions for this Mac
As the user, I see suggestions for UserSettings.txt from this Mac's chip, memory, display, and power source (limit frames in the background; match the frame cap to the display; a performance preset on battery), see each change as old and new value, and apply or undo them.
Screens: game-folder-graphics
Depends: S-028
Acceptance:
- [unit] Reads and writes `SET KEY "value"` lines, keeping order, unknown keys, and line endings; only keys on a known list change.
- [unit] Rules are pure functions of HostProfile, display refresh rate, power source, and the current settings, e.g. `USE_BACKGROUND_FPS_LIMIT "0"` gives "Limit frames in the background"; a cap above the display's refresh rate gives "Match the frame cap to your display".
- [self] Apply backs up UserSettings.txt, writes, and Undo restores it; both refuse while ESO runs.
- [manual] After applying on this Mac, the game starts with the new values and its settings menu shows them.
Status: todo

### S-033 Logs, crash reports, and guild history
As the user, I open or clear Logs and Errors, and clear GuildHistory's contents when guild history is stuck.
Depends: S-028
Acceptance:
- [unit] Clearing GuildHistory moves its files to the Trash and keeps the folder.
- [self] Each clear asks first and refuses while ESO runs.
Status: todo

### S-034 Game folder from the command line
As an agent, I run `macminion folder` (scan), `folder savedvars`, `folder addonsettings`, and `folder graphics` for the same results as the page, and the matching clean-up and apply commands.
Depends: S-028
Acceptance:
- [self] `check-agent-cli.sh macminion` passes with the new commands; changing commands refuse while ESO runs.
Status: todo

## M8 SavedVariables Inspector

Read-only. Walks every SavedVariables file as a tree, names the IDs in it, and points at what is broken or worth trimming. See `docs/research/SAVEDVARIABLES.md`.

### S-035 Read any SavedVariables file
As the user, I see every SavedVariables file read into a tree, or exactly where and why one can't be read.
Depends: S-029
Acceptance:
- [unit] Parses the serializer's subset of Lua: several `Name = { ... }` variables per file, `["key"]` and `[n]` keys, strings with `\"`, `\\`, `\n`, `\r`, `\t`, and `\ddd` escapes, integers, decimals, exponents, `true`, `false`, `nil`, and `--` comments.
- [unit] Each node keeps its key path, child count, and byte span, so a subtree's size is known without re-reading.
- [unit] A truncated or broken file reports line, column, and the last complete key path; what was read before the error stays browsable.
- [manual] Every file in a real SavedVariables folder parses (`MM_REAL_SV=<folder> swift test -c release --filter parsesARealFolder`): 91 files, 1.1 million entries, 0.18 s; TamrielTradeCentre (16 MB) 0.03 s.
Status: done

### S-036 Browse the tree
As the user, I open Inspector on the Game Folder page (or double-click a SavedVariables file) and expand the tree, or open a table to show only its entries and go back up with the path bar: server, account, and character levels are labeled, each row shows key, value or child count, and size.
Screens: gameFolder-inspector, gameFolder-inspector-character
Depends: S-035
Acceptance:
- [snap] An outline with Key, Value, and Size columns, a path bar of the open table, and Open Table / Copy Path / Copy Value / Show Raw / Look Up on UESP in the context menu and the Inspector menu.
- [self] Opening a 100 000-row table shows the first rows at once: rows are made when a table opens.
- [self] Open Table (⌘↓) shows only that table; Enclosing Table (⌘↑) goes back and selects it; Copy Path writes `Var["key"][1]`.
- [unit] Levels are recognized as server (`NA Megaserver`, `EU Megaserver`, `Default`), account (`@name`), and character (16-digit ID, or `Name^Mx` in older files).
Status: done

### S-037 Name the IDs
As the user, I see a name beside each ID I recognize: characters, accounts, guilds, items, sets, zones, maps, quests, and achievements, with where the name came from.
Depends: S-035
Acceptance:
- [unit] Character IDs get names from `ZO_Ingame.lua` and from addons that store ID-to-name tables; accounts are marked yours (in the path of your own data) or someone else's.
- [unit] Item links decode into item ID, quality, level, trait, and style; the set comes from LibSets' data files, zones and maps from LibZone, quests from LibQuestData, read as text, never run.
- [unit] Items, sets, quests, zones, and achievements link to UESP; Look Up on UESP (⌥⌘L) opens the page in the browser. UESP's data API answers apps with a Cloudflare challenge, so nothing is fetched.
- [unit] LibGuildStore's sales rows (numbers for item links, accounts, and guilds) are named from its own indexes in GS16Data and GS17Data.
- [manual] On a real folder (`MM_REAL_SV=<folder> swift test -c release --filter namesARealFolder`): 38 characters, 435 guilds, 712 sets covering 119 646 items, 1 103 zones, 3 264 quests, in 0.5 s.
- [snap] A named ID shows "Masisi · character" in the Value column, with the source in its help tag; an ID no file names reads "Unknown character" in red.
Status: done

### S-038 Find every place an ID appears
As the user, I type a name or ID in the Inspector's find field (⌘F), or choose Find Everywhere (⇧⌘F) on a row, and see every file and path that mentions it, across all SavedVariables; double-clicking a place opens it in the tree.
Screens: gameFolder-inspector-find
Depends: S-037
Acceptance:
- [unit] An index of characters, accounts, items (links, item IDs, LibGuildStore's numbers and item-ID keys), guilds, sets, zones, quests, achievements, and maps to file and byte offset; a place's key path is found again from its offset.
- [unit] Finding matches an ID exactly, or a name (character, set, zone, quest, guild, account) containing the text; most-mentioned first.
- [self] Finding "Masisi" lists WritWorthy and ZO_Ingame; Find Everywhere on an item link finds it in LibGuildStore's index and sales; Show in Tree opens the file at that place; the index is rebuilt when a file changes.
- [manual] On a real folder: 88 941 IDs in 343 952 places, built with the names in 1.2 s.
- [snap] Results are grouped by ID, then by file, with the path (names in place of character IDs) and the value.
UX: at most 500 places per ID and 3 000 in all are listed, with the full count in the header.
Status: done

### S-039 Find why an addon breaks
As the user, I open Problems on the Game Folder page (⌥⌘P) and see, errors first: files that don't parse or end early, empty files, files with none of the variables their addon declares, variables an addon no longer declares, named keys whose type differs between characters or entries, lists of 5 000 entries or more, and files over 5 MB. Double-clicking one opens it in the Inspector at that place.
Screens: gameFolder-problems
Depends: S-035
Acceptance:
- [unit] Each check has a case on a small fixture and names the file, path, and a sentence on what it means.
- [unit] No false alarms from what addons do on purpose: older names still declared but no longer written, positional lists (`{ x, y, "name" }`) that mix types, and `false` standing in for a table.
- [self] The seed folder's file that ends early, long log, undeclared variable, and mixed-type key are reported, errors first, and Show in Inspector opens the place.
- [manual] On a real folder: 4 problems (TamrielTradeCentre and GS16Data over 5 MB, LibDebugLogger's 6 769-entry log, AutoResearch's leftover AutoResearch_Account).
Status: done

### S-040 Find what to trim
As the user, I open Space on the Game Folder page (⌥⌘S) and see what takes space in SavedVariables, largest first with a bar for its share: the biggest tables across all files, and totals by character, account (yours, then other players your addons keep data about), server, and file.
Screens: gameFolder-space
Depends: S-036, S-037
Acceptance:
- [unit] Sizes roll up by file, by character (any key that is a character ID), by account (an `@name` holding a table), and by server.
- [unit] A table is listed unless one child table holds three quarters of it, so a chain of wrappers shows once.
- [unit] Character IDs are 16 digits starting 87; the 19-digit item instance IDs some addons key by are not characters.
- [unit] A character ID with no name in any current source is "Unknown character"; data for other accounts is listed apart.
- [self] Double-clicking a table opens it in the Inspector; a character or account finds everywhere it appears.
- [manual] On a real folder: 38 characters (none unknown), 2 accounts of yours and 2 563 others', Default 25.9 MB, the biggest table TamrielTradeCentre's guild listings at 15.5 MB.
UX: read-only; Copy Path on each table for when trimming arrives.
Status: done

### S-041 Inspect from the command line
As an agent, I run `macminion sv files`, `sv tree <file> [--path]`, `sv find <text or id>`, `sv id <id>`, `sv problems`, and `sv biggest [--by]` for the same results as the page, as text or `--json`.
Depends: S-035
Acceptance:
- [unit] `--path` reads Copy Path's form (`Var["NA Megaserver"][1]`) and `Var › NA Megaserver › 1`; a number typed for a character ID finds it stored as a string.
- [self] Each command returns what the page shows for the seed folder; a missing file is `not_found` and says to run `sv files`.
- [self] `check-agent-cli.sh macminion` passes with the new commands.
UX: text output puts a match's places on indented lines below it.
Status: done

## M9 MacMinion Companion

An in-game addon (`EsoMacMinion`, repo `solaegis/eso-mac-minion`) that writes what only the running game knows to its own SavedVariables. Spec: `docs/COMPANION-ADDON.md`. MacMinion bundles and installs it.

### S-042 Companion addon: environment, roster, and addon states
As the user, I install ESO Mac Minion and, after one login, MacMinion knows my game version, every character on each server (class, level, last played), and which addons loaded, failed, or are out of date.
Acceptance:
- [unit] Lua: the roster, addon states, and missing dependencies come from the ESO API through the mock harness, under `EsoMacMinion_Data` at schema 1.
- [unit] Swift: a schema-1 fixture reads into a companion snapshot; an unknown schema skips what it can't read and says so. `EsoMacMinion.lua` and `EsoMacMinion_Data.lua` both count.
- [manual] In game, `/emm` shows each section filled; login and `/reloadui` times with and without the companion differ by less than 100 ms.
Status: in progress

### S-043 Lua errors by addon
As the user, I see which addons threw Lua errors last session, how often, and the message, in Problems and on the addon's Installed row.
Depends: S-042
Acceptance:
- [unit] Lua: errors are attributed by the `user:/AddOns/<name>/` path, repeats add to a count, at most 50 are kept, messages cut at 500 characters.
- [self] A seeded companion file's errors appear in Problems with the addon, count, and message.
Status: in progress

### S-044 Names from the game itself
As the user, I see real item, quest, achievement, collectible, zone, and set names (and item quality and icon) for IDs no library names: MacMinion asks the companion while ESO is closed, and the game answers at the next login.
Depends: S-042, S-037
Acceptance:
- [unit] Swift: requests are written only while ESO is closed, merged with ones already waiting, capped at 2 000; answers go into MacMinion's own cache.
- [unit] Lua: requests are answered a few hundred per frame and moved to answers.
- [self] A seeded answer names an item the libraries don't know, ranked above LibSets.
Status: todo

### S-045 Deleted characters, for certain
As the user, I see data kept for characters that no longer exist on my roster, by addon and size, now that the roster is known.
Depends: S-042, S-040
Acceptance:
- [unit] A character ID in other files that isn't on its server's roster is deleted; one on another server's roster is not.
- [snap] Space's characters show deleted ones apart, with their size.
Status: todo

### S-046 Performance over time
As the user, I see frame rate, latency, Lua memory, and load-screen times across my sessions, and which graphics changes helped.
Depends: S-042
Acceptance:
- [unit] Lua: samples every 60 s out of combat into a 240-sample ring; loads into a 50-load ring.
- [snap] Overview charts frame rate and load time by session.
Status: todo

### S-047 Install and update the companion
As the user, I install ESO Mac Minion from Settings > Game Folder, and MacMinion keeps it current with the app and the game's API version.
Depends: S-042
Acceptance:
- [self] Install copies the bundled addon into AddOns; a newer bundled version replaces it; it's never touched while ESO runs.
- [snap] The setting shows the installed version and when it last wrote data.
Status: in progress

## M10 Visual Inspector

The same data as the Inspector, for people who don't read Lua tables: pictures, cards, and plain words. The tree stays for detail.

### S-048 Where your space goes, as a treemap
As the user, I open Space and see Map first: SavedVariables as tiles sized by bytes, one per addon (its bundled data addons share its tile; the game's own files are "The game"), colored by what they hold (prices and sales, map data, logs that grow, the game's own, settings and other data). Clicking a tile zooms in, to an addon's files, a file's tables, and tables inside those; a leaf opens in the Inspector. The path bar and Zoom Out (⌘-) zoom back out.
Screens: gameFolder-space, gameFolder-space-zoom
Depends: S-040
Acceptance:
- [unit] A squarified layout: tile areas match their bytes, tiles fill the space without overlapping, and stay under 3:1 where the data allows.
- [unit] Zooming into a file sees through a single variable, server, or account; entries under 0.4% of the whole, or past the 39th, are gathered into one "N smaller" tile.
- [unit] Data addons nested in another addon's folder (GS16Data in LibGuildStore) are grouped with it.
- [self] Top-level tiles are per addon and largest first; HarvestMap's two files share a tile; zooming into WritWorthy lands on its characters; Zoom Out goes back a level.
- [snap] The top level and a zoomed file, light and dark.
UX: tiles name the addon as ESOUI does; hover gives size, share of the total, and kind; the map uses a custom Layout, so tiles sit on the layout, not on offsets.
Status: removed in S-064 (the size tally stays for character lines, unknown characters, and `macminion sv biggest`)

### S-049 Character cards
As the user, I open Space > Characters and see each character as a card with server, class, level, and champion points, and how much addons keep about them; characters no file names show apart under No Name Found. Clicking a card lists that character's data by addon, largest first, each opening in the Inspector at the character's table.
Screens: gameFolder-space-characters
Depends: S-040 (class, level, and champion points from MacMinion Companion's roster when it's installed)
Acceptance:
- [unit] The companion's `EsoMacMinion_Data[server][account]["$AccountWide"].characters` reads into a roster with class and race names; roster names rank above every other source.
- [unit] Space totals by character also give bytes per file and the servers the data sits under ("Default" only when nothing else).
- [self] The seed's Masisi card reads "NA · Nightblade 50 · CP 2,410"; the unnamed character is flagged; Masisi's WritWorthy row opens at her table; per-addon sizes add up to the card's.
- [snap] Without the companion, cards show name, server, and size only.
Status: done

### S-050 Settings as you'd read them
As the user, I open an addon in the Inspector and see its saved settings as a readable sheet, the default view: a section for every character and one for settings shared by all, with switches for true and false, swatches for colors, item tags for item links, dates for timestamps, gold for money, and names for IDs, labeled in words ("Show timestamps", not showTimestamps). Tree (⌥⌘V) shows every key and value.
Screens: gameFolder-inspector-settings
Depends: S-036, S-037
Acceptance:
- [unit] Colors: `{ r, g, b, a }` tables anywhere, `{ 1, 0, 0 }` lists and `RRGGBB` hex under a color key, and ESO's `|cRRGGBB` codes anywhere. Dates: numbers between 2014 and a year from now under a time, date, stamp, seen, expire, or last key (`dailyResetWarnTime = 60` stays a number). Gold: gold, money, price, cost, spent, or budget keys. Versions and IDs without thousands separators.
- [unit] Labels: camelCase, snake_case, and Hungarian prefixes become words; ID, UI, HUD, CP keep their capitals; keys with spaces (character names, servers) stay as written.
- [unit] Server and account tables are see-through: sections are titled "Every character" or the character's name, with the server and account under the title.
- [self] The seed's WritWorthy settings read as switches, two colors, a date, gold, an item with its set, and a zone name; plain text and versions stay plain.
- [manual] Real pChat, WritWorthy, PersonalAssistant, and LostTreasure files read sensibly.
UX: read-only; right-click a row to show it in the tree or copy its path; a table inside a section opens with a click.
Status: done

### S-051 Connections map
As the user, I pick a character, item, guild, or account (Show Connections ⌥⌘K on a tree row, Connections on a find result or character sheet) and see a map with it in the middle, the files that mention it and the things stored with it around it, lines thicker for more mentions; clicking a thing follows it, Back returns, and clicking a file opens it at the mention.
Screens: gameFolder-inspector-connections
Depends: S-038
Acceptance:
- [unit] The neighborhood of a target: the files that mention it, and the other IDs that share a table with it (inside its own table, or beside it when it's a plain value), most mentioned first, at most 12 and at most 4 of a kind; other keys of a list it's a key of (a character ID -> name map) are siblings, not connections.
- [self] Masisi's map has WritWorthy, ZO_Ingame, and MacMinion Companion around her, and her zone and reward item; following the item shows the seller and guild of its sale; Back returns; a file opens at the mention.
- [manual] On a real folder: Masisi's map builds in under 10 ms from 2 000 mentions.
- [snap] A radial layout for Masisi from the seed data.
Status: done

### S-052 Health in plain words
As the user, I open Problems and in ten seconds know whether anything is broken in game, whether any saved data is at risk, and the one thing that fixes each: one card per cause, worst first, with the raw checks one click away (Details, ⌘I). Plan: `docs/HEALTH-FINDINGS-PLAN.md`.
Screens: gameFolder-problems
Depends: S-039, S-042
Acceptance:
- [unit] Every raw problem is in exactly one finding, for every fixture, in the same order however the input is shuffled.
- [unit] Each cause groups its inputs: a missing library with its dependents' Didn't load and Lua errors (two libraries the same addons need are one finding); an out-of-date addon with its own errors; a damaged file with the rest of that file's rows; a large file with its long list and its addon's slow load; a missing variable with that file's undeclared ones.
- [unit] Tiers run broken > data at risk > out of date > clean up > size; within a tier, more addons or characters first; size never outranks another tier, and a large file alone is behind Nothing to Do Here.
- [unit] Every count is interpreted: "N addons are out of date" carries how many still need LibStub or have an update ready. LibStub is never offered as a library to install.
- [unit] A file not written in 90 days is certain only when the companion shows its addon off for every character; possible, naming who, when a character has it on.
- [self] On the seed: every raw problem is in one finding; LibLazyCrafting's finding holds Missing Lib Addon's Didn't load and offers Install; Dustman.lua is one Damaged finding offering Backups; HarvestMapAD.lua's large file and long list are one "keeps growing" finding; LibDebugLogger's undeclared log joins its missing variable.
- [self] Restore from Backup opens Backups on Dustman.lua, lists the backup holding a good copy, and Restore This File puts back only that file (HarvestMap.lua stays as it was), after which the damaged-file finding is gone.
- [self] `macminion sv problems --json` returns the same findings in the same order, each with its action and targets; `--raw` returns the raw checks.
- [snap] Problems with a card in every tier, light and dark; again with Details open on the first card.
UX: a damaged file's Restore from Backup… opens Backups on that file: the backups that hold it, each with Restore This File, which saves what you have now and puts back only that file. The selected card's button is the prominent one; the menu bar's Fix (⌘↩), Show Problem Details (⌘I), Show Problem in Inspector (⌥⌘↩), and Clean Up All Not in Use… (⌥⌘⌫) act on it.
Status: done

### S-058 Problems from other tabs
As the user, I see a small "1 problem" link beside an addon on Addons or a character on Characters when a Problems finding names them, and it opens Problems with that finding selected. The other tabs never restate the problem.
Depends: S-052, S-054
Acceptance:
- [unit] A finding records the addon folders it concerns (named, from a companion problem, or owning one of its files) and the IDs of the characters it names.
- [self] WritWorthy's card on Addons links to its mixed-types finding; ZO_Ingame has no link; Masisi's page lists only what's broken for her; following a link opens Problems with that finding selected.
- [snap] Addons with the link on WritWorthy's card; Masisi's page with its Problems section.
UX: the link says how many ("2 problems") and its tooltip lists their titles; only findings with something to do link.
Status: done

### S-059 An installed addon's files and problems
As the user, I see two icons on an addon on Installed or Updates (row or card): a magnifying glass that opens Game Folder > Inspector with only that addon's SavedVariables files listed, and a warning triangle with a count that opens Problems with only the findings about that addon. A bar above each narrowed list names the addon and has Show All (⎋). Show Files in Inspector (⇧⌘I) and Show Problems (⇧⌘P) in the Addons menu and the context menu do the same for the selected addon.
Depends: S-052, S-058
Acceptance:
- [self] WritWorthy links to WritWorthy.lua and to the same findings as its card on Addons; an addon with no files and no problems shows neither icon.
- [self] Show Files leaves only that addon's files in the Inspector and opens the first; Show All Files lists every file again.
- [self] Show Problems shows only findings about the addon, the first selected; a link to one finding (S-058) clears the filter.
- [snap] Installed as a grid and as a list with the icons; Problems narrowed to Dustman; the Inspector narrowed to HarvestMap.
UX: each icon shows only when there is something behind it. Installed reads the game folder when it opens, so the icons don't wait for a visit to Game Folder.
Status: done

### S-060 Copy settings from one character to another
As the user, Compare shows each character in their own color (the accent, and orange, or teal when the accent is warm): their header, their values, and buttons with their name. Each addon's heading reads "Clone row from" over the buttons: on a row, the button with a character's name gives their value to the other. The summary line reads "Clone all from" over the same buttons on the Only differences line, which give every difference to the other after asking (⌥⇧⌘C for the left character, ⌥⇧⌘V for the right). A setting only one has gets a button with that character's name; Clone leaves those alone. Two characters with the same name show their megaserver. MacMinion refuses while ESO runs (it writes its own copy when it quits) and backs up before the first copy between two characters. Packed addon data (LibCharacterKnowledge's encoded strings) and timestamps aren't settings, so they never show or clone.
Depends: S-057
Acceptance:
- [unit] A change rewrites only the entry it touches, in the game's format; a missing setting is added with the tables on the way; a file that doesn't read cleanly is left alone.
- [unit] A setting goes to the other character's own entry, or the same place under their table in the same variable.
- [unit] Packed strings and timestamps are left out of a character's settings; names like LibAddonMenu2 stay.
- [self] Refused while the game runs; one copy makes that setting the same and leaves the rest; an only-one setting can be given; cloning the other way leaves no differences; every file still reads.
- [self] Same-named characters read "Masisi (NA)" and "Masisi (EU)"; different names stay plain.
- [snap] Compare with the colored columns, the name buttons on each row, and the two Clone buttons.
Status: done

### S-065 An addon's creator filters by creator
As the user, I click a creator's name (on a card, a list row, the detail panel's "by …", or the Overview's lists) and the page shows only their addons: on Installed my addons by them, on Find More (and from the Overview) everything they publish on ESOUI, installed ones too. A "By sirinsidiator ✕" chip clears it. Addons › Show Addons by Creator (⌥⌘A) does the same for the selected addon.
Acceptance:
- [unit] The creator filter matches the name whatever its case.
- [self] Shinni's name filters Installed to HarvestMap; on Find More it shows all Shinni's addons, HarvestMap included.
- [snap] Installed filtered to ziggr, with the chip.
Status: done

### S-064 Game Folder in four tabs
As the user, Game Folder has four tabs: Characters, Inspector, Problems, and Game Settings. The Addons tab is gone (an installed addon's search icon opens its files in the Inspector; the Characters grid's addon names still open one addon across every character), and so is Files: Folder, SavedVariables, and Space. Game Settings, which was inside Files, is its own tab. The tabs are ⌃⌘1 to ⌃⌘4 in toolbar order (Appearance moved to ⌃⌥⌘1–3), Compare Characters… is ⌃⌘C, and Save and Copy in Game Settings and Compare can be undone with ⌘Z. Clean Up… (⇧⌘T and the toolbar button) asks as before and opens Problems, where those files are listed.
Depends: S-053, S-059, S-062
Acceptance:
- [self] The tabs are exactly Characters, Inspector, Problems, Game Settings; the Characters tab starts at every character.
- [snap] The toolbar with four tabs; Game Settings on its own.
- [cli] `macminion sv biggest --by characters` still totals by character.
Status: done

### S-063 Unknown characters are a problem
As the user, Problems shows a Clean up card for each character ID that addons keep data for but no file names: "Data for an unknown character (8796093079837777)", which files hold it and how much, and that it's likely a character I deleted (or one that hasn't logged in since its name was last saved). Find Everywhere opens the Inspector on every place the ID appears. Agents get the same finding from `macminion sv problems`, with the action `findCharacter`.
Depends: S-052
Acceptance:
- [unit] One finding per unknown character across every file that keeps it, in Clean up, marked likely, with Find Everywhere.
- [self] The sample's nameless character is a Clean up finding; Find Everywhere lists where its data is.
- [snap] Problems with the unknown-character card.
Status: done

### S-062 Edit the game's settings files
As the user, Files › Game Settings shows UserSettings.txt, AddOnSettings.txt, and MachineSettings.txt as forms. Each field is edited the way its value reads: a switch for on/off settings, number fields, a color well for AARRGGBB colors, width × height for the resolution, pickers for the realm, the language, and the API version (named by update, from the ESOUI wiki), and text for the rest. AddOnSettings shows its headers, then each character's addons as switches. Edits are a draft: a dot and an undo arrow on each, a count beside Save (⌘S) and Revert (⌥⌘Z). Save refuses while ESO runs, backs up first, and rewrites only the changed lines, each with its own line ending. Backups now hold MachineSettings.txt too. Hover help explains curated high-value settings and their options; unknown keys have no tip. Sources: docs/research/SETTINGS-FILES.md.
Depends: S-028
Acceptance:
- [unit] Each value gets the editor that fits it; LastRealm and the API version are pickers with names.
- [unit] Saving rewrites only the changed lines and keeps CRLF and LF endings; with no edits the bytes come back the same.
- [unit] AddOnSettings reads its headers and each character's block, names with spaces included.
- [unit] Curated keys return hover help; unknown keys return none; AddOn character rows share one tip.
- [self] Saving is refused while the game runs; a save changes one line and keeps CRLF; an edit set back isn't an edit; backups hold MachineSettings.txt.
- [snap] UserSettings with one edit, and AddOnSettings with each character's addons.
Status: done

### S-061 An account's megaservers and a megaserver's characters
As the user, I click an account (@SOLAEGIS) over the Characters grid to see it with the megaservers it has characters on around it, then a megaserver to see that account's characters on it; a character opens their addons. Clicking a megaserver in the grid's header goes straight there.
Depends: S-054
Acceptance:
- [self] @SOLAEGIS › NA Megaserver holds that account's NA characters and none from EU.
- [snap] The account graph and the megaserver graph.
Status: done

## M11 Characters and addons

The Game Folder page leads with what your addons are set up to do, for which characters, and where a character is set up differently, from SavedVariables configuration only (never the addons' Lua code). File sizes move behind a Files tab. Grounded in a real folder: 13 addons keep settings per character, mostly for all 38; most per-character settings are the same everywhere (Dolgubon's Lazy Writ Creator: 4 of 55 differ), and shared settings carry the bulk (BeamMeUp 148, Wizard's Wardrobe 58).

### S-053 Lead with characters and addons
As the user, I open Game Folder on Characters; the tabs are Characters, Addons, Inspector, Problems, and Files, where Files holds the folder items, the SavedVariables list, and Space.
Acceptance:
- [snap] Characters is the first tab and the default; Files shows Folder, SavedVariables, and Space as its own segments.
- [self] Every action that opened Folder, SavedVariables, or Space still reaches them, and their menu items still work.
Status: done; superseded by S-064 (no Addons or Files tabs)

### S-054 Which addons keep settings for which characters
As the user, I see a grid of the addons that keep per-character settings (rows) by my characters (columns, by name): shaded by how many settings, outlined with a count where some are set differently from my other characters, empty where it has none. I dig down from there: a character (their addons around them, badged where different, with what's different beside), one character in one addon (their settings, odd ones highlighted with the usual value), and one setting across every character (a bar per value, with who has it). A path bar and Back (⌘[) climb out.
Screens: gameFolder, gameFolder-character, gameFolder-character-addon, gameFolder-setting
Depends: S-053
Acceptance:
- [unit] Per addon: its account-wide settings, and for each character its settings flattened to key paths (two levels into nested tables), with each one's value.
- [unit] A setting differs when not every character has the same value; a character's setting is odd one out when it isn't the most common value.
- [unit] Long encoded strings (LibCharacterKnowledge's packed knowledge) are data, not settings; tables keyed by a character's name count as that character's.
- [manual] On a real folder: 19 addons by 38 characters.
- [snap] The seed's grid, with Masisi's WritWorthy cell outlined.
Status: done

### S-055 An addon's settings, across characters
As the user, I open an addon and see how many settings are shared by every character, how many are the same on every character, and which are set differently, each with its values and how many characters have each one (in readable form: switches, colors, items, dates, gold); clicking a value lists the characters with it.
Depends: S-054, S-050
Acceptance:
- [unit] Value groups: every distinct value of a differing setting with the characters that have it, most common first; settings only some characters have are listed apart, with who.
- [snap] Dolgubon-style counts and value chips for the seed's WritWorthy.
Status: done

### S-056 A character's settings, across addons
As the user, I open a character and see which addons keep settings for them, what's set differently from my other characters (addon, setting, their value, the usual value), and addons that keep settings only for them, with a link to their connections map.
Depends: S-054, S-049
Acceptance:
- [unit] A character's odd-one-out settings across all addons, and the addons where they're the only character with settings.
- [snap] Masisi's page from the seed.
Status: done

### S-057 Compare two characters
As the user, I compare two characters (Compare With… on a character, or Compare Characters… ⌃⌘C) and see every setting, across all addons, where they differ, side by side and readable, then the settings only one of them has.
Screens: gameFolder-compare
Depends: S-054
Acceptance:
- [unit] The differing settings of two characters, grouped by addon; settings only one of them has are listed apart; a character compared with itself has no differences.
- [self] Masisi beside Alpha Top: Auto craft and Writ count differ in WritWorthy, Minimap pins in HarvestMap; Gold spent is Masisi's alone; the comparison is a level the path bar climbs out of.
- [snap] Masisi beside Alpha Top.
Status: done

### S-066 Compare two characters in one addon
As the user, from a character in one addon (Masisi › WritWorthy), I choose Compare With… another character and see only that addon's differing settings side by side, with the same Clone row and Clone all actions limited to that file. Full Compare With… on a character and Compare Characters… ⌃⌘C still cover every addon.
Screens: gameFolder-compare-addon
Depends: S-057, S-060
Acceptance:
- [self] From Masisi › WritWorthy, Compare With Alpha Top opens a scoped compare; Back returns to character-in-addon; scoped Copy All is only WritWorthy's differences; cloning clears those and leaves HarvestMap's differences.
- [snap] Masisi beside Alpha Top in WritWorthy only.

## Dropped
- WoW / WoWInterface support: ESO only.
- Login, account registration, cloud backup, SavedVariables sync: account and premium features.
- Install-later queue: tied to a website account.
- Google Analytics, news, spotlight, ads: exist for the vendor.
- Minion self-update: the app is built locally.

## Later
- Backup and restore of SavedVariables to a local zip.
- Dependency hints from `## DependsOn:` in manifests (offer missing libraries).
