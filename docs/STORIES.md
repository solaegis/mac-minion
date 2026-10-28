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
Status: todo

### S-002 See installed addons
As the user, I open Installed and see every addon in my AddOns folder, matched to ESOUI.
Screens: installed
Depends: S-001
Acceptance:
- [unit] Folders are matched by UIDir; an addon counts as installed when all its UIDir folders exist; nested `Libs` are ignored.
- [unit] Install records are seeded once from `~/.minion/minion.xml` (uid, ui-version, md5, dirs, ignored).
- [snap] The table shows Name, Author, Installed, Latest, Status; unmatched folders show a manifest title and "Not on ESOUI".
UX: Status badge words are "Up to date", "Update available", "Ignored", "Not on ESOUI".
Status: todo

### S-003 Update one addon
As the user, I click Update on a row and the addon is replaced with the latest version.
Screens: installed, updates
Depends: S-002
Acceptance:
- [unit] The zip is downloaded from UIDownload, its MD5 checked against UIMD5, unzipped to a temp folder, and each top-level folder replaces the matching folder in AddOns.
- [unit] A failed MD5 check or unzip leaves the existing folders untouched.
- [self] A progress indicator shows on the row; on success the row reads "Up to date".
Status: todo

### S-004 Update all
As the user, I press Update All (⌘U) and every addon with an update (that isn't ignored) is updated, two at a time.
Screens: updates
Depends: S-003
Acceptance:
- [unit] Update All runs at most 2 concurrent downloads.
- [self] The toolbar shows "Updating 3 of 12…"; errors are listed per addon and don't stop the rest.
Status: todo

### S-005 Search and install
As the user, I search Find More, select an addon and press Install.
Screens: find-more, details
Depends: S-001, S-003
Acceptance:
- [unit] Search matches name and author, case- and diacritic-insensitive.
- [snap] The details pane shows thumbnail, author, version, date, downloads, favorites, compatibility, description (BBCode to plain text) and changelog.
- [self] Install writes the folders and the addon then appears in Installed.
UX: The primary button reads "Install", "Update" or "Reinstall" depending on state; "Open on ESOUI" is secondary.
Status: todo

### S-006 Remove an addon
As the user, I choose Remove… from a row's context menu and confirm, and its folders are moved to the Trash.
Screens: installed
Depends: S-002
Acceptance:
- [unit] Folders are moved to the Trash (recoverable), never hard-deleted; SavedVariables are left alone.
- [self] A confirmation alert names the folders: "Move “HarvestMap” to the Trash?".
Status: todo

### S-007 Ignore updates for an addon
As the user, I toggle "Ignore Updates" on a row, so Update All skips it.
Screens: installed
Depends: S-002
Acceptance:
- [unit] Ignored state persists and is excluded from the update count.
Status: todo

## M2 Organize

### S-008 Browse by category
As the user, I pick a category in the sidebar's Find More section and see only those addons, sorted by downloads, favorites, newest or name.
Screens: find-more
Acceptance:
- [unit] Category filter includes child categories (UICATParentIDs).
- [snap] Sort picker in the toolbar.
Status: todo

### S-009 Choose the AddOns folder
As the user, I choose live or PTS (or any folder) in Settings.
Screens: settings
Acceptance:
- [unit] Changing the folder rescans Installed.
- [self] The default is the live folder when it exists.
Status: todo

## M5 System

### S-010 Menu bar update count
As the user, I see the number of available updates in the menu bar and can run Update All from there.
Screens: menubar
Depends: S-004
Acceptance:
- [self] The MenuBarExtra shows a count badge, "Update All", "Open MacMinion", and "Check for Updates".
- [unit] Auto-check runs on a timer (default every 60 min).
Status: todo

## M6 Polish

### S-011 App icon and empty states
Acceptance:
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
