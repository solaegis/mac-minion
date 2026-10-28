#!/bin/zsh
# Runs the in-app self-test against a fresh store in /tmp. Exit code 0 when every check passed.
set -u
rm -rf ~/Library/Saved\ Application\ State/com.solaegis.macminion.savedState
store=/tmp/MacMinion-self
rm -rf $store
APP_STORE=$store ~/Applications/MacMinion.app/Contents/MacOS/MacMinion --selftest
