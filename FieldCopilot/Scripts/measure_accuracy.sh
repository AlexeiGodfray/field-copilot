#!/bin/sh
# Builds the app's reading engine with measure_accuracy/*.swift and reports its coverage and accuracy.
# See measure_accuracy/main.swift for the parts. Run from anywhere:
#   FieldCopilot/Scripts/measure_accuracy.sh [coverage | lookup | serials | synthetic [labels] | rules |
#                                             heatpumps [per maker] | photos <folder>]
set -e
root=$(cd "$(dirname "$0")/.." && pwd)
out=$(mktemp -d)
swiftc -O -target arm64-apple-macos26.0 -default-isolation MainActor \
  "$root"/FieldCopilot/*.swift \
  "$root"/Scripts/measure_accuracy/*.swift -o "$out/measure_accuracy"
"$out/measure_accuracy" "$root" "$@"
