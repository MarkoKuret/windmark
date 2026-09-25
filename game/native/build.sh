#!/bin/sh
# Builds the Windmark GDExtension for this machine into game/bin/: fetches the pinned godot-cpp into
# game/native/third_party/godot-cpp when it is missing, configures and builds with CMake and Ninja.
#   game/native/build.sh [template_debug|template_release]    (default template_debug)
set -eu
here=$(cd "$(dirname "$0")" && pwd)
target=${1:-template_debug}
GODOT_CPP_TAG=10.0.0-stable
GODOT_CPP_COMMIT=507ed9d840c01a3c5b2a39af8bb4000bfac30bf5
cpp="$here/third_party/godot-cpp"
if [ ! -d "$cpp/.git" ]; then
    mkdir -p "$here/third_party"
    git clone --quiet --depth 1 --branch "$GODOT_CPP_TAG" https://github.com/godotengine/godot-cpp "$cpp"
fi
have=$(git -C "$cpp" rev-parse HEAD)
if [ "$have" != "$GODOT_CPP_COMMIT" ]; then
    echo "godot-cpp at $have, expected $GODOT_CPP_COMMIT ($GODOT_CPP_TAG): remove $cpp and run again"
    exit 1
fi
build="$here/build/$target"
cmake -S "$here" -B "$build" -G Ninja -DGODOTCPP_TARGET="$target" >/dev/null
cmake --build "$build"
# Register the extension in the project's cache so the next Godot run loads it at start-up. A headless
# `--import` that discovers a new extension crashes on exit in Godot 4.6.3 (the extension docs are generated
# after the extension is unloaded); with the entry already there it loads normally.
"$here/register.sh"
ls "$here/../bin"
