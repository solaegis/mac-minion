# Releasing MacMinion

How to cut and publish a new MacMinion release. The GitHub Actions workflow in [`.github/workflows/release.yaml`](.github/workflows/release.yaml) does the build, signing, GitHub Release, Sparkle feed, and docs redeploy when you push a version tag. This file is the checklist before and after that tag.

## Versioning

- Tags are semantic: `vMAJOR.MINOR.PATCH` (for example `v0.6.0`). The historical first ship was `v0.5`; keep that tag as-is.
- The tag name without the leading `v` is the app’s short version (`CFBundleShortVersionString`) and must match a CHANGELOG heading exactly: `## 0.6.0 — YYYY-MM-DD`.
- The release workflow extracts notes with awk on that heading’s second field (`$2`). A heading like `## 0.6` will not match tag `v0.6.0`.
- Never force-push `main` or an existing release tag.

## Secrets (GitHub Actions)

Required repository secrets (never print them):

| Secret | Purpose |
| --- | --- |
| `SIGNING_CERT_P12_BASE64` | Base64 of the “MacMinion Release” `.p12` |
| `SIGNING_CERT_PASSWORD` | Password for that `.p12` |
| `SPARKLE_ED_PRIVATE_KEY` | Sparkle EdDSA private key (key-file format: base64 seed). Public half is `SUPublicEDKey` in `Info.plist.in`. |

CI signs with the stable **MacMinion Release** identity so TCC answers survive updates. Releases are not Apple Developer ID and are not notarized.

## Checklist

Replace `X.Y.Z` with the version you are shipping (for example `0.6.0`).

### 1. Local verify

On Apple Silicon with Xcode 26:

```bash
./build.sh
swift test --scratch-path ~/Library/Developer/MacMinion/test-build
tools/selftest.sh
tools/missing-strings.sh
```

All must pass. `tools/missing-strings.sh` must report **0 keys missing**. Prefer a `/tmp` `APP_STORE` for self-test and snapshots; never point tests at `~/Library/Application Support/MacMinion/`.

### 2. Docs ready

- [`CHANGELOG.md`](CHANGELOG.md) has `## X.Y.Z — YYYY-MM-DD` with the user-facing notes for this ship, and a fresh empty `## Unreleased` above it.
- User docs match the ship: [`README.md`](README.md) and [`site/pages/`](site/pages/) (especially Game Folder, Settings, AI, install).
- Commit those changes on `main` (local commit/merge is fine; pushing needs express permission).

### 3. Push `main`

```bash
git push origin main
```

Only with express permission to update remote `main`.

### 4. CI green

Confirm the CI workflow on that `main` commit is green (`gh run list --branch main --limit 5`). Do not tag a red commit.

### 5. Tag and push the tag

```bash
git checkout main
git pull --ff-only
git tag -a "vX.Y.Z" -m "MacMinion X.Y.Z"
git push origin "vX.Y.Z"
```

Pushing the tag starts the **Release** workflow.

### 6. Watch the Release workflow

It should:

1. Import the release signing certificate into a temporary keychain.
2. Build and sign with `MACMINION_VERSION=X.Y.Z` and `MACMINION_BUILD` = the run number (`./build.sh --package dist`).
3. Zip `MacMinion-X.Y.Z-macos-arm64.zip`.
4. Sparkle-sign the zip (EdDSA) and verify the signature.
5. Create the GitHub Release titled `MacMinion X.Y.Z` with notes from the matching CHANGELOG section (or generated notes if that section is missing).
6. Prepend an item to `site/appcast.xml` on `main` and commit `Update feed: MacMinion X.Y.Z`.
7. Dispatch `pages.yml` so the docs site and feed redeploy.

Watch with `gh run list --workflow=release.yaml --limit 3` and open the run if anything fails.

### 7. Smoke after publish

- Release asset: `MacMinion-X.Y.Z-macos-arm64.zip` on the GitHub Release.
- Appcast: `https://solaegis.github.io/mac-minion/appcast.xml` lists `<sparkle:shortVersionString>X.Y.Z</sparkle:shortVersionString>`.
- Docs site: install and feature pages still load at `https://solaegis.github.io/mac-minion/`.
- Optional: install the zip on a Mac, confirm Gatekeeper first-open, and Check for MacMinion Updates… from an older build.

### 8. Announcements (optional)

Drafts and venue notes live in [`docs/LAUNCH-KIT.md`](docs/LAUNCH-KIT.md). They are not part of the automated cut. Remember r/elderscrollsonline bans AI mentions in any form.

## Flow

```text
docs + CHANGELOG → push main → CI green → tag vX.Y.Z → Release workflow → appcast + Pages
```

## Related

- [`CHANGELOG.md`](CHANGELOG.md) — release notes source
- [`docs/LAUNCH-KIT.md`](docs/LAUNCH-KIT.md) — repo About, topics, off-GitHub drafts
- [`SECURITY.md`](SECURITY.md) — only the latest release gets fixes
