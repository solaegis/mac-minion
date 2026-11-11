# The game's settings files

ZeniMax publishes no schema for these files. What MacMinion knows comes from:
- the ESOUI wiki, read on 2026-11-09 (sources at the end)
- the shape of the values in a real live folder (this Mac, 2026-11-09)

## The three files

| File | Format | Line endings here | Notes |
| --- | --- | --- | --- |
| `UserSettings.txt` | `SET <Key> "<value>"`, one per line, 284 lines | CRLF | The machine-specific part of the in-game settings: video, audio, input, camera. The wiki says changes are overwritten while the game runs. |
| `MachineSettings.txt` | `SET <Key> "<value>"`, 7 lines | LF | Renderer flags and `RESOLUTION`. Not on the wiki's UserFolder page, but present in this live folder. |
| `AddOnSettings.txt` | `#Header value` lines, then one block per character: `#Default` or `#<Megaserver>-<Character>`, followed by `<AddonFolder> 0/1` lines | LF | Which addons load for which character. Changes are overwritten while the game runs. |

### AddOnSettings.txt headers
- `#Version 101051`: the API version the file was written under.
- `#AcknowledgedOutOfDateAddonsVersion 101051`: the API version for which the player last acknowledged the out-of-date addons warning.
- `#AddOnsEnabled 1`: the master switch for loading addons.
- A block header is a `#` line with no known header name, for example `#Default` or `#NA Megaserver-Spymaster Walsingham`. The character name can contain spaces.

## How a field's type is chosen
MacMinion keeps a short curated list for keys whose values it knows. Every other key gets its type from its current value:

| Value | Shown as |
| --- | --- |
| A key named `…Enabled`, `Use…`, `Show…`, `Invert…`, `Enable…`, `Is…`, with value `0`/`1` | Toggle |
| Integer (`60`, `-1`) | Whole-number field |
| Decimal (`0.85000002`) | Number field |
| 8 hex digits (`ffa4ecee`) | Color well (AARRGGBB) |
| `<w>x<h>` (`5120x1440`) | Width × height |
| Anything else | Text |

Curated keys:

| Key | Choices | Source |
| --- | --- | --- |
| `LastRealm` | NA Megaserver, EU Megaserver, PTS | `GetWorldName()` values on the wiki's APIVersion page |
| `Language.2`, `LastValidLanguage`, `LastPlatformLanguage` | en, de, fr, es, ru, jp, zh | the client's languages (plus whatever the file holds) |
| `#Version`, `#AcknowledgedOutOfDateAddonsVersion` | the API versions below, by update name | wiki APIVersion page |

## API versions (wiki APIVersion page)
The scheme changed after 100035: `101031` lines up with game version 7.1.

| API | Game version and name |
| --- | --- |
| 101052 | 12.2.0 "2026 Season 2 – Patch 52 – Echoes of Skyrim" (PTS; live January 19, 2027) |
| 101051 | 12.1.0 "2026 Season 1 – Patch 51" (live September 28, 2026) |
| 101050 | 12.0.0 "2026 Season 0 – Part 2" |
| 101049 | 11.3.0 "2026 Season 0" |
| 101048 | 11.2.0 "Season of the Worm Cult Part 2" |
| 101047 | 11.1.0 "Feast of Shadows" |
| 101046 | 11.0.0 "Seasons of the Worm Cult Part 1" |
| 101045 | 10.3.0 "Fallen Banners" |
| 101044 | 10.2.5 |
| 101043 | 10.1 |
| 101042 | 10.0 "Gold Road" |
| 101041 | 9.3.5 "Scions of Ithelia" |
| 101040 | 9.2 "Secret of the Telvanni" |
| 101039 | 9.1.5 |
| 101038 | 9.0 "Necrom" |
| 101037 | 8.3 "Scribes of Fate" |
| 101036 | 8.2 "Firesong" |
| 101035 | 8.1.5 "Lost Depths" |
| 101034 | 8.0 "High Isle" |
| 101033 | 7.3 "Ascending Tide" |
| 101032 | 7.2 "Deadlands" |
| 101031 | 7.1 "Waking Flame" |
| 100035 | 7.0 "Blackwood" |
| 100034 | 6.3.0 "Flames of Ambition" |
| 100033 | 6.2.0 "Markarth" |
| 100032 | 6.1.0 "Stonethorn" |
| 100031 | 6.0.0 "Greymoor" |
| 100030 | 5.3.0 "Harrowstorm" |

Older versions, down to 100003 (release, 1.0), are on the wiki page.

## Writing safely
- The game overwrites these files from memory while it runs and when it quits, so MacMinion refuses to save while ESO is running.
- MacMinion backs up first. Backups hold `AddOnSettings.txt`, `UserSettings.txt` and, from this change on, `MachineSettings.txt`.
- Only changed lines are rewritten. Each line keeps its own ending (CRLF or LF), and lines MacMinion doesn't understand stay byte for byte.

## Sources
- https://wiki.esoui.com/APIVersion: API version history, `GetWorldName()` values.
- https://wiki.esoui.com/UserFolder: what each file in the user folder is for, and that the game overwrites them while running.
