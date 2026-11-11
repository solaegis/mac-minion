# MacMinion macOS UI architecture

How MacMinion's interface is put together, and the macOS rules it follows. Read this before you add a
window, page, sheet, menu item, setting, or control. `design/DESIGN-SYSTEM.md` holds the tokens
(accent, radii, spacing, motion); this file holds the structure and the platform rules around them.

Source: Apple's Human Interface Guidelines, reviewed November 2026: *Designing for macOS* and the pages it
leads to (windows, the menu bar, toolbars, sidebars, split views, sheets, panels, settings, search fields,
context menus, keyboards, focus and selection, undo and redo, going full screen, layout, color, dark mode,
materials, typography, accessibility). Links are at the end. Each rule below carries its HIG page in
brackets, so a reviewer can check the source.

Rules are written **must** (the lint or review fails without it), **should** (do it unless the section
names an exception), and **avoid**.

---

## 1. What a Mac app owes its people

Apple's summary of the platform, and what each point means here:

| The Mac | What MacMinion does |
| --- | --- |
| Large, high-resolution displays, often more than one | Show more in fewer levels: a sidebar of pages, a grid or list, details in an inspector. Few sheets, no nested navigation stacks. Keep density comfortable (`CardSize` in Settings > Layout). |
| Keyboard and pointer first; touch, Voice Control, and assistive devices too | Every action has a menu item and a shortcut. Every control is reachable with Full Keyboard Access and VoiceOver. |
| Sessions last minutes to hours, beside other apps | Windows resize, hide, move, and go full screen. Nothing grabs focus or pops up uninvited. State survives a quit. |
| People personalize | Customizable toolbar, a chosen accent, grid or list, card size, sidebar shown or hidden. |

---

## 2. Scene structure

`Sources/MacMinion/App.swift` owns every scene. Keep it the only place that declares scenes and commands.

```
MacMinionApp
├── Window("MacMinion", id: "main")      the one main window: NavigationSplitView
│     ContentView
│     ├── sidebar   pages (SidebarItem): Overview, Installed, Find More, Game Folder, Backups, …
│     ├── content   the page: grid/list, or a custom page marked with .gridArea
│     └── inspector details for the selection (.inspector)
├── Settings { SettingsView }             one tab per SettingsTab case, one grouped Form each
├── MenuBarExtra                          optional, Settings > General; mirrors menu commands
└── .commands                             View, Addons, Inspector, Help menus (section 4)
```

Rules:

- **Must** use the system window frame, title bar, toolbar, and traffic lights. No custom window chrome,
  no hidden title bar to fake a design. [windows]
- **Must** let the main window resize freely above its minimum (`minWidth 860, minHeight 520`), and lay out
  fluidly at every width. Never resize the window from code, including in full screen. [windows, going full screen]
- **Must** support system full screen (`Control-Command-F`, View > Enter Full Screen). Never a custom
  full-screen mode. In full screen every task stays possible without leaving it. [going full screen]
- **Should** give each page a title (`.navigationTitle`) and a status line (`.navigationSubtitle`); the
  window shows the page, not just the app name. [toolbars › Titles]
- **Avoid** critical controls or information at the bottom of a window or sidebar. People push windows
  partly off screen. Put actions in the toolbar, the inspector, or menus. Settings is in the App menu
  only (`Command-,`), not repeated at the foot of the sidebar. [layout, sidebars, windows]
- A new kind of window (a second document, a detached panel) needs a reason: the content is worth viewing
  side by side. Name it a *window* in UI text. [windows]

### Sidebar and split view

- Pages are `SidebarItem` cases with an SF Symbol and a one-word label. Icons stay monochrome unless color
  carries meaning. [sidebars]
- At most two levels in the sidebar; group with section headers or disclosure. [sidebars]
- People can hide the sidebar (View > Hide Sidebar, `Control-Command-S`, from `SidebarCommands()`) and the
  inspector. Every hidden pane has a menu item and a shortcut to bring it back. [split views]
- Keep the current selection highlighted in every pane that leads to the detail. [split views]
- Panes have minimum widths that keep the divider grabbable. Thin dividers only. [split views]

### Inspector, sheets, and panels

Choose the lightest container that does the job:

| Need | Use | Not |
| --- | --- | --- |
| Details or settings for the selected item, while working | `.inspector` | a sheet |
| A short, self-contained task that must finish or cancel (restore a backup, customize Overview) | `.sheet` | a new window |
| Repeated input while watching the result (find, compare chooser) | a panel or inline view | a sheet |
| Confirm a destructive action | `.confirmationDialog` / `.alert` with the destructive role | a custom view |

Sheet rules [sheets]:

- **Must** open at a sensible fixed size, with `.fitsContent()` so there is no scroll bar with nothing to
  scroll, and `.noInitialFocus()` so no field is selected on open (`UI/WindowBehavior.swift`).
- **Must** close with Escape: a Cancel button (`.cancelAction`), or `.onExitCommand` when the sheet only
  shows something and has just Done. One default action (Return, `.defaultAction`).
- **Must** show one sheet at a time. Never a sheet from a sheet.
- **Avoid** long or multi-step flows in a sheet; use a page or the inspector.

---

## 3. Toolbar

[toolbars]

- `.windowToolbarStyle(.unified)`. Toolbar items are system buttons with SF Symbols, no bezels and no tint
  unless the item is the key action.
- **Must** keep every toolbar item also in a menu, with the same name and shortcut. People hide and
  customize the toolbar. [toolbars › macOS]
- **Should** let people customize the toolbar. Not yet: see section 12. `ToolbarCommands()` is in place.
- Group by function: navigation leading, page actions in the middle, search trailing. Few groups. Keep
  text-labeled items apart from icon-only ones.
- **One** prominent item at most, for the page's key action.
- **Never** a Settings button in the toolbar. Settings lives in the App menu (`Command-,`). [settings]
- Search sits at the trailing edge of the toolbar (`.searchable`) and filters as people type, with
  placeholder text that says what it searches. Scope chips and tokens filter; default to the broadest
  scope. [search fields]

---

## 4. Menu bar and keyboard

The menu bar is the complete list of what the app can do. [the menu bar]

### Menu layout

| Menu | Holds |
| --- | --- |
| MacMinion (App) | About first, Check for App Updates, Settings… (`Command-,`), Hide, Quit |
| File | standard items only; New is removed (`CommandGroup(replacing: .newItem) {}`) |
| Edit | Undo/Redo at the top (`Command-Z`, `Shift-Command-Z`), Cut/Copy/Paste, Find |
| View | Sidebar, toolbar, grid/list, Clear Filters, Show/Hide Inspector (`Option-Command-I`), Customize Overview… (`Option-Command-O`), Filter, appearance. Show/Hide titles reflect the current state. |
| Addons | Check for Updates, Update All, Back Up Now, Summarize; the selected addon (Install/Update/Reinstall, Ignore Updates, Thumbs Up/Down, Open on ESOUI, Show Addon in Finder, Remove Addon…); the selected backup (Restore Backup…, Move Backup to Trash…, Show Backups in Finder); clean-up; Show Files in Inspector, Show Problems for Addon, Show Addons by Creator; folders in Finder |
| Inspector | Game Folder: Go to Characters/Inspector/Problems/Game Settings (`Control-Command-1`–`4`), table navigation, copy, Show as Tree/Settings (`Control-Command-T`), Compare and Clone (`Control-Option-Command-Left/Right Arrow`), Save/Revert Game Settings, problem actions, Find |
| Window | system Window menu, always present |
| Help | MacMinion Help (`Command-?`), Help for This Page (`Option-Command-?`), links |

Rules:

- **Must** give every action a menu item; context menus, toolbar items, and buttons are shortcuts to it,
  never the only way. [the menu bar, context menus, toolbars]
- **Must** keep the same items in a menu at all times; disable what does not apply now, do not remove it.
  (Context menus are the opposite: hide what does not apply.) [the menu bar, context menus]
- Menu titles are one word. Items are title case verbs; an item that opens more UI ends in `…`.
- App menus run from most to least used and follow the app's structure. [the menu bar › App-specific menus]

### Shortcuts

- **Must** keep the standard shortcuts for the standard items (`Command-,`, `Command-Z`, `Command-F`,
  `Command-W`, `Command-Q`, …). [keyboards]
- **Avoid** reusing a standard shortcut for a custom action. A few are reused on purpose because
  MacMinion has no text formatting (no Format menu): `Command-B` Back Up Now, `Command-U` Update All,
  `Command-I` Show Problem Details. Each is marked `// hig: ok` with the reason. Add no more without the
  same justification. [keyboards]
- Custom shortcuts only for frequent commands. Modifiers in the order Control, Option, Shift, Command.
  Shift only with lowercase-row keys. Do not make a new shortcut by adding a modifier to an unrelated one.
  [keyboards › Custom keyboard shortcuts]
- Show shortcuts in the main menus, not in context menus. [context menus]
- Mention shortcuts in `.help` tooltips ("Update every addon (Command-U)").

### Undo

- Changes people make to their data register with the window's `UndoManager`, so Edit > Undo and
  `Command-Z` work. Game Settings' Save and Compare's Copy already do (`GameSettingsView.swift`); every new
  edit must too. Name the action ("Undo Save Game
  Settings"). [undo and redo]
- Show the result of an undo: select or scroll to what changed.

---

## 5. Focus, keyboard navigation, selection

[focus and selection, keyboards, accessibility]

- Windows and sheets open calm: `.noInitialFocus()`. A view whose only job is typing (search, find) may
  focus its field on purpose.
- **Never** move focus without a person's action.
- Use system focus rings on fields and system highlight in lists and grids; never draw custom focus.
- **Must** make every control work with Full Keyboard Access (Tab, arrows, Space, Return, Escape).
- A card or row that reacts to a click with `.onTapGesture` **must** also have a keyboard and VoiceOver
  path: `.accessibilityAction(named:)` or a selection in a `List`/`Table` that arrows reach, plus
  `.accessibilityAddTraits(.isSelected)` when selected. Prefer a `Button` or a selectable `List` row over
  a tap gesture.
- Double-click opens; single click selects. Same as Finder.

---

## 6. Settings

[settings]

- One window from App menu > Settings… (`Command-,`); one tab per topic (`SettingsTab`), each one grouped
  `Form`. The tab bar is system, not customizable, and always shows the active tab.
- The window sizes to the tab (`.windowResizability(.contentSize)`, `.fitsContent()`); no minimize or zoom.
- It reopens on the last tab (`settings.tab` in UserDefaults).
- Good defaults first; fewer settings is better. Do not copy system settings into the app.
- Options for the task at hand belong next to the task (a toolbar picker, a menu), not only in Settings.
  Settings holds the rarely changed defaults.
- **Accepted deviation:** Settings > Appearance offers Light/Dark/System. Apple advises against an
  app-specific appearance setting [dark mode]. MacMinion keeps it because people pick it on purpose, and the
  default is **System**. Never default to anything else, and never add another per-app copy of a system
  setting.

---

## 7. Content: layout, type, color, materials

### Layout [layout]

- Spacing comes from `Space` (4 pt grid, `UI/Grid.swift`); custom pages and cards carry `.gridArea` and
  `.gridProbe`. `tools/grid-lint.sh` and `tools/check-layout.swift` enforce it.
- Order by importance, align to scan, group related things, disclose progressively. Controls look like
  controls; content looks like content.
- Layouts adapt to width and to longer localized text (de, es, fr, ru run up to 40% longer). Never fix a
  text width that a translation can overflow.
- Empty states use `ContentUnavailableView` with a next step.

### Type [typography]

- SF Pro through text styles only: `.font(.title)`, `.headline`, `.body`, `.callout`, `.caption`, …
  Weight and color for hierarchy, not new sizes. **Never** `.font(.system(size:))` for text.
- A large SF Symbol used as decoration may set a point size; mark the line `// hig: ok decorative symbol`.
- Avoid light and ultralight weights. Use `.monospaced()` for versions, paths, and hex.
- macOS has no Dynamic Type, but text must not clip at Accessibility > Display > larger text, and must
  not truncate a translation where a wrap fits.

### Color [color, dark mode]

- System colors and semantic styles only: `.primary`, `.secondary`, `.tint`, `.separator`, plus the tokens
  in `UI/Theme.swift` (`Palette.accent`, `accentText`, `onAccent`, `accentWash`, `counterpart`,
  `series2`, `series3`, `positive`, `caution`, `negative`). **Never** `Color.orange`, `.orange`,
  `Color.white`, `Color(red:…)`, or hex in a view: a named color gets a token with a meaning first.
- One color, one meaning, app-wide: accent = needs attention / selected; positive = good; negative =
  failed. Never use a color to mean two things.
- Color is never the only signal: pair it with a symbol, a label, or a shape.
- Test light, dark, Increase Contrast, and a warm and a cool accent (`APP_ACCENT=<id> tools/snap.sh`).
- Data that *is* a color (a game color in SavedVariables) is drawn as itself; mark it `// hig: ok data color`.

### Materials and Liquid Glass [materials]

- Liquid Glass belongs to the system's floating controls (toolbar, sidebar, sheets, popovers). **Never**
  `.glassEffect` on content: cards, rows, the Overview banner.
- Card backgrounds are `.cardSurface` / `.accentSurface` from `UI/Surfaces.swift`: opaque enough for text,
  system colors, vibrant text on top.
- Inactive windows look inactive: use system backgrounds so the system can dim them. [windows]

### Motion [accessibility]

- Durations and curves come from `UI/Motion.swift` (`Motion.hover`, `Motion.quick`). Never a literal
  `.easeInOut(duration:)` or `.spring(…)` in a view.
- Under Reduce Motion nothing scales or slides (`Motion.hoverScale`). Search results and layout switches
  never animate. Nothing blinks or flashes.

---

## 8. Context menus

[context menus]

- Every card, row, and item that can be acted on has a context menu, consistently across Installed, Find
  More, the inspector, and Game Folder.
- A few relevant items, most used first, one submenu level at most, separators between groups. Hide
  unavailable items.
- Each item also exists in the main menus. No shortcuts shown here.

---

## 9. Accessibility

[accessibility]

- Every image-only button has a label: `Label("Update", systemImage: …)` with `.labelStyle(.iconOnly)`,
  or `.accessibilityLabel`. Every control has a `.help` tooltip that says what it does.
- Custom views combine or describe themselves for VoiceOver (`.accessibilityElement(children:)`,
  `.accessibilityValue`, `.accessibilityAddTraits`). Charts get a summary label.
- Controls are at least the system's regular size; keep space between targets.
- Contrast meets 4.5:1 for text (the `Palette` tokens have Increase Contrast variants).
- No timed UI that disappears before it can be read.

---

## 10. Text in the interface

- All UI text goes through the String Catalogs (`tools/missing-strings.sh`), with de, es, fr, ru.
- A literal passed where Swift expects a `String` (a custom view's `title: String`, one branch of a ternary,
  a `switch` that returns `String`) is never looked up. Wrap it in `String(localized:)`, or make the
  parameter a `LocalizedStringKey`. `tools/missing-strings.sh` cannot see these.
- Title case for menu items, buttons, window and tab titles; sentence case for descriptions and help.
- Say *window*, *Settings*, *sidebar*, *inspector*: the words macOS uses. Name the thing, not the
  implementation.

---

## 11. How adherence is checked

Three layers; a change is not done until all pass.

1. **Lint (automatic)** `tools/hig-lint.sh` catches the mechanical rules:

   | Check | Rule |
   | --- | --- |
   | raw color | `Color.red`/`.orange`/…, `Color(red:)`, `Color(.sRGB…)`, `NSColor.systemX` in a view (section 7) |
   | fixed font size | `.font(.system(size:))` (section 7) |
   | literal motion | `.easeInOut(duration:)`, `.spring(`, `.linear(duration:)` outside `Motion.swift` (section 7) |
   | glass on content | any `.glassEffect` (section 7) |
   | sheet focus and Escape | a `struct …Sheet: View` without `.noInitialFocus()`, or without `.cancelAction` / `.onExitCommand` (section 2) |
   | unlocalized text | a literal beside `String(localized:)` in a ternary: the literal stays English (section 10) |
   | standard shortcut | Command alone plus A, B, C, H, I, M, P, T, U, V, W, X, or Z: standard Edit, Format, and window shortcuts that a custom item would take over (section 4) |
   | tap without keyboard path (warning) | `.onTapGesture` with no `accessibilityAction` within 10 lines (section 5) |

   Silence one line with a reason: `// hig: ok <why>`. The reason is reviewed like code.

2. **Existing gates** `./build.sh` (no warnings), `tools/grid-lint.sh`, `tools/check-layout.swift`,
   `tools/missing-strings.sh`, and the light and dark snapshots from `tools/snap.sh`.

3. **Review checklist** for every UI change (copy into the commit or PR description when it helps):

   - [ ] New action is in a menu, with a shortcut, and in a context menu where it fits.
   - [ ] Nothing new is only in the toolbar, a context menu, or a hover.
   - [ ] Works with the keyboard alone (Tab, arrows, Return, Escape) and with VoiceOver.
   - [ ] New window or sheet: `.noInitialFocus()`, `.fitsContent()` on sheets, Cancel and default buttons.
   - [ ] No new raw color, size, radius, duration, or font size; tokens only.
   - [ ] Light, dark, Increase Contrast, and one other accent look right in the snapshots.
   - [ ] Still works at the minimum window size, in full screen, and with the sidebar hidden.
   - [ ] Strings are in the catalogs in all five languages; no clipped German.
   - [ ] User data changes can be undone.
   - [ ] Destructive actions confirm, name what will be lost, and use the destructive role.

---

## 12. Known gaps

The November 2026 review's findings are fixed except this one. Record new gaps here with the file and line.

- The toolbar is not customizable. `.toolbar(id:)` with `ToolbarItem(id:)` on each page crashes AppKit on
  macOS 27.2 (`NSToolbarItemViewer minSize` throws during layout when the window restores or a page swaps
  its items), so the pages keep plain `.toolbar`. Retry with one toolbar declared once on the
  `NavigationSplitView` instead of per page, and run `tools/selftest.sh` before keeping it.

---

## Sources

Apple Human Interface Guidelines, https://developer.apple.com/design/human-interface-guidelines/ :
designing-for-macos, windows, the-menu-bar, toolbars, sidebars, split-views, sheets, panels, settings,
search-fields, context-menus, keyboards, focus-and-selection, undo-and-redo, going-full-screen, layout,
color, dark-mode, materials, typography, accessibility.
