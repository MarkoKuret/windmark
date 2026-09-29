#!/bin/sh
# Second-architecture determinism check (WM-033, conventions.md §5): builds the core for x86_64 next to the native
# arm64 build on an Apple Silicon Mac, runs the same races through windmark_race_trace in both (the x86_64 one
# under Rosetta) and compares the per-tick checksums of every tick. Also runs the x86_64 build's quick test set,
# which checks the math and environment vector files there.
#
#   core/tools/cross_arch_check.sh [seed ...]     (from the repository root; default seed 33)
#
# Seeds are for the AI fleet race; the scripted full race runs with its test seed. Builds in core/build (native)
# and core/build-x86_64; writes the checksum files to core/build-x86_64/traces. Exit code 1 on any difference.
set -eu

root=$(cd "$(dirname "$0")/../.." && pwd)
native="$root/core/build"
x86="$root/core/build-x86_64"
out="$x86/traces"
seeds=${*:-33}

if [ "$(uname -s)" != Darwin ] || [ "$(uname -m)" != arm64 ]; then
  echo "cross_arch_check.sh: needs an Apple Silicon Mac (arm64 native, x86_64 under Rosetta)" >&2
  exit 2
fi
if ! arch -x86_64 /usr/bin/true 2>/dev/null; then
  echo "cross_arch_check.sh: Rosetta is not installed (softwareupdate --install-rosetta)" >&2
  exit 2
fi

cmake -S "$root/core" -B "$native" -G Ninja >/dev/null
cmake -S "$root/core" -B "$x86" -G Ninja -DCMAKE_OSX_ARCHITECTURES=x86_64 >/dev/null
cmake --build "$native" --target windmark_race_trace
cmake --build "$x86"
file "$x86/tests/windmark_race_trace" | grep -q x86_64 || { echo "not an x86_64 build" >&2; exit 1; }

echo "== x86_64 quick tests under Rosetta"
ctest --test-dir "$x86" -LE long --output-on-failure  # its x86_64 test binaries run under Rosetta

mkdir -p "$out"
status=0
compare() {  # mode seed
  echo "== $1 race, seed $2"
  "$native/tests/windmark_race_trace" "$1" --seed "$2" --out "$out/$1-$2-arm64.txt"
  arch -x86_64 "$x86/tests/windmark_race_trace" "$1" --seed "$2" --out "$out/$1-$2-x86_64.txt"
  if cmp -s "$out/$1-$2-arm64.txt" "$out/$1-$2-x86_64.txt"; then
    echo "   same checksum every tick ($(($(wc -l <"$out/$1-$2-arm64.txt") - 1)) ticks)"
  else
    echo "   DIFFERENT, first differing lines:"
    diff "$out/$1-$2-arm64.txt" "$out/$1-$2-x86_64.txt" | head -6
    status=1
  fi
}
compare full 20260925
for seed in $seeds; do compare ai "$seed"; done
exit $status
