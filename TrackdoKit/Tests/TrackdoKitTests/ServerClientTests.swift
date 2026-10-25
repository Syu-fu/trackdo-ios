import Foundation
import Testing
@testable import TrackdoKit

@Suite struct ServerClientTests {
    let server = StubServer()

    var client: ServerClient {
        ServerClient(settings: try! ServerSettings(url: server.url, token: "secret"), session: server.session)
    }

    // MARK: GET /healthz

    @Test func healthCheckPassesForCompatibleServer() async throws {
        server.respond(status: 200, json: #"{"status":"ok","protocol_version":4}"#)

        try await ServerClient.checkHealth(of: server.url, session: server.session)

        let request = try #require(server.requests.first)
        #expect(request.method == "GET")
        #expect(request.path == "/base/healthz")
        #expect(request.headers["Authorization"] == nil)
    }

    @Test func healthCheckRefusesOtherProtocolVersions() async {
        server.respond(status: 200, json: #"{"status":"ok","protocol_version":3}"#)

        await #expect(throws: ServerError.unsupportedProtocol) {
            try await ServerClient.checkHealth(of: server.url, session: server.session)
        }
    }

    @Test(arguments: [
        (200, "<html>", ServerError.unexpected(status: 200, message: "<html>")),
        (404, "not found", .unexpected(status: 404, message: "not found")),
        (503, "", .serverFailure(status: 503)),
    ])
    func healthCheckRefusesWhatIsNotATrackdoServer(status: Int, body: String, error: ServerError) async {
        server.respond(status: status, json: body)

        await #expect(throws: error) {
            try await ServerClient.checkHealth(of: server.url, session: server.session)
        }
    }

    @Test func unreachableServerIsOffline() async {
        server.respond { _ in throw URLError(.notConnectedToInternet) }

        await #expect(throws: ServerError.offline(.notConnectedToInternet)) {
            try await ServerClient.checkHealth(of: server.url, session: server.session)
        }
    }

    // MARK: POST /ops

    @Test func postsOpsWithAuthAndProtocolHeaders() async throws {
        server.respond(status: 200, json: #"{"accepted":[]}"#)

        let response = try await client.postOps(Data("[]".utf8))

        #expect(response == HTTPResponse(status: 200, body: Data(#"{"accepted":[]}"#.utf8)))
        let request = try #require(server.requests.first)
        #expect(request.method == "POST")
        #expect(request.path == "/base/ops")
        #expect(request.headers["Authorization"] == "Bearer secret")
        #expect(request.headers["Trackdo-Protocol"] == "4")
        #expect(request.headers["Content-Type"] == "application/json")
        #expect(request.body == Data("[]".utf8))
    }

    @Test func opsResponsesAreReturnedForTheCoreToInterpret() async throws {
        server.respond(status: 422, json: #"{"error":{"code":"invalid_op","message":"m"}}"#)

        let response = try await client.postOps(Data("[]".utf8))

        #expect(response.status == 422)
    }

    @Test func postingOpsOfflineThrows() async {
        server.respond { _ in throw URLError(.timedOut) }

        await #expect(throws: ServerError.offline(.timedOut)) {
            try await client.postOps(Data("[]".utf8))
        }
    }

    // MARK: GET /snapshot

    @Test func fetchesSnapshotBody() async throws {
        server.respond(status: 200, json: #"{"log_id":"x"}"#)

        let body = try await client.snapshot()

        #expect(body == Data(#"{"log_id":"x"}"#.utf8))
        let request = try #require(server.requests.first)
        #expect(request.method == "GET")
        #expect(request.path == "/base/snapshot")
        #expect(request.headers["Authorization"] == "Bearer secret")
        #expect(request.headers["Trackdo-Protocol"] == "4")
    }

    @Test(arguments: [
        (401, #"{"error":{"code":"unauthorized","message":"m"}}"#, ServerError.unauthorized),
        (400, #"{"error":{"code":"unsupported_protocol_version","message":"m"}}"#, .unsupportedProtocol),
        (400, #"{"error":{"code":"invalid_json","message":"m"}}"#,
         .unexpected(status: 400, message: #"{"error":{"code":"invalid_json","message":"m"}}"#)),
        (500, "", .serverFailure(status: 500)),
    ])
    func snapshotErrorsAreClassified(status: Int, body: String, error: ServerError) async {
        server.respond(status: status, json: body)

        await #expect(throws: error) {
            try await client.snapshot()
        }
    }

    // MARK: GET /events

    @Test func sessionTreatsSilenceBeyondThreeKeepalivesAsDisconnected() {
        let configuration = ServerClient.makeSession().configuration

        #expect(configuration.timeoutIntervalForRequest == 45)
        #expect(configuration.urlCache == nil)
    }

    @Test func streamsEventsFromTheLastPosition() async throws {
        server.respond(status: 200, json: ":keepalive\n\nid: log:5\nevent: op\ndata: {}\n\n")

        var events: [ServerSentEvent] = []
        for try await event in try await client.events(lastEventId: "log:4") {
            events.append(event)
        }

        #expect(events == [ServerSentEvent(id: "log:5", event: "op", data: "{}")])
        let request = try #require(server.requests.first)
        #expect(request.method == "GET")
        #expect(request.path == "/base/events")
        #expect(request.headers["Last-Event-ID"] == "log:4")
        #expect(request.headers["Accept"] == "text/event-stream")
        #expect(request.headers["Authorization"] == "Bearer secret")
        #expect(request.headers["Trackdo-Protocol"] == "4")
    }

    @Test func streamsFromTheStartWithoutAPosition() async throws {
        server.respond(status: 200, json: "")

        for try await _ in try await client.events(lastEventId: nil) {}

        #expect(server.requests.first?.headers["Last-Event-ID"] == nil)
    }

    @Test(arguments: [
        (410, #"{"error":{"code":"resync_required","message":"m"}}"#, ServerError.resyncRequired),
        (401, #"{"error":{"code":"unauthorized","message":"m"}}"#, .unauthorized),
        (503, "", .serverFailure(status: 503)),
    ])
    func streamErrorsAreClassified(status: Int, body: String, error: ServerError) async {
        server.respond(status: status, json: body)

        await #expect(throws: error) {
            try await client.events(lastEventId: "log:1")
        }
    }
}
