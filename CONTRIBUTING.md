# Contributing to MacMinion

Thanks for helping make MacMinion, the Mac addon manager for The Elder Scrolls Online, better.

## Report a bug or ask for a feature

[Open an issue](https://github.com/solaegis/mac-minion/issues/new/choose) and pick a form. For a bug, include your macOS version, the MacMinion version (MacMinion > About MacMinion), and the steps that show it.

A problem inside one addon (an error in game, a broken feature) belongs to that addon's author on [ESOUI](https://www.esoui.com), not here. Report it here when MacMinion installs, updates, matches, or removes the addon wrongly.

## Pull requests

Open an issue first so we can agree on the change before you write it. MacMinion is licensed under the [PolyForm Noncommercial License 1.0.0](LICENSE), which is not an open-source license; please read it before you contribute. By sending a pull request, you agree that your contribution may be distributed under this license and under any other license the author offers MacMinion under later.

Everyone who takes part follows the [code of conduct](CODE_OF_CONDUCT.md).

## Build and check

MacMinion is a Swift package with no Xcode project. You need macOS 26 and Xcode 26 (Swift 6.2) on Apple Silicon.

```bash
./build.sh --open
swift test --scratch-path ~/Library/Developer/MacMinion/test-build
tools/selftest.sh
```

- `./build.sh` builds, signs, and installs `~/Applications/MacMinion.app`. Fix any warnings it shows.
- `tools/selftest.sh` runs the app's real functions against a store in `/tmp`. Never test against your real database in `~/Library/Application Support/MacMinion/`.
- For a UI change, run `tools/snap.sh` and look at the light and dark snapshots in `/tmp/MacMinion-shots/`.
- Design rules are in [design/DESIGN-SYSTEM.md](design/DESIGN-SYSTEM.md): system controls, design tokens, no hard-coded colors.

Write commit messages that say what someone can now do, for example "Install older releases from ESOUI's archive".
