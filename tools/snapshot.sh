#!/bin/zsh
# Renders UI snapshots for visual review: ./tools/snapshot.sh [out-dir]
set -euo pipefail
cd "${0:A:h}/.."
OUT="${1:-build/snapshots}"
mkdir -p "$OUT" build
swiftc -swift-version 5 -target "$(uname -m)-apple-macos14.0" \
  $(ls Sources/*.swift | grep -v main.swift) tools/main.swift -o build/Snapshot
./build/Snapshot "$OUT"
