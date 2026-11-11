# MacMinion architecture

## Targets and dependency direction

```
MacMinion (app, SwiftUI, defaultIsolation MainActor)
   │  depends on
   ├── MacMinionKit (rules and data logic, no SwiftUI, nonisolated by default)
   └── Sparkle (app updates)

MacMinionKitTests → MacMinionKit   (recorded fixtures; no network, no app)
```

Kit never imports the app. Anything that can be tested without a window
belongs in Kit.

## Layers

- **Kit — pure rules and file formats**: catalog decoding (`MMOUIClient`), installs
  (`Installer`), Lua and SavedVariables parsing (`LuaTable`, `SV*`), backups
  (`Backup`, `BackupRestore`), health findings, AI providers, and Inspector
  navigation (`SVTableCursor`, `[LuaKey].luaPath`).
- **Kit — operations**: Sendable value types whose work runs off the main
  actor (`@concurrent` or `Task.detached` at the call site). Examples:
  `SVFolderRead`, `MinionBackup`, `BackupRestore`, `SVEdit.apply(toFiles:)`.
- **App — `AppModel`** (`Models.swift` plus `extension AppModel` blocks beside
  each feature's views): one `@Observable` store. It owns UI state, busy and
  error text, and orchestration (rescan, install, undo, messages). It calls
  Kit operations and does no heavy file work itself.
- **App — `GameFolder/`**: `GameFolderModel`, an `@Observable` class that
  `AppModel` owns as `model.gameFolder`. It holds everything the Game Folder
  pages show and do, one file per area: the SavedVariables read
  (`GameFolderModel.swift`: `lastRead`, a `SavedVariablesRead`; `current` is
  that read while the files are unchanged; `load()` reads them), `+Files` (the
  scan, Clean Up, the tab, and the page's messages), `+Inspector`, `+Find`,
  `+SourceNames`, `+Problems`, `+Connections`, `+Characters` (Compare and Copy
  Settings too), and `+GameSettings`. It reaches the rest of the app through
  `app` (unowned): installs, updates, backups, navigation, and whether the
  game runs stay in `AppModel`. That is honest coupling, not a seam; Problems
  uses it most.
- **App — views**: SwiftUI pages, each in its feature's file. Design tokens in
  `UI/`.
- **App — `SelfTest/`**: the in-app self-test, one function per area in
  `SelfTest+<Area>.swift`. `SelfTest.swift` runs them in a fixed order, since
  later areas use what earlier ones left on disk and in the model.
- **App — agent**: `Agent/` exposes the same `AppModel` methods to the
  `macminion` CLI and MCP.

## Seams

| Seam | Production | Test |
|---|---|---|
| Store location | `~/Library/Application Support/MacMinion` | `APP_STORE` in /tmp (`Store.isOverridden`) |
| ESO running | `NSWorkspace` process check | `AppModel.simulatesRunningGame` (replaces, never adds to, the real check) |
| AI provider | `LLMProvider` adapters | recorded NDJSON/SSE fixtures |
| Backup restore | `BackupRestore(gameFolder:safetyRoot:)` | same type on temp folders (`BackupRestoreTests`) |

## Known debt

See `docs/architecture-review-2026-11-10.md`: `GameFolderModel` still
carries `inspectorRoots`, `inspectorFocus`, and `inspectorRows` as names over
`inspectorCursor`; Game Settings save and file undo write on the main thread;
`AppModel` is still about 1,150 lines of addons, AI, and backups; and
`CharactersExplorer.swift` is over 900 lines of views.
