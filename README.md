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

## Development

Requires Xcode 26.5 and the Rust toolchain pinned in
[`rust-toolchain.toml`](rust-toolchain.toml), which also installs the iOS
targets.

```sh
cargo test --workspace
cargo clippy --workspace --all-targets -- -D warnings
cargo fmt --check
```

## License

[MIT](LICENSE)
