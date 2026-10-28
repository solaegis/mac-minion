#!/bin/zsh
# Builds MacMinion and installs it to ~/Applications/MacMinion.app.
# Build products live in ~/Library/Developer/MacMinion, outside the repo
# (and outside Dropbox or iCloud, which would try to sync them).
#
# Usage: ./build.sh                 release build, install
#        ./build.sh --debug         debug build, install
#        ./build.sh --open          install, then quit the running copy and open the new one
#        ./build.sh --package <dir> write MacMinion.app to <dir>, skip home install and PATH symlink
#
# Env:   MACMINION_VERSION  CFBundleShortVersionString (default 0.1)
#        MACMINION_BUILD    CFBundleVersion (default date, or GITHUB_RUN_NUMBER in CI)
#        APP_DEST           full path of the .app; overrides --package and the home install
#        SIGN_IDENTITY      codesign identity; default Apple Development, then "MacMinion Local"
#                           (tools/make-signing-identity.sh), else ad hoc (-)
set -euo pipefail
here=${0:A:h}
name="MacMinion"
scratch="$HOME/Library/Developer/$name/build"
config=release
open=0
package_dir=""
while (( $# )); do
  case "$1" in
    --debug) config=debug ;;
    --open) open=1 ;;
    --package)
      shift
      package_dir="${1:-}"
      [[ -n $package_dir ]] || { echo "build.sh: --package needs a directory"; exit 1; }
      ;;
    *) echo "build.sh: unknown option $1" >&2; exit 1 ;;
  esac
  shift
done

version="${MACMINION_VERSION:-0.1}"
version="${version#v}"
build="${MACMINION_BUILD:-${GITHUB_RUN_NUMBER:-$(date +%Y%m%d%H%M)}}"

# Sign with your Apple Development certificate when you have one (Xcode >
# Settings > Accounts). Otherwise sign ad hoc, which is fine for your own Mac.
identity="${SIGN_IDENTITY:-}"
if [[ -z "$identity" ]]; then
  identity=$(security find-identity -v -p codesigning 2>/dev/null | grep -m1 -o '"Apple Development: [^"]*"' | tr -d '"' || true)
fi
# Next best: the local identity from tools/make-signing-identity.sh. Self-signed, so it is not
# "valid" to find-identity -v, but codesign uses it and its requirement stays the same every build.
if [[ -z "$identity" ]] && security find-identity -p codesigning 2>/dev/null | grep -q '"MacMinion Local"'; then
  identity="MacMinion Local"
fi
[[ -n "$identity" ]] || identity=-

swift build -c $config --package-path "$here" --scratch-path "$scratch" 2>&1 | grep -E "error|warning|Build complete" | grep -v "^\[" || true
bin="$scratch/$config/$name"
[[ -x "$bin" ]] || { echo "build failed"; exit 1; }
# swift build can report success while an edited file failed to compile. Catch that.
stale=$(find "$here/Sources" -name '*.swift' -newer "$bin" | head -1)
if [[ -n "$stale" ]]; then
  echo "build failed: binary is older than $stale"
  swift build -c $config --package-path "$here" --scratch-path "$scratch" 2>&1 | grep -E "error" | head -20
  exit 1
fi

if [[ -n "${APP_DEST:-}" ]]; then
  app="$APP_DEST"
elif [[ -n $package_dir ]]; then
  app="$package_dir/$name.app"
else
  app="$HOME/Applications/$name.app"
  mkdir -p "$HOME/Applications"
fi
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$bin" "$app/Contents/MacOS/$name"
sed -e "s/__VERSION__/${version}/" -e "s/__BUILD__/${build}/" "$here/Info.plist.in" > "$app/Contents/Info.plist"
# The icon: Icon/AppIcon.icon -> Resources/Assets.car + AppIcon.icns, rebuilt when it changed.
if [[ -d "$here/Icon/AppIcon.icon" ]]; then
  car="$here/Resources/Assets.car"
  if [[ ! -f "$car" || -n "$(find "$here/Icon/AppIcon.icon" -newer "$car" | head -1)" ]]; then
    "$here/tools/make_icon.sh"
  fi
  cp -X "$car" "$here/Resources/AppIcon.icns" "$app/Contents/Resources/"
fi
xattr -cr "$app"
codesign --force --sign "$identity" "$app" 2>&1 | grep -v "replacing existing signature" || true
echo "installed $app (signed: ${identity}, version: ${version})"
if [[ "$identity" == "-" && -z "${GITHUB_ACTIONS:-}" ]]; then
  echo "note: signed ad hoc, so macOS asks for Documents access after every build."
  echo "      Run tools/make-signing-identity.sh once to stop that."
fi

# The CLI: the app binary under a short name on PATH (bama agent-cli skill).
if [[ -z "${APP_DEST:-}" && -z $package_dir ]]; then
  mkdir -p "$HOME/.local/bin"
  ln -sf "$app/Contents/MacOS/$name" "$HOME/.local/bin/macminion"
fi

if (( open )) && [[ -z $package_dir && -z "${APP_DEST:-}" ]]; then
  osascript -e "quit app \"$name\"" 2>/dev/null || true
  sleep 0.5
  open "$app"
fi
