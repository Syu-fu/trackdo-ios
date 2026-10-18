import Foundation
import Testing
import TrackdoFFI
@testable import TrackdoKit

@Suite struct StateFileTests {
    let directory = FileManager.default.temporaryDirectory
        .appending(path: "StateFileTests-\(UUID().uuidString)/trackdo")

    var file: StateFile { StateFile(directory: directory) }

    @Test func loadsNothingBeforeTheFirstSave() throws {
        #expect(try file.load() == nil)
    }

    @Test func loadsWhatWasSaved() throws {
        try file.save(Data("first".utf8))
        try file.save(Data("second".utf8))

        #expect(try file.load() == Data("second".utf8))
    }

    @Test func savingExcludesTheDirectoryFromBackups() throws {
        try file.save(Data("state".utf8))

        let values = try directory.resourceValues(forKeys: [.isExcludedFromBackupKey])
        #expect(values.isExcludedFromBackup == true)
    }

    @Test func livesInApplicationSupport() throws {
        let file = try StateFile.inApplicationSupport()

        #expect(file.url.pathComponents.suffix(3) == ["Application Support", "trackdo", "state.json"])
    }

    @Test func opensFreshCoreWithoutSavedState() throws {
        let core = try file.openCore()

        #expect(core.needsSnapshot())
        #expect(core.tasks().isEmpty)
    }

    @Test func opensSavedCore() throws {
        let saved = TrackdoCore()
        let id = try saved.create(title: "a")
        try file.save(saved.stateJson())

        let core = try file.openCore()

        #expect(core.tasks().map(\.id) == [id])
        #expect(core.nextPushBatch() == saved.nextPushBatch())
    }

    @Test func refusesToOpenCorruptState() throws {
        try file.save(Data("not json".utf8))

        #expect {
            try file.openCore()
        } throws: { error in
            if case FfiError.InvalidState = error { true } else { false }
        }
    }
}
