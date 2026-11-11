# Changelog

What changed in each MacMinion release. The newest is first.

## Unreleased

- Polish after 0.5: OpenAI beside Ollama and Claude; Light, Dark, or Match System; Installed and Find More without quitting; community docs and GitHub templates; Buy Me a Coffee; UI in English, German, French, Spanish, and Russian; About and the docs credit Minion and the addon authors; the macminion skill loads cleanly.
- Keep checking for addon updates from the menu bar with the Dock minion glyph; at login it can start there with the window closed.
- Game Folder for SavedVariables: clean unused files; Inspector, Find, Problems, and space; readable settings; characters, compare, and connections; companion install and what it recorded; `macminion sv` on the command line.
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
