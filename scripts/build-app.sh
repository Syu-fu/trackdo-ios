#!/usr/bin/env bash
# Generates App/Trackdo.xcodeproj with a pinned XcodeGen and builds the app
# for the iOS Simulator. Build the XCFramework first
# (scripts/build-xcframework.sh).
set -euo pipefail

version=2.45.4
sha256=090ec29491aad50aec10631bf6e62253fed733c50f3aab0f5ffc86bc170bdbef
root=$(cd "$(dirname "$0")/.." && pwd)
tools="$root/target/xcodegen-$version"
xcodegen="$tools/xcodegen/bin/xcodegen"

if [[ ! -x "$xcodegen" ]]; then
  mkdir -p "$tools"
  curl -fsSL -o "$tools/xcodegen.zip" \
    "https://github.com/yonaskolb/XcodeGen/releases/download/$version/xcodegen.zip"
  echo "$sha256  $tools/xcodegen.zip" | shasum -a 256 -c --quiet
  unzip -q -o "$tools/xcodegen.zip" -d "$tools"
fi

"$xcodegen" generate --spec "$root/App/project.yml" --quiet
xcodebuild -project "$root/App/Trackdo.xcodeproj" -scheme Trackdo \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath "$root/target/DerivedData" \
  build "$@"
