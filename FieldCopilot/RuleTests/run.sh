#!/bin/sh
# Builds the app's reading engine (FieldCopilot/*.swift; the screens live in FieldCopilot/App) with the tests
# and runs them on this Mac.
set -e
cd "$(dirname "$0")/.."
out=$(mktemp -d)
swiftc -O -target arm64-apple-macos26.0 -default-isolation MainActor \
  FieldCopilot/*.swift \
  RuleTests/*.swift -o "$out/ruletests"
"$out/ruletests"
