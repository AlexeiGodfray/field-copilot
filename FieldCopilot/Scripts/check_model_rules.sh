#!/bin/sh
# Builds the app's reading engine with check_model_rules/main.swift and checks every model-number rule
# against ENERGY STAR's published specs. Needs the network. See main.swift for what's compared.
set -e
cd "$(dirname "$0")/.."
out=$(mktemp -d)
swiftc -O -target arm64-apple-macos26.0 -default-isolation MainActor \
  FieldCopilot/*.swift \
  Scripts/check_model_rules/main.swift -o "$out/check_model_rules"
"$out/check_model_rules"
