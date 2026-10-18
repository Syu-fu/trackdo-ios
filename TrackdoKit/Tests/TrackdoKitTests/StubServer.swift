import Foundation
@testable import TrackdoKit

/// Answers requests to one made-up host with canned responses and records
/// what was sent. Hosts keep parallel tests apart.
final class StubServer: @unchecked Sendable {
    struct Recorded: Sendable {
        let method: String
        let path: String
        let headers: [String: String]
        let body: Data
    }

    typealias Handler = @Sendable (Recorded) throws -> (status: Int, body: Data)

    let url: ServerURL
    let session: URLSession
    private let lock = NSLock()
    private var handler: Handler
    private var recorded: [Recorded] = []
    private var openPaths: Set<String> = []
    private let arrivals: AsyncStream<Recorded>
    private let arrived: AsyncStream<Recorded>.Continuation

    init(handler: @escaping Handler = { _ in (200, Data()) }) {
        let host = "stub-\(UUID().uuidString.lowercased()).test"
        url = try! ServerURL("https://\(host)/base")
        self.handler = handler
        (arrivals, arrived) = AsyncStream.makeStream()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        session = URLSession(configuration: configuration)
        StubURLProtocol.register(self, for: host)
    }

    func respond(_ handler: @escaping Handler) {
        lock.withLock { self.handler = handler }
    }

    func respond(status: Int, json: String) {
        respond { _ in (status, Data(json.utf8)) }
    }

    var requests: [Recorded] { lock.withLock { recorded } }

    func requests(to endpoint: String) -> [Recorded] {
        requests.filter { $0.path == url.endpoint(endpoint).path() }
    }

    /// `200` responses to `endpoint` stay open after their body, like an
    /// event stream, until the client cancels them.
    func holdOpen(_ endpoint: String) {
        lock.withLock { _ = openPaths.insert(url.endpoint(endpoint).path()) }
    }

    /// Returns once `count` requests to `endpoint` arrived. One waiter at a
    /// time.
    func waitForRequests(to endpoint: String, count: Int) async {
        let path = url.endpoint(endpoint).path()
        var seen = requests(to: endpoint).count
        guard seen < count else {
            return
        }
        for await request in arrivals where request.path == path {
            seen = requests(to: endpoint).count
            if seen >= count {
                return
            }
        }
    }

    fileprivate func holdsOpen(_ path: String) -> Bool {
        lock.withLock { openPaths.contains(path) }
    }

    fileprivate func handle(_ request: Recorded) throws -> (status: Int, body: Data) {
        let handler = lock.withLock {
            recorded.append(request)
            return self.handler
        }
        arrived.yield(request)
        return try handler(request)
    }
}

final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0

    /// The value before incrementing.
    func increment() -> Int {
        lock.withLock {
            defer { value += 1 }
            return value
        }
    }
}

final class StubURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) private static var servers: [String: StubServer] = [:]
    private static let lock = NSLock()

    static func register(_ server: StubServer, for host: String) {
        lock.withLock { servers[host] = server }
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url, let host = url.host(),
              let server = Self.lock.withLock({ Self.servers[host] })
        else {
            client?.urlProtocol(self, didFailWithError: URLError(.cannotFindHost))
            return
        }
        let recorded = StubServer.Recorded(
            method: request.httpMethod ?? "GET",
            path: url.path(),
            headers: request.allHTTPHeaderFields ?? [:],
            body: request.httpBody ?? request.httpBodyStream.map(Self.read) ?? Data()
        )
        do {
            let (status, body) = try server.handle(recorded)
            // As the real server does. Without a type, URLSession holds the
            // response back to sniff the first 512 bytes.
            let type = url.lastPathComponent == "events" && status == 200 ? "text/event-stream" : "application/json"
            let response = HTTPURLResponse(
                url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": type]
            )!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: body)
            // Like the real server, only a streaming 200 stays open.
            if status != 200 || !server.holdsOpen(recorded.path) {
                client?.urlProtocolDidFinishLoading(self)
            }
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}

    private static func read(_ stream: InputStream) -> Data {
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            guard count > 0 else { break }
            data.append(buffer, count: count)
        }
        return data
    }
}
