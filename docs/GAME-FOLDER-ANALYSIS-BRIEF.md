# Brief: plan the Game Folder health analysis

You are planning, not coding. Read the files listed under "Ground truth", then write an
implementation plan for MacMinion (native macOS SwiftUI app, see CLAUDE.md) that turns the
Game Folder's raw checks into a short, ranked list of distinct problems a player can act on.
This brief replaces and extends story S-052 "Health in plain words" in docs/STORIES.md.

## The problem

Problems today lists one row per check per file (SVProblems.checkAll + SVFileProblems +
companion data). One cause often shows up as several rows: a missing library makes three
addons "Didn't load"; a removed addon leaves "No addon uses it", "Not written lately", and
"Variable not declared". Size checks (Large file, Long list) sit next to broken addons as if
they mattered as much. The player has to do the correlation themselves.

## Goal

A player opens Problems and in ten seconds knows: is anything broken in game, is any saved
data at risk, and what single action fixes each thing. Size is never the headline.

## Ground truth (read before planning; do not invent other data)

- Sources/MacMinionKit/SVProblems.swift: `SVProblem.Kind` (17 kinds), `Severity`
  (note/warning/error), `isFileNotInUse`, `SVFileProblems`.
- Sources/MacMinionKit/Libraries.swift: `LibraryAdvisor.missing` (missing dependencies).
- Sources/MacMinionKit/SVGraph.swift: nodes (account, character, addon, svGlobal, ...),
  edges (owns, declares, dependsOn, enabledFor, hasDataIn), `orphans()`, `explain()`.
- Sources/MacMinionKit/CompanionData.swift: didntLoad, luaError, slowLoad, and the game's
  APIVersion from the companion addon.
- Sources/MacMinionKit/SVUsage.swift, GameFolder.swift: sizes and file ownership.
- Sources/MacMinion/ProblemsView.swift: current UI and its actions (installLibraries,
  update, showAddon, showBackups, showInInspector, cleanUp).
- docs/STORIES.md M7, M10, M11 (S-039, S-043, S-045, S-052, S-053); docs/GLOSSARY.md;
  design/DESIGN-SYSTEM.md.

ESO facts that limit what we can claim:
- The player does not control load order. Dependencies come from the manifest's
  DependsOn / OptionalDependsOn. Don't plan "load-order conflict" findings.
- SavedVariables are written only on /reloadui, logout, or quit. A file that looks stale may
  belong to a character that just hasn't logged in. Deleted characters are only certain
  through S-045.
- LibStub is deprecated. An addon that still needs it is an "out of date" cause, not a
  library to install.
- Analysis reads SavedVariables and manifests only, never an addon's Lua code.

## Rules for the analysis

1. Root cause over symptom. Group raw problems under one finding when one action fixes all
   of them. Plan these causes at least, and say which raw kinds and which graph or
   manifest facts link to each:
   - Missing library: missing dependency → didntLoad (and luaError) in its dependents.
   - Removed addon leftovers: unusedFile, staleFile, unknownVariable for an addon that is no
     longer installed.
   - Out of date for this game version: outOfDateAddon, plus luaError and didntLoad in the
     same addon.
   - Damaged file: unreadable or endsEarly. Backups can restore it.
   - Runaway data: largeFile together with longList in the same file. Size alone is not a
     finding.
   Anything that matches no group stays a finding of its own.
2. Rank by what the player experiences, in this order: broken in game (didntLoad, luaError)
   > saved data at risk (unreadable, endsEarly, typeMismatch, missingVariable) > out of date
   > clutter that can be cleaned up (isFileNotInUse kinds) > size and performance (largeFile,
   longList, slowLoad). Within a tier, more addons or characters affected ranks higher.
   Size may appear only as supporting detail inside a finding.
3. Each raw problem appears in exactly one finding. Other tabs (Addons, Characters,
   Inspector) may link to a finding but never repeat it as a problem.
4. Interpret every count. "12 addons out of date" is not allowed on its own; "12 out of
   date, 4 because they still need LibStub" is.
5. Cut any finding that doesn't change what the player does. Notes can't be acted on, so
   they go behind a disclosure, not into the main list.

## What each finding shows (one card, S-052)

- Title: plain words, the cause, not the symptom ("LibAddonMenu-2.0 is missing").
- Impact: one sentence on what the player sees in game or could lose.
- Affected: the addons, characters, or files, by name, collapsed past a few.
- Action: one primary button mapped to an existing ProblemsView action (or a new one
  named in the plan), with a menu item and keyboard shortcut.
- Detail: the raw SVProblems and their paths, one click away. Double-click still opens
  the Inspector.
Text is short and plain, not paragraphs. Use the string catalogs (de, es, fr, ru).

## What the plan must contain

- Where the grouping logic lives: a pure, Sendable type in MacMinionKit (for example
  `HealthFindings.build(problems:graph:libraries:companion:)`), no SwiftUI. Inputs, output
  type, and how ties are ordered.
- The data type for a finding and how it maps to the card.
- UI changes to ProblemsView, within CLAUDE.md design rules (system controls, Palette,
  Space grid, ContentUnavailableView when there are no problems, .noInitialFocus).
- CLI parity: `macminion sv problems` gains grouped output (text and --json).
- Edits to S-052 acceptance criteria in docs/STORIES.md, plus any new story.
- Tests: unit tests per group rule (one raw problem → one finding; each cause with its
  inputs; ranking order), a SelfTest.swift check on seeded data, a snapshot of the Problems
  tab with one card per tier.
- Risks and open questions, especially groupings that could be wrong (stale file vs.
  character not logged in) and how the card says how sure it is.

## Out of scope

New raw checks, reading addon Lua code, changes to the Space treemap or file sizes,
automatic fixes without a button press.

## Done when

The plan names files and types, maps every `SVProblem.Kind` to a tier and to a group (or
"stands alone"), and lists the build, test, self-test, snapshot, grid-lint, and
missing-strings checks from CLAUDE.md as verification.
