import Foundation
import Network

public enum ServerURLError: Error, Equatable, Sendable {
    case malformed
    case unsupportedScheme
    /// Plain HTTP is only for development servers on this device or the
    /// local network.
    case insecureRemoteHost
    case hasQueryOrFragment
    case hasCredentials
}

/// Base URL of a trackdo-server, normalized to a lowercase scheme and host
/// without a trailing slash.
public struct ServerURL: Sendable, Hashable {
    public let url: URL

    public init(_ text: String) throws(ServerURLError) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var components = URLComponents(string: trimmed),
              let scheme = components.scheme?.lowercased(),
              let host = components.host?.lowercased(), !host.isEmpty
        else {
            throw .malformed
        }
        guard scheme == "https" || scheme == "http" else {
            throw .unsupportedScheme
        }
        guard components.user == nil, components.password == nil else {
            throw .hasCredentials
        }
        guard components.query == nil, components.fragment == nil else {
            throw .hasQueryOrFragment
        }
        if scheme == "http", !Self.isLocal(host) {
            throw .insecureRemoteHost
        }

        components.scheme = scheme
        components.percentEncodedHost = components.percentEncodedHost?.lowercased()
        while components.path.hasSuffix("/") {
            components.path.removeLast()
        }
        guard let url = components.url else {
            throw .malformed
        }
        self.url = url
    }

    /// `path` below the base URL, e.g. `ops` for `POST /ops`.
    public func endpoint(_ path: String) -> URL {
        url.appending(path: path)
    }

    /// Loopback, link-local and private addresses, and `.local` names.
    private static func isLocal(_ host: String) -> Bool {
        if host == "localhost" || host.hasSuffix(".local") {
            return true
        }
        if let address = IPv4Address(host) {
            let bytes = [UInt8](address.rawValue)
            return address.isLoopback || address.isLinkLocal
                || bytes[0] == 10
                || (bytes[0] == 172 && (16...31).contains(bytes[1]))
                || (bytes[0] == 192 && bytes[1] == 168)
        }
        // URLComponents keeps the brackets of IPv6 literals.
        let literal = host.trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        if let address = IPv6Address(literal) {
            let isUniqueLocal = [UInt8](address.rawValue)[0] & 0xFE == 0xFC
            return address.isLoopback || address.isLinkLocal || isUniqueLocal
        }
        return false
    }
}
