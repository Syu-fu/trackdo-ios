import Foundation
import os
import TrackdoKit

/// Everything the screens share: the replica and the settings that decide
/// where it syncs.
@MainActor
final class AppModel {
    private static let logger = Logger(subsystem: "dev.syufu.trackdo", category: "app")

    let store: TrackdoStore
    let settings: SettingsEditor
    private let settingsStore: SettingsStore
    private let session = ServerClient.makeSession()

    init() throws {
        let store = try TrackdoStore(file: StateFile.inApplicationSupport())
        let session = session
        let settingsStore = SettingsStore()
        self.store = store
        self.settingsStore = settingsStore
        settings = SettingsEditor(store: settingsStore, session: session) { settings in
            if let settings {
                await store.connect(client: ServerClient(settings: settings, session: session))
            } else {
                await store.disconnect()
            }
        }
    }

    /// Starts syncing with the saved settings, if any.
    func start() async {
        do {
            guard let saved = try settingsStore.load() else {
                return
            }
            await store.connect(client: ServerClient(settings: saved, session: session))
        } catch {
            Self.logger.error("Loading the settings failed: \(error)")
        }
    }
}
