# MacMinion

A native macOS addon manager for The Elder Scrolls Online.
Find, install, update, and remove [ESOUI](https://www.esoui.com) addons without the Java Minion app.

![MacMinion Overview showing addon counts, update history, and popular addons](docs/images/overview.png)

MacMinion runs on this Mac only. There is no account and no server of its own. It reads your AddOns folder, matches folders to the public ESOUI catalog, and downloads zips when you install or update.

## Features

- **Overview** of how your addons stand, with recent activity and popular catalog picks; show, hide, and reorder its sections
- **Installed** list or card grid, matched to ESOUI (unmatched local folders stay visible)
- **Updates** for one addon or all of them (⌘U), two downloads at a time by default
- **Find More** to search and browse the catalog, read details and changelogs, then install
- Filters on Installed and Find More: category, status, update age, rating, current game version, and libraries
- Ignore updates for addons you want to pin; Update All skips them
- Remove an addon to the Trash; SavedVariables are left alone
- Install any older release ESOUI still has (Version menu in an addon's details); older versions are pinned
- Backups of SavedVariables, settings files, and the addon list, in Minion's own format and folder, so either app restores the other's (Backups in the sidebar, ⌘B)
- Live or PTS AddOns folder (or any folder you choose)
- Menu bar extra with the update count and Update All
- Checks ESOUI for updates once a day by default (Settings → Updates)
- Optional AI, via Ollama on this Mac or Claude:
  - changelog summaries for one addon or every pending update
  - **Recommended for You** on the Overview: addons that would add something to the ones you have
  - a search bar on the Overview that finds addons from a description in your own words
  - thumbs up and down on any addon steer both; a thumbs down keeps that addon out of them
  - for Ollama, a model recommendation for this Mac from the models on your server, using its memory, what is loaded, and a speed benchmark

ESO only. No WoW catalog, no login, and no cloud backup or SavedVariables sync.

![Installed addons in a card grid with details and an Update button](docs/images/installed.png)

## Requirements

- macOS 26 or later, Apple Silicon
- The Elder Scrolls Online AddOns folder (default `~/Documents/Elder Scrolls Online/live/AddOns`)
- Xcode 26 or later (Swift 6.2) only if you build from source

## Install

### Download (Apple Silicon)

1. Open the [latest GitHub Release](https://github.com/solaegis/mac-minion/releases/latest).
2. Download `MacMinion-*-macos-arm64.zip`.
3. Unzip and drag `MacMinion.app` into `/Applications` or `~/Applications`.
4. Open it the first time with a right-click → **Open**.

The release is ad-hoc signed (there is no Apple Developer ID), so macOS treats a download from the internet as unsigned. That first-open step is expected. If macOS still blocks it, use System Settings → Privacy & Security → **Open Anyway**, or:

```bash
xattr -cr ~/Applications/MacMinion.app
open ~/Applications/MacMinion.app
```

To put the CLI on your PATH after a download:

```bash
mkdir -p ~/.local/bin
ln -sf ~/Applications/MacMinion.app/Contents/MacOS/MacMinion ~/.local/bin/macminion
```

### Build from source

```bash
git clone https://github.com/solaegis/mac-minion.git
cd mac-minion
./build.sh --open
```

That installs `~/Applications/MacMinion.app` and a `macminion` link in `~/.local/bin`. To stop macOS asking for Documents access after every build, create a local signing identity once with `tools/make-signing-identity.sh`; `build.sh` uses it from then on. The build signs with your Apple Development certificate when Xcode has one, otherwise ad hoc. An app you build on this Mac is not quarantined, so it usually opens without the Gatekeeper step.

## Use

- **Overview**, **Installed**, **Updates**, and **Find More** in the sidebar
- **Update All** with ⌘U; **Check for Updates** with ⌘R
- Switch Installed and Find More between grid and list from the toolbar, or Option-⌘-1 / Option-⌘-2
- Menu bar item: update count, Update All, Open MacMinion
- Settings (⌘,): General, Updates, Layout, AI, Appearance

## Coming from Minion

On first launch MacMinion reads `~/.minion/minion.xml` once (installed versions, ignored addons, and Minion’s update log). Minion’s own files are not changed. Settings → General → **Import from Minion** runs that import again.

Turn off Minion’s auto-update so the two apps do not both write to AddOns.

## Privacy

State lives in `~/Library/Application Support/MacMinion/` (install records and a cached catalog). MacMinion has no account. It goes online only for public ESOUI feeds (`https://api.mmoui.com`) and addon zip downloads. Summaries stay off until you pick Ollama or Claude in Settings → AI; a Claude API key is stored in the Keychain.

## Command line

`./build.sh` also links `macminion` on your PATH. Run `macminion help` for commands such as `status`, `addons list`, `catalog search`, `updates install`, `addons recommend`, and `ai benchmark`. Add `--json` for agents. The app must be running (or the command will launch it). `.claude/skills/macminion/SKILL.md` teaches Claude Code the commands.

## Help

[Open an issue](https://github.com/solaegis/mac-minion/issues) on this repository.

## License

Copyright Lewis Vavasour. MacMinion is licensed under the [PolyForm Noncommercial License 1.0.0](LICENSE). You may use it for personal, noncommercial purposes. Commercial use needs permission. The copyright stays with the author, who may offer other licenses later.
