#!/usr/bin/env bash
# Runs TrackdoKit's integration tests against a local trackdo-server.
# Build the XCFramework first (scripts/build-xcframework.sh).
set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
server="$root/scripts/test-server.sh"
port=${TRACKDO_TEST_SERVER_PORT:-18787}

"$server" start
trap '"$server" stop' EXIT

cd "$root/TrackdoKit"
TRACKDO_TEST_SERVER_URL="http://127.0.0.1:$port" \
  TRACKDO_TEST_SERVER_TOKEN=integration-test-token \
  TRACKDO_TEST_SERVER_SCRIPT="$server" \
  swift test --filter TrackdoKitIntegrationTests "$@"
