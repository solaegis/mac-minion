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
UX: Provider choices read "Off", "Ollama (on this Mac)", "Claude". AI is off until chosen.
Status: done

### S-014 Settings for updates, the app, and AI
As the user, I set how often MacMinion checks, whether it installs updates itself, how many download at once, notifications, the menu bar item, open at login, and the AI provider.
Screens: settings-general, settings-updates, settings-ai
Acceptance:
- [snap] Tabs: General, Updates, AI, Appearance.
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
As the user, I see on the Overview, right under the banner, the libraries my addons ask for that I don't have: required ones flagged first, then optional ones, each with the addons that want it, Install, and Install All.
Acceptance:
- [unit] Read from every manifest's DependsOn and OptionalDependsOn; optional ones must be ESOUI libraries; LibStub and names not on ESOUI are left out.
- [unit] A library bundled inside another addon (up to three folders down, with its own manifest) counts as installed, as the game loads it.
- [self] Each row has thumbs; an optional library with a thumbs down is hidden for good, a required one always shows.
- [self] Install All installs them and the card disappears.
Status: done

## M6 Polish

### S-011 App icon and empty states
Acceptance:
- [snap] The Dock icon is a one-eyed red creature with a fanged grin, after Minion's icon, as two glass layers (eye, grin).
- [snap] Empty Installed shows "No addons found in <folder>" plus a "Choose Folder…" button.
- [manual] The icon matches the native style.
Status: todo

## Dropped
- WoW / WoWInterface support: ESO only.
- Login, account registration, cloud backup, SavedVariables sync: account and premium features.
- Install-later queue: tied to a website account.
- Google Analytics, news, spotlight, ads: exist for the vendor.
- Minion self-update: the app is built locally.

## Later
- Backup and restore of SavedVariables to a local zip.
- Dependency hints from `## DependsOn:` in manifests (offer missing libraries).
