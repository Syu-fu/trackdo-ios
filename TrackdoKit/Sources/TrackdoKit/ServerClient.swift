import Foundation
import TrackdoFFI

/// Why a request to trackdo-server did not produce a usable response.
public enum ServerError: Error, Equatable, Sendable {
    /// The request did not complete: no network, timeout, cancellation.
    case offline(URLError.Code)
    /// The token is wrong (`401`).
    case unauthorized
    /// The app or the server needs updating.
    case unsupportedProtocol
    /// The server failed (`5xx`); try again later.
    case serverFailure(status: Int)
    /// A response the API does not specify, e.g. from something that is not
    /// a trackdo-server.
    case unexpected(status: Int, message: String)
}

public struct HTTPResponse: Sendable, Equatable {
    public let status: Int
    public let body: Data
}

/// Requests to trackdo-server's API (its `docs/design.md`). Bodies are passed
/// through as bytes; the core encodes and interprets them.
public struct ServerClient: Sendable {
    public let settings: ServerSettings
    private let session: URLSession

    public init(settings: ServerSettings, session: URLSession) {
        self.settings = settings
        self.session = session
    }

    /// `GET /healthz`, unauthenticated: the URL points at a trackdo-server
    /// speaking this app's protocol version.
    public static func checkHealth(of url: ServerURL, session: URLSession) async throws(ServerError) {
        let response = try await send(URLRequest(url: url.endpoint("healthz")), with: session)
        let body = try successBody(of: response)
        guard let health = try? JSONDecoder().decode(Health.self, from: body), health.status == "ok" else {
            throw unexpected(response)
        }
        guard health.protocolVersion == protocolVersion() else {
            throw .unsupportedProtocol
        }
    }

    /// `POST /ops` with a body from `TrackdoCore.nextPushBatch()`. Every
    /// response is returned for `TrackdoCore.handlePushResponse`.
    public func postOps(_ body: Data) async throws(ServerError) -> HTTPResponse {
        var request = authorized("ops")
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        return try await Self.send(request, with: session)
    }

    /// `GET /snapshot`, for `TrackdoCore.applySnapshot`.
    public func snapshot() async throws(ServerError) -> Data {
        let response = try await Self.send(authorized("snapshot"), with: session)
        return try Self.successBody(of: response)
    }

    func authorized(_ path: String) -> URLRequest {
        var request = URLRequest(url: settings.url.endpoint(path))
        request.setValue("Bearer \(settings.token)", forHTTPHeaderField: "Authorization")
        request.setValue(String(protocolVersion()), forHTTPHeaderField: "Trackdo-Protocol")
        return request
    }

    private static func send(_ request: URLRequest, with session: URLSession) async throws(ServerError) -> HTTPResponse {
        do {
            let (body, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw URLError(.badServerResponse)
            }
            return HTTPResponse(status: http.statusCode, body: body)
        } catch let error as URLError {
            throw .offline(error.code)
        } catch {
            throw .offline(.unknown)
        }
    }

    /// The body of a `200`, or the error any endpoint may answer with.
    static func successBody(of response: HTTPResponse) throws(ServerError) -> Data {
        switch response.status {
        case 200:
            return response.body
        case 401:
            throw .unauthorized
        case 400 where errorCode(of: response.body) == "unsupported_protocol_version":
            throw .unsupportedProtocol
        case 500...599:
            throw .serverFailure(status: response.status)
        default:
            throw unexpected(response)
        }
    }

    private static func unexpected(_ response: HTTPResponse) -> ServerError {
        .unexpected(status: response.status, message: String(decoding: response.body, as: UTF8.self))
    }

    private static func errorCode(of body: Data) -> String? {
        try? JSONDecoder().decode(ErrorBody.self, from: body).error.code
    }
}

private struct Health: Decodable {
    let status: String
    let protocolVersion: UInt32

    enum CodingKeys: String, CodingKey {
        case status
        case protocolVersion = "protocol_version"
    }
}

private struct ErrorBody: Decodable {
    struct Detail: Decodable {
        let code: String
    }

    let error: Detail
}
