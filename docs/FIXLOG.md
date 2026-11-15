# Fix log

## 2026-11-14 — Companion SavedVariables write left EsoMacMinion.lua unparsable

At 16:28 only `EsoMacMinion.lua` changed (ESO saves all addon SV files together, so the
game did not write it). `lookups.requests.svGlobals` grew 122→123, matching
`CompanionRequests.write` while `!gameIsRunning`. Damage was outside `requests`: an
`errors[1]` entry lost indent and the closers for `errors` / `$AccountWide` / `@account`
vanished, so Lua failed with `'}' expected … near <eof>` and logout wiped other megaserver
blocks. The only string with `\"` and `<Locals>` sat at the end of that block (500-byte clip).

`CompanionRequests.apply` on a four-block fixture with that message shape (replace, insert
requests, insert lookups, CRLF, UTF-8) does **not** reproduce the missing closers; the live
file also survives apply. Cause of the exact byte damage was not reproduced in-process.

Hardening anyway: `apply` re-parses and refuses if anything but `lookups`/`requests` changed;
every Lua SV write goes through `SavedVariablesWrite` (parse, allowlisted path diff, stamp
check, `*.lua.macminion.bak`, atomic); refusals surface on the Game Folder banner; CrossOver
`eso64.exe` is detected via process command lines so writes do not run while Wine has the
client up even when `NSRunningApplication` does not.

Rule: Never write SavedVariables bytes you have not re-parsed; never overwrite a file that
changed since you read it; keep one backup beside the file.

## 2026-11-14 — File undo could overwrite newer files and claimed success when it failed

Found in the undo review. Edit › Undo for Save Game Settings and Copy Settings wrote the old bytes with
`try?` and always said "Undid …", and never checked whether ESO or another app had written the file since,
so an undo after the game ran threw away the game's changes. The Inspector's Save also registered with the
key window's undo manager, which is the Settings window's when that is in front. Undo now goes through
`FileSnapshot.write(_:expecting:)`, which writes only when every file still holds what the action wrote and
reports why not, and every action registers with the main window's manager (`MainUndo`).

Rule: An undo restores only what it can prove is still its own; otherwise it says so and changes nothing.

## 2026-11-09 — Self-test failed while ESO was open

Found during the Backup Restore refactor. `gameIsRunning` was
`simulatesRunningGame || gameProcessRunning`, so on a Mac with ESO running
(even under CrossOver) every self-test check that writes files was refused,
and 18 checks failed for reasons unrelated to the code under test.
`simulatesRunningGame` is now `Bool?`: when the self-test sets it, it replaces
the real process check; nil asks the system as before.

Rule: A test seam replaces the real input; it never ORs with it.

## 2026-11-10 — Main didn't compile after merging a branch into a rebased main

Merging `companion-lean-addons-snapshot` into `main` brought back four files the
branch had deleted with the Space tab on 2026-11-09 (`SpaceMapView.swift`,
`SpaceView.swift`, `SpaceMap.swift`, `SpaceMapTests.swift`). A pull had just
rebased `main`, so `main` carried rewritten copies of the commits that add those
files while the branch still had the originals; the merge base fell back to
before either, and Git saw "main adds them, the branch has nothing". No conflict
was reported, and `MacMinionKit` failed on a redeclared `topFolders(_:depth:)`.
The four files are deleted again.

Rule: After a merge, build and run the unit tests before anything else; and
don't rebase a branch that another branch was cut from.
