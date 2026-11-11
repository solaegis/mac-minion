# MacMinion app UI localization (de / fr / es / ru)

## Goal

Ship MacMinion’s user-visible UI in German, French, Spanish, and Russian, with English as the source language. Follow the Mac’s language by default; allow an optional override in Settings → Appearance that applies on relaunch.

## Decisions

| Topic | Choice |
| --- | --- |
| Surface | App UI only (not README, GitHub Pages, or EsoMacMinion) |
| Locales | `en` (source), `de`, `fr`, `es`, `ru` |
| Selection | System Language & Region by default; Settings → Appearance override |
| Override apply | Write/clear `AppleLanguages`; prompt to relaunch |
| Translations | Machine-translate for v1 |
| Mechanism | Apple String Catalogs (`.xcstrings`), not hand-rolled `L10n` tables |

## Out of scope

- Agent CLI output (stay English for scripts)
- Self-test / snapshot harness / seed copy
- Addon titles, authors, changelogs, SavedVariables (external data)
- View-menu language item (Settings only for v1)

## Architecture

- `Localizable.xcstrings` on the MacMinion app target and on MacMinionKit
- `InfoPlist.xcstrings` for `NSDocumentsFolderUsageDescription`
- SPM `resources: [.process(...)]` so catalogs compile into product resources
- `build.sh` copies compiled localization products into `MacMinion.app/Contents/Resources`
- Info.plist declares `CFBundleDevelopmentRegion` and `CFBundleLocalizations`
- Kit `LocalizedError` strings use `String(localized:bundle: .module)`
- SwiftUI `Text` / `Button` / `Label` string literals resolve via the app catalog once keys exist

## Language preference

- `LanguagePreference`: `system`, `en`, `de`, `fr`, `es`, `ru`
- `LanguageController` mirrors `AppearanceController` (AppStorage key, apply at launch)
- Settings → Appearance shows a Language picker with native names
- Changing language offers Relaunch / Later

## Verification

- `./build.sh` succeeds; locale resources present in the app bundle
- Self-test: preference persistence; system clears override
- Spot snapshots: Overview + Settings Appearance in `de` (light/dark)
- Grid lint after UI changes
