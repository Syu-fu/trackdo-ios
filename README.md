# trackdo-ios

iOS client of **trackdo**, a personal app that combines a to-do list with
time tracking and syncs across devices.

Domain logic and the wire format come from
[trackdo-core](https://github.com/Syu-fu/trackdo-core); the app syncs with
[trackdo-server](https://github.com/Syu-fu/trackdo-server). See
[docs/design.md](docs/design.md) for how the client is put together.

> **Status:** early development.

## Layout

| Path | Purpose |
|---|---|
| [`crates/trackdo-ffi`](crates/trackdo-ffi) | UniFFI bindings of trackdo-core, including a sans-IO sync driver. |
| [`crates/uniffi-bindgen`](crates/uniffi-bindgen) | Generates the Swift bindings for `trackdo-ffi`. |
| [`TrackdoKit`](TrackdoKit) | Swift package: the bindings (`TrackdoFFI`) over the Rust library (`TrackdoFFIC.xcframework`). |

## Development

Requires Xcode 26.5 and the Rust toolchain pinned in
[`rust-toolchain.toml`](rust-toolchain.toml), which also installs the iOS
targets.

```sh
cargo test --workspace
cargo clippy --workspace --all-targets -- -D warnings
cargo fmt --check

scripts/build-xcframework.sh   # Rust library and Swift bindings for TrackdoKit
(cd TrackdoKit && swift test)
scripts/swift-coverage.sh      # the same tests, failing below 80% line coverage
scripts/integration-test.sh    # TrackdoKit against a local trackdo-server
scripts/build-app.sh           # the app for the iOS Simulator
scripts/check-localizations.sh # after a build: string catalogs match the code, all translated
```

Run the script again after changing `crates/trackdo-ffi`; its outputs are not
committed.

## License

[MIT](LICENSE)
