import Foundation
import TrackdoFFI
@testable import TrackdoKit

let testLog = "01928f30-0000-7000-8000-000000000001"
let otherLog = "01928f30-0000-7000-8000-000000000002"

/// Records backoff delays instead of waiting.
final class RecordedSleeps: @unchecked Sendable {
    private let lock = NSLock()
    private var delays: [Duration] = []

    var count: Int { lock.withLock { delays.count } }

    func sleep(_ delay: Duration) async throws {
        lock.withLock { delays.append(delay) }
    }
}

/// Backoff that waits until cancelled and reports that it started waiting.
final class SleepGate: Sendable {
    private let started: AsyncStream<Void>
    private let start: AsyncStream<Void>.Continuation

    init() {
        (started, start) = AsyncStream.makeStream()
    }

    func sleep(_ delay: Duration) async throws {
        start.yield()
        try await Task.sleep(for: .seconds(3600))
    }

    func waitUntilBackingOff() async {
        for await _ in started {
            return
        }
    }
}

let offline: StubServer.Handler = { _ in throw URLError(.notConnectedToInternet) }

func status(_ status: Int, _ body: String = "") -> StubServer.Handler {
    { _ in (status, Data(body.utf8)) }
}

/// Answers the n-th request with the n-th handler, repeating the last.
func inOrder(_ handlers: [StubServer.Handler]) -> StubServer.Handler {
    let next = Counter()
    return { request in try handlers[min(next.increment(), handlers.count - 1)](request) }
}

func accepted(_ request: StubServer.Recorded) -> (status: Int, body: Data) {
    let ids = sentOps(request).map { $0["op_id"] as! String }
    return (200, try! JSONSerialization.data(withJSONObject: ["accepted": ids]))
}

func sentOps(_ request: StubServer.Recorded) -> [[String: Any]] {
    try! JSONSerialization.jsonObject(with: request.body) as! [[String: Any]]
}

func firstOpId(of request: StubServer.Recorded) -> String {
    sentOps(request)[0]["op_id"] as! String
}

let emptySnapshot = status(200, #"{"log_id":"\#(testLog)","seq":null,"tasks":[],"time_entries":[]}"#)

/// An event stream delivering `ops` as the server would, from seq 1.
func eventStream(_ ops: [Data], log: String = testLog) -> StubServer.Handler {
    let body = ops.enumerated().map { index, op in
        "id: \(log):\(index + 1)\nevent: op\ndata: \(String(decoding: op, as: UTF8.self))\n\n"
    }.joined()
    return status(200, body)
}

/// The ops another device has queued, each as `OpDto` JSON.
func opsOf(_ core: TrackdoCore) -> [Data] {
    let batch = try! JSONSerialization.jsonObject(with: core.nextPushBatch()!) as! [Any]
    return batch.map { try! JSONSerialization.data(withJSONObject: $0) }
}

let healthy = status(200, #"{"status":"ok","protocol_version":3}"#)

func routes(
    health: @escaping StubServer.Handler = healthy,
    ops: @escaping StubServer.Handler = accepted,
    snapshot: @escaping StubServer.Handler = emptySnapshot,
    events: @escaping StubServer.Handler = status(200)
) -> StubServer.Handler {
    { request in
        switch request.path.split(separator: "/").last {
        case "healthz": try health(request)
        case "ops": try ops(request)
        case "snapshot": try snapshot(request)
        case "events": try events(request)
        default: (404, Data())
        }
    }
}

extension TrackdoStore {
    /// Returns once `condition` holds, checking after every change.
    func eventually(_ condition: @Sendable (TrackdoStore) async throws -> Bool) async rethrows {
        let (changes, changed) = AsyncStream<Void>.makeStream()
        onChange { changed.yield() }
        onProblem { _ in changed.yield() }
        onSyncStatus { _ in changed.yield() }
        if try await condition(self) {
            return
        }
        for await _ in changes {
            if try await condition(self) {
                return
            }
        }
    }
}
