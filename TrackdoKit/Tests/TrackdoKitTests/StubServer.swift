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

    init(handler: @escaping Handler = { _ in (200, Data()) }) {
        let host = "stub-\(UUID().uuidString.lowercased()).test"
        url = try! ServerURL("https://\(host)/base")
        self.handler = handler
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

    fileprivate func handle(_ request: Recorded) throws -> (status: Int, body: Data) {
        let handler = lock.withLock {
            recorded.append(request)
            return self.handler
        }
        return try handler(request)
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
            let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: body)
            client?.urlProtocolDidFinishLoading(self)
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
