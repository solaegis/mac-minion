# Architecture review — 2026-11-10

Check-in one day after `docs/architecture-review-2026-11-09.md`. Three of that
review's cards are done (Backup Restore, Copy Settings writes, Inspector
navigation, all in Kit). This survey looks at what is left; its Game Folder card
continues here as cards 1 and 2.

## Survey (what the code looks like today)

- Targets unchanged and clean: `MacMinionKit` (no SwiftUI) ← `MacMinion` (app,
  MainActor by default) + Sparkle. One protocol, `LLMProvider`, with real and
  fixture adapters. No drifted `private struct` copies.
- `AppModel` in `Models.swift`: 1,250 lines, 153 stored or computed properties,
  55 methods, plus 17 `extension AppModel` blocks in 11 view files.
- Game Folder is still the bulk of it: `Models.swift` lines 708–809 hold about
  60 Game Folder properties, and about 720 lines of its logic sit in extensions
  inside `InspectorView`, `InspectorFind`, `ProblemsView` (4 blocks),
  `ConnectionsView`, `CharactersExplorer` (2), `CharacterCardsView`,
  `GameSettingsView` (2), and `GameFolderView`.
- Hot spots, 30 days: `SelfTest.swift` 63 commits, `Models.swift` 57,
  `InspectorView.swift` 39, `Snapshot.swift` 28, `ContentView.swift` 26.
- Over 1,000 lines (the "act" line): `Models.swift` 1,250,
  `CharactersExplorer.swift` 1,062, `SelfTest.swift` 1,033. Over 600:
  `ContentView` 798, `OverviewView` 782, `InspectorView` 675, `SettingsView` 637,
  `ProblemsView` 612.
- `SelfTest.swift` is one function: 272 checks inside a single
  `Task` closure about 1,000 lines long.
- Main-thread file work that remains: Game Settings load and save
  (`GameSettingsView.swift:7`, `:50`), file undo (`:73`), and the small JSON
  state files in `App.swift`. All are small files.

---

## 1. SavedVariables read held as one value  [Strong] — done

Done 2026-11-10 in one commit. `SavedVariablesRead` (app, `GameFolder/`) holds the read's fields itself,
not Kit's `SVFolderRead` whole: the self-test edits one character's name, and Kit's fields are `let`.
`AppModel.svLastRead` is the last read and `svReadIsCurrent` says whether the files have changed since;
`svRead` is nil when they have. Names, references, problems, usage, the matrix, and addon folders read
`svRead`. The graph, roster, top folders, and read time read `svLastRead`, as they did before: they
stay while the files are read again. Whether they should is still open.
Proof: 163 unit tests and all 272 self-test checks pass before and after, with the same self-test
output. The window opened at a different size in the two snapshot runs, so the Game Folder pages were
compared by eye, not by pixels. One snapshot changed: `gameFolder-loading` shows "Problems (3)" where it
showed "Problems (10)". The snapshot used to hide only the matrix, a state the app never reaches; it
now sets the whole read aside, as a file change does.

Files: `InspectorView.swift` (`loadInspectorNames`, `readInspectorData`, lines
47–109), `GameFolderView.swift` (`scanGameFolder`, lines 33–54), `Models.swift`
(lines 716, 764–797), `Snapshot.swift:88–93`.
Signal: Pure bookkeeping in a `@MainActor` store; one feature's state spread
over a god model.
Problem: Kit already returns the read as one value (`SVFolderRead`: names,
references, problems, usage, matrix, roster, graph). The store unpacks it into
10 separate optionals, one assignment each. "Is it loaded" is a five-way nil
check (`InspectorView.swift:50`). Throwing it away is six assignments in
`scanGameFolder`, and they do not match the ten that were set: after the files
change, `inspectorGraph`, `inspectorRoster`, `inspectorTopFolders`, and
`inspectorReadAt` keep values from the old files while the other six are nil.
A new read result has to be added in four places, and forgetting the clear is
silent.
Proposal:
```swift
// Sources/MacMinion/GameFolder/SavedVariablesRead.swift (app target)
struct SavedVariablesRead {
    var folder: SVFolderRead            // Kit's result, kept whole
    var topFolders: [String: String]    // from SavedVariablesAudit.index
    var addonFolders: [String: URL]
    var at: Date
}
// AppModel
var svRead: SavedVariablesRead?         // nil: not read, or the files changed
var inspectorNames: SVNameIndex? { svRead?.folder.names }   // and the other nine,
                                                            // as names over svRead
```
The old names stay as read-only names over `svRead`, as `inspectorRoots` did
over `inspectorCursor`, so about 100 readers do not change. `Snapshot.swift`
sets `settingsMatrix` directly; that one name keeps a setter.
Benefits: Locality: loaded is `svRead != nil`, cleared is `svRead = nil`, and a
new result is one field. Views get one change per read, not ten. It is also the
first slice of card 2, so no work is thrown away.
Proof of same behavior: `tools/selftest.sh` (272 checks) before and after;
`tools/snap.sh` Game Folder pages compared before and after; unit tests
unchanged (Kit is not touched).
Open point to settle in the step, not before: whether graph, roster, and top
folders must stay readable between a file change and the next read. If a view
depends on that, those three keep their last value on purpose, with a comment
that says so.
Plan: (1) add `SavedVariablesRead` and `svRead`, switch the ten properties to
names over it, one clear and one loaded check; (2) update `ARCHITECTURE.md`.

## 2. Game Folder model out of AppModel  [Strong, large] — done

2026-11-10, three commits: `AppModel.gameFolder` (the path) became `gameFolderURL`; `GameFolderModel`
(`model.gameFolder`, `unowned let app`) took the SavedVariables read and its loading (`names`, `matrix`,
`svProblems`, `usage`, `load()`, and the rest; 96 references); then the Inspector's open file, cursor,
selection, and their methods (149 references), which keep their `inspector…` names. Three view bindings
became `Bindable(model.gameFolder).…`. Proof after each commit: the same 272 self-test lines; after the
last, 163 unit tests, the lints, and the Inspector snapshots compared by eye (the window size still
differs between runs). `Models.swift` is 1,203 lines and `InspectorView.swift` 541.
Then two more commits: Find with its result types and `reveal(file:path:)` (61 references), and names
from source and AI (23 references), each in its own `GameFolderModel+….swift`. Same proof: 272
self-test lines after each, 163 unit tests, lints, and the Find and source-names snapshots by eye.
`InspectorView.swift` and `InspectorFind.swift` now hold views only.
Then Problems (findings, their buttons, the filters, and the links from other pages; 123 references)
and Connections (40), one commit each, with the same proof. `installedAddon(folder:)`,
`libraries(for:)`, and `selectedAddonLinks` stayed on `AppModel`: they are about installed addons.
`pendingTrash` stays until scan and tidy moves. `ProblemsView.swift` and `ConnectionsView.swift` hold
views plus that one small `AppModel` extension. `Models.swift` is 1,177 lines.
Last, one commit each: Characters, Compare, and Copy Settings (116 references); Game Settings and file
undo (38); and the scan, Clean Up, `savedVariables`, the tab, and the page's messages (102), where
`gameFolderTab`, `gameFolderMessage`, `gameFolderError`, and `scanGameFolder` became `tab`, `message`,
`errorMessage`, and `scan`. `AppModel` keeps no Game Folder state: only `gameFolderURL`,
`gameIsRunning`, the companion snapshot, and addon names (`addonName`, `addonTitle`, `byName`).
Final proof: 272 self-test lines the same after every commit, 163 unit tests, the lints, the agent CLI
check (`check-agent-cli.sh macminion`, all PASS), and the Characters, Compare, and Game Settings
snapshots by eye. `Models.swift` is 1,156 lines (from 1,250); the eight Game Folder view files hold
views only, apart from two small `AppModel` extensions about addons.
Not done: the `inspectorRoots`/`Focus`/`Rows` names over the cursor are still there. Then drop the `inspectorRoots`/`Focus`/`Rows` names over the cursor.

Files: `Models.swift` (lines 708–809), the 13 extension blocks listed in the
survey, and every reader: `SelfTest.swift` (120 uses of
`model.inspector…`/`gameFolder…`/`problems…`), `InspectorView` 84,
`Snapshot` 22, `ReadableSheetView` 22, `ProblemsView` 11, `AgentSVCommands` 10,
and 10 more files.
Signal: God model; a type far over 400 lines; one feature in 8+ files; the
three hottest source files are all part of it.
Problem: Unchanged from 2026-11-09. Adding one Inspector feature means storage
in `Models.swift` and logic in a view file, and every Game Folder method can
reach installs, backups, and AI.
Proposal: `@Observable final class GameFolderModel` at `model.gameFolder`, in
`Sources/MacMinion/GameFolder/`. Two interfaces were weighed:
- Values and closures in `init` (addons folder, `gameIsRunning`, `backUp`). A
  real seam, but the app target has no unit tests, so it would have one adapter.
- `unowned let app: AppModel` back-reference. Not a seam, but the move is
  mechanical and honest about the coupling. **Pick this one**; narrow it later
  if a second adapter appears.
`AppModel.gameFolder: URL` is renamed `gameFolderURL` first to free the name.
Benefits: `Models.swift` drops about 100 lines of storage and the view files
drop about 720 lines of model logic into one folder. Game Folder changes stop
touching `Models.swift`.
Proof of same behavior: selftest, all snapshots, `check-agent-cli.sh macminion`
for the `sv` commands, after every commit.
Plan: one moved group per commit, each under about 10 files where possible:
read results (card 1) → Inspector file and cursor → Find → Problems →
Connections → Characters and Compare → Game Settings → scan and tidy. The
SelfTest renames ride with each group. Several sessions.

## 3. Self-test split by feature  [Worth exploring] — done

Done 2026-11-10 in one commit: 22 functions in six files under `SelfTest/` (Addons, Backups, Inspector,
Problems, Characters, App), called in the old order from `SelfTest.swift` (69 lines). The move was
mechanical; only S-061 needed its own copy of a character ID. Proof: the 272 PASS lines are the same,
in the same order, before and after. One difference: the language checks' `defer`, which puts back
`AppleLanguages` and the saved language, now runs when `appearance` returns. Before, it sat at the end
of the closure, after `NSApp.terminate`, which normally does not return, so it likely never ran.
An area still cannot be run alone: later areas lean on earlier ones.

Files: `SelfTest.swift` (1,033 lines, 63 commits in 30 days).
Signal: Over 1,000 lines; the most-edited file in the repo.
Problem: 272 checks live in one closure. Every story edits the same function,
later checks lean on state earlier ones left behind, and one failing area
cannot be run alone.
Proposal: `SelfTest/` with one `static func` per area taking the model
(`catalog`, `installs`, `backups`, `gameFolder`, `inspector`, `problems`,
`characters`, `ai`), called in today's order from `runIfRequested`.
Benefits: Smaller diffs, and card 2's renames land in the matching file. No
design change.
Proof of same behavior: the same 272 check names print in the same order;
compare the output before and after with `diff`.
Plan: one commit per area moved. Best done before card 2's larger groups.

## 4. Game Settings save through the Kit file-edit operation  [Speculative]

Files: `GameSettingsView.swift` (lines 35–81).
Signal: File I/O in a `@MainActor` method.
Problem: Save reads and writes on the main thread, and file undo writes with
`try?` and then says "Undid" whether or not the write worked. The files are a
few kilobytes, so the window does not stall.
Proposal: reuse `SVEdit.apply(toFiles:)`'s `FileEdits` shape for the write and
the undo, and report undo failures.
Benefits: One write-and-undo path for Copy Settings and Game Settings.
Note: the silent undo failure is a small bug, not a refactor. It should get its
own fix commit and a `docs/FIXLOG.md` entry if it is confirmed.

## 5. Split the long view files by screen  [Speculative]

Files: `CharactersExplorer.swift` (1,062), `ContentView.swift` (798),
`OverviewView.swift` (782).
Unchanged from 2026-11-09: long, but sets of independent private views.
`CharactersExplorer` loses about 130 lines to card 2 on its own.

## Top recommendation

**Card 1 (done), then card 2 in groups.** Card 1 is small (about 4 files, one commit
plus the doc), removes a real inconsistency, and is the first group of card 2
anyway. Card 3 is a sensible detour before card 2's bigger groups, since every
group renames lines in `SelfTest.swift`.

## Considered, not recommended

- **Closure seam for `GameFolderModel`**: one adapter today; see card 2.
- **Protocols for MMOUI or the installer**: same answer as 2026-11-09.
- **Moving the `App.swift` state-file reads off the main thread**: small JSON
  files read once at launch and written rarely.
- **Splitting `SettingsView.swift`**: one tab per topic already.

