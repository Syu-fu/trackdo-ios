import Foundation

/// The server URL in `UserDefaults` and the token in a ``TokenStore``.
public struct SettingsStore: Sendable {
    static let urlKey = "serverURL"

    /// `UserDefaults` is not `Sendable`, so it is opened on every use.
    private let suiteName: String?
    private let tokens: any TokenStore

    /// `suiteName` `nil` means the app's standard defaults.
    public init(suiteName: String? = nil, tokens: any TokenStore = KeychainTokenStore()) {
        self.suiteName = suiteName
        self.tokens = tokens
    }

    /// The last saved URL, kept after the token is deleted so it can be
    /// edited.
    public var savedURL: ServerURL? {
        defaults.string(forKey: Self.urlKey).flatMap { try? ServerURL($0) }
    }

    /// `nil` until both a URL and a token are saved.
    public func load() throws -> ServerSettings? {
        guard let url = savedURL, let token = try tokens.load() else {
            return nil
        }
        return try ServerSettings(url: url, token: token)
    }

    /// Call only once the server accepted the settings.
    public func save(_ settings: ServerSettings) throws {
        try tokens.save(settings.token)
        defaults.set(settings.url.url.absoluteString, forKey: Self.urlKey)
    }

    public func deleteToken() throws {
        try tokens.delete()
    }

    private var defaults: UserDefaults {
        suiteName.flatMap(UserDefaults.init(suiteName:)) ?? .standard
    }
}
