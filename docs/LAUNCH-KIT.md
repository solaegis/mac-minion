# MacMinion launch kit

Copy-paste text for remaining GitHub settings and drafts for posts. About, website, topics, and wiki-off are already set.
Primary keyword: **ESO addon manager for Mac**. Secondary: Elder Scrolls Online addon manager macOS, ESOUI addons Mac, Minion alternative Mac.

## 1. About description (repo home → ⚙ next to About)

```
ESO addon manager for macOS: install, update, back up, and remove ESOUI addons in a native Mac app. A Minion alternative with Minion import, a menu bar update count, and optional AI.
```

182 characters. First 60: `ESO addon manager for macOS: install, update, back up, and r` (keyword in the first 27).

- **Website:** `https://solaegis.github.io/mac-minion/` (set)
- Tick **Releases**; untick **Packages** and **Deployments** if they show nothing useful.

## 2. Topics (same dialog, in this order)

```
elder-scrolls-online eso eso-addon esoui addon-manager mod-manager macos macos-app swiftui swift apple-silicon minion ollama
```

These 13 topics are on the repo. GitHub's API lists them alphabetically.

| Topic | Why |
| --- | --- |
| elder-scrolls-online | The game, spelled out; the main domain topic (146 repos) |
| eso | How players write it (158 repos) |
| eso-addon | The ESO addon niche (41 repos; `eso-addons` has 16) |
| esoui | The catalog it uses (61 repos) |
| addon-manager | What it is (51 repos) |
| mod-manager | The broader term people search (706 repos) |
| macos | Platform |
| macos-app | Platform, app listing (4.7k repos) |
| swiftui | Tech stack; developers browse it |
| swift | Tech stack |
| apple-silicon | The only supported Mac hardware |
| minion | People looking for a Minion replacement |
| ollama | Optional local AI; Ollama users browse this topic |

Repo counts are from GitHub's search API on 2026-10-28.

## 3. Social preview (Settings → General → Social preview → Edit → Upload an image)

Upload `site/images/social-preview.png` (1280×640, 620 KB, under GitHub's 1 MB limit). It shows the real app icon, "MacMinion / ESO addon manager for macOS / Install and update ESOUI addons", and the dark Overview screenshot. The docs site uses the same image for its share cards.

## 4. Other settings

- Settings → General → Features: **Discussions** left off; issues are the one channel. Wiki is off.
- Settings → Code security → **Private vulnerability reporting**: already on (SECURITY.md points to it).
- Optional: pin the repo on your profile (profile → Customize your pins).

## 5. v0.5 release notes (Releases → MacMinion 0.5 → Edit, replace the body)

The `0.5` section of CHANGELOG.md, followed by:

```
**Install:** download `MacMinion-0.5-macos-arm64.zip`, unzip, drag MacMinion to Applications, and open it the first time with right-click → Open. Needs macOS 26 on Apple Silicon. [Install guide](https://solaegis.github.io/mac-minion/install.html)
```

From the next tag on, the release workflow uses that version's CHANGELOG section as the notes.

## 6. Off-GitHub drafts

**Before posting anywhere:** MacMinion reads MMOUI's public feeds (`api.mmoui.com`) and downloads from ESOUI. Consider letting the ESOUI/MMOUI admins know before a wide announcement, so new traffic from a third-party client is not a surprise. Check each venue's current self-promotion rules; I could not verify them.

### ESOUI forums / official ESO forums (Add-Ons section)

> **MacMinion: a native Mac addon manager for ESO (Minion alternative)**
>
> I play ESO on a Mac and wanted an addon manager that feels like a Mac app, so I made MacMinion. It installs, updates, backs up, and removes ESOUI addons, using the same catalog Minion does.
>
> - Imports your Minion settings on first launch, and uses Minion's backup format, so you can switch back and forth
> - Update All (⌘U), a menu bar update count, and pinning addons you don't want updated
> - Shows libraries your addons need but don't have, with Install All
> - Optional AI (local Ollama, Claude, or OpenAI) for changelog summaries and suggestions; off by default
>
> Free for personal use, macOS 26 on Apple Silicon. It's unofficial and not made by MMOUI. Download and docs: https://github.com/solaegis/mac-minion
>
> Bug reports and ideas welcome on GitHub.

### Reddit: r/elderscrollsonline, r/macgaming

> **I made a native Mac addon manager for ESO (an alternative to Minion)**
>
> [screenshot: docs/images/overview.png]
>
> MacMinion installs and updates ESOUI addons in a SwiftUI app: grid or list views, Update All, a menu bar update count, SavedVariables backups in Minion's format, and Minion settings import. AI features are optional and can run locally with Ollama. No account, no telemetry.
>
> Free for personal use (PolyForm Noncommercial). macOS 26, Apple Silicon. https://github.com/solaegis/mac-minion
>
> It's my first release, so I'd love to hear what breaks.

r/macgaming leans toward Mac-specific angles: lead with "native, Apple Silicon, no Java".

### Directory listings

- **jaywcjlove/awesome-mac**: check whether it has a games or game-tools section and its rules on non-open-source apps before opening a PR. Not verified.
- **serhii-londar/open-source-mac-os-apps**: likely not eligible; it lists open-source apps and PolyForm Noncommercial is source-available, not open source.

PR description draft (awesome-mac):

> Add MacMinion, a native macOS addon manager for The Elder Scrolls Online (ESOUI addons). Free for personal use, source available under PolyForm Noncommercial 1.0.0, actively maintained.

## 7. Verification checklist

- [x] Repo home shows the new About text, website link, and 13 topics
- [ ] github.com/topics/eso-addon and /topics/elder-scrolls-online list MacMinion (can take a few minutes)
- [ ] GitHub search `ESO addon manager` (Repositories) shows MacMinion; try logged out
- [ ] Paste the repo URL into a Slack/Discord/iMessage draft: the card shows the social preview
- [ ] Paste https://solaegis.github.io/mac-minion/ the same way after the docs deploy
- [x] Insights → Community standards shows README, license, contributing, security, issue and PR templates
- [x] New issue → the Bug report and Feature request forms appear, with the docs and ESOUI links
- [ ] On a second Mac account or a clean Mac: follow the README Download steps and confirm the app opens

## 8. Traffic monitoring

Insights → Traffic keeps 14 days only. Check it weekly for the first 6 weeks, and note in a table: views, unique visitors, clones, top referrers, top pages, stars. Or save it with:

```bash
gh api repos/solaegis/mac-minion/traffic/views > traffic-$(date +%F).json
gh api repos/solaegis/mac-minion/traffic/popular/referrers >> traffic-$(date +%F).json
```

Release downloads: `gh release view v0.5 --json assets --jq '.assets[] | {name, downloadCount}'`.

On 2026-10-28 traffic was 0 views and 0 clones (repo created that day), so every number after a post is attributable to it.
