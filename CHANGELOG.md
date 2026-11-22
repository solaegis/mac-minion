# Changelog

What changed in each MacMinion release. The newest is first.

## Unreleased

## 0.7.0 — 2026-11-22

- Optional AI via Apple Intelligence on this Mac (Foundation Models): no API key, first-launch default when available; Ollama, Claude, and OpenAI stay as choices.
- Ask About Your Game Folder… (⌃⌘A): ask in plain words about characters, addon settings, and problems; Explain with AI on a problem; Allow Saved Values per provider (asked once a session). Explain Setting… shows what the addon's source says, with an optional AI paragraph that never reads saved values.
- Settings recommend an Ollama model that can look things up for Ask, and warn when the chosen one cannot.
- Characters, Compare, and the Inspector name settings the way each addon's settings panel does (tooltips, ranges, choices), from addon source and from what the companion saw in game; ability and champion-skill IDs get names after the next login. Problems flags saved numbers outside a slider's range.
- Show All Addons for settings a character runs on from defaults or account-wide tables; Clone which addons load between characters; Compare and Clone warn about odd values before writing.
- Companion page shows frame rate, latency, Lua memory, and load times; Problems re-reads after Clean Up, hides Lua errors fixed by an update, and notes out-of-date addons that still loaded.
- Guard every Lua SavedVariables write: re-parse before replace, refuse edits that change unexpected keys, refuse if the file changed since it was read, and keep one `*.lua.macminion.bak` beside the file. Companion request writes and Compare Clone share this path; refusals show on the Game Folder banner.
- Detect Elder Scrolls Online under CrossOver/Wine via `eso64.exe` on the process command line (not Steam or the Bethesda launcher alone), so MacMinion does not write companion requests while the game is up.
- Companion `lookups.requests` updates re-check that the spliced file still parses and that only those request paths changed.
- Overview remounts after Check for Updates or Update All; Find More no longer crashes when the kit string catalog is missing from the app bundle; Check for Updates, Update All, and Back Up Now from `macminion://` links or the Dock menu.

## 0.6.0 — 2026-11-11

- Polish after 0.5: OpenAI beside Ollama and Claude; Light, Dark, or Match System; Installed and Find More without quitting; community docs and GitHub templates; Buy Me a Coffee; UI in English, German, French, Spanish, and Russian; About and the docs credit Minion and the addon authors; the macminion skill loads cleanly.
- Keep checking for addon updates from the menu bar with the Dock minion glyph; at login it can start there with the window closed.
- Game Folder for SavedVariables: four tabs (Characters, Inspector, Problems, Game Settings); clean unused files; Find and connections; readable settings; characters, compare, and companion install; `macminion sv` on the command line.
- Compare two characters across every addon, or Compare With… from one character in one addon to clone only that file’s differences.
- Edit UserSettings.txt, AddOnSettings.txt, and MachineSettings.txt as forms; curated keys show hover help for what they do.
- Game Folder opens and updates faster with less memory, and its state lives in its own model.
- Dense windows stay readable; the page and selection come back at launch; layouts work at the minimum size; snapshots wait for a real key window and capture that size too.

## 0.5 — 2026-10-28

The first release: a native Mac addon manager for The Elder Scrolls Online.

- **Overview** of your addons: update history, stats, popular catalog picks, and libraries your addons need but lack, with Install and Install All. Reorder and hide its sections.
- **Installed** and **Find More** as a card grid or a list, with filters for category, status, update age, rating, game version, and libraries.
- **Update** one addon or all of them (⌘U), ignore updates for addons you pin, and install any older release ESOUI still has.
- **Remove** an addon, or a folder not on ESOUI, to the Trash. SavedVariables are left alone.
- **Backups** of SavedVariables, settings, and the addon list in Minion's own format, so either app restores the other's.
- **Minion import** on first launch: installed versions, ignored addons, and the update log.
- **Optional AI** with Ollama or Claude: changelog summaries, Recommended for You, plain-language catalog search, and thumbs up or down to steer them.
- Menu bar item with the update count and Update All, and a daily update check.
- `macminion` command line for scripts and agents.
- MacMinion updates itself with Sparkle 2 (EdDSA-signed releases).
