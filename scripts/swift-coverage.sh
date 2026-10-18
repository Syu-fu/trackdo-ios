#!/usr/bin/env bash
# Runs TrackdoKit's tests with coverage and fails when its hand-written
# sources fall below a line coverage minimum (default 80%). The generated
# bindings in Sources/TrackdoFFI are not counted.
#
#   scripts/swift-coverage.sh [minimum percent]
#
# Build the XCFramework first (scripts/build-xcframework.sh).
set -euo pipefail

minimum=${1:-80}
kit="$(cd "$(dirname "$0")/.." && pwd)/TrackdoKit"

cd "$kit"
swift test --enable-code-coverage
bin=$(swift build --show-bin-path)
tests="$bin/TrackdoKitPackageTests.xctest/Contents/MacOS/TrackdoKitPackageTests"
profile="$bin/codecov/default.profdata"

xcrun llvm-cov report "$tests" -instr-profile "$profile" Sources/TrackdoKit
percent=$(xcrun llvm-cov export "$tests" -instr-profile "$profile" -summary-only Sources/TrackdoKit |
  jq '.data[0].totals.lines.percent')

if ! awk -v percent="$percent" -v minimum="$minimum" 'BEGIN { exit !(percent >= minimum) }'; then
  printf 'TrackdoKit line coverage %.2f%% is below %s%%\n' "$percent" "$minimum" >&2
  exit 1
fi
printf 'TrackdoKit line coverage %.2f%% (minimum %s%%)\n' "$percent" "$minimum"
