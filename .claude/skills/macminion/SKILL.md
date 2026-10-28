---
name: macminion
description: Drive the MacMinion app on this Mac from the shell with the `macminion` command: list installed Elder Scrolls Online addons and pending updates, search the ESOUI catalog, install, update, ignore, or remove addons, and summarize changelogs with the configured AI. Use when the user asks about their ESO addons, ESOUI, Minion, or MacMinion.
---

# MacMinion

`macminion` runs commands in the MacMinion app (a native replacement for Minion). Changes show in its
window at once. If the app is closed, the command opens it in the background. Addons are named by their
ESOUI id: the number in `esoui.com/downloads/info<id>`.

## Rules

- Always add `--json` and read the JSON. Exit 0 is ok; otherwise read `error.code` and `error.message`,
  and do what the message says.
- Find ids with `macminion addons list --search T` (installed) or `macminion catalog search T` (ESOUI).
- `addons remove` only reports what it would move to the Trash. Show the user that report and ask
  before you run it again with `--yes`.
- Installs and updates write to the live AddOns folder. Ask before `addons install` or `updates install`
  unless the user asked for that change.
- `addons summarize` and `updates summarize` send changelog text to the AI provider in Settings
  (Ollama on this Mac, or Claude). They can take a minute on a local model.
- To try something without real data, put `APP_STORE=/tmp/macminion-test` in front of the command.

## Main commands

| Command | Does |
| --- | --- |
| `macminion status --json` | Folder, catalog age, counts of installed addons and updates |
| `macminion addons list [--status update] [--search T] --json` | Installed addons and their versions |
| `macminion catalog search T [--sort monthly] [--limit N] --json` | Find addons on ESOUI |
| `macminion addons install <id> --json` | Install, update, or reinstall one addon |
| `macminion updates install --json` | Update everything that has an update |
| `macminion addons summarize <id> --json` | What changed since the installed version |
| `macminion addons recommend [--refresh] --json` | Addons that would add something to what is installed |
| `macminion catalog ask "what you want" --json` | AI search of the catalog in plain words |
| `macminion addons rate <id> up\|down\|none --json` | Thumbs up or down; steers recommendations and search |
| `macminion addons versions <id> --json` / `addons install <id> --version V` | Older releases; installing one pins it |
| `macminion ai models --json` | Ollama models ranked for this Mac, with the recommended one |
| `macminion ai benchmark --json` | Measure the top three models' speed here, then recommend again |
| `macminion backups list --json` / `backups create` | Minion-format backups of SavedVariables, settings, and the addon list |
| `macminion backups restore <name> [--remove-others] --yes --json` | Restore one; reports first without `--yes`; saves the current state first |
| `macminion open <page> [--addon <id>]` | Show overview, installed, updates, or findMore |

Everything else: `macminion help`, and `macminion help <command>` for its options.
