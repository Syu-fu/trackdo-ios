import Network
import Synchronization

/// Calls `onReconnect` each time the network becomes usable again, so
/// syncing need not wait out its backoff.
final class NetworkMonitor: Sendable {
    private let monitor = NWPathMonitor()

    init(onReconnect: @escaping @Sendable () -> Void) {
        let wasSatisfied = Mutex(true)
        monitor.pathUpdateHandler = { path in
            let isSatisfied = path.status == .satisfied
            let reconnected = wasSatisfied.withLock { wasSatisfied in
                defer { wasSatisfied = isSatisfied }
                return isSatisfied && !wasSatisfied
            }
            if reconnected {
                onReconnect()
            }
        }
        monitor.start(queue: DispatchQueue(label: "dev.syufu.trackdo.network"))
    }

    deinit {
        monitor.cancel()
    }
}
