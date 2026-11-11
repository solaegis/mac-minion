# Fix log

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
