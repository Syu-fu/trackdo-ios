import Foundation
import Testing
@testable import TrackdoKit

@MainActor
@Suite struct SettingsEditorTests {
    let server = StubServer()
    let tokens = InMemoryTokenStore()
    let store: SettingsStore
    let applied = AppliedSettings()

    init() {
        let suite = "SettingsEditorTests-\(UUID().uuidString)"
        UserDefaults(suiteName: suite)!.removePersistentDomain(forName: suite)
        store = SettingsStore(suiteName: suite, tokens: tokens)
    }

    func makeEditor() -> SettingsEditor {
        SettingsEditor(store: store, session: server.session) { [applied] in applied.record($0) }
    }

    func saved(token: String = "secret") throws -> ServerSettings {
        try ServerSettings(url: server.url, token: token)
    }

    @Test func startsEmptyWithoutSettings() {
        let editor = makeEditor()

        #expect(editor.url == "")
        #expect(editor.token == "")
        #expect(!editor.hasSavedToken)
    }

    @Test func startsFromTheSavedURLButNeverShowsTheToken() throws {
        try store.save(saved())

        let editor = makeEditor()

        #expect(editor.url == server.url.url.absoluteString)
        #expect(editor.token == "")
        #expect(editor.hasSavedToken)
    }

    @Test func savesSettingsTheServerAccepts() async throws {
        server.respond(routes())
        let editor = makeEditor()
        editor.url = server.url.url.absoluteString
        editor.token = " secret\n"

        let didSave = await editor.save()

        #expect(didSave)
        #expect(editor.issue == nil)
        #expect(try store.load() == saved())
        #expect(try applied.values == [saved()])
        #expect(editor.token == "")
        #expect(editor.hasSavedToken)
        let snapshot = try #require(server.requests(to: "snapshot").first)
        #expect(snapshot.headers["Authorization"] == "Bearer secret")
    }

    @Test func reportsInvalidInputWithoutContactingTheServer() async throws {
        let editor = makeEditor()
        editor.url = "http://sync.example.com"
        editor.token = "two words"

        let didSave = await editor.save()

        #expect(!didSave)
        #expect(editor.urlIssue == .insecureRemoteHost)
        #expect(editor.tokenIssue == .invalidToken)
        #expect(server.requests.isEmpty)
        #expect(try store.load() == nil)
        #expect(applied.values.isEmpty)
    }

    @Test func requiresATokenWhenNoneIsSaved() async {
        let editor = makeEditor()
        editor.url = server.url.url.absoluteString

        _ = await editor.save()

        #expect(editor.urlIssue == nil)
        #expect(editor.tokenIssue == .invalidToken)
        #expect(server.requests.isEmpty)
    }

    @Test func anEmptyTokenKeepsTheSavedOne() async throws {
        try store.save(try ServerSettings(url: ServerURL("https://old.example.com"), token: "secret"))
        server.respond(routes())
        let editor = makeEditor()
        editor.url = server.url.url.absoluteString

        _ = await editor.save()

        #expect(editor.issue == nil)
        #expect(try store.load() == saved())
        #expect(try applied.values == [saved()])
    }

    @Test(arguments: [
        (healthy, status(401), ServerError.unauthorized),
        (status(200, #"{"status":"ok","protocol_version":3}"#), emptySnapshot, .unsupportedProtocol),
        (offline, offline, .offline(.notConnectedToInternet)),
    ])
    func keepsTheOldSettingsWhenTheServerRefuses(
        health: @escaping StubServer.Handler,
        snapshot: @escaping StubServer.Handler,
        error: ServerError
    ) async throws {
        try store.save(try ServerSettings(url: ServerURL("https://old.example.com"), token: "old"))
        server.respond(routes(health: health, snapshot: snapshot))
        let editor = makeEditor()
        editor.url = server.url.url.absoluteString
        editor.token = "secret"

        _ = await editor.save()

        #expect(editor.issue == .server(error))
        #expect(try store.load() == ServerSettings(url: ServerURL("https://old.example.com"), token: "old"))
        #expect(applied.values.isEmpty)
        #expect(editor.token == "secret")
    }

    @Test func aNewAttemptClearsTheLastIssue() async throws {
        server.respond(routes(snapshot: status(401)))
        let editor = makeEditor()
        editor.url = server.url.url.absoluteString
        editor.token = "wrong"
        _ = await editor.save()

        server.respond(routes())
        editor.token = "secret"
        _ = await editor.save()

        #expect(editor.issue == nil)
        #expect(editor.urlIssue == nil)
        #expect(editor.tokenIssue == nil)
    }

    @Test func savingAgainWhileCheckingDoesNothing() async {
        server.respond(routes())
        let editor = makeEditor()
        editor.url = server.url.url.absoluteString
        editor.token = "secret"

        async let first = editor.save()
        async let second = editor.save()
        let results = await [first, second]

        #expect(results.filter { $0 }.count == 1)
        #expect(server.requests(to: "healthz").count == 1)
        #expect(applied.values.count == 1)
    }

    @Test func removingTheTokenStopsSyncingAndKeepsTheURL() async throws {
        try store.save(saved())
        let editor = makeEditor()

        await editor.removeToken()

        #expect(try store.load() == nil)
        #expect(store.savedURL == server.url)
        #expect(!editor.hasSavedToken)
        #expect(editor.url == server.url.url.absoluteString)
        #expect(applied.values == [nil])
    }

    @Test func reportsWhenTheTokenCannotBeStored() async throws {
        server.respond(routes())
        let editor = SettingsEditor(
            store: SettingsStore(suiteName: nil, tokens: FailingTokenStore()),
            session: server.session
        ) { [applied] in applied.record($0) }
        editor.url = server.url.url.absoluteString
        editor.token = "secret"

        _ = await editor.save()

        #expect(editor.issue == .storage("KeychainError(status: -25291)"))
        #expect(applied.values.isEmpty)
    }
}

/// The settings handed to the store, in order.
@MainActor
final class AppliedSettings {
    private(set) var values: [ServerSettings?] = []

    func record(_ settings: ServerSettings?) {
        values.append(settings)
    }
}

struct FailingTokenStore: TokenStore {
    func load() throws -> String? { nil }
    func save(_ token: String) throws { throw KeychainError(status: errSecNotAvailable) }
    func delete() throws { throw KeychainError(status: errSecNotAvailable) }
}
