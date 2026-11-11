## Learned User Preferences

- When building from a plan: create a feature branch, commit after verified success, merge into local `main`, then delete the feature branch and stay on `main` (no push unless asked).
- Write GitHub README and user docs for people installing and using the app; keep agent/build internals (snapshots, grid lint, MCP, CI badges) out of the main path. README shields stay at latest-release, macOS, and license only — no CI, vanity, or AI badges.
- Do not propose Developer ID, notarization, App Store, sandbox, or SwiftLint unless Lewis changes those product goals.
- Treat MacMinion as source-available under PolyForm Noncommercial, not open source — do not suggest MIT/Apache or lists that require an OSI license.
- When driving GitHub UI for this repo, use the Safari Personal window (solaegis account); Work Safari is the Acxiom session. Cursor Computer Use needs Accessibility and Screen Recording; if those are off, drive Safari via accessibility or AppleScript instead.
- Localization v1 is app UI only (not README/docs or EsoMacMinion; agent CLI/harness stay English): English source plus German, French, Spanish, and Russian; follow macOS language by default with an optional Settings → Appearance override; use Apple String Catalogs and machine-translate for the first ship (not hand-rolled L10n tables). Keep the English README invite for native speakers to improve de/fr/es/ru wording.

## Learned Workspace Facts

- Public repo is `solaegis/mac-minion`; docs and Sparkle feed live at `https://solaegis.github.io/mac-minion/`.
- In-game companion addon is **EsoMacMinion** (`solaegis/eso-mac-minion`, `~/git/solaegis/eso-mac-minion`); reads SV global `EsoMacMinion_Data` (game file often `SavedVariables/EsoMacMinion.lua`). Do not use legacy `MacMinionCompanion` / `eso-macminion-companion` names.
- Game Folder is an experimental sidebar for ESO SavedVariables, characters, problems, and space; when extending it, surface companion state from `CompanionData` and keep Problems actionable.
- License is PolyForm Noncommercial 1.0.0 (copyright Lewis Vavasour); GitHub classifies it as Other.
- Shipping is GitHub Releases plus Sparkle 2 (EdDSA). CI signs with the MacMinion Release certificate so TCC survives updates; not Apple Developer ID and not notarized.
- GitHub About (Releases on; Packages/Deployments off) and the social-preview image have no API and are already set — do not re-upload or treat them as leftover launch work.
- SPM-only SwiftUI app (no Xcode project); macOS 26, Apple Silicon. Release tags use semantic versioning (`vMAJOR.MINOR.PATCH`, e.g. `v0.6.0`); historical `v0.5` stays. A matching tag cuts a release.
- App store persistence is file-backed JSON under Application Support (or `APP_STORE`): `state.json`, `catalog.json`, `categories.json`, and related caches — not SwiftData or SQLite (CLAUDE.md’s “SwiftData database” line is stale). Game Folder data stays a derived in-memory view of on-disk ESO files, not a SQL/graph primary store.
- Optional support is Buy Me a Coffee via `.github/FUNDING.yml` (`buy_me_a_coffee: lewisvavasw`); the public page display name is solaegis. Do not add a BMC shield.
- r/elderscrollsonline bans anything that uses AI in any form ([wiki/rules](https://www.reddit.com/r/elderscrollsonline/wiki/rules/)). Posts, comments, screenshots, and linked copy for that sub must not mention AI, Ollama, Claude, OpenAI, or related features.
