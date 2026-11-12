# Compare radio Clone

## Goal

On Compare, choose a source per setting with optional radios (or none), then one **Clone** applies mixed directions—including creating keys, copying empty values, and deleting keys when the source has no key—after a confirm that highlights deletions.

## Decisions

| Topic | Choice |
| --- | --- |
| Row control | Optional radio under each character’s value cell |
| Default | Nothing selected; re-click clears |
| Mutual exclusion | At most one source per row |
| Header | Radio per character sets every eligible visible row to that character; re-click clears all |
| Eligible rows | Differing rows; only-one-has rows when shown (Only differences off) |
| Top action | One **Clone** button; disabled when nothing selected |
| Shortcut | One submit shortcut (⌃⌥⌘←); remove left/right Clone pair |
| Confirm | Backup-and-copy dialog; call out key deletions when any |
| Source has key (even empty) | Write that value; keep the key |
| Source has no key | Remove the key on the destination |
| Layout | Radios under values (not trailing gutter) |

## Apply pipeline

1. Selection maps `(file, key) → sourceCharacter`.
2. Clone builds ops; confirm shows counts and highlights deletions.
3. Writer: copy via existing `SVEdit.Change` set; delete via `SVEdit.Change.remove`.
4. Backup once per character pair; refuse while ESO runs; rescan after write.

## Out of scope

- Packed / timestamp non-settings (unchanged filter)
- Game Settings copy UI
- Bulk clone without radios (header select-all covers “all from one”)
