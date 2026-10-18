import Foundation
import Security

/// Where the server token is kept.
public protocol TokenStore: Sendable {
    func load() throws -> String?
    func save(_ token: String) throws
    /// Succeeds when no token is stored.
    func delete() throws
}

public struct KeychainError: Error, Equatable, Sendable {
    public let status: OSStatus
}

/// The token as a Keychain generic password. It stays on this device, out of
/// backups, and is readable while locked after the first unlock so background
/// sends can authenticate.
public struct KeychainTokenStore: TokenStore {
    public static let defaultService = "dev.syufu.trackdo.server-token"

    private let service: String

    public init(service: String = defaultService) {
        self.service = service
    }

    public func load() throws -> String? {
        var query = itemQuery
        query[kSecReturnData] = true
        query[kSecMatchLimit] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess, let data = result as? Data else {
            throw KeychainError(status: status)
        }
        return String(decoding: data, as: UTF8.self)
    }

    public func save(_ token: String) throws {
        let data = Data(token.utf8)
        let updated = SecItemUpdate(itemQuery as CFDictionary, [kSecValueData: data] as CFDictionary)
        if updated == errSecSuccess {
            return
        }
        guard updated == errSecItemNotFound else {
            throw KeychainError(status: updated)
        }
        var item = itemQuery
        item[kSecValueData] = data
        item[kSecAttrAccessible] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let added = SecItemAdd(item as CFDictionary, nil)
        guard added == errSecSuccess else {
            throw KeychainError(status: added)
        }
    }

    public func delete() throws {
        let status = SecItemDelete(itemQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError(status: status)
        }
    }

    private var itemQuery: [CFString: Any] {
        [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: "default",
        ]
    }
}
