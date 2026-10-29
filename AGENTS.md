## Learned User Preferences

- Write GitHub README and user docs for people installing and using the app; keep agent/build internals (snapshots, grid lint, MCP) out of the main path.
- Do not propose Developer ID, notarization, App Store, sandbox, or SwiftLint unless Lewis changes those product goals.
- Treat MacMinion as source-available under PolyForm Noncommercial, not open source — do not suggest MIT/Apache or lists that require an OSI license.
- When driving GitHub UI for this repo, use the Safari Personal window (solaegis account); Work Safari is the Acxiom session. Cursor Computer Use needs Accessibility and Screen Recording; if those are off, drive Safari via accessibility or AppleScript instead.

## Learned Workspace Facts

- Public repo is `solaegis/mac-minion`; docs and Sparkle feed live at `https://solaegis.github.io/mac-minion/`.
- License is PolyForm Noncommercial 1.0.0 (copyright Lewis Vavasour); GitHub classifies it as Other.
- Shipping is GitHub Releases plus Sparkle 2 (EdDSA). CI signs with the MacMinion Release certificate so TCC survives updates; not Apple Developer ID and not notarized.
- GitHub About “include Releases” and the social-preview image have no API — change those in the signed-in browser.
- SPM-only SwiftUI app (no Xcode project); macOS 26, Apple Silicon. A `v*` tag cuts a release.
