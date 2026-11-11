# Architecture review — 2026-11-09

Survey only; no code changed. There is no `ARCHITECTURE.md`, `docs/adr/`, or
`docs/FIXLOG.md` yet.

## What the code looks like today

- Two targets: `MacMinionKit` (no SwiftUI, 19 test files, ~150 tests) and
  `MacMinion` (app, `defaultIsolation(MainActor)`, depends on Kit + Sparkle).
  Dependency direction is clean: Kit never imports the app.
- One `@Observable` store, `AppModel`, declared in `Models.swift` (1,259 lines,
  ~290 `var`/`let`) and extended in **13 other files** (`InspectorView`,
  `ProblemsView`, `CharactersExplorer`, `GameFolderView`, `GameSettingsView`,
  `ConnectionsView`, `InspectorFind`, …), ~1,000 more lines of model logic
  living inside view files.
- Hot spots (30 days): `SelfTest.swift` (61 commits), `Models.swift` (53),
  `InspectorView.swift` (38), `ContentView.swift` (25).
- Files over 600 lines: `Models.swift` 1,259 · `CharactersExplorer.swift` 1,076 ·
  `SelfTest.swift` 1,031 · `ContentView.swift` 794 · `OverviewView.swift` 782 ·
  `InspectorView.swift` 714 · `SettingsView.swift` 637 · `ProblemsView.swift` 612.
- Heavy reads already go through `Task.detached` into Kit (`SVFolderRead`,
  `MinionBackup`, `SavedVariablesAudit`). The exceptions are file writes in
  restore and Copy Settings, which run on the main actor.
- No drifted `private struct` copies.

---

## Backup Restore as one Kit operation  [Strong] — done

Done 2026-11-09 in four commits. Final interface takes the zip inside the scope:
`run(.everything(from: zip) | .file("SavedVariables/X.lua", from: zip) | .saveOnly, addonIDs:)`.
Proof: 157 unit tests (7 new) and all 272 self-test checks pass before and after.
Found on the way: the self-test failed while ESO was open (see `docs/FIXLOG.md`).

Files: Sources/MacMinion/Models.swift (`restore`, `restoreFile`, lines 887–1009),
Sources/MacMinionKit/Backup.swift
Signal: Pure logic and file I/O inside a `@MainActor` store; same code twice;
`Models.swift` over 1,000 lines.
Problem: `restore` and `restoreFile` each repeat "save what's there → unpack to a
temp folder → trash replaced addon folders → copy into place → same two error
messages". The copy loop (`trashItem`, `removeItem`, `copyItem` per file) runs on
the main thread, so a large AddOns restore stalls the window. Which addon folders
a full backup replaces is computed inline and can only be tested through the
self-test, against a real app model.
Proposal:
```swift
// MacMinionKit/BackupRestore.swift
public struct BackupRestore: Sendable {
    public let gameFolder: URL, addonsFolder: URL, safetyRoot: URL
    public enum Scope: Sendable { case everything, file(String) }  // "SavedVariables/X.lua"
    public struct Result: Sendable { public var safety: URL; public var restored: Int }
    public enum Failure: Error { case couldNotSaveFirst(Error), stopped(Error, safety: URL), missing(String) }
    /// Saves what's there, then puts `scope` back from `zip`. Runs off the main actor.
    public func run(_ zip: URL, scope: Scope, addonIDs: [Int]) async throws(Failure) -> Result
    static func replacedAddonFolders(_ files: [URL], gameFolder: URL) -> Set<String>
}
```
`AppModel.restore` keeps the busy text, the rescan, reinstall/remove-others, and
the messages; it calls `BackupRestore.run` once.
Benefits: Locality — restore rules live in one Kit file. Leverage — both menu
commands and the agent CLI get the same safe path. Kit tests can cover "full
backup replaces whole addon folders", "single file leaves others alone",
"missing file changes nothing", and the two failure messages, with temp dirs,
no app. Main thread stays free during large restores.
Proof of same behavior: existing `KitTests` saveBeforeRestore test; self-test
restore checks (lines 208–240 of `SelfTest.swift`: restores files, saves first,
refuses while ESO runs, keeps the first safety copy, reinstall/remove); new Kit
tests written *before* the move against the current behavior (byte-compare
restored files).
Plan: (1) add `BackupRestore` + Kit tests, unused; (2) move `restoreFile` to it;
(3) move `restore` to it and delete the inline copy loop.

## Game Folder state out of AppModel  [Worth exploring] — continued in architecture-review-2026-11-10.md

Files: Models.swift (~60 `inspector*`/`gameFolder*`/`problems*` properties,
lines 706–801), InspectorView.swift (253-line `extension AppModel`),
InspectorFind.swift, ProblemsView.swift (4 extensions), ConnectionsView.swift,
CharactersExplorer.swift, GameSettingsView.swift, GameFolderView.swift.
Signal: God model; one feature (Game Folder) touches 8+ files; a type well over
400 lines.
Problem: Everything the Game Folder pages read — the parsed document, names,
references, problems, roster, graph, settings matrix, find results, progress —
are stored properties on the app-wide store, and their logic sits in
`extension AppModel` blocks inside view files. Adding one Inspector feature
means editing `Models.swift` for storage plus a view file for logic, and every
Game Folder method can reach installs, backups, and AI.
Proposal: an `@Observable final class GameFolderModel` owned by `AppModel`
(`model.gameFolder`), holding the read results and the Inspector/Problems/
Compare state; its methods move from the view-file extensions into
`GameFolder/GameFolderModel*.swift`. It takes the few things it needs from
`AppModel` (addons folder, `gameIsRunning`, a `backUp()` closure) in its init.
Benefits: `Models.swift` drops ~400 lines; Game Folder changes stay in one
folder; views take `GameFolderModel` and can be snapshotted with a seeded one.
Proof of same behavior: `tools/selftest.sh` (65 inspector references), all
`tools/snap.sh` pages byte-compared before/after, agent CLI `sv` commands.
Plan: one commit per moved group (read results → Inspector navigation → Find →
Problems → Compare/Copy), each building and passing selftest. Large: ~10 files,
so split across several sessions. Do Backup Restore first; it removes one of
the cross-calls (`restoreFile` → `scanGameFolder`/`loadInspectorNames`).

## Inspector table navigation as a value type  [Worth exploring] — done

Done 2026-11-09 in two commits. `SVTableCursor { roots, focus, rows; node(_:); open(_:) -> Bool;
enclosing() -> SVNode.ID? }` and `[LuaKey].luaPath` in Kit. `AppModel.inspectorRoots`/`inspectorFocus`/
`inspectorRows` stay as names over `inspectorCursor`, so ~50 callers didn't churn; the Game Folder
split removes them. Proof: 163 unit tests (4 new), all 272 self-test checks, and the 18 Inspector
snapshots show the same content before and after (pixel diffs only in window-active chrome).

Files: InspectorView.swift (`refreshInspectorRows`, `inspectorNode`,
`inspectorOpen`, `inspectorEnclosing`, `luaPath`, `inspectorRawText`)
Signal: Pure logic in a `@MainActor` store.
Problem: Walking `SVNode` trees by focus path and finding a row by its
`\u{1F}`-joined ID is pure, but it lives on `AppModel` driven by `didSet`, so it
can only be tested through the self-test.
Proposal: `struct SVTableCursor { roots, focus; var rows; func node(_ id:) -> SVNode?; mutating func open(_:); mutating func enclosing() -> SVNode.ID?; static func luaPath(_:) }`
in Kit; `AppModel` holds one `var inspectorCursor`.
Benefits: Kit tests for ID lookup under opened rows, enclosing selection, and
Lua path escaping. Folds naturally into the Game Folder card above.
Proof of same behavior: new Kit tests against current outputs; selftest.
Plan: (1) add type + tests; (2) switch `AppModel` to it.

## Copy Settings writes off the main thread  [Worth exploring] — done

Done 2026-11-09 in two commits: `SettingsMatrix.copyChanges(_:from:to:)` builds the edits and
`SVEdit.apply(toFiles:) async -> FileEdits` writes them. Proof: 159 unit tests (2 new) and all 272
self-test checks, including the Copy Settings and Undo checks, pass before and after.

Files: CharactersExplorer.swift (`copySettings`, lines 770–820)
Signal: Slow work on the main thread; pure logic in a store.
Problem: For each addon file, `Data(contentsOf:)`, `SVEdit.apply`, and an
atomic write run on the main actor. Grouping rows into per-file changes is also
inline.
Proposal: `SVEdit.apply(_ byFile: [URL: [Change]]) async -> (before: [URL: Data], after: [URL: Data], failures: [String: String])`
in Kit, run detached; the store keeps backup-once, undo, and messages.
Benefits: Small, testable with temp files, keeps the window responsive on big
SavedVariables.
Proof of same behavior: `SVEditTests`, selftest Copy Settings checks.
Plan: one commit.

## Split the biggest view files by screen  [Speculative]

Files: CharactersExplorer.swift (1,076; 12 private views + 2 model extensions),
SelfTest.swift (1,031), ContentView.swift (794), OverviewView.swift (782).
Signal: Files over 1,000 lines.
Problem: Long, but each is a set of independent private views or independent
checks; they rarely conflict and compile fine. `SelfTest.swift` is the most-
edited file because every story adds a check there.
Proposal: `CharactersExplorer/` folder (Grid, Constellations, Compare); 
`SelfTest/` split per feature (`SelfTest+Backups.swift`, `+GameFolder`, …).
Benefits: Smaller diffs and fewer merge conflicts; no design change.
Proof of same behavior: build, selftest, snapshots identical.
Plan: one mechanical move per file.

---

## Top recommendation

**Backup Restore as one Kit operation** (done; see its card).

Then (done): **Copy Settings writes off the main thread.** It is the same shape as
Backup Restore (file reads and atomic writes in a `@MainActor` method, moved
into a Kit operation with temp-folder tests), one commit, and it shrinks the
`CharactersExplorer.swift` model extension before any Game Folder split. Then
(done): **Inspector table navigation**.

Next: **Game Folder state out of AppModel**, in its own sessions, one moved
group per commit.

## Considered, not recommended

- **Protocol seams for MMOUI / AI clients**: AI already has `LLMProvider` with
  recorded-fixture tests; catalog decoding is in Kit. A protocol now would have
  one conformer.
- **Moving `inspectorProgress` off the store**: `@Observable` tracks per
  property and only the progress view reads it; updates are a few per second.
- **Splitting `Preferences.swift` / `SettingsView.swift`**: under 650 lines,
  already one tab per topic.
