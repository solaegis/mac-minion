# The ESO `live` folder

Everything in `~/Documents/Elder Scrolls Online/live/` besides `AddOns`, what the game does with it, and what MacMinion may do. Sources: the ESOUI Wiki and community troubleshooting guides, checked against a real folder on this Mac (2026-10-29). Stories: S-028 to S-034.

Other servers have their own folders next to `live` (`liveeu`, `pts`). The game rewrites the settings files and SavedVariables while it runs and when it quits, so MacMinion changes nothing while ESO runs (`AppModel.isGameRunning`).

## Items

| Item | What it is | Missing? | MacMinion may |
|---|---|---|---|
| `UserSettings.txt` | Video, audio, and system settings as `SET KEY "value"` lines | Recreated with defaults | Back up, suggest changes to known keys, apply with a preview |
| `MachineSettings.txt` | A few renderer flags and the resolution | Recreated | Read only |
| `AddOnSettings.txt` | `#Version`, then a block per character (`#Default`, `#NA Megaserver-<name>`) of `<addon> 0/1` lines | Recreated; all addon choices reset | Back up, flag stale entries, copy one character's choices to another |
| `SavedVariables/` | One `<addon name>.lua` per addon whose manifest has `## SavedVariables:` (the line names the Lua variables inside, not the file), plus the game's own `ZO_*.lua` | Addon settings lost | Back up, show sizes, flag files named after no installed addon; never touch `ZO_*` |
| `ShaderCache.cooked`, `PipelineCache.esopc` | Compiled shaders, rebuilt at login after each update | Rebuilt in a few minutes | Move to Trash to fix stutter or glitches after a patch |
| `CachedData/` | Game cache settings | Recreated | Leave alone |
| `GuildHistory/` | Guild history cache, also read by addons | **The game does not recreate the folder** | Clear its contents after confirmation; never remove the folder |
| `Logs/` | `client.log`, `interface.log` | Recreated | Show, open, clear |
| `Errors/` | Crash dumps sent to ZOS | Recreated | Show, clear |
| `Screenshots/` | The player's screenshots | — | Show, move to another folder; never delete |

## Rules

- Nothing is deleted outright: removed files go to the Trash, after a backup when they hold settings.
- AddOns are found up to three folders deep, as the game does; an addon's name is its manifest name (`<Folder>/<Folder>.txt` or `.addon`).
- Characters are never known for sure from files alone: a block for a deleted character looks like any other. The user decides which to remove.

## On this Mac (2026-10-29)

- Apple M2 Ultra, 76 GPU cores, 5120×1440 fullscreen, settings near maximum.
- `SavedVariables`: 104 MB in 147 files; 52 hand-made `.bak` files (28 MB) inside it, and a 57 MB `SavedVariables.bak-prune-*` folder beside it. Matching file names to top-level folders flags 38 files, wrongly: GS00–17Data and HarvestMapAD are addons nested inside LibGuildStore and HarvestMap. Matched against manifest names up to three folders deep, only 2 files (424 KB) belong to no installed addon: EsoSocial and IJA_FavCollectibles_Saves. The clutter is the hand-made copies (85 MB), not orphans.
- Largest files: TamrielTradeCentre 16.7 MB (price table, replaced by its client), GS16Data 6.8 MB, CraftStoreFixedAndImproved 4.1 MB, IIfA 3.5 MB, LibDebugLogger 1.9 MB (a log, trimmed in that addon's settings).
- `AddOnSettings.txt`: 33 character blocks (20 NA, 13 EU); 4 entries name addons that are no longer installed (AutoDailyRewards, ESODatabaseExport, EsoSocial, _0_MapAPI). Four hand-made `.bak` copies beside it.
- `UserSettings.txt`: `USE_BACKGROUND_FPS_LIMIT "0"` (full speed while in the background), `MinFrameTime.2 "0.01"` (100 fps cap) with VSync on.
- `Logs/interface.log` is 72 KB, not empty as the guides say.

## Cleaned up (2026-10-29)

After a MacMinion backup (`~/.minion/minion-backups/ESO-1/2026-10-29.zip`, 295 files), everything below went to the Trash: the top-level `.bak` copies and backup folders (from the Game Folder page), 53 copies in SavedVariables (31 MB including the two stale files), and the stale EsoSocial and IJA_FavCollectibles_Saves files. The 48 `AddOnSettings.txt` lines naming the 4 uninstalled addons were removed from the file. SavedVariables is a git repository (`.git`, `.gitignore`, `README.md`); those stay, and the scan leaves non-`.lua` files like the README alone. `TitleStorage` is the game's own (empty) folder.
