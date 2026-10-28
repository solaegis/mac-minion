# MacMinion design system

Apple's controls and layout, one accent: **Minion red `#E63833`**, the same red as the Dock icon
(`Icon/AppIcon.icon` fill, srgb 0.902 0.220 0.200). Use the tokens below; never raw colors, radii, or durations.

## Theme.swift: accent and status
- `ThemeStore.defaultID = "minion"`. People can still pick System or another accent in Settings > Appearance.
- `.tint` / `Palette.accent`: fills, prominent buttons, chart bars, the Overview banner, selection rings.
- `Palette.accentText`: accent-colored text and symbols (deep shade in light mode, light shade in dark).
- `Palette.onAccent`: text and symbols on an accent fill. Never a fixed white.
- `Palette.accentWash` / `Palette.accentEdge`: the soft fill and border of accent cards (AI summary, icon wells, thumbnail placeholders).
- `Palette.positive` (green): up to date, a passing test. `Palette.caution` (amber): errors and failed downloads.
  Errors are amber, not red, so they never read as the accent. Both have Increase Contrast values.
- Neutral states (ignored, version unknown) use `.secondary`.
- Update available always uses the accent (`StatusChip`), so "needs attention" has one color app-wide.

## Surfaces.swift
- `.cardSurface(radius, selected:)`: every neutral card (Overview cards, stat tiles, bento cards).
  Secondary background, hairline border; selected cards get a 2 pt accent ring.
- `.accentSurface()`: cards that belong to the accent (the What's New summary).

## Radius.swift
- `bar 2` chart bars · `chip 8` thumbnails and icon wells · `tile 12` stat tiles, small bento cards, AI card
  · `card 16` Overview cards, wide and large bento cards · `hero 20` the Overview banner.
- Inner corners are concentric: inner radius = outer radius - inset (the large card image uses `card - Space.md`).

## Grid.swift: spacing
- `Space` on a 4 pt grid (`xs 4` … `section 32`, `margin 20`). `tools/grid-lint.sh` flags anything else.
- Bento cells: `CardSize` (Settings > Layout) sets the narrowest cell and the cell height; the grid fits as many
  columns as it can. Spans: `small 1×1`, `wide 2×1` (updates, Find More 3–6), `large 2×2` (Find More top 2).

## Motion.swift
- `Motion.hover` for hover lift, `Motion.quick` for small flips. `Motion.hoverScale` returns 1 under Reduce Motion.
- Search results and layout switches do not animate.

## Icon
- Two glass layers on a Minion-red `automatic-gradient`: the eye (front) and the grin (back, 75%). No text, no SF Symbols.
- If the accent ever changes, change the icon fill in the same commit.

## Rules
- One primary (prominent) button per card: Update when there is one, else none.
- Accent sparingly: banner, selection, Update, charts. Body text and most controls stay system.
- Every action has a menu item and a shortcut (grid/list: Option-Command-1/2).
