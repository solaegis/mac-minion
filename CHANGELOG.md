# Changelog

What changed in each MacMinion release. The newest is first.

## Unreleased

- OpenAI is a third AI provider beside Ollama and Claude. Each provider keeps its own model and API key, keys are saved in the Keychain, Settings → AI shows a connection status, and the model field takes any ID or a list fetched with your key.
- About MacMinion and the docs credit MMOUI's Minion, ESOUI, and the addon authors.
- The `macminion` Claude Code skill loads without a YAML error.

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
