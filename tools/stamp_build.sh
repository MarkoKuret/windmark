#!/bin/sh
# Writes game/build.txt, the build stamp the main menu shows next to the version (docs/specs/menus.md section 1),
# from git describe. Run before an export (the export's non-resource filter includes build.txt); the file is not
# committed.
set -eu
repo=$(cd "$(dirname "$0")/.." && pwd)
git -C "$repo" describe --tags --always --dirty > "$repo/game/build.txt"
cat "$repo/game/build.txt"
