# Game Folder: performance review and plan

Measured 2026-10-30 on a /tmp copy of the real SavedVariables: 92 files, 74 MB, 1.12 million entries,
with the real AddOns folder (90 addons) read-only. Release build. Rerun with:

    MM_REAL_SV=<copy>/SavedVariables MM_ADDONS=<AddOns> swift test -c release --filter benchmarksTheGameFolderRead
    (add MM_BENCH_FILE=GS16Data.lua to time the tree on a 79 000-row table)

## Where the time goes

Everything below runs before the Characters, Addons, Problems, and Space tabs show anything, and
again in full after any SavedVariables file changes.

| Stage | Time | Note |
|---|---|---|
| Parse 92 files | 0.28 s | One thread. Memory grows by ~155 MB for 74 MB of files. |
| Name index | 0.25 s | |
| Manifests (declarations) | 0.07 s | AddOns walked again by `saverFolders` and `topFolders`. |
| Problems | **1.01 s** | Builds a joined-string "shape" for every one of 1.1 M entries. |
| Reference index | 0.69 s | 70 k IDs, 308 k mentions. |
| Usage, settings matrix | 0.32 s | |
| Names from addon source | **2.70 s** | Half the total. Every addon's Lua is run through about ten regex passes, but only the open file needs it. |
| **Total** | **~5.4 s** | Peak about 330 MB resident. |

Already fast: the folder scan on each activation (0.02 s), the SavedVariables audit (0.08 s), opening a file
in the Inspector (0.03 s for the 17 MB TamrielTradeCentre.lua), building children lazily, and the
settings sheet (0.03 s, capped at 200 rows).

## Data-structure findings

1. **Rows recompute their ID string on every access.** `SVNode.id` joins the whole path each time. On
   GS16Data's 79 227-row table, one pass over the IDs takes 30 ms, and finding one row by ID 40 ms
   (`inspectorNode`, a recursive `hasPrefix` search). The Inspector does several of these per render:
   the selection, the Inspector menu's `disabled` checks, and the context menu.
2. **Derived lists are computed properties that views read.** `inspectorRows` walks the focus path with
   `first(where:)` each time. `keysToNameWithAI` scans every visible row (79 k on a big table) whenever
   the Inspector menu re-renders. `fileProblems`/`allProblems` rebuild on every toolbar render, and
   `addonCardFiles` re-sorts with a linear `addonTitle` lookup per comparison.
3. **All documents stay in memory together during the read.** Every stage needs every document, so peak
   memory is all 92 trees at once (~2× the file size, plus the indexes). Parsing is the cheapest stage, so
   reading twice to keep only one tree at a time costs ~0.3 s.
4. **Repeated keys are separate strings.** Each `"itemLink"`, `"version"`, or character ID the parser meets is a
   new heap string. `LuaEntry` is 48 bytes (key 17, value 8, `Range<Int>` 16). Interning keys at parse time,
   and storing spans as two `Int32`s, cuts memory and allocations.
5. **Any change re-reads everything.** One changed file, or a clean-up that trashes one copy, bumps
   `inspectorGeneration` and redoes all 5.4 s. Problems, names, references, and usage are per-file facts
   that can be cached by (name, size, modified date).
6. **Lookups are linear.** `LuaTable.subscript`, `SVDocument.subscript`, and the path-following in
   `inspectorRows` are `first(where:)`. That's fine for small tables, but it's O(n) per step into 79 k-entry lists.

## Plan

Each step is one commit. The benchmark and the self-test show it's faster and nothing changed.

**Phase 1: quick wins. Done 2026-10-30: the read went from 5.4 s to 1.9 s**

| Stage | Before | After |
|---|---|---|
| Names from addon source | 2.70 s | read when a file opens (~30 ms for most addons, 0.3 s for the largest) |
| Problems | 1.01 s | 0.36 s, the same problems on the real folder |
| Row IDs, one render of 79 k rows | 30 ms | under 10 ms (stored) |
| Finding the selected row | 40 ms | a dictionary lookup |
| Total read | ~5.4 s | ~1.9 s |

Not done in Phase 1: names from source are kept in memory only, until the files change, not on disk.
References (0.70 s) are now the slowest stage, and Phase 2 runs them in parallel.

1. Names from addon source become lazy: read when a file opens in the Inspector, kept per addon
   (folder, version, newest .lua date) in memory and on disk. Cuts 2.7 s from the read.
2. `SVNode.id` becomes a stored property, set once. Keep a `[ID: SVNode]` index for the rows on screen,
   so `inspectorNode` is a lookup instead of a search.
3. Store `inspectorRows`, `keysToNameWithAI` (only the count is needed for the menu), `fileProblems`,
   and `addonCardFiles`. Update them when the focus, file, scan, or names change.
4. Problems: intern each shape as an `Int` from (parent shape, key shape) instead of joining strings.
   Expect 1.0 s → ~0.2 s.

**Phase 2: use every core and show pages sooner. Done 2026-10-30: the read went from 1.9 s to 0.75 s**

| Stage | Before | After |
|---|---|---|
| Parse 92 files | 0.27 s | 0.07 s (every core) |
| References | 0.70 s | 0.37 s (every core, merged in file order: the same hits in the same order) |
| Problems | 0.35 s | ~0.14 s (every core, the same problems) |
| AddOns walked | 3 times | once (`SavedVariablesAudit.index`) |
| Characters and Addons show | after everything | after 0.6 s |
| Everything ready | ~1.9 s | ~0.75 s |

Peak memory is unchanged: all documents are still in memory together (Phase 3).

5. Parse, check problems, and build each file's references in a `TaskGroup` (bounded to the core count), then
   merge. These stages are independent per file.
6. Publish in stages: names and the settings matrix first (Characters and Addons can show), then problems,
   references, and usage. Each page's own loading view already handles a nil index.
7. Walk AddOns once per read: `declarations`, `saverFolders`, and `topFolders` share one manifest scan.

**Phase 3: memory and incremental reads**

The disk cache from the caching discussion was dropped: once Phase 2 made the read 0.75 s, it would only save
about 0.6 s at launch, at the cost of an on-disk format for five structures and the risk of showing out-of-date data.

Step 9, done 2026-10-30 (`SVFolderRead`): two passes, at most 8 files' trees in memory at once.
The read is unchanged at ~0.8 s; peak memory went from ~313 MB to ~250 MB. Every structure is identical
to reading all files at once (checked on the real folder and in `SVFolderReadTests`). Only 35 MB is still
in use after the read. The rest of the peak is the trees of the files in flight, mostly the largest
(TamrielTradeCentre.lua, 17 MB), plus malloc keeping freed pages. With one file at a time the peak is
~207 MB and the read takes 2.1 s. Step 10 targets the trees themselves.

Step 10, done 2026-10-30: parsed trees take 94 MB instead of 136 MB for 61 MB of files (31% less), and parse at the
same speed. `LuaValue` is no longer `indirect`, so values sit in their entries instead of one heap box each.
Each table's entries array is trimmed to its size, so the room left over from growing goes (that alone saved 24 MB).
Spans are 32-bit offsets. Sharing strings over 15 bytes saved only 6 MB and parsed 35% slower, so it was left out.
Peak RSS when reading all files at once: 313 → 274 MB. The two-pass read peaks about 250 MB with 8 files at once,
and its peak is no longer set by the trees.

Step 8, done 2026-10-30 (`SVFolderRead.Cache`): each file's pass-one and pass-two results are kept, stamped
with its size and date. After one file changes, the read parses only that file and takes 0.18 s instead of 0.8 s.
If the merged names change, pass two runs for every file again, because references and settings depend on names.
A file that goes to the Trash just drops out. Cost: 61 MB kept after the read instead of 39 MB. The 0.18 s left
is merging the parts (the libraries' names take 0.04 s and the reference merge 0.02 s of it).

Step 11, done 2026-11-11 (`SVDocumentCache`): Find, Connections, character places, and the Inspector share a
stamped LRU of the last 4 parsed trees (Inspector open file pinned). On the real folder, a second look at
GS16Data.lua (7 MB) went from 18 ms re-parse to a 0 ms cache hit; cold fill stays ~18–19 ms. Space map UI is gone;
the same cache would have served its file zoom. Cost: at most a few trees (tens of MB when the largest files are open).

**Phase 3 in all:** peak memory 313 → ~250 MB, parsed trees 136 → 94 MB, a re-read after one change 0.8 → 0.18 s;
39–61 MB kept after a read; Find/Connections reuse up to 4 parsed trees (Step 11).

8. Cache per file: problems, name contributions, references, and usage buckets, keyed by name, size, and
   modified date. A change re-reads only the files that changed, and a clean-up only drops entries.
   (After a play session the game rewrites most files anyway, so this helps clean-ups and partial changes most.)
9. Two-pass read with one tree in memory at a time: pass one builds the name index, and pass two
   re-parses each file for the rest and drops it. Peak memory goes from about all files to about the largest
   file, for ~0.3 s more parse time.
10. Intern keys in the parser, and store `LuaEntry.span` as `Int32` offsets. Measure retained memory with
    `footprint`/Instruments before and after. RSS can't show it, because malloc keeps freed pages.
11. Keep the last few parsed documents for Find, Connections, and the Inspector (`SVDocumentCache`), which
    used to re-parse files per query.

**Not worth it now:** a custom binary format or a SQLite cache of SavedVariables. Parsing all 74 MB
takes 0.28 s, so the cost is in what runs after parsing, not in reading the files.

## Checks for every step

- The benchmark above, before and after, with numbers in the commit message.
- `tools/selftest.sh` (all checks), unit tests, and snapshots for any step that touches views.
- UI stalls: open GS16Data in the Inspector, focus the 79 k-row table, and change the selection. Profile with
  Instruments' Hangs and SwiftUI templates (see the bama `performance` skill) before and after steps 2 and 3.
