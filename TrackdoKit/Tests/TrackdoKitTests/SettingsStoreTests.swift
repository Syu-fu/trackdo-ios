import Foundation
import Testing
@testable import TrackdoKit

final class InMemoryTokenStore: TokenStore, @unchecked Sendable {
    private let lock = NSLock()
    private var token: String?

    func load() throws -> String? { lock.withLock { token } }
    func save(_ token: String) throws { lock.withLock { self.token = token } }
    func delete() throws { lock.withLock { token = nil } }
}

@Suite struct SettingsStoreTests {
    let defaults: UserDefaults
    let tokens = InMemoryTokenStore()
    let store: SettingsStore

    init() {
        let suite = "SettingsStoreTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        store = SettingsStore(suiteName: suite, tokens: tokens)
    }

    func settings(_ url: String = "https://sync.example.com", token: String = "secret") throws -> ServerSettings {
        try ServerSettings(url: ServerURL(url), token: token)
    }

    @Test func nothingIsConfiguredAtFirst() throws {
        #expect(try store.load() == nil)
        #expect(store.savedURL == nil)
    }

    @Test func loadsWhatWasSaved() throws {
        try store.save(settings())
        try store.save(settings("https://other.example.com", token: "newer"))

        #expect(try store.load() == settings("https://other.example.com", token: "newer"))
    }

    @Test func keepsTheTokenOutOfUserDefaults() throws {
        try store.save(settings(token: "secret"))

        let stored = defaults.dictionaryRepresentation().values.compactMap { $0 as? String }
        #expect(!stored.contains("secret"))
        #expect(try tokens.load() == "secret")
    }

    @Test func deletingTheTokenKeepsTheURLForEditing() throws {
        try store.save(settings())

        try store.deleteToken()

        #expect(try store.load() == nil)
        #expect(store.savedURL == (try ServerURL("https://sync.example.com")))
    }

    @Test func ignoresAnInvalidStoredURL() throws {
        try store.save(settings())
        defaults.set("not a url", forKey: SettingsStore.urlKey)

        #expect(store.savedURL == nil)
        #expect(try store.load() == nil)
    }

    @Test func tokensAreTrimmed() throws {
        #expect(try settings(token: "  secret\n").token == "secret")
    }

    @Test(arguments: ["", "  \n", "sec ret", "sec\nret"])
    func refusesMalformedTokens(token: String) {
        #expect(throws: ServerSettingsError.invalidToken) { try settings(token: token) }
    }
}
