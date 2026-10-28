# MacMinion

A native macOS SwiftUI addon manager for Elder Scrolls Online. It lets one player find, install, update and remove ESOUI addons without the bundled-JRE JavaFX Minion.

Bundle id: `com.solaegis.macminion` (decided by the agent; "Minion" is already taken by `/Applications/Minion.app`).

## Replaces
Minion 3.0.12 (`/Applications/Minion.app`, MMOUI/ESOUI, JavaFX + bundled JRE).

## Main jobs
1. **Installed**: see every addon in `~/Documents/Elder Scrolls Online/live/AddOns`, matched to its ESOUI entry, with the ones that are out of date flagged.
2. **Update**: update one addon or all of them (zip download → MD5 check → replace the folders).
3. **Find More**: search and browse the ESOUI catalog by category or sort (downloads, favorites, newest), read the details and changelog, then install.

## Data
Remote feeds (public, no login), from `https://api.mmoui.com/v3/game/ESO/`:
- `filelist.json`: catalog entries (UID, UICATID, UIName, UIAuthorName, UIVersion, UIDate, UIDir[], thumbs, download/favorite counts, compatibility).
- `filedetails/<uid>.json`: UIDownload, UIMD5, UIFileName, UIDescription (BBCode), UIChangeLog.
- `categorylist.json`: UICATID, UICATTitle, UICATICON.
Local state (JSON in Application Support):
- InstalledAddOn: uid, uiVersion, uiDate, md5, dirs[], ignored flag.
- Seeded once from `~/.minion/minion.xml` (`<addon uid md5 ui-version><dirs>`, plus ignored list), read-only.
- Settings: AddOns folder (default live, PTS selectable), auto-check interval.

## Shape
A sidebar window (Installed / Updates / Find More / categories), macOS 26 or later. Works offline from the cached catalog; it goes online only to refresh feeds and download. No accounts.

## System hooks
A menu bar extra showing the update count, with "Update All" (decided by the agent; this replaces Minion's tray icon). Opens addon pages on esoui.com in the browser.

## Reference
Minion 3.0.12. Its screens (Installed, Find More, Details, Options) are the reference, rebuilt in native style.

## Look
Native, using the system accent color. Standard sidebar, toolbar search and inspector-style details (decided by the agent).

## Not in version one
- WoW / WoWInterface support (ESO only).
- Login, cloud backup and SavedVariables sync (premium account features).
- "Install later" queue, analytics, news and spotlight home feed.
