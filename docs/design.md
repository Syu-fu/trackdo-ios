# trackdo-ios design

The iOS client of trackdo. Domain logic, conflict resolution and timer healing
live in [trackdo-core](https://github.com/Syu-fu/trackdo-core) v0.4.0; the
sync API is specified in trackdo-server's
[`docs/design.md`](https://github.com/Syu-fu/trackdo-server/blob/main/docs/design.md).
This client only drives them.

## Repository layout

- `crates/trackdo-ffi`: UniFFI bindings of `trackdo-core` and
  `trackdo-protocol`. Kept here rather than shared with the Web client, which
  binds through wasm-bindgen instead. Code worth sharing with Web can be
  extracted into its own crate when the Web client starts.
- `crates/uniffi-bindgen`: the bindings generator, built from the same UniFFI
  version as the library.
- `TrackdoKit/`: Swift package wrapping the generated bindings with
  persistence, settings and sync.
- `App/`: the SwiftUI app. `App/project.yml` generates its Xcode project with
  XcodeGen 2.45.4 (`scripts/build-app.sh`); the project is not committed.

## Split between Rust and Swift

Rust is a sans-IO sync driver; Swift does all I/O and scheduling.

| Concern | Side |
|---|---|
| Commands and queries on `Replica` | Rust |
| `Clock` (`SystemTime`, ms UTC) and `IdGen` (UUIDv7) | Rust |
| JSON encoding and validation through `trackdo-protocol` | Rust |
| Interpreting responses and events: batches of at most 500 ops, 200 / 409 / 422 / 401 / 400 / 5xx, `EventId` parsing, log changes, ops queued by healing | Rust |
| HTTP and SSE over `URLSession` | Swift |
| Backoff, reconnects, app lifecycle | Swift |
| Reading and writing the state file, Keychain | Swift |

The FFI object guards the replica with a `Mutex`. Calls are synchronous and
in memory; one Swift actor owns the object and serializes every call. The UI
reads owned value types published by a `@MainActor` `@Observable` model.

## Persistence

- The replica is stored as JSON, `{"format": 1, "state": ReplicaStateDto}`,
  in `Application Support/trackdo/state.json`. `format` versions the local
  file and is independent of `PROTOCOL_VERSION`. `ReplicaStateDto` comes
  from `trackdo-protocol`, which validates it on load like server data.
  Files written before trackdo-core v0.4.0, without tags and the newer task
  fields, still load.
- A file that cannot be read is reported instead of being replaced by a new
  replica, since it may hold unsent edits.
- The file is written atomically after every call that changes state:
  commands, `acknowledge`, `reject`, `apply_remote` and `apply_snapshot`.
- File protection is `completeUntilFirstUserAuthentication`, so background
  sends can write it while the device is locked.
- The file is excluded from backups. The device id lives in the state's HLC,
  so a missing file means a new install with a new device id. Restoring a
  device id with an older HLC could reissue timestamps it already used.

## UniFFI

- `uniffi` is pinned with `=` because bindings must match the library version.
- Proc-macros only, no UDL.
- Bindings are generated in library mode from the host `cdylib`.
- `scripts/build-xcframework.sh` builds `aarch64-apple-ios`,
  `aarch64-apple-ios-sim` and `aarch64-apple-darwin` (for `swift test`) into
  `TrackdoFFIC.xcframework`, the C module consumed by `TrackdoKit` as a
  `binaryTarget`. The generated Swift forms the `TrackdoFFI` target on top of
  it (`crates/trackdo-ffi/uniffi.toml`). Intel simulators are not supported.
- Generated files are not committed.
- UniFFI 0.32's bindings generator needs Rust 1.88 (through askama), so this
  repository pins 1.88.0 while trackdo-core pins 1.87.0.

## Sync lifecycle

- When the app becomes active: fetch a snapshot if no `log_id` is known, push
  pending ops, then connect `GET /events`.
- In the background: disconnect the stream; if ops are pending, try a last
  push within a `beginBackgroundTask` grace period. No background refresh for
  now.
- One push loop runs at a time. Local edits, ops queued by healing and the
  network coming back all wake it. It repeats taking a batch, posting it and
  handling the response until nothing is pending.
  - 409 / 422: the named op is rejected and the rest is sent again.
  - 5xx and network errors: retried after backoff.
  - 401 and `unsupported_protocol_version`: sending stops and the error is
    shown until settings change.
- One event stream at a time. A `410 resync_required`, or an event id from
  another log, triggers a snapshot and a reconnect. The server sends a
  keepalive every 15 s, so 45 s without data counts as a disconnect.
- Settings shows the sync status: off, connecting, live, paused in the
  background, or the current problem, with Retry Now when retrying can help.
- Backoff is exponential with full jitter, from 1 s up to 60 s. It resets
  after a successful connection or push, and `NWPathMonitor` retries at once
  when the network comes back.

## Settings and secrets

- The server URL is stored in `UserDefaults`. It must be `https`, except for
  `localhost` and local-network hosts (`NSAllowsLocalNetworking`), which are
  for development.
- The token is a Keychain generic password with
  `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`.
- Settings are saved only after `GET /healthz` reports the client's
  `protocol_version` (4) and an authenticated `GET /snapshot` succeeds.
- Without settings, the app works locally only.
- Switching servers is allowed: the new `log_id` triggers a resync, and core
  queues the writes the new server lacks.

## UI

- SwiftUI with Observation, `NavigationStack`. Requires iOS 26.
- The app works on its own: it opens on the task list, and every edit is
  saved on the device. Sync is an optional setting reached from the list's
  toolbar.
- Structure and interaction follow Apple's Human Interface Guidelines:
  navigation bar with a large title, toolbar actions, list swipe actions
  with the same actions in a menu, sheets and confirmation dialogs.
  `App/Sources/Design` holds the colors and type sizes, taken from the
  Digital Agency design system (DADS, `@digital-go-jp/design-tokens` 2.0.1),
  and the shared pieces: buttons, form fields, chip labels, notification
  banners, the focus indicator and a flow layout. New screens no longer
  follow DADS component specs. Dates and times use the system compact
  `DatePicker`. The system font stands in for Noto Sans JP, and text sizes
  follow Dynamic Type. The palette is light only, so the app sets
  `UIUserInterfaceStyle` to `Light` for now.
- Controls are placed by how often they are used. Frequent actions take one
  tap and sit within the thumb's reach: the running timer with its Stop
  button and Add Task in the bottom toolbar, and a checkbox and a timer
  button on every task row and beside the title on the detail screen. Rare
  actions such as renaming, moving and deleting wait in a More menu and in
  swipe actions.
- Rows say little in words. The round checkbox is tinted by priority (red
  high, orange medium, blue low, gray none), as in Todoist. A due date is
  just the date, red when overdue and a green Today. Tags are chips in a
  color picked from the tag id, so it is the same on every device and kept
  through renames. Details wrap onto more lines rather than being cut off,
  and each row is read as one sentence that does say everything, priority
  and tags included.
- The app is in English and Japanese. Strings live in String Catalogs
  (`Localizable.xcstrings` and `InfoPlist.xcstrings`); the build extracts
  them from the code, and `scripts/check-localizations.sh` fails when the
  catalog is out of step or a string lacks a Japanese translation. Japanese
  keeps the DADS markers "※必須" and "＊". Dates, times and spoken
  durations follow the device's locale.
- Screen logic that can be tested, such as `TaskListModel`,
  `TaskDetailModel` and `SettingsEditor`, lives in `TrackdoKit`; views only
  lay it out.
- The MVP has three screens:
  - Task list: top-level tasks only, in creation order, with add, complete
    or reopen, rename and delete. Each row completes or reopens its task
    with a checkbox, starts or stops a timer, and shows the total counting
    up live, then the due date, subtask progress, plan, a note mark and
    tags. A one-line bar in the bottom toolbar shows the running timer with
    a Stop button, and opens its task. Deleting a task deletes its
    subtasks, and the confirmation says so.
  - Task detail, opened from a task's title: a link to the parent for a
    subtask, the checkbox, title, timer and total, then priority, due date,
    plan, tags and note, each changed in place; empty fields take one tap
    to add, and the note saves when editing leaves it. Tags are chosen in a
    sheet that narrows them as a name is typed, adds the name when it is
    new, and renames or deletes a tag behind a swipe. Subtasks follow as
    rows like the list's, completed and timed in place and opening their
    own detail, with Add Subtask at the end. Then the time entries newest
    first, with editing, deleting and adding past entries; entries that
    need fixing or were stopped automatically carry chip labels, and a
    banner points to entries that need fixing. Rename, Move (to the top
    level or under any task not below it) and Delete are in the More menu.
  - Settings: server URL, token, connection check and sync status.
- Not in the MVP: reports, widgets, Live Activities, notifications, search,
  iPad layouts, choosing a tag's color (core tags carry no color).

## Testing and CI

- Rust (Linux runner): `cargo fmt --check`, `clippy -D warnings`, tests, and
  `cargo llvm-cov --fail-under-lines 80`, not counting `uniffi-bindgen`.
- Swift (macOS runner): Swift Testing unit tests for `TrackdoKit`, with at
  least 80% line coverage of its hand-written sources, checked by
  `scripts/swift-coverage.sh`. The generated bindings and the app's views are
  not counted.
- Integration tests run `TrackdoKit` against a real trackdo-server v0.3.1
  (`scripts/integration-test.sh`). `scripts/test-server.sh` builds the server
  with `cargo install` and runs it on 127.0.0.1, both locally and in CI:
  macOS runners have no Docker, so the published image cannot be used. It can
  restart the server on the same database, which gives the log a new id.
  The tests are skipped unless `TRACKDO_TEST_SERVER_URL` is set. CI caches
  the server binary.
- The app is only built for the simulator, without UI tests.
- Workflows pin actions by SHA and are checked with `actionlint` and
  `pinact run --check`.

## Distribution

Simulator only for now; there is no signing setup. The bundle id is
`dev.syufu.trackdo`.
