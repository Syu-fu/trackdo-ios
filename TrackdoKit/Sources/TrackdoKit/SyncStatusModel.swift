import Observation

extension SyncStatus {
    /// Whether trying again at once might help, rather than new settings
    /// or an update.
    public var canRetryNow: Bool {
        switch self {
        case .failing(.unreachable), .failing(.unexpected), .failing(.serverInconsistent): true
        default: false
        }
    }
}

/// The store's sync status for the settings screen.
@MainActor
@Observable
public final class SyncStatusModel {
    public private(set) var status = SyncStatus.off

    private let store: TrackdoStore

    public init(store: TrackdoStore) {
        self.store = store
    }

    /// Follows the store's status from now on.
    public func start() async {
        await store.onSyncStatus { [weak self] status in
            Task { @MainActor in self?.status = status }
        }
        status = await store.syncStatus
    }

    public func retryNow() async {
        await store.retryNow()
    }
}
