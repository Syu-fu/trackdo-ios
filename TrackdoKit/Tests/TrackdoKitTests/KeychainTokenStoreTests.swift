import Foundation
import Testing
@testable import TrackdoKit

@Suite struct KeychainTokenStoreTests {
    let store = KeychainTokenStore(service: "dev.syufu.trackdo.tests.\(UUID().uuidString)")

    @Test func storesReplacesAndDeletesTheToken() throws {
        defer { try? store.delete() }
        #expect(try store.load() == nil)

        try store.save("first")
        try store.save("second")
        let saved = try store.load()
        try store.delete()

        #expect(saved == "second")
        #expect(try store.load() == nil)
    }

    @Test func deletingAMissingTokenSucceeds() throws {
        try store.delete()
    }
}
