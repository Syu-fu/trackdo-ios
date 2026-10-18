import Foundation
import Observation

/// Why the edited settings were not saved, besides invalid input.
public enum SettingsIssue: Error, Equatable, Sendable {
    /// The health check or the authenticated snapshot failed.
    case server(ServerError)
    /// The settings could not be stored on this device.
    case storage(String)
}

/// The settings screen's state: settings are saved only once the server
/// answered `GET /healthz` with this app's protocol and accepted the token
/// on `GET /snapshot`. The saved token is never shown again.
@MainActor
@Observable
public final class SettingsEditor {
    public typealias Apply = @MainActor (ServerSettings?) async -> Void

    public var url: String
    /// Empty keeps the saved token.
    public var token = ""
    public private(set) var urlIssue: ServerURLError?
    public private(set) var tokenIssue: ServerSettingsError?
    public private(set) var issue: SettingsIssue?
    public private(set) var isChecking = false
    public private(set) var hasSavedToken: Bool

    private let store: SettingsStore
    private let session: URLSession
    private let apply: Apply

    /// `apply` receives saved settings to sync with, or `nil` once the token
    /// was removed.
    public init(store: SettingsStore, session: URLSession, apply: @escaping Apply) {
        self.store = store
        self.session = session
        self.apply = apply
        url = store.savedURL?.url.absoluteString ?? ""
        do {
            hasSavedToken = try store.load() != nil
        } catch {
            hasSavedToken = false
            issue = .storage(String(describing: error))
        }
    }

    /// Checks the edited settings with the server, then saves and applies
    /// them. Returns whether they were saved; does nothing while a check is
    /// running.
    @discardableResult
    public func save() async -> Bool {
        guard !isChecking else {
            return false
        }
        urlIssue = nil
        tokenIssue = nil
        issue = nil
        guard let settings = validated() else {
            return false
        }
        isChecking = true
        defer { isChecking = false }
        do {
            try await check(settings)
            try store.save(settings)
        } catch let error as SettingsIssue {
            issue = error
            return false
        } catch {
            issue = .storage(String(describing: error))
            return false
        }
        token = ""
        hasSavedToken = true
        await apply(settings)
        return true
    }

    /// Deletes the token and stops syncing. The URL stays for editing.
    public func removeToken() async {
        issue = nil
        do {
            try store.deleteToken()
        } catch {
            issue = .storage(String(describing: error))
            return
        }
        hasSavedToken = false
        await apply(nil)
    }

    /// Records every invalid field, not just the first.
    private func validated() -> ServerSettings? {
        var serverURL: ServerURL?
        var validToken: String?
        do {
            serverURL = try ServerURL(url)
        } catch {
            urlIssue = error
        }
        do {
            validToken = try ServerSettings.normalized(token: token.isEmpty ? savedToken() : token)
        } catch {
            tokenIssue = error
        }
        guard let serverURL, let validToken else {
            return nil
        }
        return try? ServerSettings(url: serverURL, token: validToken)
    }

    private func savedToken() -> String {
        (try? store.load())?.token ?? ""
    }

    private func check(_ settings: ServerSettings) async throws(SettingsIssue) {
        do {
            try await ServerClient.checkHealth(of: settings.url, session: session)
            _ = try await ServerClient(settings: settings, session: session).snapshot()
        } catch {
            throw .server(error)
        }
    }
}
