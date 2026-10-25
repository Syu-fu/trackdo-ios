#!/usr/bin/env bash
# Runs a trackdo-server for the integration tests on 127.0.0.1.
#
#   scripts/test-server.sh start    # fresh database
#   scripts/test-server.sh restart  # same database, new log id
#   scripts/test-server.sh stop
#
# The server is built from its release tag with `cargo install`, since the
# macOS runners CI uses have no Docker to run its container image.
set -euo pipefail

version=v0.3.1
root=$(cd "$(dirname "$0")/.." && pwd)
state="$root/target/test-server"
port=${TRACKDO_TEST_SERVER_PORT:-18787}
token=integration-test-token
# Per version, so changing `version` installs that release.
install_root="$state/$version"
binary="$install_root/bin/trackdo-server"
pidfile="$state/server.pid"

install_server() {
  if [[ ! -x "$binary" ]]; then
    cargo install --locked --quiet --root "$install_root" \
      --git https://github.com/Syu-fu/trackdo-server --tag "$version" trackdo-server
  fi
}

stop_server() {
  if [[ -f "$pidfile" ]]; then
    kill "$(cat "$pidfile")" 2>/dev/null || true
    while kill -0 "$(cat "$pidfile")" 2>/dev/null; do sleep 0.1; done
    rm -f "$pidfile"
  fi
}

launch_server() {
  TRACKDO_LISTEN="127.0.0.1:$port" \
    TRACKDO_DATABASE="$state/trackdo.db" \
    TRACKDO_TOKEN_HASHES=$(printf %s "$token" | shasum -a 256 | cut -d' ' -f1) \
    RUST_LOG=warn \
    "$binary" >>"$state/server.log" 2>&1 &
  echo $! >"$pidfile"
  for _ in $(seq 100); do
    if curl -fsS "http://127.0.0.1:$port/healthz" >/dev/null 2>&1; then
      return
    fi
    sleep 0.1
  done
  echo "trackdo-server did not start; see $state/server.log" >&2
  exit 1
}

mkdir -p "$state"
case "${1:-}" in
  start)
    install_server
    stop_server
    rm -f "$state"/trackdo.db*
    launch_server
    ;;
  restart)
    stop_server
    launch_server
    ;;
  stop)
    stop_server
    ;;
  *)
    echo "usage: $0 start|restart|stop" >&2
    exit 2
    ;;
esac
