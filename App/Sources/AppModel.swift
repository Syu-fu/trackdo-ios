import os
import TrackdoKit
import UIKit

/// Everything the screens share: the replica, the task list over it, the
/// optional settings that decide where it syncs, and syncing that follows
/// the app between foreground and background.
@MainActor
final class AppModel {
    private static let logger = Logger(subsystem: "dev.syufu.trackdo", category: "app")

    let store: TrackdoStore
    let tasks: TaskListModel
    let settings: SettingsEditor
    let syncStatus: SyncStatusModel
    private let settingsStore: SettingsStore
    private let session = ServerClient.makeSession()
    private var network: NetworkMonitor?

    init() throws {
        let store = try TrackdoStore(file: StateFile.inApplicationSupport())
        let session = session
        let settingsStore = SettingsStore()
        self.store = store
        tasks = TaskListModel(store: store)
        syncStatus = SyncStatusModel(store: store)
        self.settingsStore = settingsStore
        settings = SettingsEditor(store: settingsStore, session: session) { settings in
            if let settings {
                await store.connect(client: ServerClient(settings: settings, session: session))
            } else {
                await store.disconnect()
            }
        }
    }

    /// Shows the saved tasks, keeps the list current with synced changes
    /// and starts syncing with the saved settings, if any.
    func start() async {
        let tasks = tasks
        await store.onChange {
            Task { @MainActor in await tasks.reload() }
        }
        await tasks.reload()
        await syncStatus.start()
        network = NetworkMonitor { [store] in
            Task { await store.retryNow() }
        }
        do {
            guard let saved = try settingsStore.load() else {
                return
            }
            await store.connect(client: ServerClient(settings: saved, session: session))
        } catch {
            Self.logger.error("Loading the settings failed: \(error)")
        }
    }

    /// Syncs again after the app was in the background.
    func enterForeground() async {
        await store.resume()
    }

    /// Closes the event stream and tries to send pending edits once, within
    /// the time the system grants before suspending the app.
    func enterBackground() async {
        let task = UIApplication.shared.beginBackgroundTask(withName: "Send pending edits")
        await store.suspend()
        if task != .invalid {
            UIApplication.shared.endBackgroundTask(task)
        }
    }
}
