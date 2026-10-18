import Foundation
import TrackdoFFI

/// The replica's state on disk, rewritten after every change.
///
/// The directory is excluded from backups: the device id lives in the state,
/// and a restored copy could reissue timestamps the device already used.
public struct StateFile: Sendable {
    public let url: URL

    public init(directory: URL) {
        url = directory.appending(path: "state.json")
    }

    /// `Application Support/trackdo/state.json`.
    public static func inApplicationSupport() throws -> StateFile {
        let support = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return StateFile(directory: support.appending(path: "trackdo"))
    }

    /// `nil` before the first save.
    public func load() throws -> Data? {
        do {
            return try Data(contentsOf: url)
        } catch CocoaError.fileReadNoSuchFile {
            return nil
        }
    }

    /// Replaces the file atomically. It stays readable while the device is
    /// locked after the first unlock, so background sends can save too.
    public func save(_ data: Data) throws {
        try prepareDirectory()
        try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    /// The saved replica, or a new one with a new device id before the first
    /// save. Unreadable state throws rather than being replaced, since it may
    /// hold unsent edits.
    public func openCore() throws -> TrackdoCore {
        guard let data = try load() else {
            return TrackdoCore()
        }
        return try TrackdoCore.restore(stateJson: data)
    }

    private func prepareDirectory() throws {
        var directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try directory.setResourceValues(values)
    }
}
