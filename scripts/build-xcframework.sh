#!/usr/bin/env bash
# Builds TrackdoKit/TrackdoFFIC.xcframework and the Swift bindings in
# TrackdoKit/Sources/TrackdoFFI from crates/trackdo-ffi.
set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
kit="$root/TrackdoKit"
lib=libtrackdo_ffi
# Device, Apple Silicon simulator, and macOS for `swift test`.
targets=(aarch64-apple-ios aarch64-apple-ios-sim aarch64-apple-darwin)

export IPHONEOS_DEPLOYMENT_TARGET=26.0
export MACOSX_DEPLOYMENT_TARGET=26.0

cd "$root"
for target in "${targets[@]}"; do
  cargo build --locked --release -p trackdo-ffi --target "$target"
done

generated=$(mktemp -d)
trap 'rm -rf "$generated"' EXIT
cargo run --locked -q -p uniffi-bindgen -- generate \
  --library "target/aarch64-apple-darwin/release/$lib.dylib" \
  --language swift \
  --out-dir "$generated"

headers="$generated/headers"
mkdir "$headers"
cp "$generated/TrackdoFFIC.h" "$headers/"
cp "$generated/TrackdoFFIC.modulemap" "$headers/module.modulemap"

libraries=()
for target in "${targets[@]}"; do
  libraries+=(-library "target/$target/release/$lib.a" -headers "$headers")
done
rm -rf "$kit/TrackdoFFIC.xcframework"
xcodebuild -create-xcframework "${libraries[@]}" -output "$kit/TrackdoFFIC.xcframework" >/dev/null

mkdir -p "$kit/Sources/TrackdoFFI"
cp "$generated/TrackdoFFI.swift" "$kit/Sources/TrackdoFFI/"
