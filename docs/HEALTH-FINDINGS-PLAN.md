# Plan: Game Folder health findings (S-052)

Turns the raw rows of Problems (`SVProblems.checkAll`, `SVFileProblems.check`, `CompanionData.problems`)
into a short ranked list of findings, one per cause, each with one action. Brief:
`docs/GAME-FOLDER-ANALYSIS-BRIEF.md`. Planning only; no code yet.

## 0. What the code says that the brief doesn't

Read before building. Each point changes a grouping.

1. **`unknownVariable` never comes from a removed addon.** `SVProblems.check` only runs the
   declared-variable checks when `declared != nil`, which means an installed addon owns the file. So
   `unknownVariable` means "an installed addon's older version left this", not "a removed addon left this".
2. **`staleFile` never comes from a removed addon either.** `SVFileProblems` emits it only for
   `owner == .addon(_)`, an installed addon that hasn't loaded on any character for 90 days.
3. **The only raw sign of a removed addon is `unusedFile`** (`owner == .none`). The graph backs it up:
   `SVGraph.build` links every global no manifest declares to the synthetic `addon:missing` node with
   `orphan=true`.
4. **`SVGraph.build` is not called by the app.** Only `SVGraphTests` call it. `SVFolderRead` has every
   input except the manifests' `dependsOn`, so the plan builds the graph there (step 3).
5. **`luaError` has no addon in its path.** The path is `[EsoMacMinion_Data, errors]`, and
   `ProblemsView.problemAddonFolder` guesses the addon by matching the message text. The other companion
   kinds put the addon folder in `path.last`.
6. **`LibraryAdvisor.missing` drops LibStub on purpose** (`obsolete`). "Still needs LibStub" has to come
   from manifests (`dependsOn` contains `LibStub`), which the graph has as `addon:X -dependsOn-> addon:LibStub`
   with `missing=true`.

So "removed addon leftovers" becomes three findings with different causes and different certainty:

| Brief's group | What the data supports |
|---|---|
| Removed addon leftovers | `unusedFile` only: **Leftovers from removed addons** |
| (staleFile in the same group) | **Addons you haven't used lately**: installed, unused on every character |
| (unknownVariable in the same group) | **Leftovers from older versions**, or part of **Data the game ignores** (below) |

## 1. Where the logic lives

New file `Sources/MacMinionKit/HealthFindings.swift`. It is pure and `Sendable`, with no SwiftUI and no AppModel.

```swift
public enum HealthFindings {
    public struct Context: Sendable {
        public var files: [SavedVariablesFile]          // owners, sizes, dates (GameFolder.swift)
        public var libraries: [MissingLibrary]          // LibraryAdvisor.missing, unfiltered
        public var graph: SVGraph?                      // dependsOn (LibStub), declares, enabledFor, hasDataIn
        public var companion: CompanionSnapshot?        // addon states, errors, roster, apiVersion
        public var installed: Set<String>               // lowercased installed folders: an installed library that
                                                        // didn't load joins the group of what it is missing
        public var updatable: Set<String>               // lowercased addon folders with an update ready
    }
    public static func build(problems: [SVProblem], context: Context) -> [HealthFinding]
}
```

The brief suggested `build(problems:graph:libraries:companion:)`. Putting those inputs in a `Context`
keeps the call site stable as inputs grow. `updatable` is needed for rule 4 ("3 have an update ready").
It comes from the AppModel, so the Kit never sees `InstalledAddon`.

### Small changes it needs (not new checks)

- `SVProblem` gets `public var addon: String?`, the addon folder a companion problem is about.
  `CompanionData.problems` sets it for `didntLoad`, `outOfDateAddon`, `slowLoad` (the `path.last` it
  already writes), and `luaError` (`error.addon`). It replaces the message matching in
  `problemAddonFolder`. It's left out of `id`, so ids stay the same.
- `SVFolderRead` builds `SVGraph` in pass two and exposes `graph: SVGraph`. It needs the manifests'
  `dependsOn` passed in next to `declarations`. Done in step 3: pass one keeps a small `SVGraph.FilePart`
  per file (top-level globals and ZO scopes), so no tree is kept. Measured on a copy of a real 54 MB folder:
  10 ms for 1 194 nodes and 2 586 edges, so the graph is built on every read, not lazily.

### Algorithm: claim passes, then leftovers

Every raw problem is claimed by exactly one finding. The passes run in this order. Each one takes only
problems no earlier pass claimed:

1. **Missing libraries.** Start from `libraries.filter(\.required)`, plus companion `addon.missing`
   names the catalog can install. Join libraries to their dependents (`wantedBy` ∪ the companion's
   `missing`), then take connected components, so two libraries needed by the same addons make *one*
   finding. Claim each dependent's `didntLoad`, plus `luaError` where `problem.addon ∈ dependents`.
2. **Out of date.** Per addon, with `outOfDateAddon`, or with `didntLoad` where `missing == ["LibStub"]`,
   or with a graph `dependsOn → addon:LibStub`. Claim that addon's `outOfDateAddon`, `luaError`, and
   unclaimed `didntLoad`. An addon with a `luaError` or `didntLoad` gets its **own** finding (tier
   *broken*). The rest merge into **one** finding: "N addons are out of date".
3. **Damaged file.** One per file: `unreadable` or `endsEarly`, plus every other inside-file problem in
   that file. A file that doesn't parse makes those unreliable, so they become detail.
4. **Data the game ignores.** One per file with `missingVariable`. Also claims that file's
   `unknownVariable` rows, because those are the names it actually saves under. Same cause, one finding.
5. **Runaway data.** One per file with `largeFile` and at least one `longList`. Also claims the owning
   addon's `slowLoad` (owner via `SavedVariablesFile.owner` / graph `declares`) as supporting detail.
6. **Clutter**, three findings at most:
   - *Leftovers from removed addons*: all `unusedFile`.
   - *Addons you haven't used lately*: all `staleFile`.
   - *Copies and stray items*: all `copyFile` and `strayItem`.
7. **Per-file groups:** `typeMismatch` by file ("Settings with mixed types in X") and `unknownVariable`
   by file ("Leftovers from an older X").
8. **Stands alone:** everything left gets one finding per problem. That covers `didntLoad` with no known
   cause, unattributed `luaError`, `longList` alone, `largeFile` alone, `slowLoad` alone, `empty`, and
   `unknownSchema`.

A debug `assert` checks that the claimed ids equal the input ids. The unit tests check the same thing.

### Ordering

Tier first, then within a tier:

1. Addons and characters affected, most first. Characters come from `graph.characters(for:)`, or else from
   `companion.enabledBy`.
2. Worst `Severity` among its problems.
3. Bytes, largest first. This is only a tie-breaker; size never lifts a finding over another tier.
4. Title, `localizedStandardCompare`.
5. Finding id, so the order is the same on every run.

## 2. The finding type

```swift
public struct HealthFinding: Sendable, Identifiable, Equatable {
    public enum Tier: Int, Sendable, Comparable, CaseIterable {
        case broken, dataAtRisk, outOfDate, clutter, size, info   // info = behind the disclosure
    }
    public enum Cause: String, Sendable {
        case missingLibraries, outOfDateAddon, outOfDateAddons, damagedFile, ignoredData,
             runawayData, removedAddonLeftovers, unusedAddons, copiesAndStrays,
             mixedTypes, olderVersionLeftovers, single
    }
    public enum Certainty: Sendable { case certain, likely, possible }
    public enum Action: Sendable, Equatable {
        case installLibraries(folders: [String])
        case update(folders: [String])          // one or many; "Update 3"
        case showAddon(folder: String)
        case restoreFromBackup(files: [String]) // opens Backups at those files
        case cleanUp(problemIDs: [String])      // the existing Trash flow
        case showInInspector(problemID: String)
    }
    public enum Subject: Sendable, Hashable { case addon(String), character(String), file(String) }

    public let id: String              // "<cause>|<key>", stable across runs
    public let cause: Cause
    public let tier: Tier
    public let certainty: Certainty
    public let title: String           // the cause, localized in the Kit catalog
    public let impact: String          // one sentence: what you see in game or could lose
    public let summary: String?        // the interpreted count (rule 4), or nil
    public let affected: [Subject]     // ordered; the card collapses past 3
    public let action: Action?         // nil: no button, and the finding goes behind the disclosure
    public let problems: [SVProblem]   // the raw rows, for Detail
    public let bytes: Int64
    public var isMain: Bool { action != nil && tier != .info }
}
```

Text is built in the Kit with `String(localized:bundle: .module)`, the way `SVProblem.Kind.title` is,
so the CLI and the app say the same thing.

Card mapping: title → headline. Impact → secondary line. Summary → a third line when present.
Affected → a `Text` list of names with "and N more" past 3. Action → one `.borderedProminent` button.
`problems` → the Detail disclosure. Certainty → a caption under the impact when it's not `.certain`.

## 3. Every `SVProblem.Kind`: tier and group

| Kind | Severity today | Tier | Group (first pass that claims it) |
|---|---|---|---|
| `didntLoad` | warning | broken | Missing libraries → Out of date (LibStub or out of date) → stands alone |
| `luaError` | warning/error | broken | Missing libraries → Out of date (same addon) → stands alone (per addon, or "An addon") |
| `unreadable` | error | dataAtRisk | Damaged file |
| `endsEarly` | error | dataAtRisk | Damaged file |
| `missingVariable` | warning | dataAtRisk | Data the game ignores |
| `typeMismatch` | warning | dataAtRisk | Damaged file (same file) → Mixed types (per file) |
| `outOfDateAddon` | warning | outOfDate | Out of date (one per broken addon, or the merged finding) |
| `unusedFile` | note | clutter | Leftovers from removed addons |
| `staleFile` | note | clutter | Addons you haven't used lately |
| `copyFile` | note | clutter | Copies and stray items |
| `strayItem` | note | clutter | Copies and stray items |
| `unknownVariable` | warning | clutter | Damaged file → Data the game ignores → Leftovers from an older version (per file, info) |
| `longList` | warning | size | Damaged file → Runaway data → stands alone |
| `largeFile` | note | size | Damaged file → Runaway data → stands alone (info) |
| `slowLoad` | note | size | Runaway data (its addon's file) → stands alone (info) |
| `empty` | note | info | stands alone |
| `unknownSchema` | note | info | stands alone |

A finding's tier is the **highest** tier of its problems. An out-of-date addon throwing Lua errors is
*broken*, and a runaway file whose addon is slow is still *size*.

### Each cause: title, impact, action, certainty

| Cause | Title (example) | Count interpreted (rule 4) | Action | Certainty |
|---|---|---|---|---|
| missingLibraries | "LibAddonMenu-2.0 is missing" / "2 libraries are missing" | "3 addons don't load without it" | Install (`installLibraries`) | certain from manifests, likely from companion only |
| outOfDateAddon (broken) | "Wizard's Wardrobe is out of date" | "12 Lua errors last session" | Update if one is ready, else Show Addon | certain |
| outOfDateAddons | "12 addons are out of date" | "4 still need LibStub, 3 have an update ready" | Update 3 (`update(folders:)`); with none ready: Show Addons | certain |
| damagedFile | "HarvestMap's saved data is damaged" | "Ends at line 812; 2 backups have it" | Restore from Backup… | certain |
| ignoredData | "WritWorthy saves under names it doesn't declare" | "1.2 MB the game never loads" | Update if one is ready, else Show in Inspector | likely |
| runawayData | "LibDebugLogger's log keeps growing" | "6 769 entries, 5.4 MB of 7.1 MB" | Show in Inspector (the list) | certain |
| removedAddonLeftovers | "Files from 9 removed addons" | "4.1 MB the game never loads" | Clean Up… | certain |
| unusedAddons | "3 addons haven't loaded in 90 days" | "on none of your 38 characters" | Clean Up… | see §7 |
| copiesAndStrays | "5 copies and stray items" | "620 kB" | Clean Up… | certain |
| mixedTypes | "Some WritWorthy settings mix types" | "4 settings, on 2 characters" | Show in Inspector | likely |
| olderVersionLeftovers | "AutoResearch keeps an old variable" | "340 kB" | none (info) | certain |
| single | the kind's title | — | per `ProblemsView.problemFix` today | per kind |

"2 backups have it" needs a count from `Backup.swift` in the Context. If that's costly, use "A
backup may have it" and leave it out of the Context.

## 4. UI: `ProblemsView`

- The list is `List(selection:)` over `HealthFinding.ID`. Sections are by tier, with headers "Broken in
  game", "Saved data at risk", "Out of date", "Clean up", and "Size". Empty tiers are hidden. The
  `.info` findings and those with no action go in a final `DisclosureGroup("More (N)")`, collapsed.
- `FindingCard` is a row, not a custom surface: `Label` with a tier SF Symbol (`xmark.octagon.fill`
  `Palette.negative` / `exclamationmark.triangle.fill` system orange / `clock.arrow.circlepath` /
  `trash` / `chart.bar` / `info.circle` `.secondary`). Then title (body semibold), impact (callout
  secondary), summary, affected names, and a certainty caption. One button trails the row:
  `.borderedProminent` only on the selected row, `.bordered` otherwise. That keeps the "one prominent
  button per card" rule without a wall of accent. `DisclosureGroup("Details")` lists the raw rows
  with the existing `ProblemRow`. Spacing comes from `Space`; the list gets `.gridArea`/`.gridProbe`.
- Double-click: on a finding, it opens its first problem the way `openProblem` does today. On a Detail
  row, it opens that row in the Inspector or Finder.
- The top summary strip becomes counts by tier ("2 broken · 1 at risk · 4 to clean up"), replacing
  `problemsSummary`. The bottom explanation strip stays.
- Empty: `ContentUnavailableView("No Problems", systemImage: "checkmark.seal", …)` as today. Only notes
  left: the same view with the disclosure under it.
- `.noInitialFocus()` on the page. Nothing is selected on open.
- `AppModel` gets `healthFindings: [HealthFinding]`, rebuilt where `inspectorProblems` and
  `fileProblems` are set (`InspectorView.swift:105`, `GameFolderView.swift:58`).
  `applyFindingAction(_:)` maps `HealthFinding.Action` to the existing `ProblemFix` paths. The
  `update(folders:)` folders become `InstalledAddon` ids, and `cleanUp(problemIDs:)` goes to
  `askToCleanUp`. The only new behavior: `restoreFromBackup` opens Backups on the file, listing the
  backups that hold it (`MinionBackup.files(in:)`), each with Restore This File (`MinionBackup.unpack(_:from:into:)`
  plus the full restore's safety copy).
- Menu bar: a **Problems** group in the Game Folder menu acts on the selected finding.
  - **Fix** (the button's verb, ⌘↩), disabled when there's no action.
  - **Show Details** (⌘I).
  - **Show in Inspector** (⌥⌘I).
  - **Clean Up All Not in Use…** (keeps today's header button).

  Grep `keyboardShortcut` before picking these, because ⌘I or ⌥⌘I may already be used in the Inspector.
- Addons, Characters, and Inspector tabs: a small "1 problem" link (accent text) beside an addon or
  character that's in a finding's `affected`. It opens Problems with that finding selected. Those tabs
  never restate the problem.

## 5. CLI: `macminion sv problems`

- Default output is grouped: one block per finding (tier, title, impact, summary, affected, action
  verb), with raw rows indented below. `--raw` keeps today's flat list.
- `--json`: `{"findings":[{"id","tier","cause","certainty","certaintyNote","title","impact","summary","main",
  "affected":[names],"action","actionTitle","targets":[…],"bytes","problems":[…today's row, plus "addon"…]}],"total"}`.
  The action is flat (`action` kind + `targets`), not an object, so the text output stays one line per finding
  with its raw checks indented below. Paging (`limit`/`offset`) applies to findings. `file=` keeps findings
  that have a problem in that file.
- New `sv fix <finding-id>` is **not** in scope, so there's no automatic fix from the CLI. The JSON
  names the action, and agents run the existing `install`/`update`/`folder` commands.
- Update the `AgentSVCommands.swift` summary text and `.claude/skills/macminion/SKILL.md`.

## 6. Stories (`docs/STORIES.md`)

Replace S-052's acceptance with:

```
### S-052 Health in plain words
As the user, I open Problems and in ten seconds know whether anything is broken in game, whether any
saved data is at risk, and the one thing that fixes each: one card per cause, worst first, with the raw
checks one click away.
Depends: S-039, S-042
Acceptance:
- [unit] Every raw problem is in exactly one finding, for every fixture and the seed folder.
- [unit] Each cause groups its inputs: a missing library with its dependents' Didn't load and Lua errors;
  an out-of-date addon with its own errors; a damaged file with the rest of that file's rows; a large
  file with its long list; missingVariable with that file's undeclared variables.
- [unit] Tiers order broken > data at risk > out of date > clean up > size; within a tier, more addons or
  characters first; size alone never outranks a warning.
- [unit] Every count is interpreted: "N addons are out of date" always carries how many need LibStub
  or have an update ready.
- [unit] Every SVProblem.Kind has a tier and a group (a test iterates `Kind.allCases`).
- [self] On the seed folder: LibLazyCrafting missing groups the didn't-load addons; the file that ends
  early is one Damaged card offering Restore; leftover files are one Clean Up card.
- [self] `macminion sv problems --json` returns the same findings, in the same order.
- [snap] Problems with one card per tier and the More disclosure closed, light and dark.
Status: todo
```

New story **S-058 Problems from other tabs**: a link from an addon or character to its finding, with no
problem text repeated. Depends on S-052 and S-054.

Add `docs/GLOSSARY.md` entries: **Finding**, **Tier**, **Raw check**.

## 7. Tests

- `Tests/MacMinionKitTests/HealthFindingsTests.swift`:
  - `everyProblemInExactlyOneFinding`: for each fixture and a random mix of every Kind.
  - `everyKindHasATier`: iterate `SVProblem.Kind.allCases` and build one problem of each.
  - One test per cause, with its minimal inputs and a negative case. For example: a library missing
    but nothing failed to load is still a finding (required) without Lua errors. A `largeFile` with no
    `longList` stays alone in info. A `staleFile` with an `enabledFor` edge from a character played
    in the last 90 days is `possible`.
  - Two libraries sharing dependents make one finding. A dependent on two components goes to the
    first, by library name.
  - LibStub: `dependsOn LibStub` → out of date, never `installLibraries`.
  - Ordering: tier beats count, and count beats bytes. A big clean-up never outranks a broken addon.
  - Stable ids and order across shuffled input.
- `CompanionDataTests`: `addon` is set on all four companion kinds.
- `SelfTest.swift`: a check per `[self]` line above, run on the seeded store. Add a large file with a
  long list to the seed if it doesn't have one, so the size tier has a card.
- `Snapshot.swift`: the existing `gameFolder-problems` capture, plus `gameFolder-problems-expanded` with
  the More disclosure and one card's Details open.

## 8. Risks and open questions

- **Stale file vs. a character who hasn't logged in.** Files are only written on reload, logout, or
  quit. `staleFile` is `certain` only when the companion's `enabledBy` shows the addon off for every
  character on the roster. It's `likely` without companion data. It's `possible` when a character has it
  enabled; then the caption reads "Turned on for Masisi, who hasn't played since June." Clean Up stays
  available, but at `possible` the confirmation says the addon's settings reset.
- **Deleted characters** are out until S-045. No finding claims a character is gone.
- **Lua error attribution** depends on the companion's `user:/AddOns/<name>/` path. An unattributed
  error stands alone as "An addon threw Lua errors" (`likely`). It's never grouped by guessing from text.
- **Companion schema drift:** with `unknownSchema`, skipped sections can hide `didntLoad`. That finding
  stays in info and says which sections were skipped.
- **Missing library not in the catalog** (renamed or private): there's no Install button, so the finding
  becomes "X needs Y, which ESOUI doesn't list" with Show Addon.
- **A library that is installed but failed to load** (its own dependency is missing) chains: A needs B,
  and B needs C. Components join through `wantedBy`, so C's finding claims B's and A's rows. The title
  names C, the root. Test it.
- **Out-of-date counts** use the companion's `outOfDate`, which reflects the game's APIVersion. Without
  companion data there's no out-of-date finding. Say so in the info disclosure rather than guessing
  from manifest APIVersion.
- **Graph cost**: see §1. Without a graph, certainty drops a level and affected characters are left out.
- **Open:** should "Addons you haven't used lately" offer to turn the addon off or remove it, as well as
  trash its file? That's a new action. It's out of scope here, so for now the card says to remove the
  addon on Installed first.

## 9. Order of work

1. `SVProblem.addon` and `CompanionData` (tests green).
2. `HealthFindings` and the tests in §7.
3. `SVFolderRead` builds the graph and passes the manifests' `dependsOn`, then a benchmark.
4. `AppModel.healthFindings`, `ProblemsView` cards, menu items, and shortcuts.
5. CLI grouped output and the SKILL.md update.
6. Strings: `tools/missing-strings.sh`, then add de, es, fr, ru for each new key.
7. STORIES, GLOSSARY, SelfTest, Snapshot.

Commit after each step that builds and passes.

## 10. Verification (CLAUDE.md)

```
./build.sh                                            # no errors, no warnings
swift test --scratch-path ~/Library/Developer/MacMinion/test-build
tools/selftest.sh                                     # exit 0
tools/missing-strings.sh                              # prints nothing
tools/snap.sh                                         # then look at gameFolder-problems*-light/-dark.png
tools/grid-lint.sh                                    # PASS
swift tools/check-layout.swift /tmp/MacMinion-shots/*-layout.json   # PASS
check-agent-cli.sh macminion                          # sv problems grouped output
```

Snapshots, seed, and self-test run only against a /tmp `APP_STORE`, never the real database.
